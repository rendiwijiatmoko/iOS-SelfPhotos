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

    func buckets(albumId: String? = nil) async throws -> [TimeBucketDTO] {
        try await api.send(.init(
            path: "/timeline/buckets",
            query: baseQuery(albumId: albumId)))
    }

    func bucket(_ timeBucket: String, albumId: String? = nil) async throws -> [AssetLite] {
        let dto: TimelineBucketDTO = try await api.send(.init(
            path: "/timeline/bucket",
            query: [URLQueryItem(name: "timeBucket", value: timeBucket)] + baseQuery(albumId: albumId)))

        return parseTimelineBucket(dto)
    }

    private func baseQuery(albumId: String?) -> [URLQueryItem] {
        var query = [URLQueryItem(name: "order", value: "desc")]
        if let albumId {
            query.append(.init(name: "albumId", value: albumId))
        } else {
            query.append(.init(name: "visibility", value: "timeline"))
        }
        return query
    }

    private func parseTimelineBucket(_ dto: TimelineBucketDTO) -> [AssetLite] {
        var assets: [AssetLite] = []

        // Respons berbentuk kolom (array paralel); jaga-jaga kalau ada kolom
        // yang lebih pendek supaya tidak crash index-out-of-range.
        func value<T>(_ array: [T]?, _ i: Int) -> T? {
            guard let array, i < array.count else { return nil }
            return array[i]
        }

        for i in 0..<dto.id.count {
            let isVideo = !(value(dto.isImage, i) ?? true)
            let ratio = value(dto.ratio, i) ?? 1.0
            let thumbhash = value(dto.thumbhash, i) ?? nil
            let dateStr = value(dto.fileCreatedAt, i) ?? ""
            let createdAt = parseISO8601Date(dateStr) ?? Date()

            assets.append(AssetLite(
                id: dto.id[i],
                isVideo: isVideo,
                ratio: ratio,
                thumbhash: thumbhash,
                createdAt: createdAt,
                isFavorite: value(dto.isFavorite, i) ?? false,
                duration: value(dto.duration, i)?.seconds
            ))
        }

        return assets
    }

    private func parseISO8601Date(_ dateString: String) -> Date? {
        ISO8601DateFormatter.immichFractional.date(from: dateString)
            ?? ISO8601DateFormatter.immichPlain.date(from: dateString)
    }
}
