import Foundation

final class SearchRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func smartSearch(_ query: String, page: Int = 1) async throws -> SearchResponseDTO {
        let body = SearchRequestDTO(query: query, page: page)
        return try await api.send(.json("/search/smart", method: .post, body: body))
    }

    func metadataSearch(_ request: SearchRequestDTO) async throws -> SearchResponseDTO {
        try await api.send(.json("/search/metadata", method: .post, body: request))
    }

    func suggestions() async throws -> [String] {
        struct Response: Decodable {
            let suggestions: [String]
        }
        let response: Response = try await api.send(.init(path: "/search/suggestions"))
        return response.suggestions
    }

    func explore() async throws -> ExploreResponseDTO {
        try await api.send(.init(path: "/search/explore"))
    }
}

struct ExploreResponseDTO: Decodable {
    let cities: [String]?
    let things: [String]?
}
