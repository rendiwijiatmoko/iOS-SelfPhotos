import UIKit

/// Placeholder blur yang dihitung dari string thumbhash milik asset
/// (`AssetLite.thumbhash`) — instan, sinkron, tanpa jaringan.
///
/// Algoritmanya ada di `ThumbHashDecoder`; di sini hanya pembungkus `UIImage`
/// dan cache hasil decode.
enum ThumbHash {

    /// Hasil decode disimpan supaya scroll tidak menghitung ulang DCT untuk
    /// cell yang sama berulang kali. Gambarnya mungil (maks 32 px), jadi batas
    /// jumlah entri sudah cukup.
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 300
        // Batas biaya ikut dipasang: batas jumlah saja tidak menjamin apa pun
        // kalau ternyata gambarnya lebih besar dari dugaan.
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    /// Placeholder untuk sebuah string thumbhash base64, atau `nil` kalau asset
    /// tidak punya thumbhash / string-nya tidak valid.
    static func placeholder(for base64: String?) -> UIImage? {
        guard let base64, !base64.isEmpty else { return nil }

        if let cached = cache.object(forKey: base64 as NSString) {
            return cached
        }

        guard let data = Data(base64Encoded: base64),
              let bitmap = ThumbHashDecoder.decode([UInt8](data)),
              let image = image(from: bitmap) else { return nil }

        cache.setObject(
            image,
            forKey: base64 as NSString,
            cost: image.cgImage.map { $0.bytesPerRow * $0.height } ?? 1)
        return image
    }

    static func clearCache() {
        cache.removeAllObjects()
    }

    private static func image(from bitmap: ThumbHashDecoder.Bitmap) -> UIImage? {
        guard let provider = CGDataProvider(data: Data(bitmap.rgba) as CFData),
              let cgImage = CGImage(
                width: bitmap.width,
                height: bitmap.height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bitmap.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else { return nil }

        return UIImage(cgImage: cgImage)
    }
}
