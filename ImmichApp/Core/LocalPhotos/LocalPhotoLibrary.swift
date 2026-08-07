import AVFoundation
import Observation
import Photos
import UIKit

/// Penampung byte yang aman dipakai dari beberapa antrean sekaligus.
///
/// Sengaja sekecil ini: satu kunci, satu buffer, satu bendera. Yang dijaga hanya
/// perakitan potongan berkas dari `PHAssetResourceManager` — bukan sebuah
/// abstraksi umum.
private final class DataAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var completed = false

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(chunk)
    }

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    /// - Returns: true HANYA untuk pemanggil pertama.
    func claimCompletion() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        return true
    }
}

/// Satu album di perangkat yang bisa dipilih untuk ikut ditampilkan.
struct LocalAlbum: Identifiable, Sendable {
    let id: String
    let title: String
    let count: Int
    /// `PHAsset.localIdentifier` foto sampulnya, kalau albumnya tidak kosong.
    var coverAssetID: String?
}

/// Satu foto milik perangkat, dilihat dari sisi aplikasi ini.
struct LocalPhoto: Identifiable, Sendable {
    /// `PHAsset.localIdentifier`.
    let id: String
    let createdAt: Date
    let isVideo: Bool
    let duration: Double?
    let ratio: Double
}

/// Jembatan ke pustaka foto perangkat.
///
/// **Kenapa terpisah dari lapisan jaringan.** Foto perangkat dan foto server
/// tidak berbagi apa pun kecuali tempatnya berakhir: keduanya sama-sama petak di
/// linimasa. Sumbernya, cara memuat gambarnya, izin yang dibutuhkannya, dan cara
/// menghapusnya semuanya berbeda — dan menyelipkan percabangan itu ke dalam
/// repository yang sudah ada hanya membuat setiap pemanggil ikut menanggung
/// keduanya.
///
/// Yang disatukan justru di titik paling akhir: `AssetLite`. Grid, layar detail,
/// dan mode pilih tidak perlu tahu asal fotonya kecuali untuk menggambar lencana.
@MainActor
@Observable
final class LocalPhotoLibrary {
    static let shared = LocalPhotoLibrary()

    /// Awalan id untuk membedakan aset perangkat dari aset server.
    ///
    /// Keduanya hidup berdampingan di daftar yang sama dan diindeks dengan
    /// `String` yang sama, jadi tabrakan id bukan sesuatu yang boleh
    /// diserahkan pada keberuntungan — `localIdentifier` berbentuk UUID beserta
    /// sufiks, dan id server juga UUID.
    nonisolated static let idPrefix = "device:"

    private(set) var photos: [LocalPhoto] = []
    private(set) var isAuthorized = false

    /// `localIdentifier` foto → nama album perangkat asalnya.
    ///
    /// Dipakai "Sync albums": aset yang diunggah ditaruh di album server dengan
    /// nama yang sama. Dikumpulkan sekalian saat enumerasi karena keanggotaan
    /// album hanya bisa dibaca dari arah album ke aset — menanyakannya per foto
    /// belakangan berarti mengulang seluruh enumerasi sekali lagi.
    private(set) var albumTitles: [String: String] = [:]

    /// Album perangkat yang ikut ditampilkan dan dicocokkan.
    ///
    /// KOSONG secara bawaan, dan itu disengaja — sama seperti Immich resmi.
    /// Menghitung checksum berarti membaca seluruh byte setiap foto, dan pada
    /// pustaka yang sebagian isinya masih di iCloud itu berarti mengunduhnya
    /// lebih dulu. Pekerjaan sebesar itu tidak boleh dimulai tanpa seseorang
    /// memintanya.
    var selectedAlbumIDs: Set<String> {
        didSet {
            guard selectedAlbumIDs != oldValue else { return }
            UserDefaults.standard.set(Array(selectedAlbumIDs), forKey: Self.selectionKey)
        }
    }

    private static let selectionKey = "localPhotos.selectedAlbums"

    private let imageManager = PHCachingImageManager()

