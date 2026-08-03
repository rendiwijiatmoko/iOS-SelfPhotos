import Foundation
import Observation

@MainActor
@Observable
final class SessionManager {
    enum AuthMode: String { case bearer, apiKey }

    private(set) var baseURL: URL?
    private(set) var currentUser: UserResponseDTO?
    var isLoggedIn: Bool = false

    private var token: String?
    private var mode: AuthMode = .bearer

    nonisolated var authHeaders: [String: String] {
        MainActor.assumeIsolated {
            guard let token else { return [:] }
            return mode == .bearer ? ["Authorization": "Bearer \(token)"]
                                   : ["x-api-key": token]
        }
    }

    private lazy var api = APIClient(session: self)

    func setServer(_ raw: String) throws {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if !s.hasPrefix("http") { s = "https://" + s }
        if s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s + "/api") else { throw APIError.invalidURL }
        baseURL = url
    }

    func ping() async throws { let _: ServerPingDTO = try await api.send(.init(path: "/server/ping")) }
    func features() async throws -> ServerFeaturesDTO { try await api.send(.init(path: "/server/features")) }

    func loginPassword(email: String, password: String) async throws {
        let ep = Endpoint.json("/auth/login", method: .post,
                               body: LoginRequestDTO(email: email, password: password))
        let res: LoginResponseDTO = try await api.send(ep)
        applyAuth(token: res.accessToken, mode: .bearer)
        try await fetchMe()
        persist()
        isLoggedIn = true
    }

    func loginApiKey(_ key: String) async throws {
        applyAuth(token: key, mode: .apiKey)
        try await fetchMe()
        persist()
        isLoggedIn = true
    }

    private func fetchMe() async throws { currentUser = try await api.send(.init(path: "/users/me")) }

    func restore() async {
        guard let server = KeychainStore.read("serverURL"),
              let tok = KeychainStore.read("token"),
              let m = KeychainStore.read("mode").flatMap(AuthMode.init) else { return }
        try? setServer(server.replacingOccurrences(of: "/api", with: ""))
        applyAuth(token: tok, mode: m)
        do { try await validate(); try await fetchMe(); isLoggedIn = true }
        catch { logout() }
    }

    private func validate() async throws { try await api.sendVoid(.init(path: "/auth/validateToken", method: .post)) }

    func logout() {
        Task { try? await api.sendVoid(.init(path: "/auth/logout", method: .post)) }
        token = nil; currentUser = nil; isLoggedIn = false
        ["serverURL","token","mode"].forEach(KeychainStore.delete)
    }

    private func applyAuth(token: String, mode: AuthMode) { self.token = token; self.mode = mode }
    private func persist() {
        if let baseURL { KeychainStore.save(baseURL.absoluteString, for: "serverURL") }
        if let token { KeychainStore.save(token, for: "token") }
        KeychainStore.save(mode.rawValue, for: "mode")
    }
}

// Placeholder DTOs for SessionManager
struct UserResponseDTO: Decodable, Identifiable {
    let id: String
    let email: String
    let name: String
    let profileImagePath: String?
    let storageLabel: String?
}

struct ServerPingDTO: Decodable { let res: String }
struct ServerFeaturesDTO: Decodable {
    let smartSearch: Bool
    let facialRecognition: Bool
    let oauth: Bool
    let passwordLogin: Bool
    let search: Bool
}

struct LoginRequestDTO: Encodable { let email: String; let password: String }
struct LoginResponseDTO: Decodable {
    let accessToken: String
    let userId: String
    let userEmail: String
    let name: String
    let isAdmin: Bool
    let shouldChangePassword: Bool
}
