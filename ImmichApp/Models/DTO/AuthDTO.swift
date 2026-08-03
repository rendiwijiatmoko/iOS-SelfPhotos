import Foundation

struct LoginRequestDTO: Encodable {
    let email: String
    let password: String
}

struct LoginResponseDTO: Decodable {
    let accessToken: String
    let userId: String
    let userEmail: String
    let name: String
    let isAdmin: Bool
    let shouldChangePassword: Bool
}
