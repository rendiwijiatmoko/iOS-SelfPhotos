import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class SwiftDataManager {
    static let shared = SwiftDataManager()

    let modelContainer: ModelContainer
    let modelContext: ModelContext

    private init() {
        let schema = Schema([CachedAsset.self, BackupRecord.self, SyncState.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        self.modelContainer = try! ModelContainer(for: schema, configurations: [modelConfiguration])
        self.modelContext = ModelContext(modelContainer)
    }

    func getCachedAsset(id: String) -> CachedAsset? {
        var descriptor = FetchDescriptor<CachedAsset>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func getAllCachedAssets() -> [CachedAsset] {
        let descriptor = FetchDescriptor<CachedAsset>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func getCachedAssetsByDate(ascending: Bool = false) -> [CachedAsset] {
        let descriptor = FetchDescriptor<CachedAsset>(sortBy: [.init(\.createdAt, order: ascending ? .forward : .reverse)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func insertOrUpdateCachedAsset(_ asset: CachedAsset) throws {
        if let existing = getCachedAsset(id: asset.id) {
            existing.isFavorite = asset.isFavorite
            existing.isArchived = asset.isArchived
            existing.updatedAt = asset.updatedAt
            existing.exifData = asset.exifData
        } else {
            modelContext.insert(asset)
        }
        try modelContext.save()
    }

    func deleteCachedAsset(id: String) throws {
        if let asset = getCachedAsset(id: id) {
            modelContext.delete(asset)
            try modelContext.save()
        }
    }

    func clearAllCache() throws {
        try modelContext.delete(model: CachedAsset.self)
        try modelContext.save()
    }

    func getBackupRecord(deviceAssetId: String) -> BackupRecord? {
        var descriptor = FetchDescriptor<BackupRecord>(predicate: #Predicate { $0.deviceAssetId == deviceAssetId })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func insertBackupRecord(_ record: BackupRecord) throws {
        modelContext.insert(record)
        try modelContext.save()
    }

    func getSyncState() -> SyncState {
        if let state = try? modelContext.fetch(FetchDescriptor<SyncState>()).first {
            return state
        }
        let state = SyncState()
        modelContext.insert(state)
        try? modelContext.save()
        return state
    }

    func updateSyncState(_ state: SyncState) throws {
        try modelContext.save()
    }
}