    /// SATU opsi untuk permintaan maupun prefetch.
    ///
    /// PhotoKit hanya memakai ulang hasil `startCachingImages` kalau opsinya
    /// sama persis dengan permintaannya. Dua objek berbeda dengan isi yang sama
    /// pun tidak cukup — jadi keduanya berbagi yang ini.
    ///
    /// `.highQualityFormat`, bukan `.opportunistic`: yang terakhir memanggil
    /// handler-nya dua kali (buram lalu asli) dan kadang berhenti di yang buram,
    /// sedangkan `withCheckedContinuation` hanya boleh dilanjutkan tepat sekali
    /// — tidak lebih (jatuh), tidak kurang (menggantung selamanya).
    private let thumbnailOptions: PHImageRequestOptions = {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return options
    }()

    private init() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.selectionKey) ?? []
        selectedAlbumIDs = Set(stored)
    }

    // MARK: - Album

    /// Album yang bisa dipilih: album buatan pengguna plus beberapa album pintar
    /// yang berarti sehari-hari.
    ///
    /// Yang kosong dibuang — memilihnya tidak menghasilkan apa pun, dan
    /// daftarnya jadi panjang tanpa isi.
    func albums() async -> [LocalAlbum] {
        // Dipecah, dengan alasan yang sama seperti di `load()`: sisi kanan `||`
        // adalah autoclosure, dan autoclosure tidak mendukung `await`.
        if !isAuthorized {
            guard await requestAccess() else { return [] }
        }
        return await Task.detached(priority: .userInitiated) { Self.fetchAlbums() }.value
    }

    private nonisolated static func fetchAlbums() -> [LocalAlbum] {
        var result: [LocalAlbum] = []

        func collect(_ collections: PHFetchResult<PHAssetCollection>) {
            collections.enumerateObjects { collection, _, _ in
                let assets = PHAsset.fetchAssets(in: collection, options: nil)
                guard assets.count > 0 else { return }
                result.append(LocalAlbum(
                    id: collection.localIdentifier,
                    title: collection.localizedTitle ?? "Untitled",
                    count: assets.count,
                    // Foto TERAKHIR, bukan yang pertama.
                    //
                    // Urutan bawaan PhotoKit menaik, jadi yang pertama adalah
                    // foto tertua di album — sampul yang tidak pernah berubah
                    // meski albumnya bertambah tiap hari. Photos sendiri memakai
                    // yang terbaru.
                    coverAssetID: assets.lastObject?.localIdentifier))
            }
        }

        // Album pintar yang benar-benar dipakai orang; sisanya (Slo-mo, Bursts,
        // Hidden) hanya memanjangkan daftar.
        for subtype: PHAssetCollectionSubtype in [
            .smartAlbumUserLibrary, .smartAlbumFavorites, .smartAlbumScreenshots,
            .smartAlbumSelfPortraits, .smartAlbumVideos,
        ] {
            collect(PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum, subtype: subtype, options: nil))
        }
        collect(PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .any, options: nil))
        return result
    }

    /// Foto satu album, tanpa menyentuh `photos`.
    ///
    /// Terpisah dari `load()` dengan sengaja: `photos` adalah gabungan seluruh
    /// album TERPILIH dan dipakai linimasa. Detail album butuh isi satu album
    /// saja — termasuk yang sudah terunggah, yang justru dibuang dari linimasa.
    func photos(inAlbum id: String) async -> [LocalPhoto] {
        if !isAuthorized {
            guard await requestAccess() else { return [] }
        }
        return await Task.detached(priority: .userInitiated) {
            Self.fetchPhotos(inAlbums: [id]).photos
        }.value
    }

    // MARK: - Id

    nonisolated static func isLocal(_ id: String) -> Bool {
        id.hasPrefix(idPrefix)
    }

    /// `device:` dilepas kembali jadi `PHAsset.localIdentifier`.
    ///
    /// Id yang bukan milik perangkat dikembalikan apa adanya, bukan dipotong
    /// tujuh karakter — memotongnya menghasilkan identifier yang mirip sah dan
    /// bisa menunjuk foto yang salah.
    nonisolated static func localIdentifier(from id: String) -> String {
        isLocal(id) ? String(id.dropFirst(idPrefix.count)) : id
    }

    nonisolated static func assetID(for localIdentifier: String) -> String {
        idPrefix + localIdentifier
    }

    // MARK: - Izin & pemuatan

    /// - Returns: true kalau pustakanya boleh dibaca.
    ///
    /// `.readWrite`, bukan `.addOnly`: menghapus foto dari perangkat menuntut
    /// akses tulis, dan meminta izin dua kali pada dua kesempatan berbeda hanya
    /// membuat permintaan kedua terasa mencurigakan.
    @discardableResult
    func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        isAuthorized = status == .authorized || status == .limited
        return isAuthorized
    }

    func load() async {
        // DIPECAH, bukan `isAuthorized || await requestAccess()`.
        //
        // Sisi kanan `||` adalah autoclosure, dan autoclosure itu tidak
        // mendukung `await` — bentuk ringkasnya tidak sekadar kurang rapi, ia
        // tidak kompilasi.
        if !isAuthorized {
            guard await requestAccess() else {
                photos = []
                albumTitles = [:]
                return
            }
        }
        // Enumerasi DI LUAR main actor.
        //
        // Pustaka puluhan ribu foto berarti puluhan ribu iterasi, dan tidak satu
        // pun bagiannya butuh main thread — sama seperti pengelompokan linimasa
        // yang sudah lebih dulu dipindahkan keluar.
        let albumIDs = selectedAlbumIDs
        // Tidak ada yang dipilih berarti tidak ada yang perlu dibaca.
        guard !albumIDs.isEmpty else {
            photos = []
            albumTitles = [:]
            return
        }
        let result = await Task.detached(priority: .userInitiated) {
            Self.fetchPhotos(inAlbums: albumIDs)
        }.value
        photos = result.photos
        albumTitles = result.albumTitles
    }

    /// Foto dari album TERPILIH saja.
    ///
    /// Di iOS satu foto bisa berada di beberapa album sekaligus, jadi hasilnya
    /// disatukan lewat kamus ber-id — kalau tidak, foto yang ada di dua album
    /// terpilih akan muncul dua petak.
    private nonisolated static func fetchPhotos(
        inAlbums ids: Set<String>
    ) -> (photos: [LocalPhoto], albumTitles: [String: String]) {
        let collections = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: Array(ids), options: nil)

        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d || mediaType == %d",
            PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)

        var unique: [String: LocalPhoto] = [:]
        var titles: [String: String] = [:]
        collections.enumerateObjects { collection, _, _ in
            let title = collection.localizedTitle
            PHAsset.fetchAssets(in: collection, options: options)
                .enumerateObjects { asset, _, _ in
                    guard unique[asset.localIdentifier] == nil else { return }
                    // Album PERTAMA yang memuatnya, dan hanya itu.
                    //
                    // Satu foto bisa ada di beberapa album terpilih sekaligus;
                    // menaruhnya di semuanya di server berarti menggandakan
                    // aset yang sama ke banyak album tanpa pernah diminta.
                    if let title { titles[asset.localIdentifier] = title }
                    let width = Double(asset.pixelWidth)
                    let height = Double(asset.pixelHeight)
                    unique[asset.localIdentifier] = LocalPhoto(
                        id: asset.localIdentifier,
                        createdAt: asset.creationDate ?? asset.modificationDate ?? Date(),
                        isVideo: asset.mediaType == .video,
                        duration: asset.mediaType == .video ? asset.duration : nil,
                        ratio: height > 0 ? width / height : 1)
                }
        }

        // MENAIK, sama dengan urutan cache linimasa — penggabungannya jadi
        // sekadar merge dua deret terurut, bukan pengurutan ulang. Pengurutan
        // per-album tidak cukup karena hasilnya digabung dari beberapa album.
        return (unique.values.sorted { $0.createdAt < $1.createdAt }, titles)
    }

    // MARK: - Gambar

    /// Thumbnail untuk sel grid.
    ///
    /// `PHCachingImageManager` punya cache-nya sendiri, jadi hasilnya TIDAK
    /// dititipkan ke `ImageCache`: menyalin byte foto yang sudah ada di
    /// perangkat ke cache disk aplikasi hanya menggandakan penyimpanan untuk
    /// sesuatu yang tidak pernah perlu diunduh.
    func thumbnail(for id: String, size: CGSize) async -> UIImage? {
        guard let asset = Self.fetchAsset(id) else { return nil }

        return await withCheckedContinuation { continuation in
            imageManager.requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: thumbnailOptions
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// Versi untuk layar detail: UTUH, bukan dipenuhi.
    ///
    /// `.aspectFill` benar untuk petak grid yang memang persegi, tapi di layar
    /// detail ia memotong sisi panjang foto — yang terlihat bukan fotonya,
    /// melainkan bagian tengahnya.
    func preview(for id: String, size: CGSize) async -> UIImage? {
        guard let asset = Self.fetchAsset(id) else { return nil }

        return await withCheckedContinuation { continuation in
            imageManager.requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFit,
                options: thumbnailOptions
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// Aset video yang masih tersedia di perangkat, tanpa membaca seluruh
    /// berkas ke memori dan tanpa menunggu unduhan dari iCloud.
    ///
    /// `AVPlayer` dapat membaca `AVAsset` dari PhotoKit secara langsung. Jalur
    /// lokal ini membuat video yang baru saja diunggah mulai seketika; kalau
    /// salinan penuhnya tidak ada di perangkat, pemanggil segera beralih ke
    /// streaming server alih-alih menggantung menunggu iCloud.
    func videoAsset(for id: String) async -> AVAsset? {
        guard let asset = Self.fetchAsset(id), asset.mediaType == .video else {
            return nil
        }

        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = false

        return await withCheckedContinuation { continuation in
            imageManager.requestAVAsset(
                forVideo: asset,
                options: options
            ) { videoAsset, _, _ in
                continuation.resume(returning: videoAsset)
            }
        }
    }

    func startCaching(_ ids: [String], size: CGSize) {
        let assets = ids.compactMap(Self.fetchAsset)
        guard !assets.isEmpty else { return }
        imageManager.startCachingImages(
            for: assets,
            targetSize: size,
            contentMode: .aspectFill,
            options: thumbnailOptions)
    }

    /// Melupakan seluruh state PhotoKit milik sesi tanpa menghapus foto asli.
    func resetForLogout() {
        imageManager.stopCachingImagesForAllAssets()
        photos = []
        albumTitles = [:]
        selectedAlbumIDs = []
    }

    // MARK: - Berkas asli

    /// Byte asli, untuk diunggah maupun dibagikan.
    ///
    /// Lewat `PHAssetResourceManager`, BUKAN `PHImageManager`.
    ///
    /// Yang terakhir hanya mengerti gambar — video tidak punya "image data" dan
    /// akan pulang dengan tangan kosong. Resource manager membaca berkas
    /// aslinya apa adanya, foto maupun video, berikut nama berkas yang benar.
    /// Ia mengirimkan datanya BERPOTONG-POTONG, jadi buffernya dirakit sendiri.
    /// `nonisolated`, dan itu bukan penghalusan.
    ///
    /// Sebelumnya seluruh fungsi ini terikat main actor, dan akibatnya ada dua.
    /// Yang pertama terlihat di konsol: `PHAssetResource.assetResources(for:)`
    /// dijalankan di main queue, dan PhotoKit sendiri yang memperingatkan bahwa
    /// itu menurunkan kinerja — ia menarik metadata aset secara sinkron di sana.
    /// Yang kedua jauh lebih parah: membaca SELURUH byte setiap berkas juga
    /// terjadi di main actor, dan pencocokan checksum melakukan hal yang sama
    /// untuk seluruh pustaka pada saat yang bersamaan. Dua pekerjaan besar
    /// mengantre di satu-satunya utas yang juga harus menggambar antarmuka —
    /// itulah unggahan yang tidak bergerak selama belasan menit.
    ///
    /// Fungsi `nonisolated async` berjalan di kolam eksekutor umum, bukan di
    /// aktor pemanggilnya. Tidak ada state instance yang disentuh di sini, jadi
    /// tidak ada yang perlu dilindungi.
    nonisolated func originalData(for id: String) async -> (data: Data, filename: String)? {
        // `Task.detached`, bukan mengandalkan `nonisolated` saja.
        //
        // Target ini menyalakan `SWIFT_APPROACHABLE_CONCURRENCY`, dan dengan itu
        // fungsi `nonisolated async` MEWARISI eksekutor pemanggilnya alih-alih
        // pindah ke kolam umum. Pemanggilnya sering main actor — jadi
        // `PHAssetResource.assetResources(for:)`, yang menarik metadata aset
        // secara sinkron, tetap berjalan di main queue persis seperti sebelum
        // fungsi ini dijadikan nonisolated. Itulah peringatan "Fetching on
        // demand on the main queue" yang masih muncul di konsol.
        //
        // `requestData` di bawah tidak kena karena ia menyerahkan diri lewat
        // continuation; yang perlu dipindahkan hanya pencarian resource-nya.
        guard let resource = await Task.detached(priority: .utility, operation: {
            guard let asset = Self.fetchAsset(id) else { return PHAssetResource?.none }
            return Self.primaryResource(for: asset)
        }).value else { return nil }

        // DUA percobaan, dan yang pertama tidak menyentuh jaringan sama sekali.
        //
        // `isNetworkAccessAllowed = true` membuat PhotoKit menghubungi daemon
        // iCloud untuk SETIAP berkas — termasuk yang salinan penuhnya sudah ada
        // di perangkat. Kalau daemon itu sedang bermasalah (`com.apple.accounts
        // Code=7` di konsol), permintaannya tidak ditolak cepat; ia menggantung
        // belasan menit lalu menyerah. Satu foto 3 KB yang sebenarnya sudah ada
        // di disk pun ikut menunggu.
        //
        // Jalur pertama menjawab dalam milidetik untuk semua yang ada di
        // perangkat — dan itu mayoritasnya. Jaringan hanya dipakai untuk yang
        // memang benar-benar tidak ada di sini.
        if let local = await Self.requestData(resource, allowsNetwork: false) {
            return (local, resource.originalFilename)
        }
        guard let remote = await Self.requestData(resource, allowsNetwork: true) else {
            return nil
        }
        return (remote, resource.originalFilename)
    }

    private nonisolated static func requestData(
        _ resource: PHAssetResource, allowsNetwork: Bool
    ) async -> Data? {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = allowsNetwork

        return await withCheckedContinuation { continuation in
            // Penampung berkunci, bukan `var` lokal yang ditangkap closure.
            //
            // `dataReceivedHandler` dipanggil PhotoKit dari antreannya sendiri,
            // berkali-kali, sementara `completionHandler` membacanya dari
            // antrean yang belum tentu sama. Menumbuhkan sebuah `Data` dari dua
            // arah tanpa penyelarasan adalah balapan data — yang gagalnya tidak
            // sopan: bukan kesalahan yang terbaca, melainkan byte yang hilang
            // atau proses yang jatuh.
            let buffer = DataAccumulator()
            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { buffer.append($0) },
                completionHandler: { error in
                    // Penjaga sekali-jalan: continuation yang dilanjutkan dua
                    // kali menjatuhkan proses, bukan sekadar keliru.
                    guard buffer.claimCompletion() else { return }
                    continuation.resume(returning: error == nil ? buffer.value : nil)
                })
        }
    }

    /// Berkas UTAMA sebuah aset.
    ///
    /// Satu aset bisa punya beberapa resource — foto beserta versi suntingannya,
    /// video beserta foto sampulnya. Yang diambil harus sesuai jenis asetnya,
    /// kalau tidak sebuah video bisa terunggah sebagai gambar diam.
    private nonisolated static func primaryResource(for asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        let wanted: PHAssetResourceType = asset.mediaType == .video ? .video : .photo
        return resources.first { $0.type == wanted } ?? resources.first
    }

    // MARK: - Hapus

    /// Menghapus dari PUSTAKA PERANGKAT.
    ///
    /// iOS memunculkan konfirmasinya sendiri — sistem tidak mengizinkan aplikasi
    /// menghapus foto orang tanpa satu ketukan terakhir dari pemiliknya. Karena
    /// itu tidak perlu ada dialog buatan kita sebelum ini.
    @discardableResult
    func delete(_ ids: [String]) async -> Bool {
        let identifiers = ids.map(Self.localIdentifier(from:))
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        guard assets.count > 0 else { return false }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            let removed = Set(identifiers)
            photos.removeAll { removed.contains($0.id) }
            return true
        } catch {
            return false
        }
    }

    /// `static` dan `nonisolated`: tidak menyentuh state apa pun, dan memaksanya
    /// lewat main actor berarti setiap pembacaan berkas mengantre di belakang
    /// antarmuka. `static` supaya bisa dipanggil dari `Task.detached` tanpa
    /// menyeret `self` melintasi isolasi.
    fileprivate nonisolated static func fetchAsset(_ id: String) -> PHAsset? {
        let identifier = Self.isLocal(id) ? Self.localIdentifier(from: id) : id
        return PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
    }
}
