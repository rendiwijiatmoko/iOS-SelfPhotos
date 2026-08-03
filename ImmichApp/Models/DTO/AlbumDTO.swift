import Foundation

struct AlbumResponseDTO: Decodable, Identifiable {
    let id: String
    let albumName: String
    let description: String?
    let assetCount: Int
    let albumThumbnailAssetId: String?
    let shared: Bool
    let createdAt: Date
    let assets: [AssetResponseDTO]?
}
