import Foundation

class SharedLinkRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func all() async throws -> [SharedLinkDTO] {
        try await api.send(.init(path: "/shared-links"))
    }

    func update(_ id: String, edit: SharedLinkEditDTO) async throws -> SharedLinkDTO {
        try await api.send(.json("/shared-links/\(id)", method: .patch, body: edit))
    }

    /// Tautan publik untuk sekumpulan foto lepas — bukan album.
    func create(assetIds: [String]) async throws -> SharedLinkDTO {
        struct Body: Encodable {
            let type: String
            let assetIds: [String]
        }
        return try await api.send(.json(
            "/shared-links",
            method: .post,
            body: Body(type: "INDIVIDUAL", assetIds: assetIds)))
    }

    func delete(_ id: String) async throws {
        try await api.sendVoid(.init(path: "/shared-links/\(id)", method: .delete))
    }
}
