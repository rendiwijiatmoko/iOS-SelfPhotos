import Foundation

/// Identitas perangkat ini di mata server.
///
/// Server memakainya untuk mengelompokkan aset menurut asalnya — "diunggah dari
/// iPhone ini". Karena itu ia harus **tetap sama** selama aplikasinya terpasang;
/// nilai yang berubah membuat pustaka yang sama terlihat datang dari selusin
/// perangkat berbeda.
///
/// UUID yang disimpan sendiri, BUKAN `identifierForVendor`.
///
/// Yang terakhir terdengar tepat tapi tidak: nilainya hilang begitu semua
/// aplikasi dari vendor yang sama dicopot, dan ia bisa mengembalikan nil pada
/// pemakaian pertama sebelum perangkatnya dibuka kunci. Keduanya berarti
/// identitas yang berganti diam-diam. UUID yang kita buat sendiri tidak punya
/// dua masalah itu.
enum DeviceIdentity {
    private static let key = "device.identity"

    static let current: String = {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: key)
        return fresh
    }()
}
