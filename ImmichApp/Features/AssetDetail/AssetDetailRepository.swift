import Foundation

/// Satu operasi editor yang dipahami endpoint Immich `/assets/{id}/edits`.
struct AssetEditCommand: Encodable, Sendable {
    enum Payload: Sendable {
        case crop(x: Int, y: Int, width: Int, height: Int)
        case rotate(angle: Double)
        case mirror(axis: String)
    }

    let payload: Payload

    private enum CodingKeys: String, CodingKey { case action, parameters }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch payload {
        case .crop(let x, let y, let width, let height):
            struct Parameters: Encodable { let x: Int; let y: Int; let width: Int; let height: Int }
            try container.encode("crop", forKey: .action)
            try container.encode(
                Parameters(x: x, y: y, width: width, height: height),
                forKey: .parameters)
        case .rotate(let angle):
            struct Parameters: Encodable { let angle: Double }
            try container.encode("rotate", forKey: .action)
            try container.encode(Parameters(angle: angle), forKey: .parameters)
        case .mirror(let axis):
            struct Parameters: Encodable { let axis: String }
            try container.encode("mirror", forKey: .action)
            try container.encode(Parameters(axis: axis), forKey: .parameters)
        }
    }
}

struct AssetEditRecord: Decodable, Sendable {
    struct Parameters: Decodable, Sendable {
        let x: Int?
        let y: Int?
        let width: Int?
        let height: Int?
        let angle: Double?
        let axis: String?
    }

    let action: String
    let parameters: Parameters
}

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

    /// Original/hasil edit diunduh sebagai file agar video tidak masuk RAM.
    func downloadOriginalFile(_ id: String, filename: String) async throws -> URL {
        let temporary = try await api.rawFile(.init(
            path: "/assets/\(id)/original",
            query: [.init(name: "edited", value: "true")]))
        let safeName = URL(fileURLWithPath: filename).lastPathComponent
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("asset-\(UUID().uuidString)-\(safeName)")
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    func applyEdits(_ edits: [AssetEditCommand], to id: String) async throws {
        struct Body: Encodable { let edits: [AssetEditCommand] }
        struct Response: Decodable { let assetId: String }
        let _: Response = try await api.send(.json(
            "/assets/\(id)/edits", method: .put, body: Body(edits: edits)))
    }

    func removeEdits(from id: String) async throws {
        try await api.sendVoid(.init(path: "/assets/\(id)/edits", method: .delete))
    }

    func edits(for id: String) async throws -> [AssetEditRecord] {
        struct Response: Decodable { let edits: [AssetEditRecord] }
        let response: Response = try await api.send(.init(path: "/assets/\(id)/edits"))
        return response.edits
    }

    /// Immich menerima avatar sebagai multipart dengan nama field `file`.
    func setProfileImage(_ data: Data, filename: String) async throws {
        struct Response: Decodable { let profileImagePath: String }

        let boundary = "Profile-\(UUID().uuidString)"
        var body = Data()
        func append(_ text: String) {
            if let bytes = text.data(using: .utf8) { body.append(bytes) }
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: image/jpeg\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")

        let _: Response = try await api.send(.init(
            path: "/users/profile-image",
            method: .post,
            body: body,
            extraHeaders: ["Content-Type": "multipart/form-data; boundary=\(boundary)"]))
    }
}
