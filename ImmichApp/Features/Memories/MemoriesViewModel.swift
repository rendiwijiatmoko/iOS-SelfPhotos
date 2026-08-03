import Foundation
import Observation

@MainActor
@Observable
final class MemoriesViewModel {
    var memories: [MemoryDTO] = []
    var phase: LoadingPhase<Void> = .idle
    var selectedMemory: MemoryDTO?

    private let repo: MemoriesRepository

    init(repo: MemoriesRepository) {
        self.repo = repo
    }

    func loadMemories() async {
        phase = .loading
        do {
            memories = try await repo.getMemories()
            phase = .loaded(())
        } catch {
            phase = .failed((error as? APIError)?.errorDescription ?? String(localized: "Failed to load memories"))
        }
    }

    func retry() async {
        await loadMemories()
    }
}
