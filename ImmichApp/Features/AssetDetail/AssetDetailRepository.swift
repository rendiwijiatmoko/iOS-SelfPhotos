import Foundation

final class AssetDetailRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func fetchAsset(_ id: String) async throws -> AssetResponseDTO {
        try await api.send(.init(path: "/assets/\(id)"))
    }

    func toggleFavorite(_ id: String, to value: Bool) async throws {
        struct Body: Encodable { let isFavorite: Bool }
        try await api.sendVoid(.json("/assets/\(id)", method: .put, body: Body(isFavorite: value)))
    }

    func toggleArchive(_ id: String, to value: Bool) async throws {
        struct Body: Encodable { let isArchived: Bool }
        try await api.sendVoid(.json("/assets/\(id)", method: .put, body: Body(isArchived: value)))
    }

    func delete(_ id: String) async throws {
        struct Body: Encodable { let ids: [String]; let force: Bool }
        try await api.sendVoid(.json("/assets", method: .delete, body: Body(ids: [id], force: false)))
    }

    func downloadUrl(_ id: String) -> URL? {
        guard let baseURL = api.session.baseURL else { return nil }
        return baseURL.appendingPathComponent("/download/asset/\(id)")
    }
}
