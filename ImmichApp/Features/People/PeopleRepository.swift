import Foundation

class PeopleRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    /// - Parameter size: batas dari SERVER, bukan dipotong setelah diterima.
    ///   Baris di Library cuma menampilkan belasan orang; menarik seluruhnya
    ///   lalu membuang sisanya hanya membuang waktu dan memori.
    func all(size: Int? = nil) async throws -> [PersonDTO] {
        struct Response: Decodable {
            let people: [PersonDTO]
        }
        var query: [URLQueryItem] = [.init(name: "withHidden", value: "false")]
        if let size { query.append(.init(name: "size", value: String(size))) }

        let response: Response = try await api.send(
            .init(path: "/people", query: query))
        return response.people
    }

    /// GET /people/{id} hanya mengembalikan data orangnya; asetnya
    /// diambil terpisah lewat POST /search/metadata.
    func detail(_ id: String) async throws -> PersonDTO {
        try await api.send(.init(path: "/people/\(id)"))
    }

    func assets(personId: String, page: Int = 1) async throws -> SearchResponseDTO {
        var request = SearchRequestDTO(page: page)
        request.personIds = [personId]
        request.size = 100
        return try await api.send(.json("/search/metadata", method: .post, body: request))
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
