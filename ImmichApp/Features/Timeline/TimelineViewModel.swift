import Foundation
import Observation

@MainActor
@Observable
final class TimelineViewModel {
    var sections: [TimelineSection] = []
    var phase: LoadingPhase<Void> = .idle
    private var loaded = Set<String>()

    private let repo: TimelineRepository
    private let syncVM: SyncViewModel?

    init(repo: TimelineRepository, syncVM: SyncViewModel? = nil) {
        self.repo = repo
        self.syncVM = syncVM
    }

    func loadBuckets() async {
        phase = .loading

        await syncVM?.performBackgroundSync()

        do {
            let buckets = try await repo.buckets()
            sections = buckets.map { bucket in
                TimelineSection(
                    id: bucket.timeBucket,
                    title: formatBucketTitle(bucket.timeBucket),
                    assets: []
                )
            }
            phase = .loaded(())
        } catch {
            phase = .failed((error as? APIError)?.errorDescription ?? String(localized: "Failed to load photos"))
        }
    }

    func loadSectionIfNeeded(_ id: String) async {
        guard !loaded.contains(id) else { return }
        loaded.insert(id)

        do {
            let assets = try await repo.bucket(id)
            if let idx = sections.firstIndex(where: { $0.id == id }) {
                sections[idx].assets = assets
            }
        } catch {
            // Silently fail - section will remain empty
        }
    }

    func retry() async {
        await loadBuckets()
    }

    private func formatBucketTitle(_ iso: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.locale = Locale.current

        if let date = formatter.date(from: iso) {
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: date)
        }

        return iso
    }
}
