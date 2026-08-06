import Foundation

class SearchRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    /// Menerima permintaan UTUH, bukan sekadar kata kuncinya.
    ///
    /// Penyaring — orang, kota, tanggal, jenis media — dikirim di badan yang sama
    /// dengan kata kuncinya; menyaringnya di klien setelah hasil datang berarti
    /// halaman kedua bisa habis tersaring dan daftarnya berhenti tanpa alasan.
    func smartSearch(_ request: SearchRequestDTO) async throws -> SearchResponseDTO {
        try await api.send(.json("/search/smart", method: .post, body: request))
    }

    func metadataSearch(_ request: SearchRequestDTO) async throws -> SearchResponseDTO {
        try await api.send(.json("/search/metadata", method: .post, body: request))
    }

    /// GET /search/suggestions wajib menyertakan `type` dan mengembalikan [String] polos.
    func suggestions(type: String = "city") async throws -> [String] {
        try await api.send(.init(
            path: "/search/suggestions",
            query: [.init(name: "type", value: type)]))
    }
}

/// GET /search/explore mengembalikan array {fieldName, items: [{value, data}]}.
struct SearchExploreItemDTO: Decodable {
    struct Item: Decodable {
        let value: String
        let data: AssetResponseDTO
    }
    let fieldName: String
    let items: [Item]
}
