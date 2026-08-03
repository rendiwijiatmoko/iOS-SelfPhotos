import Foundation

final class MemoriesRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func getMemories() async throws -> [MemoryDTO] {
        struct Response: Decodable {
            let memories: [MemoryDTO]
        }
        let response: Response = try await api.send(.init(path: "/memories"))
        return response.memories
    }
}
