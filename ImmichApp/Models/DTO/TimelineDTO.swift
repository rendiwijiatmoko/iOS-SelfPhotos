import Foundation

struct TimeBucketDTO: Decodable {
    let timeBucket: String
    let count: Int
}

struct TimelineBucketDTO: Decodable {
    let id: [String]
    let ownerId: [String]?
    let isImage: [Bool]?
    let isFavorite: [Bool]?
    let thumbhash: [String?]?
    let fileCreatedAt: [String]?
    let duration: [String?]?
    let ratio: [Double]?
}
