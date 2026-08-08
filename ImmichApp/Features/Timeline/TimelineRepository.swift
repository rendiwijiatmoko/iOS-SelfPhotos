import Foundation

/// Satu baris hasil bacaan cache: aset plus bulan tempatnya berada.
///
/// `Sendable` karena penyusunan sectionnya dilakukan di luar main actor.
struct TimelineRow: Sendable {
    let asset: AssetLite
    let monthKey: String
}

struct TimelineSection: Identifiable, Sendable {
    let id: String
    let title: String
    var assets: [AssetLite]
    /// Jumlah foto menurut bucket, tersedia sebelum asetnya dimuat.
    ///
    /// Dipakai untuk mengetahui posisi section tanpa memindai daftarnya.
    var count: Int = 0

    /// Posisi sel pertama section ini dalam deret sel gabungan.
    ///
    /// Semua section berbagi satu grid, jadi indeks 0,1,2… per section akan
    /// bertabrakan. Offset ini membuat rentangnya tidak pernah beririsan tanpa
    /// perlu merakit string apa pun, dan sekaligus jadi penanda urutan yang bisa
    /// dibandingkan langsung.
    var startIndex: Int = 0
}

class TimelineRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    /// Mengambil seluruh isi album lewat endpoint publik stabil.
    ///
    /// `/timeline/bucket*` berstatus **Internal** di OpenAPI Immich. Selain bisa
    /// berubah tanpa masa deprecation, jalur itu memerlukan satu request per
    /// bulan. Metadata search memberi hingga 1.000 aset per halaman dan punya
    /// kontrak pagination stabil.
    func albumAssets(_ albumId: String) async throws -> [AssetLite] {
        let pageSize = 1_000
        let first = try await albumPage(albumId, page: 1, size: pageSize)
        var assets = first.assets.items.map(AssetLite.init)

        let pageCount = max(1, (first.assets.total + pageSize - 1) / pageSize)
        guard pageCount > 1 else { return assets }

        // Batasi konkurensi agar album besar tidak membuka puluhan request dan
        // decoder sekaligus. Empat halaman tetap jauh lebih cepat daripada
        // request bucket berurutan tanpa menekan memori secara berlebihan.
        let batchSize = 4
        var start = 2
        while start <= pageCount {
            let end = min(start + batchSize - 1, pageCount)
            var pages: [(Int, [AssetLite])] = try await withThrowingTaskGroup(
                of: (Int, [AssetLite]).self
            ) { group in
                for page in start...end {
                    group.addTask { [api] in
                        var request = SearchRequestDTO(page: page)
                        request.albumIds = [albumId]
                        request.order = "desc"
                        request.size = pageSize
                        request.withExif = true
                        let response: SearchResponseDTO = try await api.send(.json(
                            "/search/metadata", method: .post, body: request))
                        return (page, response.assets.items.map(AssetLite.init))
                    }
                }
                var values: [(Int, [AssetLite])] = []
                for try await value in group { values.append(value) }
                return values
            }
            pages.sort { $0.0 < $1.0 }
            assets.append(contentsOf: pages.flatMap(\.1))
            start = end + 1
        }
        return assets
    }

    private func albumPage(_ albumId: String, page: Int, size: Int) async throws -> SearchResponseDTO {
        var request = SearchRequestDTO(page: page)
        request.albumIds = [albumId]
        request.order = "desc"
        request.size = size
        request.withExif = true
        return try await api.send(.json("/search/metadata", method: .post, body: request))
    }
}
