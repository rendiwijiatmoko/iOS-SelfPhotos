import Foundation
import Observation

@MainActor
@Observable
final class OnboardingViewModel {
    var serverText = "https://photos.0xmwehehe.xyz"
    var email = ""
    var password = ""
    var apiKey = ""
    var features: ServerFeaturesDTO?
    var phase: LoadingPhase<Void> = .idle
    var step: Step = .server
    var showApiKeyTab = false

    enum Step { case server, login }

    private let session: SessionManager

    init(session: SessionManager) {
        self.session = session
    }

    func connect() async {
        phase = .loading
        do {
            try session.setServer(serverText)
            try await session.ping()
            features = try await session.features()
            step = .login
            phase = .idle
        } catch {
            phase = .failed((error as? APIError)?.errorDescription ?? String(localized: "Failed to connect"))
        }
    }

    func loginPassword() async {
        phase = .loading
        do {
            try await session.loginPassword(email: email, password: password)
        } catch {
            phase = .failed((error as? APIError)?.errorDescription ?? String(localized: "Sign in failed"))
        }
    }

    func loginApiKey() async {
        phase = .loading
        do {
            try await session.loginApiKey(apiKey)
        } catch {
            phase = .failed(String(localized: "Invalid API Key"))
        }
    }

    func reset() {
        step = .server
        serverText = ""
        email = ""
        password = ""
        apiKey = ""
        features = nil
        phase = .idle
    }
}
