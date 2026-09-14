import Foundation

// Protokol sinkronisasi Immich v2+: POST /sync/stream mengembalikan JSON Lines,
// setiap baris {type, data, ack}; klien lalu mengirim ack terakhir per tipe
// ke POST /sync/ack.

struct SyncStreamRequestDTO: Encodable {
    let types: [String]
    var reset: Bool? = nil
}

struct SyncAckSetDTO: Encodable {
    let acks: [String]
}

/// Amplop tiap baris stream; `data` didecode terpisah sesuai `type`.
struct SyncLineEnvelopeDTO: Decodable {
    let type: String
    let ack: String
}

struct SyncLineDataDTO<T: Decodable>: Decodable {
    let data: T
}

/// Payload SyncEntityType.AssetV1 — semua key selalu ada, banyak yang nullable.
struct SyncAssetV1DTO: Decodable {
    let id: String
    let ownerId: String
    let originalFileName: String
    let checksum: String
    let type: String
    let visibility: String
    let isFavorite: Bool
    let thumbhash: String?
    let width: Int?
    let height: Int?
    let duration: String?
    let stackId: String?
    let libraryId: String?
    let livePhotoVideoId: String?
    let fileCreatedAt: Date?
    let fileModifiedAt: Date?
    let localDateTime: Date?
    let deletedAt: Date?
}

/// Payload yang dipakai server Immich v3 untuk `AssetsV2`.
///
/// Bentuknya hampir sama dengan V1, tetapi `duration` berubah dari clock string
/// menjadi integer milidetik. DTO terpisah membuat satu video tidak dapat
/// menggagalkan decoding seluruh stream karena perbedaan tipe tersebut.
struct SyncAssetV2DTO: Decodable {
    let id: String
    let ownerId: String
    let originalFileName: String
    let checksum: String
    let type: String
    let visibility: String
    let isFavorite: Bool
    let thumbhash: String?
    let width: Int?
    let height: Int?
    let duration: Int?
    let stackId: String?
    let libraryId: String?
    let livePhotoVideoId: String?
    let fileCreatedAt: Date?
    let fileModifiedAt: Date?
    let createdAt: Date?
    let localDateTime: Date?
    let deletedAt: Date?
    let isEdited: Bool
}

struct SyncAssetDeleteV1DTO: Decodable {
    let assetId: String
}
