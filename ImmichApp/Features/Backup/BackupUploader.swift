import Foundation
import UIKit

enum BackupUploadPhase: String, Codable, Sendable {
    case primaryAsset
    case livePhotoMotion
}

/// State minimum yang harus selamat ketika proses aplikasi dihentikan di antara
/// dua tahap upload Live Photo. `URLSessionTask.taskDescription` disimpan oleh
/// `nsurlsessiond`, sehingga konteks ini tetap tersedia saat iOS meluncurkan
/// proses baru hanya untuk menyampaikan hasil motion video.
struct BackupUploadTaskContext: Codable, Equatable, Sendable {
    let phase: BackupUploadPhase
    let localIdentifier: String
    let checksum: String
    let bodyPath: String

    var encoded: String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func decode(_ value: String?) -> Self? {
        guard let value else { return nil }
        if let data = value.data(using: .utf8),
           let context = try? JSONDecoder().decode(Self.self, from: data) {
            return context
        }

        // Task versi sebelum C4 masih dapat selesai setelah aplikasi di-update.
        // Format lamanya: localIdentifier, checksum, bodyPath.
        let legacy = value.components(separatedBy: "\u{1}")
        guard legacy.count == 3 else { return nil }
        return Self(
            phase: .primaryAsset,
            localIdentifier: legacy[0],
            checksum: legacy[1],
            bodyPath: legacy[2])
    }
}

/// Unggahan yang berjalan terus setelah aplikasinya ditutup.
///
/// **Kenapa BUKAN Background App Refresh.** `BGProcessingTask` — yang sudah ada
/// di `BackupScheduler` — hanya memberi aplikasi ini beberapa menit sesekali,
/// dan menit-menit itu habis jauh sebelum satu pustaka foto selesai naik. Yang
/// benar-benar bisa bekerja tanpa aplikasinya hidup adalah `URLSession` LATAR:
/// unggahannya diserahkan ke `nsurlsessiond`, daemon milik sistem, yang
/// meneruskannya meski proses aplikasi ini sudah lama tidak ada. Ketika selesai,
/// sistem MELUNCURKAN kembali aplikasi ini di latar untuk memberitahukan
/// hasilnya.
///
/// **Satu batas yang tidak bisa disiasati siapa pun.** Kalau pengguna menutup
/// paksa aplikasinya dari app switcher, iOS menghentikan seluruh transfernya dan
/// tidak akan meluncurkannya kembali. Itu berlaku untuk semua aplikasi, termasuk
/// Immich resmi. Menutup aplikasi dengan cara biasa — tombol Home, berpindah
/// aplikasi, layar mati — tidak termasuk; itu justru keadaan yang dilayani di
/// sini.
///
/// Konsekuensinya pada bentuk kode: tidak ada `async/await` dan tidak ada
/// completion handler. Sesi latar hanya bekerja lewat delegate, karena
/// jawabannya bisa datang di proses yang BERBEDA dari yang mengirimkannya.
final class BackupUploader: NSObject {
    @MainActor static let shared = BackupUploader()

    static let sessionIdentifier = "app.immich.backup.upload"

    /// Diisi `AppDelegate` saat sistem meluncurkan aplikasi ini hanya untuk
    /// menyampaikan hasil transfer. WAJIB dipanggil setelah semua delegate
    /// selesai — kalau tidak, iOS mencatat aplikasi ini sebagai yang menggantung
    /// dan memperlambat penjadwalan berikutnya.
    var backgroundCompletion: (() -> Void)?

    /// Badan jawaban per task, dirakit dari potongan.
    ///
    /// Sesi latar menyerahkan datanya lewat `didReceive data`, bukan sekaligus
    /// di akhir — dan id aset yang kita butuhkan ada di dalamnya.
    private var responses: [Int: Data] = [:]
    private let lock = NSLock()
    /// `urlSessionDidFinishEvents` dapat datang sesaat setelah callback motion
    /// video, sementara tahap foto utamanya masih sedang dirakit di Task async.
    /// Group ini mencegah completion handler background dipanggil terlalu awal.
    private let completionHandlers = DispatchGroup()

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(
            withIdentifier: Self.sessionIdentifier)
        // Sistem BOLEH meluncurkan aplikasi ini kembali untuk menyampaikan
        // hasilnya. Tanpa ini transfernya tetap jalan, tapi catatannya baru
        // tertulis saat pengguna kebetulan membuka aplikasinya lagi.
        config.sessionSendsLaunchEvents = true
        // Saat task dibuat oleh BGTask, iOS memperlakukannya sebagai
        // discretionary dan dapat menunggu Wi‑Fi/daya. Saat dibuat di foreground
        // nilainya false menjaga tombol backup tetap responsif.
        config.isDiscretionary = false
        config.allowsCellularAccess = true
        // Percobaan ulang diserahkan ke sistem: ia tahu kapan jaringannya
        // kembali, dan mencoba lagi sendiri tanpa aplikasinya perlu hidup.
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    /// Menyerahkan satu unggahan ke sistem.
    ///
    /// - Parameter localIdentifier: `PHAsset.localIdentifier` foto asalnya.
    ///   Dititipkan di `taskDescription`, dan itu bukan kemalasan: properti itu
    ///   ikut disimpan bersama task-nya, jadi ia SELAMAT melewati terminasi
    ///   aplikasi. Saat jawabannya datang di proses yang baru diluncurkan, itulah
    ///   satu-satunya cara mengetahui foto mana yang barusan naik — tanpa perlu
    ///   tabel tambahan yang harus dijaga tetap sinkron.
    func enqueue(
        _ prepared: BackupRepository.PreparedUpload,
        localIdentifier: String,
        checksum: String,
        allowsCellular: Bool,
        phase: BackupUploadPhase = .primaryAsset
    ) {
        var request = prepared.request
        // Ditegakkan PER PERMINTAAN, bukan per sesi: satu sesi latar melayani
        // foto dan video sekaligus, sedangkan aturannya berbeda untuk keduanya.
        request.allowsCellularAccess = allowsCellular
        request.allowsExpensiveNetworkAccess = allowsCellular
        // Low Data Mode selalu dihormati; pengguna hanya memilih seluler biasa,
        // bukan memberi izin mengabaikan pembatasan data sistem.
        request.allowsConstrainedNetworkAccess = false

        let task = session.uploadTask(with: request, fromFile: prepared.bodyFile)
        task.taskDescription = BackupUploadTaskContext(
            phase: phase,
            localIdentifier: localIdentifier,
            checksum: checksum,
            bodyPath: prepared.bodyFile.path).encoded
        task.resume()
    }

