import XCTest
@testable import ImmichApp

@MainActor
final class RepositoryEndpointContractTests: XCTestCase {
    private var session: MockSessionManager!
    private var api: APIClient!

    override func setUp() async throws {
        try await super.setUp()
        MockURLProtocol.reset()
        session = MockSessionManager()
        try session.setServer("https://test.example.com")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        api = APIClient(
            session: session,
            urlSession: URLSession(configuration: configuration))
    }

    override func tearDown() async throws {
        MockURLProtocol.reset()
        try await super.tearDown()
    }

    func testAlbumAssetsUsesStableMetadataSearchInsteadOfInternalTimeline() async throws {
        stub(status: 200, json: """
        {
          "assets": {
            "items": [{
              "id": "11111111-1111-4111-8111-111111111111",
              "type": "IMAGE",
              "originalFileName": "photo.jpg",
              "fileCreatedAt": "2026-08-08T01:00:00.000Z",
              "isFavorite": true,
              "isArchived": false,
              "isTrashed": false,
              "duration": null,
              "thumbhash": null,
              "localDateTime": "2026-08-08T08:00:00.000Z",
              "livePhotoVideoId": null,
              "exifInfo": {"exifImageWidth": 4000, "exifImageHeight": 3000}
            }],
            "total": 1,
            "nextPage": null
          }
        }
        """)

        let assets = try await TimelineRepository(api: api).albumAssets(
            "22222222-2222-4222-8222-222222222222")

        XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(assets.first?.ratio, 4.0 / 3.0)

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/search/metadata")
        XCTAssertFalse(request.url?.path.contains("timeline") ?? true)

        let body = try bodyObject(request)
        XCTAssertEqual(
            body["albumIds"] as? [String],
            ["22222222-2222-4222-8222-222222222222"])
        XCTAssertEqual(body["order"] as? String, "desc")
        XCTAssertEqual(body["page"] as? Int, 1)
        XCTAssertEqual(body["size"] as? Int, 1_000)
        XCTAssertEqual(body["withExif"] as? Bool, true)
    }

    func testAlbumAssetsFollowsNextPageWhenTotalIsCappedAtPageSize() async throws {
        var requestCount = 0
        MockURLProtocol.responseProvider = { request in
            requestCount += 1
            let isFirstPage = requestCount == 1
            let id = isFirstPage
                ? "11111111-1111-4111-8111-111111111111"
                : "22222222-2222-4222-8222-222222222222"
            let json = """
            {
              "assets": {
                "items": [{
                  "id": "\(id)",
                  "type": "IMAGE",
                  "originalFileName": "photo.jpg",
                  "fileCreatedAt": "2026-08-08T01:00:00.000Z",
                  "isFavorite": false,
                  "isArchived": false,
                  "isTrashed": false,
                  "duration": null,
                  "thumbhash": null,
                  "localDateTime": "2026-08-08T08:00:00.000Z",
                  "livePhotoVideoId": null,
                  "exifInfo": null
                }],
                "total": \(isFirstPage ? 1_000 : 23),
                "nextPage": \(isFirstPage ? "\"2\"" : "null")
              }
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil)
            return (Data(json.utf8), response, nil)
        }

        let assets = try await TimelineRepository(api: api).albumAssets(
            "33333333-3333-4333-8333-333333333333")

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(assets.map(\.id), [
            "11111111-1111-4111-8111-111111111111",
            "22222222-2222-4222-8222-222222222222",
        ])
    }

    func testRenamePersonUsesStableBulkUpdateEndpoint() async throws {
        let id = "33333333-3333-4333-8333-333333333333"
        stub(status: 200, json: """
        [{"id":"\(id)","success":true}]
        """)

        try await PeopleRepository(api: api).rename(id, to: "Renamed")

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/api/people")
        XCTAssertFalse(request.url?.path.contains(id) ?? true)

        let body = try bodyObject(request)
        let people = try XCTUnwrap(body["people"] as? [[String: Any]])
        XCTAssertEqual(people.count, 1)
        XCTAssertEqual(people[0]["id"] as? String, id)
        XCTAssertEqual(people[0]["name"] as? String, "Renamed")
        XCTAssertNil(people[0]["isHidden"])
    }

    func testBulkPersonFailureIsNotTreatedAsSuccess() async throws {
        let id = "44444444-4444-4444-8444-444444444444"
        stub(status: 200, json: """
        [{
          "id":"\(id)",
          "success":false,
          "error":"not_found",
          "errorMessage":"Person not found"
        }]
        """)

        do {
            try await PeopleRepository(api: api).setHidden(id, to: true)
            XCTFail("Per-item failure must throw")
        } catch let error as APIError {
            guard case .server(let status, let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(status, 422)
            XCTAssertEqual(message, "Person not found")
        }
    }

    func testAssetMutationCompatibilityRouteIsExplicit() async throws {
        stub(status: 200, json: "{}")

        try await AssetDetailRepository(api: api).toggleFavorite(
            "55555555-5555-4555-8555-555555555555", to: true)

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(
            request.url?.path,
            "/api/assets/55555555-5555-4555-8555-555555555555")
        XCTAssertEqual(try bodyObject(request)["isFavorite"] as? Bool, true)
    }

    private func stub(status: Int, json: String) {
        MockURLProtocol.mockData = Data(json.utf8)
        MockURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: "https://test.example.com/api")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil)
    }

    private func bodyObject(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody ?? MockURLProtocol.lastRequestBody)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
