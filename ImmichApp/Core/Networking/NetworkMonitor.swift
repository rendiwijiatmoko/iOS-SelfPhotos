import Foundation
import Network
import Observation

/// Satu-satunya sumber kebenaran tentang "ada jalan ke jaringan atau tidak".
///
/// **Kenapa singleton, bukan environment.** Layar detail aset dipresentasikan
/// oleh grid `UICollectionView` lewat `UIHostingController`, dan hosting
/// controller TIDAK mewarisi environment SwiftUI — itu sebabnya `session` harus
/// disuntikkan tangan di setiap `detailScreen(for:)`. Menambahkan satu lagi yang
/// harus diingat di lima tempat berbeda adalah undangan untuk lupa di tempat
/// keenam, dan lupanya tidak berbunyi: nilainya cuma jadi nil dan layarnya diam-
/// diam mengira dirinya online.
///
/// Repo ini sudah punya polanya — `SwiftDataManager.shared`, `UnreadableAssets
/// .shared` — dan alasannya sama persis.
@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    /// Ada jalur jaringan yang siap. BUKAN berarti server Immich terjangkau:
    /// server di jaringan rumah tetap tidak terjawab saat kita di luar, padahal
    /// jalurnya "siap". Untuk itulah `APIError.notConnected` diperlebar.
    private(set) var isOnline = true

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self, self.isOnline != online else { return }
                self.isOnline = online
            }
        }
        monitor.start(queue: DispatchQueue(label: "network-monitor"))
    }
}
