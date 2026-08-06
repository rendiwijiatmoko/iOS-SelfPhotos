import Observation
import SwiftUI

struct OfflineBanner: View {
    let isOnline: Bool

    var body: some View {
        if !isOnline {
            HStack {
                Image(systemName: "wifi.slash")
                Text("Offline Mode - Showing Cached Photos")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal)
            .background(.orange.opacity(0.1))
            .foregroundStyle(.orange)
        }
    }
}

/// Layar yang menampilkan satu foto memenuhi layar meminta pitanya menyingkir.
///
/// Pita itu keterangan tentang keadaan aplikasi, dan di layar detail ia menyita
/// ruang dari satu-satunya hal yang sedang dilihat. Layar itu punya caranya
/// sendiri untuk berterus terang: aksi yang gagal memunculkan toast, dan panel
/// info tetap terisi dari potret lokal.
///
/// **Kenapa objek bersama, bukan `PreferenceKey`.** Layar detail muncul lewat
/// dua jalur yang sangat berbeda — didorong ke dalam `NavigationStack` milik
/// sebuah tab, dan dipresentasikan `UIHostingController` di atas seluruh scene.
/// Preference hanya merambat pada yang pertama.
///
/// Penghitung, bukan bendera: pembukaan berikutnya bisa mulai sebelum yang
/// sebelumnya benar-benar lepas, dan satu bendera akan dimatikan oleh layar yang
/// pergi meski masih ada yang tinggal.
@MainActor
@Observable
final class OfflineBannerSuppression {
    static let shared = OfflineBannerSuppression()

    private var count = 0
    var isSuppressed: Bool { count > 0 }

    private init() {}

    func begin() { count += 1 }
    func end() { count = max(0, count - 1) }
}

#Preview {
    OfflineBanner(isOnline: false)
}
