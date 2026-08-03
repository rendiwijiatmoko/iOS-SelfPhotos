import Foundation

final class AlbumRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func all() async throws -> [AlbumResponseDTO] {
        try await api.send(.init(path: "/albums"))
    }

    func detail(_ id: String) async throws -> AlbumResponseDTO {
        try await api.send(.init(path: "/albums/\(id)"))
    }

    func create(name: String, assetIds: [String] = []) async throws -> AlbumResponseDTO {
        struct Body: Encodable {
            let albumName: String
            let assetIds: [String]
        }
        return try await api.send(.json("/albums", method: .post, body: Body(albumName: name, assetIds: assetIds)))
    }

    func rename(_ id: String, to name: String) async throws {
        struct Body: Encodable {
            let albumName: String
        }
        try await api.sendVoid(.json("/albums/\(id)", method: .put, body: Body(albumName: name)))
    }

    func addAssets(_ ids: [String], to albumId: String) async throws {
        struct Body: Encodable {
            let ids: [String]
        }
        try await api.sendVoid(.json("/albums/\(albumId)/assets", method: .put, body: Body(ids: ids)))
    }

    func removeAssets(_ ids: [String], from albumId: String) async throws {
        struct Body: Encodable {
            let ids: [String]
        }
        try await api.sendVoid(.json("/albums/\(albumId)/assets", method: .delete, body: Body(ids: ids)))
    }

    func delete(_ id: String) async throws {
        try await api.sendVoid(.init(path: "/albums/\(id)", method: .delete))
    }
}
