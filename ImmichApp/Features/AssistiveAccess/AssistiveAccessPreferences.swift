import Foundation

/// Preferensi yang disiapkan oleh supporter sebelum Assistive Access dimulai.
///
/// UserDefaults tepat untuk ini: nilainya bukan rahasia, berlaku hanya pada
/// perangkat ini, dan harus bisa dibaca scene Assistive Access saat launch
/// tanpa menunggu server.
enum AssistiveAccessPreferences {
    static let showsHomeKey = "assistiveAccess.showsHome"
    static let showsFavoritesKey = "assistiveAccess.showsFavorites"
    static let albumIDKey = "assistiveAccess.albumID"
    static let albumNameKey = "assistiveAccess.albumName"

    static let defaultShowsHome = true
    static let defaultShowsFavorites = true

    /// ID dan nama album milik satu akun; keduanya tidak boleh ikut terbawa ke
    /// akun Immich berikutnya pada perangkat yang sama.
    static func clearSelectedAlbum() {
        UserDefaults.standard.removeObject(forKey: albumIDKey)
        UserDefaults.standard.removeObject(forKey: albumNameKey)
    }
}
