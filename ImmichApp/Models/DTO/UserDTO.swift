import Foundation

struct UserResponseDTO: Decodable, Identifiable {
    let id: String
    let email: String
    let name: String
    let profileImagePath: String?
    let storageLabel: String?
}
