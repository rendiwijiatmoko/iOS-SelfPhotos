import CoreGraphics
import Foundation

/// Satu petak di dalam baris terjustifikasi: asetnya plus lebar akhir yang
/// sudah dihitung. Tingginya milik baris, bukan milik petak.
struct JustifiedTile: Identifiable {
    let asset: AssetLite
    let width: CGFloat

    var id: String { asset.id }
}

/// Sebaris petak yang lebarnya persis memenuhi lebar kontainer.
struct JustifiedRow: Identifiable {
    let id: Int
    let tiles: [JustifiedTile]
    let height: CGFloat
}

/// Penata baris ala Google Photos untuk hasil pencarian.
///
/// `LazyVGrid` memberi setiap kolom lebar yang sama, jadi `.aspectRatio(r,
/// contentMode: .fill)` memaksa gambar melebar melewati selnya sendiri — itulah
/// tumpang tindih yang memakan gambar tetangganya. Di sini urutannya dibalik:
/// tinggi baris yang dicari, lebar tiap petak mengikuti rasio aslinya, dan
/// jumlah petak per baris dibiarkan berubah-ubah.
///
/// Aturannya satu: untuk setiap baris,
///
///     Σ(rasio_i) × tinggi + jarak_antar = lebar_kontainer
///
/// sehingga tinggi baris = (lebar_kontainer − jarak_antar) / Σ(rasio_i).
enum JustifiedGrid {
    /// Rasio dijepit sebelum dipakai.
    ///
    /// Panorama 5:1 sendirian akan memaksa barisnya jadi setipis pita, dan foto
    /// super tinggi memaksa satu baris setinggi layar. Menjepitnya bikin petak
    /// ekstrem ter-crop sedikit — jauh lebih murah daripada tata letak yang
    /// kacau.
    static let minRatio: Double = 0.5
    static let maxRatio: Double = 2.5

    /// Baris terakhir tidak punya petak berikutnya untuk menutup lebar, jadi
    /// kalau dipaksa memenuhi lebar ia bisa melar jadi raksasa. Tingginya
    /// dibatasi ke kelipatan ini dari tinggi target, dan sisa lebarnya
    /// dibiarkan kosong.
    private static let lastRowHeightSlack: CGFloat = 1.35

    /// Tinggi baris yang dituju, diturunkan dari setelan jumlah kolom supaya
    /// "3 kolom" tetap terasa seperti tiga foto sebaris untuk gambar persegi.
    static func targetHeight(containerWidth: CGFloat, columns: Int, spacing: CGFloat) -> CGFloat {
        let count = CGFloat(max(columns, 1))
        return max(1, (containerWidth - spacing * (count - 1)) / count)
    }

    static func layout(
        assets: [AssetLite],
        containerWidth: CGFloat,
        rowHeight: CGFloat,
        spacing: CGFloat
    ) -> [JustifiedRow] {
        guard containerWidth > 0, rowHeight > 0, !assets.isEmpty else { return [] }

        var rows: [JustifiedRow] = []
        var pending: [AssetLite] = []
        var ratioSum: Double = 0

        func flush(isLastRow: Bool) {
            guard !pending.isEmpty else { return }

            let gaps = spacing * CGFloat(pending.count - 1)
            let usableWidth = max(1, containerWidth - gaps)
            var height = usableWidth / CGFloat(ratioSum)
            if isLastRow {
                height = min(height, rowHeight * lastRowHeightSlack)
            }
            height = max(1, height.rounded())

            // Lebar dibagikan lalu petak terakhir menyerap sisa pembulatan.
            // Tanpa ini, akumulasi error setengah poin per petak membuat baris
            // melewati tepi kanan — persis gejala yang mau diperbaiki.
            var tiles: [JustifiedTile] = []
            var remaining = usableWidth
            for (index, asset) in pending.enumerated() {
                let isLastTile = index == pending.count - 1
                let natural = max(1, (CGFloat(clampedRatio(asset)) * height).rounded())
                let width = (isLastTile && !isLastRow) ? max(1, remaining) : min(natural, max(1, remaining))
                remaining -= width
                tiles.append(JustifiedTile(asset: asset, width: width))
            }

            rows.append(JustifiedRow(id: rows.count, tiles: tiles, height: height))
            pending.removeAll(keepingCapacity: true)
            ratioSum = 0
        }

        for asset in assets {
            pending.append(asset)
            ratioSum += clampedRatio(asset)

            let gaps = spacing * CGFloat(pending.count - 1)
            let projectedWidth = CGFloat(ratioSum) * rowHeight + gaps
            if projectedWidth >= containerWidth {
                flush(isLastRow: false)
            }
        }
        flush(isLastRow: true)

        return rows
    }

    /// `AssetLite.ratio` jatuh ke 1.0 diam-diam kalau EXIF-nya tidak ada, dan
    /// bisa saja 0 atau NaN dari data rusak — keduanya membagi nol di rumus
    /// tinggi baris.
    private static func clampedRatio(_ asset: AssetLite) -> Double {
        guard asset.ratio.isFinite, asset.ratio > 0 else { return 1 }
        return min(max(asset.ratio, minRatio), maxRatio)
    }
}
