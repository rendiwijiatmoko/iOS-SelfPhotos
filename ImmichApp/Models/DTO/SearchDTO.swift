import Foundation

struct SearchRequestDTO: Encodable {
    var query: String? = nil
    var page: Int? = 1
    var type: String? = nil
    var isFavorite: Bool? = nil
    var takenAfter: String? = nil
    var takenBefore: String? = nil
    var city: String? = nil
}

struct SearchResponseDTO: Decodable {
    struct AssetsPage: Decodable {
        let items: [AssetResponseDTO]
        let total: Int
        let nextPage: String?
    }
    let assets: AssetsPage
}
