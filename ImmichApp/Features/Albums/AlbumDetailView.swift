import SwiftUI

struct AlbumDetailView: View {
    let album: AlbumResponseDTO
    @Environment(SessionManager.self) private var session
    @State private var vm: AlbumDetailViewModel?
    @Namespace private var sourceNamespace
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    var body: some View {
        content
            .navigationTitle(album.albumName)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if vm == nil {
                    let api = APIClient(session: session)
                    let repo = AlbumRepository(api: api)
                    vm = AlbumDetailViewModel(repo: repo)
                }
                await vm?.loadAlbumDetail(album.id)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let vm {
            switch vm.phase {
            case .idle, .loading:
                ProgressView()

            case .loaded:
                if vm.assets.isEmpty {
                    emptyState
                } else {
                    grid
                }

            case .failed(let error):
                errorState(error, vm)
            }
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private var grid: some View {
        if let vm {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(vm.assets) { asset in
                        NavigationLink(value: asset) {
                            AuthImage(assetId: asset.id, thumbhash: asset.thumbhash)
                                .aspectRatio(asset.ratio, contentMode: .fill)
                                .clipped()
                        }
                    }
                }
                .padding(2)
            }
            .navigationDestination(for: AssetLite.self) { asset in
                let allAssets = vm.assets
                AssetDetailView(currentAsset: asset, assets: allAssets)
                    .navigationTransition(.zoom(sourceID: asset.id, in: sourceNamespace))
                    .toolbarVisibility(.hidden, for: .tabBar)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Photos")
                .font(.headline)
            Text("Add photos to this album")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func errorState(_ error: String, _ vm: AlbumDetailViewModel) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Failed to Load")
                .font(.headline)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task {
                    await vm.retry(album.id)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
@Observable
final class AlbumDetailViewModel {
    var assets: [AssetLite] = []
    var phase: LoadingPhase<Void> = .idle

    private let repo: AlbumRepository

    init(repo: AlbumRepository) {
        self.repo = repo
    }

    func loadAlbumDetail(_ albumId: String) async {
        phase = .loading
        do {
            let albumDetail = try await repo.detail(albumId)
            if let albumAssets = albumDetail.assets {
                assets = albumAssets.map { asset in
                    AssetLite(
                        id: asset.id,
                        isVideo: asset.isVideo,
                        ratio: Double(asset.exifInfo?.exifImageWidth ?? 1000) / Double(asset.exifInfo?.exifImageHeight ?? 1000),
                        thumbhash: asset.thumbhash,
                        createdAt: asset.fileCreatedAt
                    )
                }
            }
            phase = .loaded(())
        } catch {
            phase = .failed((error as? APIError)?.errorDescription ?? String(localized: "Failed to load album"))
        }
    }

    func retry(_ albumId: String) async {
        await loadAlbumDetail(albumId)
    }
}

#Preview {
    let album = AlbumResponseDTO(
        id: "album-1",
        albumName: "Summer Vacation",
        description: nil,
        assetCount: 42,
        albumThumbnailAssetId: nil,
        shared: false,
        createdAt: Date(),
        assets: nil
    )
    AlbumDetailView(album: album)
        .environment(SessionManager())
}
