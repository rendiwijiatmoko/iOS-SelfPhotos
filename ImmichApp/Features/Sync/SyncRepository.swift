import Foundation

final class SyncRepository {
    private let api: APIClient
    private let dataManager: SwiftDataManager

    init(api: APIClient, dataManager: SwiftDataManager) {
        self.api = api
        self.dataManager = dataManager
    }

    func fullSync() async throws {
        let request = FullSyncRequestDTO()
        let response: SyncResponseDTO = try await api.send(.json("/sync/full-sync", method: .post, body: request))

        for (_, assetDTO) in response.upserted {
            let cachedAsset = CachedAsset(
                id: assetDTO.id,
                assetId: assetDTO.id,
                type: assetDTO.type,
                isFavorite: assetDTO.isFavorite,
                isArchived: assetDTO.isArchived,
                createdAt: ISO8601DateFormatter().date(from: assetDTO.createdAt) ?? Date(),
                updatedAt: ISO8601DateFormatter().date(from: assetDTO.updatedAt) ?? Date(),
                ratio: extractRatio(from: assetDTO)
            )
            try dataManager.insertOrUpdateCachedAsset(cachedAsset)
        }

        for deletedId in response.deleted {
            try dataManager.deleteCachedAsset(id: deletedId)
        }

        let syncState = dataManager.getSyncState()
        syncState.lastFullSyncAt = Date()
        syncState.ackToken = response.ackToken
        syncState.totalAssets = response.upserted.count
        try dataManager.updateSyncState(syncState)
    }

    func deltaSync() async throws {
        let syncState = dataManager.getSyncState()
        let lastSync = syncState.lastDeltaSyncAt ?? syncState.lastFullSyncAt ?? Date(timeIntervalSince1970: 0)
        let updatedAfter = ISO8601DateFormatter().string(from: lastSync)

        let request = DeltaSyncRequestDTO(updatedAfter: updatedAfter, ackToken: syncState.ackToken)
        let response: SyncResponseDTO = try await api.send(.json("/sync/delta-sync", method: .post, body: request))

        for (_, assetDTO) in response.upserted {
            let cachedAsset = CachedAsset(
                id: assetDTO.id,
                assetId: assetDTO.id,
                type: assetDTO.type,
                isFavorite: assetDTO.isFavorite,
                isArchived: assetDTO.isArchived,
                createdAt: ISO8601DateFormatter().date(from: assetDTO.createdAt) ?? Date(),
                updatedAt: ISO8601DateFormatter().date(from: assetDTO.updatedAt) ?? Date(),
                ratio: extractRatio(from: assetDTO)
            )
            try dataManager.insertOrUpdateCachedAsset(cachedAsset)
        }

        for deletedId in response.deleted {
            try dataManager.deleteCachedAsset(id: deletedId)
        }

        syncState.lastDeltaSyncAt = Date()
        if let newAckToken = response.ackToken {
            syncState.ackToken = newAckToken
        }
        try dataManager.updateSyncState(syncState)
    }

    private func extractRatio(from asset: SyncAssetDTO) -> Double? {
        guard asset.thumbhash != nil else { return nil }
        return 1.0
    }
}
