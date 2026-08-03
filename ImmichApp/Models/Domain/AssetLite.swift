import Foundation

struct AssetLite: Identifiable, Hashable {
    let id: String
    let isVideo: Bool
    let ratio: Double
    let thumbhash: String?
    let createdAt: Date
}
