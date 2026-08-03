import Foundation
import Observation

@MainActor
@Observable
final class AlbumListViewModel {
    var albums: [AlbumResponseDTO] = []
    var phase: LoadingPhase<Void> = .idle
    var showCreateSheet = false
    var createAlbumName = ""

    private let repo: AlbumRepository

    init(repo: AlbumRepository) {
        self.repo = repo
    }

    func loadAlbums() async {
        phase = .loading
        do {
            albums = try await repo.all()
            phase = .loaded(())
        } catch {
            phase = .failed((error as? APIError)?.errorDescription ?? String(localized: "Failed to load albums"))
        }
    }

    func createAlbum() async {
        guard !createAlbumName.isEmpty else { return }

        do {
            let newAlbum = try await repo.create(name: createAlbumName)
            albums.append(newAlbum)
            createAlbumName = ""
            showCreateSheet = false
        } catch {
            phase = .failed((error as? APIError)?.errorDescription ?? String(localized: "Failed to create album"))
        }
    }

    func deleteAlbum(_ id: String) async {
        do {
            try await repo.delete(id)
            albums.removeAll { $0.id == id }
        } catch {
            // Handle error silently for now
        }
    }

    func retry() async {
        await loadAlbums()
    }

    var myAlbums: [AlbumResponseDTO] {
        albums.filter { !$0.shared }
    }

    var sharedAlbums: [AlbumResponseDTO] {
        albums.filter { $0.shared }
    }
}
