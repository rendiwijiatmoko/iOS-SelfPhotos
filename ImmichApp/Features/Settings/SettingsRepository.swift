import Foundation

class SettingsRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func getServerInfo() async throws -> ServerAboutDTO {
        try await api.send(.init(path: "/server/about"))
    }

    func getStorageInfo() async throws -> ServerStorageDTO {
        try await api.send(.init(path: "/server/storage"))
    }

    /// Jumlah foto & video MILIK PENGGUNA INI.
    ///
    /// Bukan `/server/statistics`, yang menghitung seluruh isi server dan hanya
    /// bisa diakses admin.
    func getAssetStats() async throws -> AssetStatsDTO {
        try await api.send(.init(path: "/assets/statistics"))
    }

    /// Versi rilis terbaru yang diketahui server.
    ///
    /// Server sendiri yang memeriksanya ke GitHub secara berkala, jadi klien
    /// tidak perlu menghubungi pihak ketiga — dan hasilnya sama dengan yang
    /// dilihat admin di antarmuka web.
    func getVersionCheck() async throws -> VersionCheckDTO {
        try await api.send(.init(path: "/server/version-check"))
    }
}

struct AssetStatsDTO: Decodable {
    let images: Int
    let videos: Int
    let total: Int
}

struct VersionCheckDTO: Decodable {
    let checkedAt: String?
    /// Bisa nil kalau pemeriksaan versi dimatikan di server.
    let releaseVersion: String?
}
