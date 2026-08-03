import Foundation

struct AlbumResponseDTO: Decodable, Identifiable, Hashable {
    let id: String
    let albumName: String
    let description: String?
    let assetCount: Int
    let albumThumbnailAssetId: String?
    let shared: Bool
    let createdAt: Date
    let assets: [AssetResponseDTO]?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AlbumResponseDTO, rhs: AlbumResponseDTO) -> Bool {
        lhs.id == rhs.id
    }
}
