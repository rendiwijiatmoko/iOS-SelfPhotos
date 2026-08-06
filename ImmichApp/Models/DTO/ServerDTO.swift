import Foundation

struct ServerPingDTO: Decodable {
    let res: String
}

struct ServerFeaturesDTO: Decodable {
    let smartSearch: Bool
    let facialRecognition: Bool
    let oauth: Bool
    let passwordLogin: Bool
    let search: Bool
}

struct ServerAboutDTO: Decodable {
    let version: String
    let versionUrl: String?
}

struct ServerConfigDTO: Decodable {
    let loginRequiredForSharedLinks: Bool?
    let oauthButtonText: String?
    let trashDays: Int?
}

struct ServerStorageDTO: Decodable {
    // diskUse/diskSize di API berupa string terformat ("1TB");
    // varian *Raw yang berupa byte count.
    let diskUse: String?
    let diskSize: String?
    let diskUseRaw: Int?
    let diskSizeRaw: Int?
    let diskUsagePercentage: Double?
}
