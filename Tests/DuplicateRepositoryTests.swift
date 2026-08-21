import XCTest
@testable import ImmichApp

@MainActor
final class DuplicateRepositoryTests: XCTestCase {
    private var session: MockSessionManager!
    private var repository: DuplicateRepository!

    override func setUp() async throws {
        try await super.setUp()
        MockURLProtocol.reset()
        session = MockSessionManager()
        try session.setServer("https://test.example.com")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        repository = DuplicateRepository(api: APIClient(
            session: session,
            urlSession: URLSession(configuration: configuration)))
    }

    override func tearDown() async throws {
        MockURLProtocol.reset()
        try await super.tearDown()
    }

    func testLoadsDuplicateGroupsAndSuggestedKeeper() async throws {
        stub(status: 200, json: """
        [{
          "duplicateId": "11111111-1111-4111-8111-111111111111",
          "assets": [\(assetJSON(id: "22222222-2222-4222-8222-222222222222")),
                     \(assetJSON(id: "33333333-3333-4333-8333-333333333333"))],
          "suggestedKeepAssetIds": ["33333333-3333-4333-8333-333333333333"]
        }]
        """)

        let groups = try await repository.all()

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].assets.count, 2)
        XCTAssertEqual(
            groups[0].initialKeepAssetIDs,
            ["33333333-3333-4333-8333-333333333333"])
        XCTAssertEqual(MockURLProtocol.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.path, "/api/duplicates")
    }

    func testV2ResponseWithoutSuggestionUsesLargestAsset() async throws {
        stub(status: 200, json: """
        [{
          "duplicateId": "11111111-1111-4111-8111-111111111111",
          "assets": [\(assetJSON(
            id: "22222222-2222-4222-8222-222222222222", fileSize: 1_000)),
                     \(assetJSON(
            id: "33333333-3333-4333-8333-333333333333", fileSize: 2_000))]
        }]
        """)

        let groups = try await repository.all()
        let group = try XCTUnwrap(groups.first)

        XCTAssertTrue(group.suggestedKeepAssetIds.isEmpty)
        XCTAssertEqual(
            group.initialKeepAssetIDs,
            ["33333333-3333-4333-8333-333333333333"])
    }

    func testResolveUsesResolveEndpointAndExpectedBody() async throws {
        let duplicateID = "11111111-1111-4111-8111-111111111111"
        stub(status: 200, json: """
        [{"id":"\(duplicateID)","success":true,"error":null,"errorMessage":null}]
        """)

        try await repository.resolve(.init(
            duplicateId: duplicateID,
            keepAssetIds: ["22222222-2222-4222-8222-222222222222"],
            trashAssetIds: ["33333333-3333-4333-8333-333333333333"]))

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/duplicates/resolve")

        let body = try bodyObject(request)
        let groups = try XCTUnwrap(body["groups"] as? [[String: Any]])
        XCTAssertEqual(groups.first?["duplicateId"] as? String, duplicateID)
        XCTAssertEqual(
            groups.first?["keepAssetIds"] as? [String],
            ["22222222-2222-4222-8222-222222222222"])
        XCTAssertEqual(
            groups.first?["trashAssetIds"] as? [String],
            ["33333333-3333-4333-8333-333333333333"])
    }

    func testResolveRejectsPerGroupFailureInsideHTTP200() async throws {
        let duplicateID = "11111111-1111-4111-8111-111111111111"
        stub(status: 200, json: """
        [{
          "id":"\(duplicateID)",
          "success":false,
          "error":"validation",
          "errorMessage":"Every asset must be selected"
        }]
        """)

        do {
            try await repository.resolve(.init(
                duplicateId: duplicateID,
                keepAssetIds: [],
                trashAssetIds: []))
            XCTFail("Per-group failure must throw")
        } catch let error as APIError {
            guard case .server(let status, let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(status, 200)
            XCTAssertEqual(message, "Every asset must be selected")
        }
    }

    func testKeepAllDismissesGroupWithoutAssetDelete() async throws {
        stub(status: 204, json: "")
        let duplicateID = "11111111-1111-4111-8111-111111111111"

        try await repository.dismiss(duplicateID)

        XCTAssertEqual(MockURLProtocol.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(
            MockURLProtocol.lastRequest?.url?.path,
            "/api/duplicates/\(duplicateID)")
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

    private func assetJSON(id: String, fileSize: Int = 1_000) -> String {
        """
        {
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
          "exifInfo": {
            "exifImageWidth": 4000,
            "exifImageHeight": 3000,
            "fileSizeInByte": \(fileSize)
          },
          "people": null
        }
        """
    }
}
