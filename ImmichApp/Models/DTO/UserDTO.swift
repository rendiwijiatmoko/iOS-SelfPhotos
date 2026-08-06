import Foundation

/// `Codable`, bukan `Decodable` saja: profil ikut disimpan di perangkat supaya
/// nama dan fotonya sudah ada sejak gambar pertama, bukan setelah `/users/me`
/// menjawab.
struct UserResponseDTO: Codable, Identifiable {
    let id: String
    let email: String
    let name: String
    let profileImagePath: String?
    /// Kapan foto profilnya terakhir diganti di server.
    ///
    /// Dibiarkan sebagai teks mentah, bukan `Date`: nilainya tidak pernah
    /// ditampilkan — ia hanya jadi penanda versi pada kunci cache gambar, dan
    /// untuk keperluan itu teks apa adanya justru yang paling aman.
    let profileChangedAt: String?
    let storageLabel: String?
    let isAdmin: Bool?
}

extension UserResponseDTO {
    /// Immich mengirim string KOSONG, bukan null, untuk pengguna yang belum
    /// pernah mengunggah foto profil — jadi `!= nil` saja tidak cukup.
    var hasProfileImage: Bool {
        !(profileImagePath ?? "").isEmpty
    }

    /// Kunci cache foto profil.
    ///
    /// Penanda perubahannya ikut masuk ke kunci karena alamat endpoint-nya
    /// selalu sama persis: tanpa itu, foto lama akan terus dijawab dari cache
    /// selamanya meski penggunanya sudah menggantinya di server. Begitu
    /// penandanya berganti, kuncinya ikut berganti dan versi barunya diunduh.
    ///
    /// `profileImagePath` disertakan sebagai cadangan: nama berkasnya acak dan
    /// ikut berganti tiap unggahan, jadi perubahan tetap terdeteksi di server
    /// lama yang belum mengirim `profileChangedAt`.
    var profileImageCacheKey: String {
        "user-\(id)-profile-\(profileChangedAt ?? "")-\(profileImagePath ?? "")"
    }
}
