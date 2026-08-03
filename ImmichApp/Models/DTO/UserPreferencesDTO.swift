import Foundation

struct UserPreferencesDTO: Codable {
    let id: String
    let userId: String
    var theme: String?
    var gridSize: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case theme
        case gridSize
    }
}
