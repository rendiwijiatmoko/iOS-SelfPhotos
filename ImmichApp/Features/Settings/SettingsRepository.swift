import Foundation

final class SettingsRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func getUser() async throws -> UserResponseDTO {
        try await api.send(.init(path: "/users/me"))
    }

    func getPreferences() async throws -> UserPreferencesDTO {
        try await api.send(.init(path: "/users/me/preferences"))
    }

    func updatePreferences(_ prefs: UserPreferencesDTO) async throws {
        try await api.sendVoid(.json("/users/me/preferences", method: .put, body: prefs))
    }

    func getServerInfo() async throws -> ServerAboutDTO {
        try await api.send(.init(path: "/server/about"))
    }

    func getStorageInfo() async throws -> ServerStorageDTO {
        try await api.send(.init(path: "/server/storage"))
    }

    func logout() async throws {
        try await api.sendVoid(.init(path: "/auth/logout", method: .post))
    }
}
