import Foundation

struct PersonDTO: Decodable, Identifiable {
    let id: String
    let name: String
    let birthDate: Date?
    let thumbnailPath: String?
    let isHidden: Bool
}
