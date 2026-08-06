import UIKit

/// Satu pintu untuk thumbnail grid.
///
/// Sel UIKit tidak punya `@Environment`, jadi cara mengambil gambar dititipkan
/// lewat objek ini — sekaligus menjaga agar kunci cache dan ukuran decode-nya
/// hanya ditulis di SATU tempat.
@MainActor
final class PhotoThumbnailLoader {
    /// Sisi terpanjang yang dibutuhkan petak grid. Thumbnail Immich sendiri
    /// biasanya lebih kecil dari ini, jadi umumnya tidak ada penyusutan sama
    /// sekali — batasnya cuma penjaga kalau server dikonfigurasi lain.
    static let maxPixelSize = 600

    /// Permintaan gambar baru dihentikan sementara.
    ///
    /// Dipakai saat grid terbang melintasi seluruh perpustakaan menuju foto
    /// terbaru: dalam setengah detik itu puluhan layar penuh sel dibangun dan
    /// dibuang lagi, dan membiarkan masing-masing meminta thumbnail berarti
    /// ratusan unduhan untuk foto yang tidak akan pernah sempat dilihat —
    /// mengantre tepat di depan foto yang benar-benar dituju.
    ///
    /// Yang sudah ada di memori TETAP terpasang; yang belum menampilkan
    /// thumbhash-nya, sama seperti saat digulir cepat dengan jari.
    var isSuspended = false

    private let session: SessionManager

    init(session: SessionManager) {
        self.session = session
    }

    func cacheKey(for assetId: String) -> String {
        "\(assetId)-thumbnail"
    }

    /// Cache hit, tanpa `await`. Dipakai sel untuk memasang gambar seketika.
    func cachedImage(for assetId: String) -> UIImage? {
        ImageMemoryCache.shared.image(
            for: ImageCache.memoryKey(cacheKey(for: assetId), Self.maxPixelSize))
    }

    func image(for assetId: String) async -> UIImage? {
        guard !isSuspended else { return nil }

        let key = cacheKey(for: assetId)
        let api = session.imageAPI
        let endpoint = Endpoint(
            path: "/assets/\(assetId)/thumbnail",
            query: [.init(name: "size", value: "thumbnail")])

        do {
            let image = try await ImageCache.shared.image(
                key: key,
                maxPixelSize: Self.maxPixelSize,
                fetch: { try await api.rawData(endpoint) })
            // Keberhasilan ikut dicatat: itulah yang membedakan "aset ini
            // hilang" dari "sambungannya sedang rusak".
            UnreadableAssets.shared.noteSuccess()
            return image
        } catch {
            // `try?` diganti do/catch justru untuk baris ini.
            //
            // Petak yang gagal karena asetnya sudah tidak bisa dibaca tidak boleh
            // sekadar jadi kotak abu-abu; ia harus hilang dari linimasa. Jenis
            // errornya disaring di dalam `report`.
            UnreadableAssets.shared.report(assetId, error: error)
            return nil
        }
    }

    /// Dipanggil `UICollectionViewDataSourcePrefetching` — pekerjaannya nyata,
    /// tapi hasilnya dibuang: yang dituju cuma mengisi cache sebelum selnya
    /// benar-benar sampai di layar.
    func prefetch(_ assetIds: [String]) {
        guard !isSuspended else { return }

        let api = session.imageAPI
        ImageCache.shared.prefetch(
            keys: assetIds.map(cacheKey(for:)),
            maxPixelSize: Self.maxPixelSize,
            fetch: { key in
                let assetId = String(key.dropLast("-thumbnail".count))
                let data = try await api.rawData(.init(
                    path: "/assets/\(assetId)/thumbnail",
                    query: [.init(name: "size", value: "thumbnail")]))
                // Keberhasilan prefetch ikut dicatat, dan itu penting justru di
                // sini: yang melaporkan kegagalan di jalur ini juga prefetch,
                // dan laporan itu dibuang kalau tidak ada satu pun keberhasilan
                // yang tercatat belakangan.
                await MainActor.run { UnreadableAssets.shared.noteSuccess() }
                return data
            },
            // Aset yang sudah tidak bisa dibaca ketahuan DI SINI, selagi selnya
            // masih beberapa baris di luar layar — jadi pembuangannya terjadi di
            // tempat yang tidak terlihat, bukan tepat saat barisnya tiba.
            onFailure: { key, error in
                let assetId = String(key.dropLast("-thumbnail".count))
                Task { @MainActor in
                    UnreadableAssets.shared.report(assetId, error: error)
                }
            })
    }
}
