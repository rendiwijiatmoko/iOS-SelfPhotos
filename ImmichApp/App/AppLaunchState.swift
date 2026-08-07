import Foundation
import Observation

/// Penanda "aplikasi siap ditampilkan".
///
/// Yang ditunggu bukan jaringan, melainkan pembacaan cache lokal dan
/// pengelompokannya jadi linimasa — sepersekian detik yang, tanpa penutup apa
/// pun, terlihat sebagai layar kosong berkedip tepat setelah aplikasi dibuka.
///
/// Dipisah dari view model mana pun karena yang memakainya adalah akar aplikasi,
/// sementara yang menyalakannya ada jauh di dalam linimasa.
@MainActor
@Observable
final class AppLaunchState {
    static let shared = AppLaunchState()

    private(set) var isReady = false

    private init() {}

    func markReady() {
        guard !isReady else { return }
        isReady = true
    }

    func reset() {
        isReady = false
    }
}
