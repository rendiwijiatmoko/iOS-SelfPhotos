import Foundation
import Observation

/// Aset yang sudah TIDAK ADA lagi, sepanjang sesi ini.
///
/// **Masalah yang dipecahkannya.** Menghapus foto dari linimasa membereskan
/// cache linimasa — dan hanya itu. Album, Favorites, dan foto per orang punya
/// daftarnya masing-masing yang diambil dari endpoint lain dan disimpan sebagai
/// potret terpisah. Tidak ada satu pun dari daftar itu yang tahu bahwa fotonya
/// baru saja dibuang, jadi foto yang sudah dihapus tetap berdiri di sana sampai
/// layarnya memuat ulang dari server.
///
/// Menyisir setiap potret setiap kali sesuatu dihapus akan berarti membaca,
/// menyunting, dan menulis ulang selusin berkas JSON untuk satu ketukan. Yang
/// dilakukan di sini kebalikannya: daftar id yang dibuang disimpan sekali di
/// memori, dan setiap layar menyaring miliknya sendiri lewat daftar itu.
///
/// Sengaja TIDAK bertahan antar peluncuran. Isinya cuma tambalan sampai sync
/// berikutnya membawa kebenaran dari server — menyimpannya ke disk berarti
/// menyimpan tebakan yang bisa keliru selamanya.
///
/// Polanya sama dengan `UnreadableAssets.shared`, dan alasannya sama: yang perlu
/// tahu tersebar di banyak layar yang tidak saling mengenal.
@MainActor
@Observable
final class RemovedAssets {
    static let shared = RemovedAssets()

    private(set) var ids: Set<String> = []

    private init() {}

    func remove(_ removed: [String]) {
        guard !removed.isEmpty else { return }
        ids.formUnion(removed)
    }

    /// Dipakai saat foto DIKEMBALIKAN dari tong sampah.
    ///
    /// Tanpa ini, memulihkan foto yang barusan dibuang akan menghasilkan foto
    /// yang ada di server tapi tetap tak terlihat di aplikasi — tersaring oleh
    /// catatan yang sudah tidak berlaku.
    func restore(_ restored: [String]) {
        guard !restored.isEmpty else { return }
        ids.subtract(restored)
    }

    /// Menyaring daftar apa pun. Pulang apa adanya kalau tidak ada yang dibuang —
    /// keadaan yang paling sering terjadi, dan tidak perlu membayar satu lintasan
    /// untuknya.
    func filter(_ assets: [AssetLite]) -> [AssetLite] {
        guard !ids.isEmpty else { return assets }
        return assets.filter { !ids.contains($0.id) }
    }
}
