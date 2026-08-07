import CryptoKit
import Foundation
import Observation

/// Mencocokkan foto perangkat dengan aset yang sudah ada di server.
///
/// **Kenapa checksum, bukan catatan unggahan.** Catatan hanya tahu apa yang
/// diunggah lewat aplikasi ini. Foto yang naik lewat aplikasi resmi Immich atau
/// lewat web tidak meninggalkan jejak apa pun di sini — dan hasilnya foto yang
/// sama tergambar dua kali di linimasa. Checksum tidak peduli siapa yang
/// mengunggah: isi yang sama menghasilkan angka yang sama.
///
/// Harganya membaca SELURUH byte setiap foto. Tiga hal menahannya supaya itu
/// terjadi sesedikit mungkin:
///
/// - Hasilnya DISIMPAN per foto. Sebuah foto dihitung sekali seumur hidupnya.
/// - Yang sudah berpasangan tidak pernah disentuh lagi.
/// - Pembacaannya di luar main actor, sepotong-sepotong, dengan jeda di antara
///   kelompoknya — supaya menggulir linimasa tidak ikut tersendat.
@MainActor
@Observable
final class DeviceAssetMatcher {
    /// Sedang mencocokkan; dipakai layar untuk menunjukkan bahwa daftarnya
    /// masih bisa berubah.
    private(set) var isMatching = false

    private let repo: BackupRepository
    private let dataManager: SwiftDataManager
    private var task: Task<Void, Never>?
    /// Penomor putaran pencocokan.
    ///
    /// `cancel()` lalu `match()` lagi bisa membuat putaran LAMA selesai
    /// belakangan dan menimpa pembukuan milik yang baru — spinner padam padahal
    /// masih berjalan, dan penjaga "satu saja" ikut bocor. Task tidak punya
    /// identitas yang bisa dibandingkan dari luar, jadi nomornya yang dipakai.
    private var generation = 0

    /// Jumlah foto per permintaan ke server.
    ///
    /// Cukup besar supaya tidak jadi ratusan perjalanan, cukup kecil supaya satu
    /// badan permintaan tidak membengkak dan satu kegagalan tidak membuang kerja
    /// seluruh pustaka.
    private static let batchSize = 200

    init(repo: BackupRepository, dataManager: SwiftDataManager) {
        self.repo = repo
        self.dataManager = dataManager
    }

    /// - Parameter onMatched: dipanggil setiap kelompok yang menghasilkan
    ///   pasangan baru, supaya linimasa bisa menyusut sambil berjalan alih-alih
    ///   melompat sekaligus di akhir.
    func match(_ photos: [LocalPhoto], onMatched: @escaping @MainActor () -> Void) {
        guard task == nil else { return }

        // Jaringan BERBAYAR menunda seluruhnya.
        //
        // Bukan permintaan ke servernya yang mahal — itu cuma daftar checksum.
        // Yang mahal foto yang aslinya masih di iCloud: menghitungnya berarti
        // mengunduhnya dulu, dan lewat seluler itu bisa gigabyte tanpa pernah
        // diminta. Immich resmi mengambil sikap yang sama untuk unggahannya.
        guard !NetworkMonitor.shared.isExpensive else { return }

        let known = dataManager.uploadedLocalIdentifiers()
        let pending = photos.filter { !known.contains($0.id) }
        guard !pending.isEmpty else { return }

        isMatching = true
        generation &+= 1
        // Nama BERBEDA dari propertinya. `let generation = generation` membaca
        // sisi kanan sebagai deklarasi yang belum ada — Swift menolaknya.
        let runID = generation
        task = Task { [self, repo, dataManager] in
            defer {
                // Hanya putaran yang MASIH tercatat yang boleh membereskan.
                if runID == self.generation {
                    self.isMatching = false
                    self.task = nil
                }
            }

            var cached = dataManager.storedChecksums()

            for group in stride(from: 0, to: pending.count, by: Self.batchSize) {
                if Task.isCancelled { return }
                let slice = Array(pending[group..<min(group + Self.batchSize, pending.count)])

                // Yang belum punya checksum dihitung dulu, DI LUAR main actor.
                let missing = slice.filter { cached[$0.id] == nil }.map(\.id)
                if !missing.isEmpty {
                    let computed = await Self.computeChecksums(missing)
                    try? dataManager.storeChecksums(computed)
                    for entry in computed { cached[entry.localIdentifier] = entry.checksum }
                }

                let candidates = slice.compactMap { photo -> (id: String, checksum: String)? in
                    guard let checksum = cached[photo.id] else { return nil }
                    return (photo.id, checksum)
                }
                guard !candidates.isEmpty else { continue }

                // Server yang menjawab pasangannya; kegagalannya diam — pustaka
                // ini akan dicocokkan lagi pada pembukaan berikutnya, dan
                // checksum yang sudah dihitung tidak hilang.
                guard let matches = try? await repo.duplicateMatches(candidates) else { continue }
                guard !matches.isEmpty else { continue }

                for match in matches {
                    try? dataManager.linkDeviceAsset(
                        localIdentifier: match.localID, to: match.serverAssetID)
                }
                onMatched()

                // Napas di antara kelompok. Membaca puluhan foto beruntun tanpa
                // jeda membuat disk dan CPU sibuk persis saat pengguna baru
                // membuka aplikasinya.
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
        isMatching = false
    }

    /// Membaca byte lalu menghitung SHA1, satu per satu.
    ///
    /// Berurutan, bukan berbarengan: yang membatasi di sini pembacaan berkas,
    /// dan menembakkan puluhan permintaan sekaligus ke PhotoKit justru membuat
    /// semuanya mengantre lebih lama sambil menahan puluhan megabyte di memori.
    private static func computeChecksums(
        _ ids: [String]
    ) async -> [(localIdentifier: String, checksum: String)] {
        var result: [(localIdentifier: String, checksum: String)] = []
        for id in ids {
            if Task.isCancelled { return result }
            guard let file = await LocalPhotoLibrary.shared.originalData(
                for: LocalPhotoLibrary.assetID(for: id))
            else { continue }
            // Hashing DI LUAR main actor.
            //
            // `BackupRepository.checksum` terikat pemanggilnya, dan pemanggilnya
            // di sini main actor — SHA1 atas puluhan megabyte di sana berarti
            // antarmuka membeku persis saat linimasa baru tergambar.
            let data = file.data
            let checksum = await Task.detached(priority: .utility) {
                Insecure.SHA1.hash(data: data)
                    .map { String(format: "%02x", $0) }
                    .joined()
            }.value
            result.append((id, checksum))
        }
        return result
    }
}
