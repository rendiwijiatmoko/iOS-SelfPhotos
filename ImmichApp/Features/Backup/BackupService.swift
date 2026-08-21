import Foundation
import Observation

private enum LivePhotoBackupError: LocalizedError {
    case motionResourceMissing
    case primaryResourceMissing
    case sessionUnavailable
    case assetNoLongerLivePhoto

    var errorDescription: String? {
        switch self {
        case .motionResourceMissing:
            String(localized: "The motion part of this Live Photo could not be read.")
        case .primaryResourceMissing:
            String(localized: "The photo part of this Live Photo could not be read.")
        case .sessionUnavailable:
            String(localized: "The upload session is no longer available.")
        case .assetNoLongerLivePhoto:
            String(localized: "This asset is no longer available as a Live Photo.")
        }
    }
}

private struct BackupPersistenceError: LocalizedError {
    var errorDescription: String? {
        String(localized: "Backup is paused because its local upload mapping cannot be saved safely.")
    }
}

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
                stop()
                BackupScheduler.cancel()
                BackupNotifier.shared.clearProgress()
                return
            }
            // Izin pemberitahuan diminta TEPAT di sini: pengguna baru saja
            // meminta pekerjaan yang berjalan tanpa dilihat, jadi alasan untuk
            // memberitahunya sudah jelas di layar.
            Task { await BackupNotifier.shared.ensureAuthorization(prompt: true) }
            BackupScheduler.schedule()
            Task { [weak self] in
                await self?.prepare()
                guard !Task.isCancelled else { return }
                self?.start()
            }
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
    private(set) var waitingForNetwork = 0
    private(set) var waitingForICloud = 0
    private(set) var waitingForAuthentication = 0
    private(set) var scheduledForRetry = 0
    private(set) var queueStatusTitle: String?
    private(set) var queueStatusBody: String?
    /// Item persisten yang sedang menunggu, aktif, atau gagal. Layar detail
    /// membaca daftar yang sama dengan scheduler dan notifikasi.
    private(set) var uploadItems: [BackupQueueItem] = []
    /// Progress byte hanya relevan selama proses hidup; lifecycle item sendiri
    /// tetap disimpan di `BackupQueueStore`.
    private(set) var uploadProgressByID: [String: Double] = [:]

    private static let enabledKey = "backup.enabled"
    private static let cellularPhotosKey = "backup.cellularPhotos"
    private static let cellularVideosKey = "backup.cellularVideos"
    private static let syncAlbumsKey = "backup.syncAlbums"

    private var repo: BackupRepository?
    private var albumRepo: AlbumRepository?
    private weak var session: SessionManager?
    private let dataManager = SwiftDataManager.shared
    private let queue = BackupQueueStore.shared
    private var task: Task<Void, Never>?
    private var libraryChangeTask: Task<Void, Never>?
    private var retryWakeTask: Task<Void, Never>?
    private var notificationRevision = 0
    private static let automaticBatchSize = 100
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
    /// Hasil transfer lama dapat tiba sesudah logout. Jangan tulis hasil itu ke
    /// database yang sudah menjadi milik sesi berikutnya.
    private var acceptsUploadResults = true
    /// False setelah server menjawab 401. Queue tetap ada, tetapi seluruh task
    /// berhenti membawa token lama sampai pengguna masuk kembali.
    private var hasAuthenticatedSession = true

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        cellularPhotos = UserDefaults.standard.bool(forKey: Self.cellularPhotosKey)
        cellularVideos = UserDefaults.standard.bool(forKey: Self.cellularVideosKey)
        syncAlbums = UserDefaults.standard.bool(forKey: Self.syncAlbumsKey)
        LocalPhotoLibrary.shared.onLibraryChange = { [weak self] in
            self?.handleLibraryChange()
        }
        NetworkMonitor.shared.onPathChange = { [weak self] online, expensive in
            self?.handleNetworkChange(isOnline: online, isExpensive: expensive)
        }
        applyQueueSnapshot(notify: false)
    }

    /// Disuntik sekali dari akar aplikasi.
    ///
    /// Layanan ini harus bisa dijangkau tugas latar, yang tidak punya view dan
    /// tidak bisa menerima apa pun lewat environment — karena itu singleton, dan
    /// karena itu sesinya dipasang belakangan.
    func configure(session: SessionManager) {
        guard repo == nil else { return }
        attach(session)
        guard isEnabled, acceptsUploadResults else { return }
        BackupScheduler.schedule()
        Task { [weak self] in
            await self?.prepare()
            self?.start()
        }
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
        // Tugas latar dapat membangunkan proses setelah logout. Jangan membuat
        // repository tanpa sesi lalu mencoba mengantre unggahan anonim.
        guard session.isLoggedIn else { return }
        attach(session)
    }

    private func attach(_ session: SessionManager) {
        self.session = session
        let api = APIClient(session: session)
        repo = BackupRepository(api: api)
        albumRepo = AlbumRepository(api: api)
        acceptsUploadResults = dataManager.isPersistentStoreAvailable
        hasAuthenticatedSession = true
        do {
            if let owner = session.backupQueueOwner {
                _ = try queue.bind(to: owner)
            }
            try queue.releaseAuthenticationWaits()
            applyQueueSnapshot()
        } catch {
            lastError = error.localizedDescription
            acceptsUploadResults = false
        }
    }

    /// Dipanggil sejak launch, termasuk cold launch yang hanya terjadi karena
    /// URLSession menyampaikan event. Task sistem direkonsiliasi sebelum scan
    /// baru agar tidak pernah ada dua executor untuk satu aset.
    func restoreBackgroundLifecycle() async {
        BackupUploader.shared.reconnect()
        do {
            let activeTasks = await BackupUploader.shared.activeTasks()
            try queue.reconcile(activeTasks: activeTasks)
            for item in queue.items where item.state == .cancelling {
                await BackupUploader.shared.cancel(localIdentifier: item.id)
            }
            await BackupUploader.shared.resumeTasks(identifiers: Set(
                activeTasks.filter {
                    $0.isSuspended
                        && queue.item(id: $0.context.localIdentifier)?.state != .cancelling
                }.map(\.taskIdentifier)))
        } catch {
            lastError = error.localizedDescription
            acceptsUploadResults = false
        }
        applyQueueSnapshot()
    }

    private func handleNetworkChange(isOnline: Bool, isExpensive: Bool) {
        guard isEnabled, isOnline else {
            applyQueueSnapshot()
            return
        }
        do {
            if !isExpensive || canUploadNow { try queue.releaseNetworkWaits() }
        } catch {
            lastError = error.localizedDescription
            acceptsUploadResults = false
            return
        }
        BackupScheduler.schedule()
        Task { [weak self] in
            await self?.continueInBackground()
        }
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
        guard isEnabled, repo != nil, !Task.isCancelled else { return }
        await NetworkMonitor.shared.waitUntilReady()
        guard !Task.isCancelled else { return }
        await prepare()
        guard !Task.isCancelled else { return }
        start()
    }

    /// PhotoKit memberi perubahan ketika aplikasi aktif/diberi waktu eksekusi.
    /// Digabung satu detik karena satu impor dapat menghasilkan banyak callback.
    private func handleLibraryChange() {
        guard isEnabled else { return }
        libraryChangeTask?.cancel()
        libraryChangeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            await self.prepare()
            guard !Task.isCancelled else { return }
            self.start()
            BackupScheduler.schedule()
        }
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
        guard isEnabled, task == nil, repo != nil, hasAuthenticatedSession else { return }
        guard dataManager.isPersistentStoreAvailable else {
            lastError = BackupPersistenceError().localizedDescription
            return
        }
        task = Task { [weak self] in
            await self?.enqueueAutomaticBatch()
            self?.task = nil
            self?.refreshCounts()
            self?.applyQueueSnapshot()
        }
    }

    /// Memulihkan antrean URLSession lebih dulu, lalu mengambil maksimal 100
    /// kandidat TERBARU. Batas yang sama dipakai Immich agar satu jatah singkat
    /// iOS cukup untuk menyerahkan pekerjaan ke daemon background.
    private func enqueueAutomaticBatch() async {
        await NetworkMonitor.shared.waitUntilReady()
        guard !Task.isCancelled else { return }

        do {
            let activeTasks = await BackupUploader.shared.activeTasks()
            try queue.reconcile(activeTasks: activeTasks)
            for item in queue.items where item.state == .cancelling {
                await BackupUploader.shared.cancel(localIdentifier: item.id)
            }
            await BackupUploader.shared.resumeTasks(identifiers: Set(
                activeTasks.filter {
                    $0.isSuspended
                        && queue.item(id: $0.context.localIdentifier)?.state != .cancelling
                }.map(\.taskIdentifier)))
        } catch {
            lastError = error.localizedDescription
            acceptsUploadResults = false
            applyQueueSnapshot()
            return
        }
        let active = await BackupUploader.shared.activeLocalIdentifiers()
        let uploaded = dataManager.uploadedLocalIdentifiers()
        let pending = LocalPhotoLibrary.shared.photos
            .filter { !uploaded.contains($0.id) && !active.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(Self.automaticBatchSize)
        do {
            try queue.enqueue(pending.map(\.id))
        } catch {
            lastError = error.localizedDescription
            acceptsUploadResults = false
            applyQueueSnapshot()
            return
        }
        applyQueueSnapshot()
        await processReadyQueueItems()
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
        guard dataManager.isPersistentStoreAvailable else {
            lastError = BackupPersistenceError().localizedDescription
            return
        }
        let wanted = Set(ids.map(LocalPhotoLibrary.localIdentifier(from:)))
        let uploaded = dataManager.uploadedLocalIdentifiers()
        let pending = LocalPhotoLibrary.shared.photos.filter {
            wanted.contains($0.id) && !uploaded.contains($0.id)
        }
        guard !pending.isEmpty else { return }

        do {
            try queue.enqueue(pending.map(\.id))
            try queue.retryFailed()
        } catch {
            lastError = error.localizedDescription
            return
        }
        applyQueueSnapshot()
        let work = Task { await processReadyQueueItems() }
        task = work
        await work.value
        task = nil
        refreshCounts()
    }

    func stop() {
        task?.cancel()
        task = nil
        libraryChangeTask?.cancel()
        libraryChangeTask = nil
        retryWakeTask?.cancel()
        retryWakeTask = nil
        // Hanya metadata album di RAM yang dibuang. Queue persisten dan transfer
        // yang sudah berada di tangan sistem tetap ada; BGTask yang kedaluwarsa
        // tidak boleh mengubah penghentian proses menjadi kehilangan pekerjaan.
        pendingPhotos.removeAll()
        applyQueueSnapshot()
    }

    /// Menghentikan backup dan membuang semua state yang terikat akun.
    func resetForLogout() {
        acceptsUploadResults = false
        stop()
        repo = nil
        albumRepo = nil
        session = nil
        albumIDsByName.removeAll()
        total = 0
        backedUp = 0
        uploadedThisRun = 0
        pendingThisRun = 0
        failures = []
        lastError = nil
        lastRunAt = nil
        waitingForNetwork = 0
        waitingForICloud = 0
        waitingForAuthentication = 0
        scheduledForRetry = 0
        queueStatusTitle = nil
        queueStatusBody = nil
        uploadItems = []
        uploadProgressByID = [:]
        hasAuthenticatedSession = false
        try? queue.clear()

        // Setelan backup termasuk state akun: akun baru tidak boleh langsung
        // mengunggah album yang dipilih oleh akun sebelumnya.
        isEnabled = false
        cellularPhotos = false
        cellularVideos = false
        syncAlbums = false
        applyQueueSnapshot()
    }

    /// Berbeda dari logout eksplisit: token yang ditolak tidak membuang queue
    /// atau mapping upload. Setelah login kembali, item dilepas otomatis tanpa
    /// pengguna harus membuka halaman Backup.
    func pauseForAuthentication() {
        hasAuthenticatedSession = false
        repo = nil
        albumRepo = nil
        task?.cancel()
        task = nil
        pendingPhotos.removeAll()
        let message = String(localized: "Your Immich session expired. Sign in again to resume backup.")
        do {
            try queue.markAllWaitingForAuthentication(error: message)
        } catch {
            lastError = error.localizedDescription
        }
        applyQueueSnapshot()
    }

    func retryFailedUploads() {
        do {
            try queue.retryFailed()
            applyQueueSnapshot()
            start()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func retryUpload(_ localIdentifier: String) {
        do {
            try queue.retryFailed(localIdentifier)
            uploadProgressByID[localIdentifier] = nil
            applyQueueSnapshot()
            start()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Menghapus pekerjaan yang belum aktif dari queue persisten. Transfer yang
    /// sedang menyiapkan atau mengirim file harus melewati `cancelUpload(_:)`
    /// agar callback URLSession tetap punya record untuk diselesaikan.
    func removeUpload(_ localIdentifier: String) {
        guard let item = queue.item(id: localIdentifier),
              !item.state.isActive
        else { return }

        do {
            try queue.discard(localIdentifier)
            pendingPhotos[localIdentifier] = nil
            uploadProgressByID[localIdentifier] = nil
            applyQueueSnapshot()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Cancel memindahkan item ke state terminal yang dapat di-Retry. Transfer
    /// aktif menunggu callback URLSession agar tidak balapan dengan completion;
    /// item yang masih menyiapkan file bisa langsung ditandai gagal.
    func cancelUpload(_ localIdentifier: String) {
        guard let item = queue.item(id: localIdentifier), item.state.isActive else { return }
        let canceledMessage = String(localized: "Upload canceled.")

        do {
            if item.state == .uploading {
                try queue.markCancelling(localIdentifier)
                applyQueueSnapshot()
                Task { [weak self] in
                    let found = await BackupUploader.shared.cancel(
                        localIdentifier: localIdentifier)
                    guard let self, !found,
                          self.queue.item(id: localIdentifier)?.state == .cancelling
                    else { return }
                    try? self.queue.markFailed(localIdentifier, error: canceledMessage)
                    self.uploadProgressByID[localIdentifier] = nil
                    self.applyQueueSnapshot()
                }
            } else if item.state == .preparing {
                try queue.markFailed(localIdentifier, error: canceledMessage)
                pendingPhotos[localIdentifier] = nil
                uploadProgressByID[localIdentifier] = nil
                applyQueueSnapshot()
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Dipanggil URLSession delegate selama badan multipart dikirim.
    func reportUploadProgress(
        localIdentifier: String,
        phase: BackupUploadPhase,
        bytesSent: Int64,
        totalBytesExpected: Int64
    ) {
        guard totalBytesExpected > 0,
              let item = queue.item(id: localIdentifier),
              item.state == .uploading
        else { return }

        let fraction = min(1, max(0, Double(bytesSent) / Double(totalBytesExpected)))
        if phase == .livePhotoMotion {
            uploadProgressByID[localIdentifier] = fraction * 0.5
        } else if item.motionAssetID != nil {
            uploadProgressByID[localIdentifier] = 0.5 + fraction * 0.5
        } else {
            uploadProgressByID[localIdentifier] = fraction
        }
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
        if photo.isLivePhoto { return cellularPhotos && cellularVideos }
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
    private func processReadyQueueItems() async {
        guard let repo else { return }
        albumIDsByName = [:]

        let ready = queue.readyItems(limit: Self.automaticBatchSize)
        guard !ready.isEmpty else {
            applyQueueSnapshot()
            return
        }
        var photos: [LocalPhoto] = []
        for item in ready {
            if let cached = LocalPhotoLibrary.shared.photos.first(where: { $0.id == item.id }) {
                photos.append(cached)
            } else if let restored = await LocalPhotoLibrary.shared.photoMetadata(for: item.id) {
                photos.append(restored)
            } else {
                try? queue.markFailed(
                    item.id,
                    error: String(localized: "This asset is no longer available on the device."))
            }
        }
        applyQueueSnapshot()

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
            if enqueueDepth == 0 { finishRunIfSettled() }
        }

        for photo in photos {
            if Task.isCancelled { return }
            // Live Photo tidak boleh terpotong menjadi still image ketika opsi
            // video seluler dimatikan. Kedua izin harus aktif agar pasangan
            // lengkap boleh naik melalui jaringan mahal.
            let allowsCellular = photo.isLivePhoto
                ? (cellularPhotos && cellularVideos)
                : (photo.isVideo ? cellularVideos : cellularPhotos)
            let mayReadFromICloud = !NetworkMonitor.shared.isExpensive || allowsCellular

            guard allowsNetwork(for: photo) else {
                do {
                    try queue.markRetry(
                        photo.id,
                        state: .waitingForNetwork,
                        error: NetworkMonitor.shared.isOnline
                            ? String(localized: "Waiting for Wi-Fi.")
                            : String(localized: "Waiting for a network connection."),
                        retryAt: Date(timeIntervalSinceNow: 15 * 60))
                } catch { lastError = error.localizedDescription }
                applyQueueSnapshot()
                continue
            }

            if photo.isLivePhoto {
                do {
                    if let motionAssetID = queue.item(id: photo.id)?.motionAssetID {
                        try queue.markPreparing(
                            photo.id,
                            phase: .primaryAsset,
                            motionAssetID: motionAssetID)
                        applyQueueSnapshot()
                        try await enqueueLivePhotoPrimary(
                            photo,
                            motionAssetID: motionAssetID,
                            repository: repo,
                            allowsCellular: allowsCellular,
                            mayReadFromICloud: mayReadFromICloud)
                    } else {
                        try queue.markPreparing(photo.id, phase: .livePhotoMotion)
                        applyQueueSnapshot()
                        try await enqueueLivePhoto(
                            photo,
                            repository: repo,
                            allowsCellular: allowsCellular,
                            mayReadFromICloud: mayReadFromICloud)
                    }
                } catch {
                    pendingPhotos[photo.id] = nil
                    handlePreparationFailure(
                        localIdentifier: photo.id,
                        error: error,
                        waitingForICloud: mayReadFromICloud)
                }
                applyQueueSnapshot()
                continue
            }

            do {
                try queue.markPreparing(photo.id, phase: .primaryAsset)
                applyQueueSnapshot()
            } catch {
                lastError = error.localizedDescription
                acceptsUploadResults = false
                continue
            }

            guard let file = await LocalPhotoLibrary.shared.originalFile(
                for: LocalPhotoLibrary.assetID(for: photo.id),
                allowsNetworkFallback: mayReadFromICloud)
            else {
                // Berkas iCloud yang sedang menunggu Wi‑Fi bukan kegagalan. Ia
                // akan ditemukan lagi oleh BGTask berikutnya di jaringan sesuai.
                let message = mayReadFromICloud
                    ? String(localized: "The original file is still downloading from iCloud.")
                    : String(localized: "Waiting for Wi-Fi to download the original from iCloud.")
                try? queue.markRetry(
                    photo.id,
                    state: .waitingForICloud,
                    error: message,
                    retryAt: Date(timeIntervalSinceNow: 15 * 60))
                applyQueueSnapshot()
                continue
            }

            do {
                let checksum = try await repo.checksum(forFile: file.url)
                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: file.url)
                    return
                }
                let prepared = try await repo.makeUploadRequest(
                    fileURL: file.url,
                    filename: file.filename,
                    checksum: checksum,
                    // `PHAsset.localIdentifier`, bukan checksum: yang diminta
                    // server adalah id foto ini DI PERANGKAT INI, dan itu yang
                    // membuatnya bisa mengenali unggahan ulang dari sumber yang
                    // sama.
                    deviceAssetId: photo.id,
                    createdAt: photo.createdAt,
                    modifiedAt: photo.modifiedAt)
                try? FileManager.default.removeItem(at: file.url)
                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: prepared.bodyFile)
                    return
                }
                pendingPhotos[photo.id] = photo

                // DISERAHKAN, bukan ditunggu.
                //
                // Yang mengirimkannya `nsurlsessiond`, dan ia tidak peduli
                // apakah aplikasi ini masih hidup. Hasilnya masuk lewat
                // `finishUpload`, bisa jadi berjam-jam kemudian di proses yang
                // sama sekali baru.
                let uploadTask = BackupUploader.shared.makeUploadTask(
                    prepared,
                    localIdentifier: photo.id,
                    checksum: checksum,
                    allowsCellular: allowsCellular)
                do {
                    try queue.markUploading(
                        photo.id,
                        phase: .primaryAsset,
                        checksum: checksum,
                        taskIdentifier: uploadTask.taskIdentifier)
                    uploadTask.resume()
                    applyQueueSnapshot()
                } catch {
                    uploadTask.cancel()
                    try? FileManager.default.removeItem(at: prepared.bodyFile)
                    throw error
                }
            } catch {
                try? FileManager.default.removeItem(at: file.url)
                pendingPhotos[photo.id] = nil
                handlePreparationFailure(
                    localIdentifier: photo.id,
                    error: error,
                    waitingForICloud: false)
            }
        }
        applyQueueSnapshot()
    }

    /// Tahap pertama Live Photo: upload motion video sebagai hidden asset.
    /// Setelah server mengembalikan id-nya, `BackupUploader` memanggil
    /// `finishLivePhotoMotionUpload` untuk merakit tahap still image.
    private func enqueueLivePhoto(
        _ photo: LocalPhoto,
        repository: BackupRepository,
        allowsCellular: Bool,
        mayReadFromICloud: Bool
    ) async throws {
        guard let motion = await LocalPhotoLibrary.shared.livePhotoMotionFile(
            for: LocalPhotoLibrary.assetID(for: photo.id),
            allowsNetworkFallback: mayReadFromICloud)
        else { throw LivePhotoBackupError.motionResourceMissing }

        do {
            let checksum = try await repository.checksum(forFile: motion.url)
            try Task.checkCancellation()
            pendingPhotos[photo.id] = photo

            // Jika motion video sudah sampai ke server pada putaran sebelumnya
            // tetapi aplikasi mati sebelum still image sempat diantrikan, pakai
            // kembali id tersebut. Ini mencegah hidden orphan bertambah tiap
            // retry dan membuat alur dua tahap idempotent.
            let correlationID = "\(photo.id):live-photo-motion"
            if let existing = try? await repository.duplicateMatches([
                (id: correlationID, checksum: checksum),
            ]).first?.serverAssetID {
                try? FileManager.default.removeItem(at: motion.url)
                try queue.markPreparing(
                    photo.id,
                    phase: .primaryAsset,
                    motionAssetID: existing)
                applyQueueSnapshot()
                try await enqueueLivePhotoPrimary(
                    photo,
                    motionAssetID: existing,
                    repository: repository,
                    allowsCellular: allowsCellular,
                    mayReadFromICloud: mayReadFromICloud)
                return
            }

            let prepared = try await repository.makeUploadRequest(
                fileURL: motion.url,
                filename: motion.filename,
                checksum: checksum,
                deviceAssetId: photo.id,
                createdAt: photo.createdAt,
                modifiedAt: photo.modifiedAt,
                // Hidden mencegah server menjalankan job media biasa pada klip
                // motion yang hanya merupakan pasangan Live Photo.
                additionalFields: ["visibility": "hidden"])
            try? FileManager.default.removeItem(at: motion.url)
            try Task.checkCancellation()

            let uploadTask = BackupUploader.shared.makeUploadTask(
                prepared,
                localIdentifier: photo.id,
                checksum: checksum,
                allowsCellular: allowsCellular,
                phase: .livePhotoMotion)
            do {
                try queue.markUploading(
                    photo.id,
                    phase: .livePhotoMotion,
                    checksum: checksum,
                    taskIdentifier: uploadTask.taskIdentifier)
                uploadTask.resume()
                applyQueueSnapshot()
            } catch {
                uploadTask.cancel()
                try? FileManager.default.removeItem(at: prepared.bodyFile)
                throw error
            }
        } catch {
            try? FileManager.default.removeItem(at: motion.url)
            throw error
        }
    }

    /// Callback tahap motion Live Photo. Fungsi ini sengaja `async`: pada cold
    /// launch daftar PhotoKit dan repository belum tentu sudah tersedia, tetapi
    /// task description masih membawa local identifier yang dibutuhkan.
    func finishLivePhotoMotionUpload(
        localIdentifier: String,
        motionChecksum: String,
        outcome: Result<String, Error>,
        remainingBackgroundTasks: Int
    ) async {
        guard acceptsUploadResults else {
            pendingPhotos[localIdentifier] = nil
            return
        }
        if queue.item(id: localIdentifier)?.state == .cancelling {
            try? queue.markFailed(
                localIdentifier,
                error: String(localized: "Upload canceled."))
            pendingPhotos[localIdentifier] = nil
            uploadProgressByID[localIdentifier] = nil
            applyQueueSnapshot()
            if remainingBackgroundTasks == 0 && enqueueDepth == 0 {
                finishRunIfSettled()
            }
            return
        }
        switch outcome {
        case .failure(let error):
            finishUpload(
                localIdentifier: localIdentifier,
                checksum: motionChecksum,
                outcome: .failure(error),
                remainingBackgroundTasks: remainingBackgroundTasks)

        case .success(let motionAssetID):
            await ensureConfigured()
            guard let repo else {
                finishUpload(
                    localIdentifier: localIdentifier,
                    checksum: motionChecksum,
                    outcome: .failure(LivePhotoBackupError.sessionUnavailable),
                    remainingBackgroundTasks: remainingBackgroundTasks)
                return
            }
            guard let photo = await LocalPhotoLibrary.shared.photoMetadata(
                for: localIdentifier), photo.isLivePhoto else {
                finishUpload(
                    localIdentifier: localIdentifier,
                    checksum: motionChecksum,
                    outcome: .failure(LivePhotoBackupError.assetNoLongerLivePhoto),
                    remainingBackgroundTasks: remainingBackgroundTasks)
                return
            }

            pendingPhotos[localIdentifier] = photo
            let allowsCellular = cellularPhotos && cellularVideos
            let mayReadFromICloud = !NetworkMonitor.shared.isExpensive || allowsCellular
            do {
                try queue.markPreparing(
                    localIdentifier,
                    phase: .primaryAsset,
                    motionAssetID: motionAssetID)
                applyQueueSnapshot()
                try await enqueueLivePhotoPrimary(
                    photo,
                    motionAssetID: motionAssetID,
                    repository: repo,
                    allowsCellular: allowsCellular,
                    mayReadFromICloud: mayReadFromICloud)
            } catch {
                pendingPhotos[localIdentifier] = nil
                handlePreparationFailure(
                    localIdentifier: localIdentifier,
                    error: error,
                    waitingForICloud: true)
                applyQueueSnapshot()
            }
        }
    }

    /// Tahap kedua Live Photo: upload still image dengan relasi ke hidden motion
    /// asset. Hanya tahap ini yang menghasilkan `BackupRecord`.
    private func enqueueLivePhotoPrimary(
        _ photo: LocalPhoto,
        motionAssetID: String,
        repository: BackupRepository,
        allowsCellular: Bool,
        mayReadFromICloud: Bool
    ) async throws {
        guard let still = await LocalPhotoLibrary.shared.originalFile(
            for: LocalPhotoLibrary.assetID(for: photo.id),
            allowsNetworkFallback: mayReadFromICloud)
        else { throw LivePhotoBackupError.primaryResourceMissing }

        do {
            let checksum = try await repository.checksum(forFile: still.url)
            try Task.checkCancellation()
            let prepared = try await repository.makeUploadRequest(
                fileURL: still.url,
                filename: still.filename,
                checksum: checksum,
                deviceAssetId: photo.id,
                createdAt: photo.createdAt,
                modifiedAt: photo.modifiedAt,
                additionalFields: ["livePhotoVideoId": motionAssetID])
            try? FileManager.default.removeItem(at: still.url)
            try Task.checkCancellation()

            let uploadTask = BackupUploader.shared.makeUploadTask(
                prepared,
                localIdentifier: photo.id,
                checksum: checksum,
                allowsCellular: allowsCellular,
                phase: .primaryAsset)
            do {
                try queue.markUploading(
                    photo.id,
                    phase: .primaryAsset,
                    checksum: checksum,
                    taskIdentifier: uploadTask.taskIdentifier)
                uploadTask.resume()
                applyQueueSnapshot()
            } catch {
                uploadTask.cancel()
                try? FileManager.default.removeItem(at: prepared.bodyFile)
                throw error
            }
        } catch {
            try? FileManager.default.removeItem(at: still.url)
            throw error
        }
    }

    /// Hasil satu unggahan, dari `BackupUploader`.
    ///
    /// Bisa dipanggil di proses yang BARU DILUNCURKAN sistem hanya untuk
    /// menyampaikan ini — jadi tidak boleh mengandaikan apa pun masih tersisa
    /// dari sesi sebelumnya. `pendingPhotos` memang kosong di keadaan itu, dan
    /// yang hilang cuma penempatan album; catatannya sendiri tetap tertulis.
    func finishUpload(
        localIdentifier: String,
        checksum: String,
        outcome: Result<String, Error>,
        remainingBackgroundTasks: Int
    ) {
        guard acceptsUploadResults else {
            pendingPhotos[localIdentifier] = nil
            return
        }
        if dataManager.getBackupRecord(localIdentifier: localIdentifier) != nil {
            try? queue.discard(localIdentifier)
            pendingPhotos[localIdentifier] = nil
            applyQueueSnapshot()
            return
        }
        if queue.item(id: localIdentifier)?.state == .cancelling,
           case .failure = outcome {
            try? queue.markFailed(
                localIdentifier,
                error: String(localized: "Upload canceled."))
            pendingPhotos[localIdentifier] = nil
            uploadProgressByID[localIdentifier] = nil
            applyQueueSnapshot()
            if remainingBackgroundTasks == 0 && enqueueDepth == 0 {
                finishRunIfSettled()
            }
            return
        }
        // Task dari versi lama mungkin selesai tepat setelah aplikasi di-update.
        // Adopsi dulu supaya hasilnya tetap masuk sumber kebenaran yang sama.
        if queue.item(id: localIdentifier) == nil {
            try? queue.enqueue([localIdentifier])
        }
        if !hasAuthenticatedSession {
            let message = String(localized: "Your Immich session expired. Sign in again to resume backup.")
            try? queue.markAllWaitingForAuthentication(error: message)
            pendingPhotos[localIdentifier] = nil
            applyQueueSnapshot()
            return
        }
        switch outcome {
        case .success(let assetID):
            do {
                guard dataManager.isPersistentStoreAvailable else {
                    throw BackupPersistenceError()
                }
                try dataManager.upsertBackupRecord(
                    assetID: assetID,
                    checksum: checksum,
                    localIdentifier: localIdentifier)
                try queue.markCompleted(localIdentifier)
            } catch {
                lastError = error.localizedDescription
                try? queue.markRetry(
                    localIdentifier,
                    state: .retryScheduled,
                    error: error.localizedDescription,
                    retryAt: retryDate(for: localIdentifier))
            }

            if syncAlbums, let photo = pendingPhotos[localIdentifier] {
                Task { await placeInAlbum(assetID, from: photo) }
            }

        case .failure(let error):
            lastError = error.localizedDescription
            switch BackupUploadFailureDisposition.classify(error) {
            case .retryNetwork:
                try? queue.markRetry(
                    localIdentifier,
                    state: .waitingForNetwork,
                    error: error.localizedDescription,
                    retryAt: retryDate(for: localIdentifier))
            case .retryServer:
                try? queue.markRetry(
                    localIdentifier,
                    state: .retryScheduled,
                    error: error.localizedDescription,
                    retryAt: retryDate(for: localIdentifier))
            case .authenticationRequired:
                handleAuthenticationRequired()
            case .permanent:
                try? queue.markFailed(
                    localIdentifier,
                    error: error.localizedDescription)
            }
        }

        pendingPhotos[localIdentifier] = nil
        refreshCounts()
        applyQueueSnapshot()
        if remainingBackgroundTasks == 0 && enqueueDepth == 0 {
            finishRunIfSettled()
        }
    }

    private func handlePreparationFailure(
        localIdentifier: String,
        error: Error,
        waitingForICloud: Bool
    ) {
        if let state = queue.item(id: localIdentifier)?.state,
           state == .failed || state == .cancelling {
            return
        }
        lastError = error.localizedDescription
        if error is BackupQueueStoreError {
            acceptsUploadResults = false
            return
        }
        if waitingForICloud,
           error is LivePhotoBackupError {
            try? queue.markRetry(
                localIdentifier,
                state: .waitingForICloud,
                error: String(localized: "The original file is still downloading from iCloud."),
                retryAt: retryDate(for: localIdentifier))
            return
        }

        switch BackupUploadFailureDisposition.classify(error) {
        case .retryNetwork:
            try? queue.markRetry(
                localIdentifier,
                state: .waitingForNetwork,
                error: error.localizedDescription,
                retryAt: retryDate(for: localIdentifier))
        case .retryServer:
            try? queue.markRetry(
                localIdentifier,
                state: .retryScheduled,
                error: error.localizedDescription,
                retryAt: retryDate(for: localIdentifier))
        case .authenticationRequired:
            handleAuthenticationRequired()
        case .permanent:
            try? queue.markFailed(localIdentifier, error: error.localizedDescription)
        }
    }

    private func handleAuthenticationRequired() {
        pauseForAuthentication()
        Task { [weak session] in
            await session?.expireForBackgroundUpload()
            await BackupUploader.shared.cancelAll()
        }
    }

    private func retryDate(for localIdentifier: String, now: Date = .now) -> Date {
        let attempts = min(queue.item(id: localIdentifier)?.attemptCount ?? 0, 9)
        let delay = min(6 * 60 * 60, 30 * pow(2, Double(attempts)))
        return now.addingTimeInterval(delay)
    }

    /// UI dan notification membaca snapshot yang sama. Tidak ada lagi angka
    /// putaran dari RAM yang bisa berbeda setelah cold launch.
    private func applyQueueSnapshot(notify: Bool = true) {
        let state = queue.snapshot
        uploadItems = queue.items.sorted { lhs, rhs in
            if lhs.state.isActive != rhs.state.isActive {
                return lhs.state.isActive
            }
            return lhs.createdAt < rhs.createdAt
        }
        let activeIDs = Set(uploadItems.filter { $0.state.isActive }.map(\.id))
        uploadProgressByID = uploadProgressByID.filter { activeIDs.contains($0.key) }
        uploadedThisRun = state.completed
        pendingThisRun = state.total
        failures = queue.failedIDs
        isUploading = state.isUploading
        waitingForNetwork = state.waitingForNetwork
        waitingForICloud = state.waitingForICloud
        waitingForAuthentication = state.waitingForAuthentication
        scheduledForRetry = state.retryScheduled
        queueStatusTitle = state.presentation?.title
        queueStatusBody = state.presentation?.body
        scheduleRetryWake(for: state.nextAttemptAt)
        if let queueError = state.lastError {
            lastError = queueError
        } else if state.total == 0 || (state.unfinished == 0 && state.failed == 0) {
            lastError = nil
        }
        notificationRevision += 1
        guard notify, isEnabled else { return }
        let revision = notificationRevision
        Task { [weak self] in
            await BackupNotifier.shared.ensureAuthorization(prompt: false)
            guard let self, self.notificationRevision == revision else { return }
            if state.unfinished == 0, state.completionNotificationPending {
                // Consume before posting. This intentionally guarantees
                // at-most-once delivery across process termination: a launch
                // can never reinterpret the same persisted completion as new.
                do {
                    try self.queue.consumeCompletionNotification()
                } catch {
                    self.lastError = error.localizedDescription
                    return
                }
            }
            BackupNotifier.shared.update(queue: state)
        }
    }

    private func scheduleRetryWake(for date: Date?) {
        retryWakeTask?.cancel()
        retryWakeTask = nil
        guard isEnabled, hasAuthenticatedSession, let date else { return }
        let delay = max(0, date.timeIntervalSinceNow)
        retryWakeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.continueInBackground()
        }
    }

    /// Menutup putaran, sekali saja.
    ///
    /// Dipanggil dari dua arah — penyelesaian terakhir, dan akhir pengantrean
    /// yang ternyata tidak menyerahkan apa pun — jadi penjaga `isUploading` di
    /// depan bukan basa-basi: tanpa itu "Backup Complete" bisa terbit dua kali
    /// untuk satu putaran.
    private func finishRunIfSettled() {
        let state = queue.snapshot
        guard state.active == 0, state.queued == 0 else { return }
        lastRunAt = Date()
        applyQueueSnapshot()
        if state.waiting > 0 { BackupScheduler.schedule() }
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
