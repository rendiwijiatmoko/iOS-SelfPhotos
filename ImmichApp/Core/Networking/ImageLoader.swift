import SwiftUI

actor ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func insert(_ img: UIImage, for key: String) {
        cache.setObject(img, forKey: key as NSString)
    }

    func clear() {
        cache.removeAllObjects()
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
