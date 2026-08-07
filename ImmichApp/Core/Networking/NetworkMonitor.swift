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
    /// Jalurnya BERBAYAR — seluler, atau hotspot.
    ///
    /// Immich resmi hanya mengunggah lewat Wi‑Fi secara bawaan, dan alasannya
    /// berlaku sama untuk pencocokan checksum: foto yang aslinya di iCloud harus
    /// diunduh dulu untuk dihitung, dan itu bisa berarti gigabyte.
    private(set) var isExpensive = false

    private let monitor = NWPathMonitor()

    private init() {
        // `[weak self]` ada di Task DALAM, bukan di handler luar.
        //
        // Handler-nya dipanggil di antrean milik `NWPathMonitor`, jadi `self`
        // yang tertangkap di sana adalah rujukan yang dipakai lintas isolasi —
        // peringatan di Swift 5, kesalahan di Swift 6. Yang menyeberang sekarang
        // hanya sebuah `Bool`.
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            let expensive = path.isExpensive || path.isConstrained
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isOnline != online { self.isOnline = online }
                if self.isExpensive != expensive { self.isExpensive = expensive }
            }
        }
        monitor.start(queue: DispatchQueue(label: "network-monitor"))
    }
}
