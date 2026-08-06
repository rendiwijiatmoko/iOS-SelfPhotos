import Observation
import SwiftUI

/// Bulan yang sedang berada di tepi atas layar.
///
/// Dipisah dari `TimelineView` dengan sengaja. Nilainya berubah puluhan kali
/// selama satu gulir, dan sebagai `@State` milik layar itu setiap perubahannya
/// menggambar ulang seluruh body — termasuk grid berisi puluhan ribu sel —
/// hanya untuk memperbarui sebaris teks di toolbar.
///
/// Dengan `@Observable` di objek terpisah, hanya `VisibleMonthLabel` yang
/// berlangganan, jadi yang digambar ulang cuma label itu.
@MainActor
@Observable
final class VisibleMonthTracker {
    private(set) var title = ""
    /// `startIndex` section yang sedang tampil; dipakai membandingkan urutan
    /// tanpa memindai daftar.
    private var currentStart = 0

    /// Bulan yang sedang berada di tepi atas layar.
    ///
    /// Sekarang cukup satu arah: collection view sendiri yang memberi tahu
    /// section mana yang paling atas, jadi tidak perlu lagi menyimpulkannya dari
    /// arah gerak probe geometri.
    func show(_ section: TimelineSection) {
        currentStart = section.startIndex
        setTitle(section.title)
    }

    func reset() {
        currentStart = 0
        title = ""
    }

    /// Hanya ditulis kalau benar-benar berbeda: probe memanggil ini berkali-kali
    /// per detik dengan bulan yang sama.
    private func setTitle(_ new: String) {
        guard title != new else { return }
        title = new
    }
}

struct VisibleMonthLabel: View {
    let tracker: VisibleMonthTracker

    var body: some View {
        Text(tracker.title)
            .font(.headline.bold())
    }
}
