import Foundation

/// HTTP responses are not our offline store. Images and app snapshots have
/// their own explicit storage; do not keep a second persistent URL cache.
enum NetworkResponseCache {
    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    static func clear(_ cache: URLCache = .shared) {
        // Use the cache owner API, never unlink a live Cache.db/WAL or Metal
        // database. Disk allocation for framework bookkeeping may remain.
        cache.diskCapacity = 0
        cache.removeAllCachedResponses()
    }
}
