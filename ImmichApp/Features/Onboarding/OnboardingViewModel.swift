import Foundation
import Observation

@MainActor
@Observable
final class OnboardingViewModel {
    var serverText = "" {
        didSet {
            guard let validatedServerText,
                  normalized(serverText) != validatedServerText
            else { return }
            self.validatedServerText = nil
            features = nil
            phase = .idle
        }
    }
    var email = ""
    var password = ""
    var apiKey = ""
    var method: Method = .password
    var phase: LoadingPhase<Void> = .idle

    /// Kemampuan server, baru diketahui SETELAH alamatnya berhasil dihubungi.
    ///
    /// Dipakai untuk menyembunyikan tab yang tidak berlaku — mis. server
    /// OAuth-only yang mematikan login kata sandi.
    var features: ServerFeaturesDTO?
    private(set) var validatedServerText: String?

    enum Method: String, CaseIterable, Identifiable {
        case password, apiKey
        var id: Self { self }
    }

    private let session: SessionManager

    init(session: SessionManager) {
        self.session = session
        serverText = UserDefaults.standard.string(forKey: Self.lastServerKey) ?? ""
        if let issue = session.compatibilityIssue {
            phase = .failed(issue.localizedDescription)
        }
    }

    /// Alamat server terakhir yang BERHASIL dipakai.
    ///
    /// Diisikan lagi saat percobaan login biasa dibuka ulang, tetapi ikut
    /// dibuang saat logout penuh bersama data akun lainnya.
    private static let lastServerKey = "onboarding.lastServer"

    static func clearStoredServer() {
        UserDefaults.standard.removeObject(forKey: lastServerKey)
    }

    var canConnect: Bool {
        !normalized(serverText).isEmpty
    }

    var canSubmit: Bool {
        guard validatedServerText != nil else { return false }
        switch method {
        case .password: return !email.isEmpty && !password.isEmpty
        case .apiKey:   return !apiKey.isEmpty
        }
    }

    /// Tahap pertama hanya menyentuh endpoint publik. Kredensial belum pernah
    /// dikirim ketika alamat salah, server tidak tersedia, atau versinya tidak
    /// kompatibel.
    @discardableResult
    func connectToServer() async -> Bool {
        guard canConnect else { return false }
        phase = .loading
        do {
            try session.setServer(serverText)
            let compatibility = try await session.checkServerCompatibility()
            features = compatibility.features
            validatedServerText = normalized(serverText)
            if !compatibility.features.passwordLogin {
                method = .apiKey
            }
            phase = .loaded(())
            return true
        } catch {
            validatedServerText = nil
            features = nil
            phase = .failed(message(for: error))
            return false
        }
    }

    /// Tahap kedua hanya mengirim kredensial ke server yang sudah lolos tahap
    /// koneksi. Kembali ke halaman server dan mengubah alamat membatalkan gate.
    @discardableResult
    func signIn() async -> Bool {
        guard canSubmit else { return false }
        phase = .loading
        do {
            switch method {
            case .password:
                guard features?.passwordLogin == true else {
                    throw ServerCompatibilityError.passwordLoginUnavailable
                }
                try await session.loginPassword(email: email, password: password)
            case .apiKey:
                try await session.loginApiKey(apiKey)
            }

            UserDefaults.standard.set(serverText, forKey: Self.lastServerKey)
            phase = .loaded(())
            return true
        } catch {
            phase = .failed(message(for: error))
            return false
        }
    }

    func prepareToEditServer() {
        phase = .idle
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Galat sambungan dan galat kredensial dibedakan: keduanya menuntut
    /// perbaikan di kolom yang berbeda.
    private func message(for error: Error) -> String {
        guard let apiError = error as? APIError else {
            return error.localizedDescription
        }
        switch apiError {
        case .unauthorized:
            return method == .apiKey
                ? String(localized: "That API key was rejected.")
                : String(localized: "Wrong email or password.")
        case .notConnected:
            return String(localized: "No internet connection.")
        case .invalidURL:
            return String(localized: "That server address doesn't look right.")
        default:
            return apiError.errorDescription
                ?? String(localized: "Couldn't reach that server.")
        }
    }
}
