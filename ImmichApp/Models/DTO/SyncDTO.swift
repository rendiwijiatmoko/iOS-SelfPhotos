import Foundation

struct FullSyncRequestDTO: Encodable {
    let collections: [String] = ["assets"]
}

struct DeltaSyncRequestDTO: Encodable {
    let collections: [String] = ["assets"]
    let updatedAfter: String?
    let ackToken: String?
}

struct SyncResponseDTO: Decodable {
    let upserted: [String: SyncAssetDTO]
    let deleted: [String]
    let ackToken: String?
}

struct SyncAssetDTO: Decodable {
    let id: String
    let type: String
    let isFavorite: Bool
    let isArchived: Bool
    let createdAt: String
    let updatedAt: String
    let exifInfo: ExifDTO?
    let thumbhash: String?
}
