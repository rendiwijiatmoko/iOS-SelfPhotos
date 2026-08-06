import Foundation

struct MemoryDTO: Decodable, Identifiable {
    let id: String
    let type: String
    let memoryAt: Date
    let assets: [AssetResponseDTO]
    /// Keterangan khas jenis kenangannya. Untuk "on this day" isinya tahun asal
    /// fotonya — itulah angka yang dipakai server saat menyusun kenangan ini,
    /// jadi label "N tahun lalu" mengikutinya, bukan menghitung sendiri.
    ///
    /// Opsional karena jenis kenangan lain tidak mengirimnya.
    let data: MemoryDataDTO?
}

struct MemoryDataDTO: Decodable {
    let year: Int?
}
