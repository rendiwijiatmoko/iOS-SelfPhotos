import Foundation
import Observation

/// Pencadangan otomatis foto perangkat ke server.
///
/// **Apa yang bisa dan tidak bisa dilakukan di iOS.** Aplikasi TIDAK bisa
/// memutuskan kapan tugas latarnya berjalan — sistem yang memilih, berdasarkan
/// kebiasaan pemakaian, baterai, dan jaringan. Immich resmi menuliskannya
/// terang-terangan: "semakin sering kamu membuka aplikasi, semakin sering tugas
/// latarnya berjalan". Jadi tulang punggungnya bukan tugas latar, melainkan
/// unggahan saat aplikasi DIBUKA atau kembali aktif; tugas latar hanya
/// pelengkap yang kadang kebagian giliran.
///
/// Karena itu layar Backup menampilkan angka, bukan janji: berapa yang ada,
/// berapa yang sudah aman, berapa yang belum. Yang belum akan naik pada
/// kesempatan berikutnya, dan pengguna bisa melihat sendiri kapan itu terjadi.
@MainActor
@Observable
final class BackupService {
    static let shared = BackupService()

    /// Pencadangan dinyalakan pengguna.
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            guard isEnabled else {
                BackupNotifier.shared.clearProgress()
                return
            }
            // Izin pemberitahuan diminta TEPAT di sini: pengguna baru saja
            // meminta pekerjaan yang berjalan tanpa dilihat, jadi alasan untuk
            // memberitahunya sudah jelas di layar.
            Task { await BackupNotifier.shared.ensureAuthorization(prompt: true) }
            start()
        }
    }

    /// Boleh memakai data seluler untuk FOTO.
    ///
    /// Dipisah dari video, seperti Immich resmi, karena selisihnya bukan soal
    /// selera: satu foto beberapa megabyte, satu video bisa ratusan. Banyak
    /// orang rela mengunggah foto lewat seluler dan sama sekali tidak rela
    /// mengunggah video. Bawaannya mati untuk keduanya.
    var cellularPhotos: Bool {
        didSet {
            guard cellularPhotos != oldValue else { return }
            UserDefaults.standard.set(cellularPhotos, forKey: Self.cellularPhotosKey)
        }
    }

    /// Boleh memakai data seluler untuk VIDEO.
    var cellularVideos: Bool {
        didSet {
            guard cellularVideos != oldValue else { return }
            UserDefaults.standard.set(cellularVideos, forKey: Self.cellularVideosKey)
        }
    }

    /// Menaruh aset yang diunggah ke album server bernama sama dengan album
    /// perangkat asalnya, membuatkannya kalau belum ada.
    var syncAlbums: Bool {
        didSet {
            guard syncAlbums != oldValue else { return }
            UserDefaults.standard.set(syncAlbums, forKey: Self.syncAlbumsKey)
        }
    }

    /// Seluruh foto unik dari album terpilih.
    private(set) var total = 0
    /// Yang sudah ada di server — diunggah dari sini maupun dari mana pun.
    private(set) var backedUp = 0
    /// Sisanya. Inilah angka yang sebenarnya berarti.
    var remainder: Int { max(0, total - backedUp) }

    private(set) var isUploading = false
    /// Nomor urut yang sedang dikerjakan, untuk bilah kemajuan.
    private(set) var uploadedThisRun = 0
    private(set) var pendingThisRun = 0
    /// Foto yang gagal diunggah pada putaran ini.
    private(set) var failures: [String] = []
    /// Alasan kegagalan TERAKHIR, apa adanya dari server atau sistem.
    private(set) var lastError: String?
    private(set) var lastRunAt: Date?

    private static let enabledKey = "backup.enabled"
    private static let cellularPhotosKey = "backup.cellularPhotos"
    private static let cellularVideosKey = "backup.cellularVideos"
    private static let syncAlbumsKey = "backup.syncAlbums"

    private var repo: BackupRepository?
    private var albumRepo: AlbumRepository?
    private let dataManager = SwiftDataManager.shared
    private var task: Task<Void, Never>?
    /// Nama album server → id-nya, supaya album yang sama tidak dicari ulang
    /// untuk setiap foto. Dikosongkan tiap putaran karena album bisa dibuat atau
    /// dihapus dari tempat lain di antara dua putaran.
    private var albumIDsByName: [String: String] = [:]
    /// Foto yang sudah diserahkan ke sistem tapi hasilnya belum kembali.
    ///
    /// Hanya di memori, dan itu memang cukup: satu-satunya gunanya adalah
    /// penempatan album dan mengetahui kapan putarannya habis. Catatan
    /// unggahannya sendiri ditulis dari `taskDescription`, yang selamat melewati
    /// terminasi aplikasi.
    private var pendingPhotos: [String: LocalPhoto] = [:]
    /// Berapa loop pengantrean yang sedang berjalan.
    ///
    /// PENGHITUNG, bukan `Bool`. `stop()` melepas `task` dan mengosongkan
    /// antrean, jadi `start()` berikutnya bisa memulai putaran B selagi loop
    /// putaran A masih tertahan di tengah foto. Dengan sebuah `Bool`, `defer`
    /// milik A akan mematikannya di tengah pengantrean B — membuka kembali
    /// persis lubang yang penanda ini dipasang untuk menutupnya.
    private var enqueueDepth = 0

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        cellularPhotos = UserDefaults.standard.bool(forKey: Self.cellularPhotosKey)
        cellularVideos = UserDefaults.standard.bool(forKey: Self.cellularVideosKey)
        syncAlbums = UserDefaults.standard.bool(forKey: Self.syncAlbumsKey)
    }

    /// Disuntik sekali dari akar aplikasi.
    ///
    /// Layanan ini harus bisa dijangkau tugas latar, yang tidak punya view dan
    /// tidak bisa menerima apa pun lewat environment — karena itu singleton, dan
    /// karena itu sesinya dipasang belakangan.
    func configure(session: SessionManager) {
        guard repo == nil else { return }
        attach(session)
    }

    /// Menyiapkan diri sendiri ketika tidak ada yang bisa menyuntikkan apa pun.
    ///
    /// Saat iOS meluncurkan aplikasi ini di latar hanya untuk menyampaikan hasil
    /// transfer, SwiftUI belum tentu membangun satu scene pun — dan `configure`
    /// dipanggil dari sana. Tanpa jalan cadangan ini, unggahan lanjutan di latar
    /// selalu berhenti pada `repo == nil`, diam-diam.
    ///
    /// `SessionManager` sendiri yang tahu cara memulihkan kredensialnya dari
    /// penyimpanan, jadi yang perlu dilakukan hanya membuatnya dan menunggu.
    func ensureConfigured() async {
        guard repo == nil else { return }
        let session = SessionManager()
        await session.restore()
        attach(session)
    }

    private func attach(_ session: SessionManager) {
        let api = APIClient(session: session)
        repo = BackupRepository(api: api)
        albumRepo = AlbumRepository(api: api)
    }

    /// Mencari pekerjaan baru, lalu menyerahkannya.
    ///
    /// **Inilah yang membuat pencadangan bisa berlanjut tanpa aplikasi dibuka.**
    /// Sesi latar hanya meneruskan transfer yang SUDAH diserahkan padanya; foto
    /// yang baru diambil setelah aplikasinya ditutup tidak dikenalnya sama
    /// sekali. Yang bisa menemukannya cuma kode ini, dan kode ini hanya berjalan
    /// saat iOS memberi aplikasi ini kesempatan hidup sebentar.
    ///
    /// Ada dua kesempatan semacam itu, dan keduanya dipakai: tugas latar
    /// terjadwal (`BackupScheduler`), dan momen tepat setelah sesi latar selesai
    /// menyampaikan hasilnya. Yang kedua membuatnya berantai — selama masih ada
    /// sisa, tiap penyelesaian membangunkan aplikasi ini untuk mengantre lagi.
    func continueInBackground() async {
        guard isEnabled else { return }
        await ensureConfigured()
        await prepare()
        start()
    }

    // MARK: - Hitungan

    /// Menghitung ulang tiga angka di layar Backup.
    ///
    /// Murah: satu enumerasi daftar yang sudah ada di memori, plus satu kueri
    /// id yang sudah berpasangan. Tidak ada byte foto yang dibaca di sini.
    func refreshCounts() {
        let photos = LocalPhotoLibrary.shared.photos
        let uploaded = dataManager.uploadedLocalIdentifiers()
        total = photos.count
        backedUp = photos.reduce(into: 0) { count, photo in
            if uploaded.contains(photo.id) { count += 1 }
        }
    }

    /// Memastikan daftar foto perangkat sudah terbaca, lalu menghitung ulang.
    ///
    /// Tanpa ini ketiga angkanya nol setiap kali layar Backup dibuka sebelum tab
    /// Photos pernah disentuh — dan nol yang berarti "belum dibaca" tidak bisa
    /// dibedakan dari nol yang berarti "semuanya sudah aman". Dua keadaan yang
    /// berlawanan, angka yang sama.
    ///
    /// Aman dipanggil berulang: `load()` hanya membaca ulang kalau pilihan
    /// albumnya memang berubah.
    func prepare() async {
        // Izin belum pernah diberikan DAN belum ada album dipilih berarti tidak
        // ada apa pun yang bisa dibaca — dan `load()` akan memunculkan permintaan
        // izin sistem untuk sesuatu yang tidak pernah diminta pengguna.
        guard LocalPhotoLibrary.shared.isAuthorized
                || !LocalPhotoLibrary.shared.selectedAlbumIDs.isEmpty
        else {
            refreshCounts()
            return
        }
        // `prompt: isEnabled` — bertanya di pembukaan aplikasi hanya kalau
        // pencadangan memang menyala. Itu yang menutup lubang lama: sakelar yang
        // sudah menyala sejak versi sebelumnya tidak pernah memicu dialognya.
        await BackupNotifier.shared.ensureAuthorization(prompt: isEnabled)
        await LocalPhotoLibrary.shared.load()
        refreshCounts()
    }

    // MARK: - Unggah

    /// Dipanggil saat aplikasi dibuka atau kembali aktif.
    func start() {
        guard isEnabled, task == nil, repo != nil else { return }
        // Masih ada yang menunggu jawaban dari sistem. Menyerahkan lagi sekarang
        // berarti foto yang sama diantre dua kali — catatan unggahannya belum
        // tertulis, jadi penyaring "sudah pernah naik" belum mengenalnya.
        guard pendingPhotos.isEmpty else { return }
        guard NetworkMonitor.shared.isOnline else { return }

        let uploaded = dataManager.uploadedLocalIdentifiers()
        // Yang jaringannya belum mengizinkan disaring DI SINI, bukan dilewati di
        // tengah putaran: kalau tidak, "3 dari 40" akan berhenti di angka empat
        // dan terlihat seperti macet, padahal 36 sisanya memang sedang menunggu
        // Wi‑Fi.
        let pending = LocalPhotoLibrary.shared.photos.filter {
            !uploaded.contains($0.id) && allowsNetwork(for: $0)
        }
        guard !pending.isEmpty else { return }

        isUploading = true
        uploadedThisRun = 0
        pendingThisRun = pending.count
        failures = []
        lastError = nil
        BackupNotifier.shared.begin(total: pending.count)

        // Task ini selesai begitu semuanya DISERAHKAN, bukan begitu semuanya
        // terkirim. Yang menutup putarannya `finishUpload`, dipanggil sistem
        // saat tiap transfer benar-benar rampung.
        task = Task { [weak self] in
            await self?.upload(pending)
            self?.task = nil
            self?.refreshCounts()
        }
    }

    /// Mengunggah foto tertentu SEKARANG, atas permintaan langsung.
    ///
    /// Terpisah dari `start()`, dan syaratnya lebih longgar: yang ini tidak
    /// menuntut pencadangan otomatis dinyalakan, dan tidak menunggu Wi‑Fi.
    /// Pengguna baru saja menunjuk foto ini dan menekan "Upload" — menahannya
    /// atas nama setelan yang mengatur pekerjaan LATAR akan terbaca sebagai
    /// tombol yang rusak.
    ///
    /// - Parameter ids: id petak, boleh berawalan `device:` maupun tidak.
    func uploadNow(_ ids: [String]) async {
        guard repo != nil, task == nil else { return }
        let wanted = Set(ids.map(LocalPhotoLibrary.localIdentifier(from:)))
        let uploaded = dataManager.uploadedLocalIdentifiers()
        let pending = LocalPhotoLibrary.shared.photos.filter {
            wanted.contains($0.id) && !uploaded.contains($0.id)
        }
        guard !pending.isEmpty else { return }

        isUploading = true
        uploadedThisRun = 0
        pendingThisRun = pending.count
        failures = []
        lastError = nil

        let work = Task { await upload(pending) }
        task = work
        await work.value
        task = nil
        refreshCounts()
    }

    func stop() {
        task?.cancel()
        task = nil
        isUploading = false
        // Antreannya IKUT dibuang.
        //
        // Transfer yang sudah di tangan sistem tetap berjalan dan hasilnya tetap
        // dicatat — itu yang diinginkan. Yang tidak diinginkan: tiap
        // penyelesaian menerbitkan ulang kemajuan yang barusan dihapus, dan yang
        // terakhir mengumumkan "Backup Complete" untuk putaran yang justru
        // dihentikan paksa. Membuangnya juga melepas `start()`, yang menolak
        // berjalan selama masih ada yang tercatat menunggu.
        pendingPhotos.removeAll()
        // Kemajuan yang membeku di "12 of 40" selamanya lebih membingungkan
        // daripada tidak ada apa-apa.
        BackupNotifier.shared.clearProgress()
    }

    /// Menunggu putaran yang sedang berjalan sampai habis.
    ///
    /// Dipakai tugas latar, yang WAJIB memanggil `setTaskCompleted` — dan tidak
    /// boleh memanggilnya sebelum kerjanya betul-betul selesai.
    ///
    /// `task` dibaca sebelum penangguhan pertama, jadi nilainya masih yang baru
    /// dipasang `start()`: putaran itu terikat main actor dan tidak bisa mulai
    /// berjalan — apalagi membereskan dirinya — selagi kita masih memegang actor.
    func waitUntilFinished() async {
        await task?.value
    }

    /// Jaringan mengizinkan foto INI naik sekarang.
    ///
    /// `isExpensive` menangkap seluler DAN hotspot — keduanya berkuota, dan
    /// keduanya sama-sama tidak diharapkan menelan pustaka foto seseorang.
    func allowsNetwork(for photo: LocalPhoto) -> Bool {
        guard NetworkMonitor.shared.isOnline else { return false }
        guard NetworkMonitor.shared.isExpensive else { return true }
        return photo.isVideo ? cellularVideos : cellularPhotos
    }

    /// Ada sesuatu yang bisa naik dengan jaringan yang ada sekarang.
    var canUploadNow: Bool {
        guard NetworkMonitor.shared.isOnline else { return false }
        guard NetworkMonitor.shared.isExpensive else { return true }
        return cellularPhotos || cellularVideos
    }

    /// Satu per satu, berurutan.
    ///
    /// Bukan karena tidak bisa berbarengan, tapi karena tiap unggahan menahan
    /// SELURUH berkas di memori — beberapa video 4K sekaligus akan membuat
    /// sistem menghentikan aplikasinya. Berurutan juga membuat kemajuan yang
    /// ditampilkan jujur.
    private func upload(_ photos: [LocalPhoto]) async {
        guard let repo else { return }
        albumIDsByName = [:]

        // Penanda "masih ada yang akan menyusul".
        //
        // Loop ini melepaskan main actor di tiap `await` — membaca berkas, lalu
        // menghitung checksum. Selama jeda itu, hasil unggahan PERTAMA bisa saja
        // sudah kembali (server yang menolak cepat menjawab dalam milidetik),
        // dan `pendingPhotos` sempat kosong padahal 39 foto lagi belum
        // diserahkan. `finishUpload` akan membaca kekosongan itu sebagai "sudah
        // selesai" dan menerbitkan "Backup Complete" di tengah putaran — lalu
        // mengulanginya di hampir setiap penyelesaian berikutnya.
        enqueueDepth += 1
        defer {
            enqueueDepth -= 1
            // Tidak ada satu pun yang sampai ke sistem: jaringan berpindah di
            // antara penyaringan di `start()` dan pemeriksaan ulang di sini,
            // atau semua berkasnya gagal dibaca. Tanpa penutupan di sini,
            // `finishUpload` tidak akan pernah dipanggil — `isUploading`
            // tersangkut menyala selamanya, dan "0 of N" menetap di pusat
            // pemberitahuan tanpa pernah ada pasangannya.
            if enqueueDepth == 0 && pendingPhotos.isEmpty { finishRun() }
        }

        for photo in photos {
            if Task.isCancelled { return }
            // Jaringan bisa berpindah di tengah jalan; diperiksa ulang di batas
            // foto, bukan di tengah satu unggahan.
            guard allowsNetwork(for: photo) else { continue }

            guard let file = await LocalPhotoLibrary.shared.originalData(
                for: LocalPhotoLibrary.assetID(for: photo.id))
            else {
                failures.append(photo.id)
                lastError = String(localized: "Could not read the file from this device.")
                continue
            }

            let checksum = await repo.checksum(for: file.data)
            // Diperiksa LAGI, tepat sebelum dicatat. Pembatalan bisa datang
            // selama dua `await` di atas, dan foto yang telanjur tercatat akan
            // memblokir `start()` berikutnya sampai jawabannya datang.
            if Task.isCancelled { return }
            pendingPhotos[photo.id] = photo

            do {
                let prepared = try await repo.makeUploadRequest(
                    data: file.data,
                    filename: file.filename,
                    checksum: checksum,
                    // `PHAsset.localIdentifier`, bukan checksum: yang diminta
                    // server adalah id foto ini DI PERANGKAT INI, dan itu yang
                    // membuatnya bisa mengenali unggahan ulang dari sumber yang
                    // sama.
                    deviceAssetId: photo.id,
                    createdAt: photo.createdAt,
                    modifiedAt: photo.createdAt)

                // DISERAHKAN, bukan ditunggu.
                //
                // Yang mengirimkannya `nsurlsessiond`, dan ia tidak peduli
                // apakah aplikasi ini masih hidup. Hasilnya masuk lewat
                // `finishUpload`, bisa jadi berjam-jam kemudian di proses yang
                // sama sekali baru.
                BackupUploader.shared.enqueue(
                    prepared,
                    localIdentifier: photo.id,
                    checksum: checksum,
                    allowsCellular: photo.isVideo ? cellularVideos : cellularPhotos)
            } catch {
                pendingPhotos[photo.id] = nil
                failures.append(photo.id)
                lastError = error.localizedDescription
            }
        }
    }

    /// Hasil satu unggahan, dari `BackupUploader`.
    ///
    /// Bisa dipanggil di proses yang BARU DILUNCURKAN sistem hanya untuk
    /// menyampaikan ini — jadi tidak boleh mengandaikan apa pun masih tersisa
    /// dari sesi sebelumnya. `pendingPhotos` memang kosong di keadaan itu, dan
    /// yang hilang cuma penempatan album; catatannya sendiri tetap tertulis.
    func finishUpload(
        localIdentifier: String, checksum: String, outcome: Result<String, Error>
    ) {
        switch outcome {
        case .success(let assetID):
            try? dataManager.insertBackupRecord(BackupRecord(
                id: UUID().uuidString,
                assetId: assetID,
                deviceAssetId: checksum,
                localIdentifier: localIdentifier))
            uploadedThisRun += 1
            // Kemajuan HANYA kalau masih ada sisa.
            //
            // Kalau ini yang terakhir, `finish()` di bawah akan membuangnya
            // beberapa mikrodetik kemudian — dan `add` maupun
            // `removeDeliveredNotifications` sama-sama tidak sinkron, jadi
            // urutan tibanya tidak dijamin. Yang sempat terlihat: dua
            // pemberitahuan berdampingan, "1 of 1 uploaded" bertahan di bawah
            // "Backup Complete". Tidak diterbitkan sama sekali lebih sederhana
            // daripada diterbitkan lalu dikejar penghapusannya.
            // Diukur dari PUTARANNYA, bukan dari antrean yang sedang menunggu.
            //
            // Unggahannya diserahkan satu per satu, jadi saat hasilnya kembali
            // `pendingPhotos.count` hampir selalu tepat 1 — gerbang lama itu
            // membuat kemajuan tidak pernah terbit sama sekali.
            if isUploading, uploadedThisRun < pendingThisRun {
                BackupNotifier.shared.progress(
                    uploaded: uploadedThisRun, total: pendingThisRun)
            }

            if syncAlbums, let photo = pendingPhotos[localIdentifier] {
                Task { await placeInAlbum(assetID, from: photo) }
            }

        case .failure(let error):
            failures.append(localIdentifier)
            // Alasannya DISIMPAN, bukan dibuang.
            //
            // Sebelumnya kegagalan hanya menambah satu angka, dan angka itu sama
            // saja bunyinya untuk kredensial kedaluwarsa, server yang tidak
            // terjangkau, dan berkas yang ditolak. Tidak ada yang bisa dilakukan
            // pengguna dengan "gagal" — ada banyak yang bisa dilakukannya dengan
            // "Unauthorized".
            lastError = error.localizedDescription
        }

        pendingPhotos[localIdentifier] = nil
        refreshCounts()

        // Selesai kalau tidak ada lagi yang ditunggu. Antreannya dikosongkan
        // satu per satu oleh sistem, jadi inilah satu-satunya tempat yang tahu
        // kapan putarannya benar-benar habis.
        // `enqueueDepth` ikut diperiksa: antrean yang kosong sekarang belum
        // tentu antrean yang habis — bisa jadi sisanya memang belum sempat
        // diserahkan.
        if enqueueDepth == 0 && pendingPhotos.isEmpty { finishRun() }
    }

    /// Menutup putaran, sekali saja.
    ///
    /// Dipanggil dari dua arah — penyelesaian terakhir, dan akhir pengantrean
    /// yang ternyata tidak menyerahkan apa pun — jadi penjaga `isUploading` di
    /// depan bukan basa-basi: tanpa itu "Backup Complete" bisa terbit dua kali
    /// untuk satu putaran.
    private func finishRun() {
        guard isUploading else { return }
        isUploading = false
        lastRunAt = Date()
        BackupNotifier.shared.finish(uploaded: uploadedThisRun, failed: failures.count)
    }

    // MARK: - Sinkronisasi album

    /// Menaruh aset di album server bernama sama dengan album perangkatnya.
    ///
    /// Kegagalannya DIAM dan tidak membatalkan apa pun: fotonya sudah aman di
    /// server, dan itu yang penting. Gagal menaruhnya ke album adalah kerapian
    /// yang tertunda, bukan data yang hilang — percobaan berikutnya akan
    /// menemukannya lagi lewat "Organize into Albums".
    private func placeInAlbum(_ assetID: String, from photo: LocalPhoto) async {
        guard let name = LocalPhotoLibrary.shared.albumTitles[photo.id] else { return }
        guard let albumID = await albumID(named: name) else { return }
        _ = try? await albumRepo?.addAssets([assetID], to: albumID)
    }

    /// Id album server dengan nama ini, dibuatkan kalau belum ada.
    private func albumID(named name: String) async -> String? {
        if let cached = albumIDsByName[name] { return cached }
        guard let albumRepo else { return nil }

        if let existing = try? await albumRepo.all().first(where: { $0.albumName == name }) {
            albumIDsByName[name] = existing.id
            return existing.id
        }
        guard let created = try? await albumRepo.create(name: name) else { return nil }
        albumIDsByName[name] = created.id
        return created.id
    }

    /// "Organize into Albums": menyusun ulang aset yang SUDAH ada di server ke
    /// dalam album, memakai pilihan album yang berlaku sekarang.
    ///
    /// Gunanya untuk yang sudah terunggah sebelum sakelar ini dinyalakan — tanpa
    /// ini, satu-satunya cara merapikannya adalah mengunggah ulang semuanya.
    func organizeIntoAlbums() async {
        // `isUploading` TIDAK disentuh di sini. Menyalakannya membuat layar
        // Backup menggambar bilah kemajuan unggahan dengan angka putaran
        // sebelumnya — kemajuan palsu untuk pekerjaan yang berbeda. Tombolnya
        // sendiri sudah menunjukkan spinner-nya.
        guard albumRepo != nil else { return }
        albumIDsByName = [:]
        let links = dataManager.serverAssetIDsByLocalIdentifier()

        for photo in LocalPhotoLibrary.shared.photos {
            if Task.isCancelled { return }
            guard let assetID = links[photo.id] else { continue }
            await placeInAlbum(assetID, from: photo)
        }
    }
}