    /// Melanjutkan sesi yang mungkin masih punya transfer berjalan.
    ///
    /// Menyentuh `session` sudah cukup: membuat ulang konfigurasi dengan
    /// identifier yang SAMA membuat sistem mengembalikan task-task lama ke sesi
    /// ini, lengkap dengan `taskDescription`-nya.
    func reconnect() {
        _ = session
    }

    /// ID PhotoKit yang sudah berada di tangan `nsurlsessiond`.
    ///
    /// Daftar ini bertahan saat proses aplikasi mati. Tanpanya cold launch
    /// background mengantre file yang sama lagi karena `pendingPhotos` hanya RAM.
    func activeLocalIdentifiers() async -> Set<String> {
        let tasks = await session.allTasks
        return Set(tasks.compactMap(Self.localIdentifier(from:)))
    }

    private static func localIdentifier(from task: URLSessionTask) -> String? {
        BackupUploadTaskContext.decode(task.taskDescription)?.localIdentifier
    }

    /// Membatalkan transfer yang sudah diserahkan ke `nsurlsessiond`.
    ///
    /// `BackupService.stop()` hanya menghentikan loop pengantrean di proses ini;
    /// task background tetap membawa header akun lama sampai dibatalkan di sini.
    func cancelAll() async {
        let tasks = await session.allTasks
        tasks.forEach { $0.cancel() }

        lock.withLock { responses.removeAll() }
    }
}

// MARK: - Delegate

extension BackupUploader: URLSessionDataDelegate {
    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data
    ) {
        lock.lock()
        defer { lock.unlock() }
        responses[dataTask.taskIdentifier, default: Data()].append(data)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
    ) {
        lock.lock()
        let body = responses.removeValue(forKey: task.taskIdentifier) ?? Data()
        lock.unlock()

        guard let context = BackupUploadTaskContext.decode(task.taskDescription) else { return }
        // Badan multipart-nya bisa ratusan megabyte; membiarkannya berarti
        // menggandakan pustaka foto di direktori sementara.
        try? FileManager.default.removeItem(atPath: context.bodyPath)

        let outcome: Result<String, Error>
        if let error {
            outcome = .failure(error)
        } else {
            outcome = Result { try BackupRepository.assetID(from: body, response: task.response) }
        }

        let completedTaskID = task.taskIdentifier
        completionHandlers.enter()
        Task { @MainActor in
            defer { self.completionHandlers.leave() }
            let activeTasks = await self.session.allTasks
            let remaining = activeTasks.filter { $0.taskIdentifier != completedTaskID }.count
            switch context.phase {
            case .primaryAsset:
                BackupService.shared.finishUpload(
                    localIdentifier: context.localIdentifier,
                    checksum: context.checksum,
                    outcome: outcome,
                    remainingBackgroundTasks: remaining)

            case .livePhotoMotion:
                await BackupService.shared.finishLivePhotoMotionUpload(
                    localIdentifier: context.localIdentifier,
                    motionChecksum: context.checksum,
                    outcome: outcome,
                    remainingBackgroundTasks: remaining)
            }
        }
    }

    /// Semua yang tertunda sudah disampaikan.
    ///
    /// Ini satu-satunya saat aplikasi ini hidup di latar tanpa diminta siapa
    /// pun, jadi dipakai sekalian untuk MENCARI pekerjaan baru. Foto yang diambil
    /// setelah aplikasinya ditutup tidak dikenal sesi latar — sesi itu cuma
    /// meneruskan apa yang sudah diserahkan padanya. Menyerahkan gelombang
    /// berikutnya di sini membuat rantainya menyambung sendiri: selama masih ada
    /// sisa, tiap penyelesaian membangunkan aplikasi ini untuk mengantre lagi.
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            await withCheckedContinuation { continuation in
                self.completionHandlers.notify(queue: .global(qos: .utility)) {
                    continuation.resume()
                }
            }
            await BackupService.shared.continueInBackground()
            // WAJIB. `continueInBackground` pulang begitu `start()` membuat
            // Task-nya — sebelum satu foto pun benar-benar diserahkan. Tanpa
            // baris ini, seluruh ongkosnya dibayar (memulihkan sesi, mengenumerasi
            // album) lalu handler-nya dipanggil dengan gelombang berikutnya masih
            // kosong: persis akibat yang hendak dicegah.
            await BackupService.shared.waitUntilFinished()
            // Dipanggil TERAKHIR, setelah pengantrean berikutnya selesai. iOS
            // menganggap aplikasi ini boleh disuspend lagi begitu handler-nya
            // dijalankan, dan pekerjaan yang belum sempat diserahkan akan ikut
            // terpotong.
            let completion = self.backgroundCompletion
            self.backgroundCompletion = nil
            completion?()
        }
    }
}
