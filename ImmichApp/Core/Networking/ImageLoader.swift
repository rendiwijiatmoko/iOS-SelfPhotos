import SwiftUI

actor ImageCache {
    static let shared = ImageCache()
    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskCacheURL: URL
    private let maxDiskCacheSize: Int = 100 * 1024 * 1024

    nonisolated private static let diskCacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("immich-image-cache")

    init() {
        diskCacheURL = Self.diskCacheDir
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }

    func image(for key: String) -> UIImage? {
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }

        let diskPath = diskCacheURL.appendingPathComponent(hashKey(key))
        if let data = try? Data(contentsOf: diskPath), let image = UIImage(data: data) {
            memoryCache.setObject(image, forKey: key as NSString)
            return image
        }
        return nil
    }

    func insert(_ img: UIImage, for key: String) {
        memoryCache.setObject(img, forKey: key as NSString)

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

    private func evictIfNeeded() {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return
        }

        var totalSize = 0
        var files: [(url: URL, date: Date)] = []

        for fileURL in contents {
            if let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
               let size = attrs[.size] as? Int {
                totalSize += size
                if let date = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date() as Date? {
                    files.append((fileURL, date))
                }
            }
        }

        if totalSize > maxDiskCacheSize {
            files.sort { $0.date < $1.date }
            var freed = 0
            for file in files {
                if freed > maxDiskCacheSize / 4 { break }
                try? fileManager.removeItem(at: file.url)
                if let attrs = try? fileManager.attributesOfItem(atPath: file.url.path),
                   let size = attrs[.size] as? Int {
                    freed += size
                }
            }
        }
    }

    private func hashKey(_ key: String) -> String {
        key.hashValue.description
    }
}

@MainActor
struct AuthImage: View {
    let assetId: String
    var size: String = "thumbnail"

    @Environment(SessionManager.self) private var session
    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var hasError = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if hasError {
                Color.gray.opacity(0.2)
            } else {
                Color.gray.opacity(0.15)
            }
        }
        .task(id: assetId) {
            await load()
        }
    }

    private func load() async {
        let key = "\(assetId)-\(size)"

        if let cached = await ImageCache.shared.image(for: key) {
            image = cached
            return
        }

        isLoading = true
        hasError = false

        do {
            let api = APIClient(session: session)
            let data = try await api.rawData(.init(
                path: "/assets/\(assetId)/thumbnail",
                query: [.init(name: "size", value: size)]))

            if let ui = UIImage(data: data) {
                await ImageCache.shared.insert(ui, for: key)
                image = ui
            }
        } catch {
            hasError = true
        }

        isLoading = false
    }
}

#Preview {
    AuthImage(assetId: "test-123")
        .environment(SessionManager())
        .frame(height: 200)
}
