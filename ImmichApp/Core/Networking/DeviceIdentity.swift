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
    static let current = SharedDeviceIdentity.current
}
