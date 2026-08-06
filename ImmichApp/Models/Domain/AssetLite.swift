import Foundation

/// `Codable` ada DI SINI, bukan di `LocalSnapshot` yang memakainya: Swift hanya
/// mensintesisnya pada deklarasi tipe atau extension di berkas yang sama.
/// Dipakai untuk memotret isi layar ke disk supaya tetap tergambar saat offline.
struct AssetLite: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let isVideo: Bool
    let ratio: Double
    let thumbhash: String?
    let createdAt: Date
    /// var supaya grid bisa menampilkan status favorit tanpa memuat detail
    /// penuh, dan memperbaruinya di tempat setelah aksi context menu.
    var isFavorite: Bool = false
    /// Durasi video dalam detik; nil untuk foto.
    ///
    /// Ikut dibawa sampai ke grid supaya petak video bisa menuliskan lamanya
    /// tanpa memuat detail penuh satu per satu.
    var duration: Double? = nil
    /// Id aset video pasangan sebuah Live Photo; nil untuk foto biasa.
    ///
    /// Ikut dibawa ke grid dan pager supaya lencana LIVE dan tekan-tahannya
    /// tidak perlu memuat detail penuh satu per satu.
    var livePhotoVideoID: String? = nil

    var isLivePhoto: Bool { livePhotoVideoID != nil }

    /// "1:35" — nil kalau bukan video atau durasinya tidak diketahui.
    var durationText: String? {
        guard let duration, duration > 0 else { return nil }
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // Identitas ditentukan HANYA oleh id.
    //
    // Kalau `isFavorite` ikut dibandingkan, satu foto yang status favoritnya
    // berubah akan dianggap objek berbeda — `firstIndex(of:)` meleset dan
    // `onChange(of: currentAsset)` di layar detail ikut terpicu tanpa foto
    // yang sebenarnya berpindah.
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AssetLite, rhs: AssetLite) -> Bool {
        lhs.id == rhs.id
    }
}

/// Init tambahan HARUS di extension.
///
/// Mendeklarasikannya di dalam struct membuat Swift berhenti membangkitkan
/// memberwise init — dan seluruh pemanggil `AssetLite(id:isVideo:...)` ikut
/// gagal kompilasi.
extension AssetLite {
    /// Konversi dari DTO lengkap; dipakai semua layar yang sumbernya
    /// `/search/metadata` (favorit, video, arsip, trash, orang).
    init(_ asset: AssetResponseDTO) {
        var ratio = 1.0
        if let width = asset.exifInfo?.exifImageWidth,
           let height = asset.exifInfo?.exifImageHeight,
           width > 0, height > 0 {
            ratio = Double(width) / Double(height)
        }

        self.init(
            id: asset.id,
            isVideo: asset.isVideo,
            ratio: ratio,
            thumbhash: asset.thumbhash,
            createdAt: asset.fileCreatedAt,
            isFavorite: asset.isFavorite,
            duration: asset.duration,
            livePhotoVideoID: asset.livePhotoVideoId)
    }
}
