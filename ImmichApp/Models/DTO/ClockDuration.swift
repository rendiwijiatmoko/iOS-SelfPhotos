import Foundation

/// Durasi ala Immich: `"0:01:23.45000"`.
///
/// Server mengirim kolom durasi APA ADANYA dari database — sebuah interval yang
/// diserialisasi jadi string jam, bukan angka. Bentuk itu muncul di beberapa
/// endpoint sekaligus (`/assets/{id}` dan kolom `duration` di
/// `/timeline/bucket`), jadi penguraiannya ditulis SEKALI di sini.
///
/// Salinan yang berbeda-beda persis yang bikin repot: `/assets/{id}` sudah
/// diperbaiki untuk menerima string, sementara kolom timeline masih menganggap
/// isinya angka milidetik — dan bug yang sama harus ditemukan dua kali.
enum ClockDuration {
    /// "0:01:23.45000" → 83.45 detik. nil kalau bukan format jam.
    static func seconds(fromClock text: String?) -> Double? {
        guard let text, !text.isEmpty else { return nil }

        // Bagian yang tidak terbaca membuat SELURUH nilainya batal, bukan
        // dilewati. Melewatinya (`compactMap`) berarti "1:xx:35" diam-diam
        // dibaca sebagai 1 menit 35 detik — sisa bagiannya bergeser tempat dan
        // hasilnya angka yang salah tanpa ada tanda apa pun.
        let components = text.split(separator: ":")
        let parts = components.compactMap { Double($0) }
        guard !parts.isEmpty, parts.count == components.count else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }
}

/// Satu sel kolom `duration` pada respons berbentuk kolom.
///
/// Sebelumnya kolomnya dideklarasikan `[Int?]`. Untuk foto server mengirim null,
/// jadi bucket yang isinya foto saja lolos — tapi satu video saja di dalamnya
/// sudah cukup untuk menjatuhkan decoding SELURUH bucket, dan album yang
/// memuatnya berhenti di "Failed to read data from server". Itulah kenapa yang
/// gagal cuma sebagian album.
///
/// Ditulis sebagai enum, bukan `String?`, supaya perbedaan bentuk antar versi
/// server tidak lagi menjatuhkan apa pun: yang tidak dikenali kehilangan label
/// durasinya saja, bukan seluruh albumnya.
enum DurationColumn: Decodable {
    case clock(String)
    case milliseconds(Double)
    case absent

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .absent
        } else if let text = try? container.decode(String.self) {
            self = .clock(text)
        } else if let number = try? container.decode(Double.self) {
            self = .milliseconds(number)
        } else {
            self = .absent
        }
    }

    /// Durasi dalam DETIK.
    ///
    /// Kontrak `TimeBucketAssetResponseDto.duration` v3 menggunakan integer
    /// milidetik. String jam tetap diterima untuk kompatibilitas server lama.
    var seconds: Double? {
        switch self {
        case .clock(let text): return ClockDuration.seconds(fromClock: text)
        case .milliseconds(let value): return value / 1_000
        case .absent: return nil
        }
    }
}
