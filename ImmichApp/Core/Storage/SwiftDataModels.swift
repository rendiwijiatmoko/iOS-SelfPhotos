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

    init(
        id: String,
        assetId: String,
        type: String,
        thumbnailPath: String? = nil,
        previewPath: String? = nil,
        isFavorite: Bool = false,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        exifData: String? = nil,
        ratio: Double? = nil
    ) {
        self.id = id
        self.assetId = assetId
        self.type = type
        self.thumbnailPath = thumbnailPath
        self.previewPath = previewPath
        self.isFavorite = isFavorite
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.exifData = exifData
        self.ratio = ratio
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
