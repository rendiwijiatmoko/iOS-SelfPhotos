import Foundation
import Observation

@MainActor
@Observable
final class OnboardingViewModel {
    var serverText = ""
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

    enum Method: String, CaseIterable, Identifiable {
        case password, apiKey
        var id: Self { self }
    }

    private let session: SessionManager

    init(session: SessionManager) {
        self.session = session
        serverText = UserDefaults.standard.string(forKey: Self.lastServerKey) ?? ""
    }

    /// Alamat server terakhir yang BERHASIL dipakai.
    ///
    /// Diisikan lagi saat layar dibuka: setelah keluar akun, mengetik ulang URL
    /// server yang sama adalah pekerjaan yang tidak perlu — dan URL itu bukan
    /// rahasia, tidak seperti kredensialnya.
    private static let lastServerKey = "onboarding.lastServer"

    var canSubmit: Bool {
        guard !serverText.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch method {
        case .password: return !email.isEmpty && !password.isEmpty
        case .apiKey:   return !apiKey.isEmpty
        }
    }

    /// Menyambung dan masuk dalam SATU tindakan.
    ///
    /// Dulu ini dua langkah terpisah dengan layar sendiri-sendiri. Memisahkannya
    /// tidak memberi apa pun kepada pengguna — alamat server dan kredensial
    /// sama-sama harus benar sebelum ada yang terjadi — dan justru menambah satu
    /// ketukan serta satu layar yang harus di-"Back".
    func submit() async {
        phase = .loading
        do {
            try session.setServer(serverText)
            try await session.ping()
            // Fitur diambil sebelum masuk supaya kalau kata sandi ditolak karena
            // server memang mematikan login kata sandi, pilihannya sudah ikut
            // menyesuaikan saat pesan galatnya muncul.
            features = try? await session.features()

            switch method {
            case .password:
                try await session.loginPassword(email: email, password: password)
            case .apiKey:
                try await session.loginApiKey(apiKey)
            }

            UserDefaults.standard.set(serverText, forKey: Self.lastServerKey)
        } catch {
            phase = .failed(message(for: error))
        }
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
