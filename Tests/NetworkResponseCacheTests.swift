import Foundation
import XCTest
@testable import ImmichApp

final class NetworkResponseCacheTests: XCTestCase {
    func testForegroundConfigurationDoesNotUsePersistentResponseCache() {
        let configuration = NetworkResponseCache.configuration()
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.identifier)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        // Every caller gets a fresh configuration, not shared mutable state.
        configuration.httpMaximumConnectionsPerHost = 1
        XCTAssertNotEqual(NetworkResponseCache.configuration().httpMaximumConnectionsPerHost, 1)
    }

    func testClearActuallyRemovesCachedResponseAndDisablesDiskStorage() throws {
        let cache = URLCache(memoryCapacity: 1_048_576, diskCapacity: 0, diskPath: nil)
        let request = URLRequest(url: URL(string: "https://cache-test.invalid/video")!)
        let response = try XCTUnwrap(HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Cache-Control": "max-age=3600"]))
        cache.storeCachedResponse(CachedURLResponse(
            response: response, data: Data([1, 2, 3]), storagePolicy: .allowedInMemoryOnly), for: request)
        XCTAssertNotNil(cache.cachedResponse(for: request))
        NetworkResponseCache.clear(cache)
        XCTAssertNil(cache.cachedResponse(for: request))
        XCTAssertEqual(cache.diskCapacity, 0)
        NetworkResponseCache.clear(cache)
        XCTAssertNil(cache.cachedResponse(for: request))
    }

    @MainActor
    func testImageSessionRetainsConnectionLimitsWithoutHTTPDiskCaching() {
        let configuration = APIClient.imageSessionConfiguration
        XCTAssertNil(configuration.urlCache)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(configuration.httpMaximumConnectionsPerHost, 8)
    }
}
