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
