import Foundation
import SwiftData

@Model
final class CachedAsset {
    @Attribute(.unique) var id: String
    var assetId: String
    var type: String
    var thumbnailPath: String?
    var previewPath: String?
    var isFavorite: Bool
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var exifData: String?
    var ratio: Double?
    var thumbhash: String?
    /// Kunci bulan "yyyy-MM", dihitung SEKALI saat sync.
    ///
    /// Linimasa dikelompokkan per bulan; menghitungnya saat menyusun berarti
    /// puluhan ribu panggilan `DateFormatter` di main thread setiap kali layar
    /// dibangun. Nilainya hanya berubah kalau tanggal fotonya berubah.
    var monthKey: String = ""
    /// Durasi video dalam detik; nil untuk foto.
    ///
    /// Punya nilai bawaan supaya penambahannya cukup ditangani migrasi ringan
    /// SwiftData, tanpa skema baru.
    var duration: Double?
    /// Id aset video pasangan sebuah Live Photo; nil untuk foto biasa.
    var livePhotoVideoId: String?

    init(
        id: String,
        assetId: String,
        type: String,
        thumbnailPath: String? = nil,
        previewPath: String? = nil,
        isFavorite: Bool = false,
        isArchived: Bool = false,
        duration: Double? = nil,
        livePhotoVideoId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        exifData: String? = nil,
        ratio: Double? = nil,
        thumbhash: String? = nil
    ) {
        self.id = id
        self.assetId = assetId
        self.type = type
        self.thumbnailPath = thumbnailPath
        self.previewPath = previewPath
        self.isFavorite = isFavorite
        self.isArchived = isArchived
        self.duration = duration
        self.livePhotoVideoId = livePhotoVideoId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.exifData = exifData
        self.ratio = ratio
        self.thumbhash = thumbhash
        self.monthKey = MonthKey.of(createdAt)
    }
}

/// Kunci bulan dalam kalender POSIX.
///
/// `DateFormatter` sengaja dihindari: ia mahal dan tidak thread-safe. Komponen
/// tanggalnya diambil langsung dari `Calendar`, lalu dirakit sebagai angka —
/// hasilnya sama untuk perangkat mana pun dan bahasa apa pun.
enum MonthKey {
    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    static func of(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        let year = parts.year ?? 0
        let month = parts.month ?? 1
        return month < 10 ? "\(year)-0\(month)" : "\(year)-\(month)"
    }

    /// Kebalikan `of(_:)`, untuk membentuk judul yang bisa dibaca.
    static func date(from key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]), let month = Int(parts[1])
        else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month))
    }
}

@Model
final class BackupRecord {
    @Attribute(.unique) var id: String
    var assetId: String
    var deviceAssetId: String
    var createdAt: Date

    init(id: String, assetId: String, deviceAssetId: String, createdAt: Date = Date()) {
        self.id = id
        self.assetId = assetId
        self.deviceAssetId = deviceAssetId
        self.createdAt = createdAt
    }
}

@Model
final class SyncState {
    @Attribute(.unique) var id: String = "sync-state"
    var lastFullSyncAt: Date?
    var lastDeltaSyncAt: Date?
    var ackToken: String?
    var totalAssets: Int = 0

    init() {}
}
