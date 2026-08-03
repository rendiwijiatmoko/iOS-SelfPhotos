import CryptoKit
import SwiftUI

/// Cache gambar dua lapis.
///
/// - **L1 (memori)**: `NSCache` dengan batas jumlah *dan* batas biaya (perkiraan
///   byte gambar setelah didekode), supaya scroll ribuan foto tidak menekan
///   memori. `NSCache` melepas isinya sendiri saat sistem kekurangan memori.
/// - **L2 (disk)**: file dengan nama SHA256 dari key (stabil lintas sesi),
///   dievict secara LRU saat melewati batas ukuran.
actor ImageCache {
    static let shared = ImageCache()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskCacheURL: URL

    /// Batas L1. `totalCostLimit` adalah plafon, bukan alokasi: `NSCache`
    /// hanya menyimpan sebanyak yang benar-benar dipakai.
    private static let memoryCountLimit = 400
    private static let memoryCostLimit = 128 * 1024 * 1024

    /// Batas L2, bisa diubah lewat Settings (UI-nya menyusul di #30).
    private static let diskLimitDefaultsKey = "imageCache.diskLimitBytes"
    private static let defaultDiskLimit = 250 * 1024 * 1024

    private var maxDiskCacheSize: Int

    nonisolated private static let diskCacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("immich-image-cache")

    init() {
        diskCacheURL = Self.diskCacheDir

        let stored = UserDefaults.standard.integer(forKey: Self.diskLimitDefaultsKey)
        maxDiskCacheSize = stored > 0 ? stored : Self.defaultDiskLimit

        memoryCache.countLimit = Self.memoryCountLimit
        memoryCache.totalCostLimit = Self.memoryCostLimit

        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        Task { await purgeLegacyFiles() }
    }

    func image(for key: String) -> UIImage? {
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }

        let diskPath = diskCacheURL.appendingPathComponent(hashKey(key))
        if let data = try? Data(contentsOf: diskPath), let image = UIImage(data: data) {
            memoryCache.setObject(image, forKey: key as NSString, cost: Self.cost(of: image))
            touch(diskPath)
            return image
        }
        return nil
    }

    func insert(_ img: UIImage, for key: String) {
        memoryCache.setObject(img, forKey: key as NSString, cost: Self.cost(of: img))

        if let data = img.jpegData(compressionQuality: 0.8) {
            let diskPath = diskCacheURL.appendingPathComponent(hashKey(key))
            try? data.write(to: diskPath)
            evictIfNeeded()
        }
    }

    func clear() {
        memoryCache.removeAllObjects()
        try? FileManager.default.removeItem(at: diskCacheURL)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }

    /// Total byte yang dipakai L2 saat ini.
    func diskCacheSize() -> Int {
        scanDiskCache().total
    }

    func diskCacheLimit() -> Int {
        maxDiskCacheSize
    }

    func setDiskCacheLimit(_ bytes: Int) {
        maxDiskCacheSize = max(16 * 1024 * 1024, bytes)
        UserDefaults.standard.set(maxDiskCacheSize, forKey: Self.diskLimitDefaultsKey)
        evictIfNeeded()
    }

    /// Perkiraan byte gambar setelah didekode — inilah yang benar-benar
    /// menempati memori, bukan ukuran file JPEG-nya.
    nonisolated private static func cost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 1 }
        return cgImage.bytesPerRow * cgImage.height
    }

    /// Menandai file sebagai baru dipakai, supaya eviction yang mengurutkan
    /// berdasarkan tanggal modifikasi benar-benar LRU (bukan sekadar FIFO
    /// menurut kapan file ditulis).
    ///
    /// Hanya ditulis kalau stempelnya sudah cukup lama, supaya scroll panjang
    /// tidak berubah jadi ribuan penulisan metadata.
    private func touch(_ url: URL) {
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if let modified, Date().timeIntervalSince(modified) < Self.touchInterval { return }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    private static let touchInterval: TimeInterval = 60 * 60

    private func scanDiskCache() -> (total: Int, files: [(url: URL, date: Date, size: Int)]) {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return (0, [])
        }

        var totalSize = 0
        var files: [(url: URL, date: Date, size: Int)] = []

        for fileURL in contents {
            guard let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
                  let size = attrs[.size] as? Int else { continue }

            totalSize += size
            let date = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            files.append((fileURL, date, size))
        }

        return (totalSize, files)
    }

    private func evictIfNeeded() {
        let fileManager = FileManager.default
        var (totalSize, files) = scanDiskCache()

        guard totalSize > maxDiskCacheSize else { return }

        // Buang yang paling lama dulu sampai turun ke bawah batas dengan
        // sisa ruang 25%, supaya eviction tidak terpicu lagi tiap insert.
        // Ukuran dibaca dari hasil scan di atas — bukan dari file yang sudah
        // dihapus (yang selalu gagal dan dulu membuat seluruh cache terkuras).
        files.sort { $0.date < $1.date }
        let target = maxDiskCacheSize - maxDiskCacheSize / 4

        for file in files {
            if totalSize <= target { break }
            try? fileManager.removeItem(at: file.url)
            totalSize -= file.size
        }
    }

    /// Sisa file dari skema key lama (`hashValue`, nama berupa angka desimal).
    /// File-file itu tidak akan pernah kena hit lagi, jadi dibuang sekali saja
    /// supaya tidak menghabiskan kuota disk cache.
    private func purgeLegacyFiles() {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: nil) else {
            return
        }

        for fileURL in contents where !Self.isStableKeyFilename(fileURL.lastPathComponent) {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    nonisolated private static func isStableKeyFilename(_ name: String) -> Bool {
        name.count == 64 && name.allSatisfy(\.isHexDigit)
    }

    /// Nama file disk untuk sebuah cache key.
    ///
    /// Harus **stabil lintas proses**: `String.hashValue` di Swift di-seed acak
    /// tiap app dijalankan, jadi nama file lama berubah tiap app dibuka dan
    /// disk cache tidak pernah hit di sesi berikutnya. SHA256 selalu
    /// menghasilkan nama yang sama untuk key yang sama.
    nonisolated private func hashKey(_ key: String) -> String {
        SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

@MainActor
struct AuthImage: View {
    let assetId: String
    var size: String = "thumbnail"
    /// Thumbhash asset, kalau ada — dipakai sebagai placeholder blur instan
    /// sebelum thumbnail asli datang.
    var thumbhash: String? = nil

    @Environment(SessionManager.self) private var session
    @State private var image: UIImage?
    @State private var hasError = false

    private var placeholder: UIImage? {
        ThumbHash.placeholder(for: thumbhash)
    }

    var body: some View {
        ZStack {
            // Lapisan bawah selalu ada, jadi tidak pernah ada kotak kosong dan
            // gambar asli bisa muncul dengan crossfade di atasnya.
            if let placeholder {
                Image(uiImage: placeholder)
                    .resizable()
                    .scaledToFill()
                    .accessibilityHidden(true)
            } else if hasError {
                Rectangle()
                    .fill(.fill.tertiary)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            } else {
                Rectangle()
                    .fill(.fill.quaternary)
            }

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .task(id: assetId) {
            await load()
        }
    }

    private func load() async {
        let key = "\(assetId)-\(size)"

        // Cache hit tidak perlu crossfade — gambarnya sudah ada, memudarkannya
        // justru terasa seperti lag.
        if let cached = await ImageCache.shared.image(for: key) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { image = cached }
            return
        }

        hasError = false

        do {
            let api = APIClient(session: session)
            let data = try await api.rawData(.init(
                path: "/assets/\(assetId)/thumbnail",
                query: [.init(name: "size", value: size)]))

            if let ui = UIImage(data: data) {
                await ImageCache.shared.insert(ui, for: key)
                withAnimation(.easeOut(duration: 0.2)) { image = ui }
            }
        } catch {
            hasError = true
        }
    }
}

#Preview {
    AuthImage(assetId: "test-123")
        .environment(SessionManager())
        .frame(height: 200)
}
