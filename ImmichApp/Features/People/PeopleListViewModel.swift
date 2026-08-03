import Foundation
import Observation

@MainActor
@Observable
final class PeopleListViewModel {
    var people: [PersonDTO] = []
    var phase: LoadingPhase<Void> = .idle

    private let repo: PeopleRepository

    init(repo: PeopleRepository) {
        self.repo = repo
    }

    func loadPeople() async {
        phase = .loading
        do {
            people = try await repo.all()
            phase = .loaded(())
        } catch {
            phase = .failed((error as? APIError)?.errorDescription ?? String(localized: "Failed to load people"))
        }
    }

    func setHidden(_ personId: String, to value: Bool) async {
        do {
            try await repo.setHidden(personId, to: value)
            if let index = people.firstIndex(where: { $0.id == personId }) {
                people[index].isHidden = value
            }
        } catch {
            // Handle silently
        }
    }

    func retry() async {
        await loadPeople()
    }
}
