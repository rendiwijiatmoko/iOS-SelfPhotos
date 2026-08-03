import Foundation

struct TimelineSection: Identifiable {
    let id: String
    let title: String
    var assets: [AssetLite]
}

final class TimelineRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func buckets() async throws -> [TimeBucketDTO] {
        try await api.send(.init(
            path: "/timeline/buckets",
            query: [.init(name: "isArchived", value: "false")]))
    }

    func bucket(_ timeBucket: String) async throws -> [AssetLite] {
        let dto: TimelineBucketDTO = try await api.send(.init(
            path: "/timeline/bucket",
            query: [.init(name: "timeBucket", value: timeBucket)]))

        return parseTimelineBucket(dto)
    }

    private func parseTimelineBucket(_ dto: TimelineBucketDTO) -> [AssetLite] {
        var assets: [AssetLite] = []

        for i in 0..<dto.id.count {
            let id = dto.id[i]
            let isVideo = !(dto.isImage?[i] ?? true)
            let ratio = dto.ratio?[i] ?? 1.0
            let thumbhash = dto.thumbhash?[i] ?? nil

            let dateStr = dto.fileCreatedAt?[i] ?? ""
            let createdAt = parseISO8601Date(dateStr) ?? Date()

            assets.append(AssetLite(
                id: id,
                isVideo: isVideo,
                ratio: ratio,
                thumbhash: thumbhash,
                createdAt: createdAt
            ))
        }

        return assets
    }

    private func parseISO8601Date(_ dateString: String) -> Date? {
        let decoder = JSONDecoder.immich
        guard let data = "\"\(dateString)\"".data(using: .utf8) else { return nil }
        return try? decoder.decode(Date.self, from: data)
    }
}
