import Foundation

final class DuplicateRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    /// GET /duplicates mengembalikan array grup secara langsung.
    func all() async throws -> [DuplicateGroupDTO] {
        try await api.send(.init(path: "/duplicates"))
    }

    /// Menyatukan metadata grup dan memindahkan aset yang tidak dipertahankan
    /// ke Trash. Responsnya tetap perlu diperiksa: operasi bulk dapat berstatus
    /// HTTP 200 sementara satu grup di dalamnya gagal.
    func resolve(_ group: DuplicateResolveGroupDTO) async throws {
        let results: [BulkIDResponseDTO] = try await api.send(.json(
            "/duplicates/resolve",
            method: .post,
            body: DuplicateResolveRequestDTO(groups: [group])))

        guard let result = results.first(where: { $0.id == group.duplicateId }),
              result.success
        else {
            let failure = results.first(where: { $0.id == group.duplicateId })
            throw APIError.server(
                status: 200,
                message: failure?.errorMessage ?? String(localized: "Failed to resolve duplicates"))
        }
    }

    /// Menghapus *penanda grup*, bukan asetnya. Ini adalah aksi "Keep All".
    func dismiss(_ duplicateId: String) async throws {
        try await api.sendVoid(.init(
            path: "/duplicates/\(duplicateId)", method: .delete))
    }
}
