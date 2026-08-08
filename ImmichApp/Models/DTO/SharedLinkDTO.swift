import Foundation

struct SharedLinkDTO: Decodable, Identifiable {
    let id: String
    /// Kunci acak yang menyusun URL publiknya.
    let key: String
    /// "ALBUM" atau "INDIVIDUAL".
    let type: String

    var description: String?
    var password: String?
    var expiresAt: Date?
    var createdAt: Date?
    var allowUpload: Bool
    var allowDownload: Bool
    var showMetadata: Bool
    /// Bagian akhir URL kustom ("/s/{slug}"); nil kalau tautannya memakai kunci
    /// acaknya.
    var slug: String?
    /// Terisi untuk tautan album.
    var album: AlbumResponseDTO?
    /// Terisi untuk tautan foto lepas.
    var assets: [AssetResponseDTO]?

    /// Decoding ditulis tangan, bukan disintesis.
    ///
    /// Nilai bawaan pada properti TIDAK membuat sintesis Decodable memaafkan
    /// field yang hilang — pemilihan `decode` vs `decodeIfPresent` semata-mata
    /// dari apakah tipenya opsional. Untuk `allowUpload`, `allowDownload`, dan
    /// `showMetadata` yang bertipe `Bool`, satu field yang tidak dikirim server
    /// versi lain akan menjatuhkan decoding SELURUH daftar tautan, bukan cuma
    /// satu barisnya.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        key = try c.decode(String.self, forKey: .key)
        type = try c.decode(String.self, forKey: .type)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        password = try c.decodeIfPresent(String.self, forKey: .password)
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        allowUpload = try c.decodeIfPresent(Bool.self, forKey: .allowUpload) ?? false
        allowDownload = try c.decodeIfPresent(Bool.self, forKey: .allowDownload) ?? true
        showMetadata = try c.decodeIfPresent(Bool.self, forKey: .showMetadata) ?? true
        slug = try c.decodeIfPresent(String.self, forKey: .slug)
        album = try c.decodeIfPresent(AlbumResponseDTO.self, forKey: .album)
        assets = try c.decodeIfPresent([AssetResponseDTO].self, forKey: .assets)
    }

    private enum CodingKeys: String, CodingKey {
        case id, key, type, description, password, expiresAt, createdAt
        case allowUpload, allowDownload, showMetadata, slug, album, assets
    }

    var isAlbum: Bool { type == "ALBUM" }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }

    /// Nama yang ditampilkan: deskripsi kalau ada, kalau tidak nama albumnya.
    var displayName: String? {
        if let description, !description.isEmpty { return description }
        return album?.albumName
    }

    /// URL yang bisa dibagikan, dirakit dari base URL server.
    ///
    /// Immich tidak mengirim URL jadi — server hanya tahu kuncinya, sedangkan
    /// alamat yang dipakai klien bisa berbeda (mis. lewat reverse proxy).
    ///
    /// Bentuk `/s/{slug}` didahulukan kalau tautannya punya URL kustom; itu yang
    /// dilihat penerima, dan menyalin bentuk `/share/{key}` untuk tautan yang
    /// sudah diberi nama sendiri hanya membingungkan.
    func publicURL(base: URL?) -> URL? {
        guard let base else { return nil }
        let root = base.deletingLastPathComponent()

        if let slug, !slug.isEmpty {
            return root.appendingPathComponent("s").appendingPathComponent(slug)
        }
        return root.appendingPathComponent("share").appendingPathComponent(key)
    }
}

/// Perubahan yang dikirim ke `PATCH /shared-links/{id}`.
///
/// Semua opsional: field yang tidak diisi tidak ikut terkirim dan nilainya di
/// server dibiarkan apa adanya.
struct SharedLinkEditDTO: Encodable {
    /// Optional berlapis membedakan "jangan ubah" (`nil`) dari "hapus"
    /// (`.some(nil)`). SharedLinkEditDto v3 menerima null secara langsung.
    var description: String?? = nil
    var password: String?? = nil
    var expiresAt: Date?? = nil
    var allowUpload: Bool? = nil
    var allowDownload: Bool? = nil
    var showMetadata: Bool? = nil
    /// Opsional BERLAPIS, dan itu disengaja.
    ///
    /// `encodeIfPresent` membuang lapisan luarnya: `nil` berarti fieldnya tidak
    /// ikut terkirim ("jangan sentuh"), sedangkan `.some(nil)` terkirim sebagai
    /// `null` ("hapus URL kustomnya"). Dengan satu lapis saja, URL kustom yang
    /// dikosongkan pengguna tidak akan pernah benar-benar terhapus — bidangnya
    /// terisi lagi begitu sheet dibuka ulang.
    var slug: String?? = nil
}
