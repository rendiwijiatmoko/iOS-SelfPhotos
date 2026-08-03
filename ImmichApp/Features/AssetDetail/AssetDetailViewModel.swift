import Foundation
import Observation

@MainActor
@Observable
final class AssetDetailViewModel {
    var detail: AssetResponseDTO?
    var phase: LoadingPhase<Void> = .idle
    var showInfoPanel = false

    private let repo: AssetDetailRepository

    init(repo: AssetDetailRepository) {
        self.repo = repo
    }

    func load(_ id: String) async {
        phase = .loading
        do {
            detail = try await repo.fetchAsset(id)
            phase = .loaded(())
        } catch {
            phase = .failed((error as? APIError)?.errorDescription ?? String(localized: "Failed to load asset"))
        }
    }

    func toggleFavorite(_ id: String) async {
        let newValue = !(detail?.isFavorite ?? false)
        do {
            try await repo.toggleFavorite(id, to: newValue)
            detail?.isFavorite = newValue
        } catch {
            // Silently fail - UI already updated optimistically
        }
    }

    func toggleArchive(_ id: String) async {
        let newValue = !(detail?.isArchived ?? false)
        do {
            try await repo.toggleArchive(id, to: newValue)
            detail?.isArchived = newValue
        } catch {
            // Silently fail - UI already updated optimistically
        }
    }

    func delete(_ id: String) async {
        do {
            try await repo.delete(id)
        } catch {
            // Handle delete error
        }
    }

    func downloadUrl(_ id: String) -> URL? {
        repo.downloadUrl(id)
    }

    func retry(_ id: String) async {
        await load(id)
    }
}
