import Foundation

struct MemoryDTO: Decodable, Identifiable {
    let id: String
    let type: String
    let memoryAt: Date
    let assets: [AssetResponseDTO]
}
