import Foundation

struct PersonDTO: Decodable, Identifiable, Hashable {
    let id: String
    var name: String
    let birthDate: Date?
    let thumbnailPath: String?
    var isHidden: Bool
}
