import Foundation

struct AssetResponseDTO: Decodable, Identifiable {
    let id: String
    let type: String
    let originalFileName: String
    let fileCreatedAt: Date
    var isFavorite: Bool
    var isArchived: Bool
    let isTrashed: Bool
    let duration: String?
    let thumbhash: String?
    let localDateTime: Date
    let exifInfo: ExifDTO?
    let people: [PersonDTO]?

    var isVideo: Bool { type == "VIDEO" }
}

struct ExifDTO: Decodable {
    let make: String?
    let model: String?
    let exifImageWidth: Int?
    let exifImageHeight: Int?
    let fileSizeInByte: Int?
    let dateTimeOriginal: Date?
    let latitude: Double?
    let longitude: Double?
    let city: String?
    let state: String?
    let country: String?
    let lensModel: String?
    let fNumber: Double?
    let focalLength: Double?
    let iso: Int?
    let exposureTime: String?
}
