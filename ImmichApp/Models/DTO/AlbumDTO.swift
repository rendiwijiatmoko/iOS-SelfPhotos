import Foundation

struct AlbumResponseDTO: Decodable, Identifiable, Hashable {
    let id: String
    /// var supaya hasil ganti nama bisa ditambal di tempat, tanpa memuat ulang
    /// seluruh daftar album.
    var albumName: String
    /// var dengan alasan yang sama seperti `albumName` — hasil sunting ditambal
    /// di tempat supaya langsung terlihat di sampul.
    var description: String?
    let assetCount: Int
    let albumThumbnailAssetId: String?
    let shared: Bool
    let createdAt: Date
    let assets: [AssetResponseDTO]?

    // Semua opsional supaya decoding tetap jalan di server versi lama yang
    // belum mengirim field-field ini. Dipakai oleh menu urutkan.
    //
    // Ditulis `var ... = nil`, bukan `let`, dengan dua alasan sekaligus:
    // memberwise init jadi punya nilai bawaan sehingga pemanggil lama tidak
    // perlu diubah, dan sintesis Decodable tetap membacanya. `let` dengan nilai
    // awal justru dilewati saat decoding karena sudah terisi dan tak bisa
    // diubah lagi.
    /// Terakhir album diubah (nama, deskripsi, isi).
    var updatedAt: Date? = nil
    /// Tanggal foto TERTUA di album.
    var startDate: Date? = nil
    /// Tanggal foto TERBARU di album.
    var endDate: Date? = nil

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AlbumResponseDTO, rhs: AlbumResponseDTO) -> Bool {
        lhs.id == rhs.id
    }
}
