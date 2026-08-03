import Foundation
import Observation

@MainActor
@Observable
final class SearchViewModel {
    var searchText = ""
    var results: [AssetLite] = []
    var phase: LoadingPhase<Void> = .idle
    var suggestions: [String] = []
    var currentPage = 1
    var nextPage: String?

    private let repo: SearchRepository

    init(repo: SearchRepository) {
        self.repo = repo
    }

    func search(_ query: String) async {
        guard !query.isEmpty else {
            results = []
            return
        }

        phase = .loading
        currentPage = 1
        nextPage = nil

        do {
            let response = try await repo.smartSearch(query, page: currentPage)
            results = response.assets.items.map { asset in
                AssetLite(
                    id: asset.id,
                    isVideo: asset.isVideo,
                    ratio: Double(asset.exifInfo?.exifImageWidth ?? 1000) / Double(asset.exifInfo?.exifImageHeight ?? 1000),
                    thumbhash: asset.thumbhash,
                    createdAt: asset.fileCreatedAt
                )
            }
            nextPage = response.assets.nextPage
            phase = .loaded(())
        } catch {
            phase = .failed((error as? APIError)?.errorDescription ?? String(localized: "Search failed"))
        }
    }

    func loadMore() async {
        guard !searchText.isEmpty, let _ = nextPage else { return }

        do {
            currentPage += 1
            let response = try await repo.smartSearch(searchText, page: currentPage)
            let newAssets = response.assets.items.map { asset in
                AssetLite(
                    id: asset.id,
                    isVideo: asset.isVideo,
                    ratio: Double(asset.exifInfo?.exifImageWidth ?? 1000) / Double(asset.exifInfo?.exifImageHeight ?? 1000),
                    thumbhash: asset.thumbhash,
                    createdAt: asset.fileCreatedAt
                )
            }
            results.append(contentsOf: newAssets)
            nextPage = response.assets.nextPage
        } catch {
            // Silently fail on pagination
        }
    }

    func loadSuggestions() async {
        do {
            suggestions = try await repo.suggestions()
        } catch {
            suggestions = []
        }
    }
}
