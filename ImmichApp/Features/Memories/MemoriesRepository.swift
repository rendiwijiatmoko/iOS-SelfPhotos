import Foundation

class MemoriesRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func getMemories() async throws -> [MemoryDTO] {
        // GET /memories mengembalikan array polos, bukan {memories: [...]}.
        try await api.send(.init(path: "/memories"))
    }
}
