import Foundation

/// Kumpulan aset yang ditolak server, dan satu-satunya jalan membuangnya dari
/// cache lokal.
///
/// Pemuat gambar tahu id aset yang gagal tapi tidak tahu apa-apa soal
/// penyimpanan; linimasa tahu penyimpanannya tapi tidak pernah melihat kegagalan
/// tiap petak. Kotak surat ini yang menyambungkan keduanya tanpa membuat salah
/// satu tahu isi yang lain.
///
/// Tanpa ini, aset yang sudah hilang di server tetap tinggal di cache: petaknya
/// abu-abu selamanya, masih bisa ditekan, dan yang muncul cuma "Not found or no
/// asset.read access" berulang-ulang.
@MainActor
final class UnreadableAssets {
    static let shared = UnreadableAssets()

    /// Dipasang linimasa. Dipanggil dengan id yang sudah dikumpulkan, sekali per
    /// gelombang.
    var onPurge: ((Set<String>) -> Void)?

    /// Belum dibuang, menunggu gelombang berikutnya.
    private var pending: Set<String> = []
    /// Sudah pernah dibuang — supaya layar lain yang masih memegang id yang sama
    /// tidak memicu pembuangan berulang.
    private var purged: Set<String> = []
    private var flushTask: Task<Void, Never>?
    /// Kapan terakhir kali ADA gambar yang berhasil dimuat.
    ///
    /// Inilah pembeda antara "aset ini memang hilang" dan "semuanya sedang
    /// rusak". Alamat server yang salah, reverse proxy yang menjawab 404 untuk
    /// seluruh `/api`, atau server yang baru diturunkan versinya membuat SETIAP
    /// permintaan gagal dengan 400/404 — dan tanpa penjaga ini seluruh cache
    /// akan terhapus sendiri, sesuatu yang cuma bisa dipulihkan lewat sync penuh.
    ///
    /// Selama ada foto lain yang masih berhasil dimuat, kegagalan yang tersisa
    /// memang milik asetnya sendiri.
    private var lastSuccessAt: Date?
    private static let successWindow: TimeInterval = 60

    /// Jeda pengumpulan.
    ///
    /// Satu layar penuh petak mati gagal hampir bersamaan. Membuangnya satu per
    /// satu berarti selayar penuh transaksi SwiftData dan animasi grid yang
    /// saling menyusul; setengah detik sudah cukup untuk menjadikannya satu
    /// gerakan.
    private let debounce: Duration = .milliseconds(500)

    private init() {}

    /// Melaporkan kegagalan yang MEMANG menyebut satu aset.
    ///
    /// Penyaringan jenis errornya ada di sini, bukan di pemanggil, supaya
    /// aturannya cuma ditulis sekali — lihat `APIError.meansAssetIsUnreadable`.
    func report(_ assetID: String, error: Error) {
        guard let apiError = error as? APIError, apiError.meansAssetIsUnreadable else { return }
        report(assetID)
    }

    func report(_ assetID: String) {
        guard !purged.contains(assetID), pending.insert(assetID).inserted else { return }

        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: self?.debounce ?? .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Dicatat pemuat gambar setiap kali sebuah foto berhasil datang.
    func noteSuccess() {
        lastSuccessAt = Date()
    }

    /// Mengosongkan kotak surat dan melepas callback milik linimasa akun lama.
    func clear() {
        flushTask?.cancel()
        flushTask = nil
        pending.removeAll()
        purged.removeAll()
        lastSuccessAt = nil
        onPurge = nil
    }

    private func flush() {
        guard !pending.isEmpty else { return }

        // Belum ada yang memasang telinga — linimasa mungkin belum pernah
        // dibuka. Laporannya DITAHAN, tidak dibuang: menandainya sudah-dibuang
        // di sini berarti aset itu tidak akan pernah benar-benar dihapus, karena
        // laporan berikutnya untuk id yang sama akan diabaikan.
        guard let onPurge else { return }

        // Tidak ada satu pun gambar yang berhasil belakangan ini: yang rusak
        // kemungkinan besar sambungannya, bukan aset-asetnya. Laporannya dibuang
        // begitu saja — kalau memang asetnya yang hilang, petaknya akan gagal
        // lagi nanti dan dilaporkan lagi.
        guard let lastSuccessAt,
              Date().timeIntervalSince(lastSuccessAt) < Self.successWindow
        else {
            pending.removeAll()
            return
        }

        let batch = pending
        pending.removeAll()
        purged.formUnion(batch)
        onPurge(batch)
    }
}
