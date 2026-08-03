import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    var user: UserResponseDTO?
    var preferences: UserPreferencesDTO?
    var storage: ServerStorageDTO?
    var serverInfo: ServerAboutDTO?
    var phase: LoadingPhase<Void> = .idle

    var selectedTheme: String = "system"
    var gridColumns: Int = 3

    private let repo: SettingsRepository

    init(repo: SettingsRepository) {
        self.repo = repo
    }

    func loadSettings() async {
        phase = .loading
        do {
            async let userTask = repo.getUser()
            async let storageTask = repo.getStorageInfo()
            async let serverTask = repo.getServerInfo()

            let (user, storage, server) = try await (userTask, storageTask, serverTask)

            self.user = user
            self.storage = storage
            self.serverInfo = server

            do {
                let prefs = try await repo.getPreferences()
                self.preferences = prefs

                if let theme = prefs.theme {
                    self.selectedTheme = theme
                }
                if let gridSize = prefs.gridSize {
                    self.gridColumns = gridSize
                }
            } catch {
                // Preferences endpoint might not exist, use defaults
            }

            phase = .loaded(())
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func updateTheme(_ theme: String) async {
        selectedTheme = theme
        await updatePreferences()
    }

    func updateGridColumns(_ columns: Int) async {
        gridColumns = columns
        await updatePreferences()
    }

    private func updatePreferences() async {
        guard var prefs = preferences else { return }
        prefs.theme = selectedTheme
        prefs.gridSize = gridColumns

        do {
            try await repo.updatePreferences(prefs)
            self.preferences = prefs
        } catch {
            // Silently fail - revert UI
            if let oldTheme = preferences?.theme {
                selectedTheme = oldTheme
            }
            if let oldGridSize = preferences?.gridSize {
                gridColumns = oldGridSize
            }
        }
    }

    func logout() async {
        do {
            try await repo.logout()
        } catch {
            // Handle logout error
        }
    }
}
