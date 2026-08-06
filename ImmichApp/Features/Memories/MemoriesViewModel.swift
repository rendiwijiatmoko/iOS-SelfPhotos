import Foundation
import Observation

@MainActor
@Observable
final class MemoriesViewModel {
    var stories: [MemoryStory] = []
    var phase: LoadingPhase<Void> = .idle

    private let repo: MemoriesRepository
    private let assetRepo: AssetDetailRepository

    init(repo: MemoriesRepository, assetRepo: AssetDetailRepository) {
        self.repo = repo
        self.assetRepo = assetRepo
    }

    func loadMemories() async {
        phase = .loading
        do {
            // Layar penuh, jadi tidak dipotong seperti baris di Library.
            stories = MemoryStory.build(from: try await repo.getMemories(), limit: .max)
            phase = .loaded(())
        } catch {
            phase = .failed((error as? APIError)?.errorDescription
                ?? String(localized: "Failed to load memories"))
        }
    }

    func retry() async {
        await loadMemories()
    }

    /// Unduh berkas asli ke lokasi sementara untuk dibagikan lewat share sheet
    /// (URL server polos akan kena 401).
    func shareURL(for asset: AssetLite) async -> URL? {
        do {
            let data = try await assetRepo.downloadOriginal(asset.id)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(asset.id).\(asset.isVideo ? "mov" : "jpg")")
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
