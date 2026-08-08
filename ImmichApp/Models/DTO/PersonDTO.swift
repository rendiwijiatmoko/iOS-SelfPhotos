import Foundation

/// `Encodable` ada DI SINI, bukan di `LocalSnapshot` yang memakainya: Swift
/// hanya mensintesisnya pada deklarasi tipe atau extension di berkas yang sama.
struct PersonDTO: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    let birthDate: Date?
    let thumbnailPath: String?
    var isHidden: Bool
}

/// Kontrak bulk update stabil Immich (`PUT /people`).
struct PeopleUpdateRequestDTO: Encodable {
    struct Item: Encodable {
        let id: String
        var name: String? = nil
        var isHidden: Bool? = nil
    }

    let people: [Item]
}

/// Respons per item dari operasi bulk Immich.
struct BulkIDResponseDTO: Decodable {
    let id: String
    let success: Bool
    let error: String?
    let errorMessage: String?
}
