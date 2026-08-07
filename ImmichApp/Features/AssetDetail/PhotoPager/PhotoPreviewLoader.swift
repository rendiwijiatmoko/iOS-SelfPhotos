import AVFoundation
import UIKit

/// Satu pintu untuk gambar layar detail.
///
/// Kembarannya `PhotoThumbnailLoader` untuk grid; dipisah karena ukuran decode,
/// endpoint, dan urutan cadangannya berbeda — dan menyatukannya hanya melahirkan
/// parameter yang harus dibaca ulang setiap kali.
@MainActor
final class PhotoPreviewLoader {
    /// Sisi terpanjang untuk layar detail.
    ///
    /// 2048px sudah melampaui resolusi layar mana pun, sementara membongkar
    /// bitmap 4000px berarti puluhan megabyte dan puluhan milidetik untuk setiap
    /// usapan halaman.
    static let maxPixelSize = 2048

    private let session: SessionManager

    init(session: SessionManager) {
        self.session = session
    }

    private func cacheKey(for assetId: String) -> String {
        "\(assetId)-preview"
    }

    /// Gambar terbaik yang SUDAH ada di memori, tanpa `await`.
    ///
    /// Kalau versi tajamnya belum ada, thumbnail seukuran grid dipakai lebih
    /// dulu — layar detail hampir selalu dibuka dari grid, jadi versi kecilnya
    /// pasti sudah ada. Menampilkannya seketika inilah yang membuat aplikasi
    /// resmi terasa tanpa loading.
    func cachedImage(for assetId: String) -> UIImage? {
        if let preview = ImageMemoryCache.shared.image(
            for: ImageCache.memoryKey(cacheKey(for: assetId), Self.maxPixelSize)) {
            return preview
        }
        return ImageMemoryCache.shared.image(
            for: ImageCache.memoryKey("\(assetId)-thumbnail", PhotoThumbnailLoader.maxPixelSize))
    }

    /// true kalau yang ada di memori sudah versi tajamnya, jadi tidak perlu
    /// mengambil apa pun.
    func hasPreview(for assetId: String) -> Bool {
        ImageMemoryCache.shared.image(
            for: ImageCache.memoryKey(cacheKey(for: assetId), Self.maxPixelSize)) != nil
    }

    func image(for assetId: String) async -> UIImage? {
        // Aset PERANGKAT tidak punya alamat di server.
        //
        // Memintanya ke sana berakhir 400/404, dan itu dibaca `UnreadableAssets`
        // sebagai "aset ini sudah tidak bisa dibaca" — lalu petaknya DIBUANG
        // dari linimasa. Foto yang masih ada di perangkat hilang dari grid
        // hanya karena dibuka.
        if LocalPhotoLibrary.isLocal(assetId) {
            return await LocalPhotoLibrary.shared.preview(
                for: assetId,
                size: CGSize(width: Self.maxPixelSize, height: Self.maxPixelSize))
        }

        let api = session.imageAPI
        let endpoint = Endpoint(
            path: "/assets/\(assetId)/thumbnail",
            query: [.init(name: "size", value: "preview")])

        do {
            let image = try await ImageCache.shared.image(
                key: cacheKey(for: assetId),
                maxPixelSize: Self.maxPixelSize,
                fetch: { try await api.rawData(endpoint) })
            UnreadableAssets.shared.noteSuccess()
            return image
        } catch {
            // Aset yang ditolak server dibuang dari linimasa — lihat
            // `UnreadableAssets`.
            UnreadableAssets.shared.report(assetId, error: error)
            return nil
        }
    }

    /// URL streaming video beserta header autentikasinya.
    ///
    /// `AVPlayer` mengambil bytenya sendiri, di luar `APIClient` — jadi
    /// headernya harus ikut dititipkan ke `AVURLAsset`, bukan dipasang di
    /// `URLRequest` seperti permintaan lain.
    func videoSource(for assetId: String) -> (url: URL, headers: [String: String])? {
        let (baseURL, headers) = session.snapshot
        guard let baseURL else { return nil }
        return (baseURL.appendingPathComponent("/assets/\(assetId)/video/playback"), headers)
    }

    /// Sumber playback tercepat yang tersedia.
    ///
    /// Aset server yang berasal dari perangkat ini tetap punya pasangan
    /// `PHAsset.localIdentifier`. Memutar pasangan lokal lebih dahulu menghindari
    /// round-trip dan transcoding server. Bila berkas lokal sudah dihapus atau
    /// hanya ada di iCloud, endpoint playback server menjadi fallback.
    func playbackAsset(for assetId: String) async -> AVAsset? {
        let localAssetID: String?
        if LocalPhotoLibrary.isLocal(assetId) {
            localAssetID = assetId
        } else if let identifier = SwiftDataManager.shared.localIdentifier(
            forServerAsset: assetId) {
            localAssetID = LocalPhotoLibrary.assetID(for: identifier)
        } else {
            localAssetID = nil
        }

        if let localAssetID,
           let localAsset = await LocalPhotoLibrary.shared.videoAsset(for: localAssetID) {
            return localAsset
        }

        // Aset yang hanya ada di perangkat tidak punya fallback server.
        guard !LocalPhotoLibrary.isLocal(assetId),
              let source = videoSource(for: assetId)
        else { return nil }

        return AVURLAsset(
            url: source.url,
            options: ["AVURLAssetHTTPHeaderFieldsKey": source.headers])
    }

    /// Menghangatkan halaman tetangga sebelum diusap ke sana.
    func prefetch(_ assetIds: [String]) {
        // Id perangkat tidak punya alamat di server; menembakkannya ke sana
        // hanya menghasilkan 404 untuk setiap tetangga halaman.
        let serverIDs = assetIds.filter { !LocalPhotoLibrary.isLocal($0) }
        guard !serverIDs.isEmpty else { return }

        let api = session.imageAPI
        ImageCache.shared.prefetch(
            keys: serverIDs.map(cacheKey(for:)),
            maxPixelSize: Self.maxPixelSize,
            fetch: { key in
                let assetId = String(key.dropLast("-preview".count))
                return try await api.rawData(.init(
                    path: "/assets/\(assetId)/thumbnail",
                    query: [.init(name: "size", value: "preview")]))
            })
    }
}
