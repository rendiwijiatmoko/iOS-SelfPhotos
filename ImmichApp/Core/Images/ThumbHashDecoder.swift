import Foundation

/// Decoder ThumbHash murni (tanpa UIKit), port dari implementasi referensi
/// ThumbHash milik Evan Wallace (MIT) — <https://github.com/evanw/thumbhash>.
///
/// Sengaja dipisah dari `ThumbHash` (yang membangun `UIImage`) supaya
/// algoritmanya bisa dikompilasi dan diuji di luar simulator.
enum ThumbHashDecoder {

    struct Bitmap {
        let width: Int
        let height: Int
        /// RGBA 8-bit, tidak dipremultiply.
        let rgba: [UInt8]
    }

    /// Ukuran keluaran: sisi terpanjang 32 px. Cukup untuk placeholder blur —
    /// yang membuatnya halus adalah interpolasi saat di-scale ke ukuran cell.
    private static let maxDimension = 32.0

    static func decode(_ hash: [UInt8]) -> Bitmap? {
        guard hash.count >= 5 else { return nil }

        // Header
        let header24 = Int(hash[0]) | (Int(hash[1]) << 8) | (Int(hash[2]) << 16)
        let header16 = Int(hash[3]) | (Int(hash[4]) << 8)

        let lDC = Double(header24 & 63) / 63
        let pDC = Double((header24 >> 6) & 63) / 31.5 - 1
        let qDC = Double((header24 >> 12) & 63) / 31.5 - 1
        let lScale = Double((header24 >> 18) & 31) / 31
        let hasAlpha = (header24 >> 23) != 0
        let pScale = Double((header16 >> 3) & 63) / 63
        let qScale = Double((header16 >> 9) & 63) / 63
        let isLandscape = (header16 >> 15) != 0

        // Jumlah koefisien DCT per sumbu. Rasio aspek dihitung dari nilai
        // sebelum di-clamp (mengikuti referensi), sedangkan loop DCT memakai
        // nilai yang sudah di-clamp minimal 3.
        let rawLx = isLandscape ? (hasAlpha ? 5 : 7) : (header16 & 7)
        let rawLy = isLandscape ? (header16 & 7) : (hasAlpha ? 5 : 7)
        let lx = max(3, rawLx)
        let ly = max(3, rawLy)

        guard hash.count >= (hasAlpha ? 6 : 5) else { return nil }
        let aDC = hasAlpha ? Double(hash[5] & 15) / 15 : 1
        let aScale = hasAlpha ? Double(hash[5] >> 4) / 15 : 0

        // Koefisien AC dibaca per-nibble berurutan dari sisa byte.
        let acStart = hasAlpha ? 6 : 5
        var acIndex = 0
        var overflowed = false

        func decodeChannel(_ nx: Int, _ ny: Int, _ scale: Double) -> [Double] {
            var ac: [Double] = []
            for cy in 0..<ny {
                var cx = cy != 0 ? 0 : 1
                while cx * ny < nx * (ny - cy) {
                    let byteIndex = acStart + (acIndex >> 1)
                    guard byteIndex < hash.count else {
                        overflowed = true
                        return ac
                    }
                    let nibble = (Int(hash[byteIndex]) >> ((acIndex & 1) << 2)) & 15
                    acIndex += 1
                    ac.append((Double(nibble) / 7.5 - 1) * scale)
                    cx += 1
                }
            }
            return ac
        }

        // Saturasi P/Q dinaikkan 1.25× untuk mengimbangi kuantisasi.
        let lAC = decodeChannel(lx, ly, lScale)
        let pAC = decodeChannel(3, 3, pScale * 1.25)
        let qAC = decodeChannel(3, 3, qScale * 1.25)
        let aAC = hasAlpha ? decodeChannel(5, 5, aScale) : []
        guard !overflowed else { return nil }

        let ratio = Double(rawLx) / Double(rawLy)
        guard ratio.isFinite, ratio > 0 else { return nil }

        let width = Int((ratio > 1 ? maxDimension : maxDimension * ratio).rounded())
        let height = Int((ratio > 1 ? maxDimension / ratio : maxDimension).rounded())
        guard width > 0, height > 0 else { return nil }

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let fxCount = max(lx, hasAlpha ? 5 : 3)
        let fyCount = max(ly, hasAlpha ? 5 : 3)
        var fx = [Double](repeating: 0, count: fxCount)
        var fy = [Double](repeating: 0, count: fyCount)

        for y in 0..<height {
            for cy in 0..<fyCount {
                fy[cy] = cos(.pi / Double(height) * (Double(y) + 0.5) * Double(cy))
            }

            for x in 0..<width {
                for cx in 0..<fxCount {
                    fx[cx] = cos(.pi / Double(width) * (Double(x) + 0.5) * Double(cx))
                }

                var l = lDC, p = pDC, q = qDC, a = aDC

                var j = 0
                for cy in 0..<ly {
                    var cx = cy != 0 ? 0 : 1
                    while cx * ly < lx * (ly - cy) {
                        if j < lAC.count { l += lAC[j] * fx[cx] * fy[cy] * 2 }
                        j += 1
                        cx += 1
                    }
                }

                j = 0
                for cy in 0..<3 {
                    var cx = cy != 0 ? 0 : 1
                    while cx < 3 - cy {
                        let f = fx[cx] * fy[cy] * 2
                        if j < pAC.count { p += pAC[j] * f }
                        if j < qAC.count { q += qAC[j] * f }
                        j += 1
                        cx += 1
                    }
                }

                if hasAlpha {
                    j = 0
                    for cy in 0..<5 {
                        var cx = cy != 0 ? 0 : 1
                        while cx < 5 - cy {
                            if j < aAC.count { a += aAC[j] * fx[cx] * fy[cy] * 2 }
                            j += 1
                            cx += 1
                        }
                    }
                }

                // LPQ → RGB
                let b = l - 2.0 / 3.0 * p
                let r = (3 * l - b + q) / 2
                let g = r - q

                let i = (y * width + x) * 4
                rgba[i] = channel(r)
                rgba[i + 1] = channel(g)
                rgba[i + 2] = channel(b)
                rgba[i + 3] = channel(a)
            }
        }

        return Bitmap(width: width, height: height, rgba: rgba)
    }

    private static func channel(_ value: Double) -> UInt8 {
        UInt8(max(0, min(255, 255 * min(1, value))))
    }
}
