import Foundation

final class PeopleRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func all() async throws -> [PersonDTO] {
        struct Response: Decodable {
            let people: [PersonDTO]
        }
        let response: Response = try await api.send(.init(path: "/people"))
        return response.people
    }

    func detail(_ id: String) async throws -> PersonDetailDTO {
        struct Response: Decodable {
            let id: String
            let name: String
            let birthDate: Date?
            let thumbnailPath: String?
            let isHidden: Bool
            let assets: [AssetResponseDTO]
        }
        return try await api.send(.init(path: "/people/\(id)"))
    }

    func rename(_ id: String, to name: String) async throws {
        struct Body: Encodable {
            let name: String
        }
        try await api.sendVoid(.json("/people/\(id)", method: .put, body: Body(name: name)))
    }

    func setHidden(_ id: String, to value: Bool) async throws {
        struct Body: Encodable {
            let isHidden: Bool
        }
        try await api.sendVoid(.json("/people/\(id)", method: .put, body: Body(isHidden: value)))
    }
}

struct PersonDetailDTO: Decodable, Identifiable {
    let id: String
    let name: String
    let birthDate: Date?
    let thumbnailPath: String?
    let isHidden: Bool
    let assets: [AssetResponseDTO]
}
