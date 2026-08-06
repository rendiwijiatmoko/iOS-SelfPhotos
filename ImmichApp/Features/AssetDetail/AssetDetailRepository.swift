import Foundation

class AssetDetailRepository {
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

    /// Immich menerima `description` di level atas UpdateAssetDto, walau
    /// membacanya kembali lewat `exifInfo.description`.
    func updateDescription(_ id: String, to text: String) async throws {
        struct Body: Encodable { let description: String }
        try await api.sendVoid(.json("/assets/\(id)", method: .put, body: Body(description: text)))
    }

    func updateDate(_ id: String, to date: Date) async throws {
        struct Body: Encodable { let dateTimeOriginal: String }
        let text = ISO8601DateFormatter.immichFractional.string(from: date)
        try await api.sendVoid(.json("/assets/\(id)", method: .put, body: Body(dateTimeOriginal: text)))
    }

    func updateLocation(_ id: String, latitude: Double, longitude: Double) async throws {
        struct Body: Encodable { let latitude: Double; let longitude: Double }
        try await api.sendVoid(.json("/assets/\(id)", method: .put,
                                     body: Body(latitude: latitude, longitude: longitude)))
    }

    func toggleArchive(_ id: String, to value: Bool) async throws {
        try await setVisibility(id, to: value ? .archive : .timeline)
    }

    /// Nilai yang diterima Immich untuk `visibility` pada UpdateAssetDto.
    enum Visibility: String {
        case timeline
        case archive
        case locked
    }

    func setVisibility(_ id: String, to value: Visibility) async throws {
        struct Body: Encodable { let visibility: String }
        try await api.sendVoid(.json("/assets/\(id)", method: .put,
                                     body: Body(visibility: value.rawValue)))
    }

    func delete(_ id: String) async throws {
        try await delete([id])
    }

    /// Endpoint-nya memang menerima banyak id sekaligus, jadi seleksi tidak
    /// perlu mengirim satu request per foto.
    ///
    /// - Parameter force: `false` memindahkan ke tong sampah, `true` menghapus
    ///   permanen. Layar tong sampah memakai `true` — di sana "hapus" memang
    ///   tidak punya tempat lain untuk dituju.
    func delete(_ ids: [String], force: Bool = false) async throws {
        struct Body: Encodable { let ids: [String]; let force: Bool }
        try await api.sendVoid(.json("/assets", method: .delete, body: Body(ids: ids, force: force)))
    }

    func downloadOriginal(_ id: String) async throws -> Data {
        try await api.rawData(.init(path: "/assets/\(id)/original"))
    }
}
