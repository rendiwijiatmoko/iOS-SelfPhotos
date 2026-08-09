import Foundation
import Observation

/// Penanda "aplikasi siap ditampilkan".
///
/// Untuk tab Photos, tanda ini baru menyala setelah sync pembuka selesai,
/// snapshot final terpasang, dan collection view sudah benar-benar berada di
/// foto terbaru. Dengan begitu splash tidak menghilang ke snapshot cache lama
/// yang sesaat kemudian melompat lagi.
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
