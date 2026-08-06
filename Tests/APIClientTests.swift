import XCTest
@testable import ImmichApp

@MainActor
final class APIClientTests: XCTestCase {
    var mockSession: MockSessionManager!
    var apiClient: APIClient!

    override func setUp() async throws {
        try await super.setUp()
        MockURLProtocol.reset()

        mockSession = MockSessionManager()
        try mockSession.setServer("https://test.example.com")

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        apiClient = APIClient(session: mockSession, urlSession: URLSession(configuration: config))
    }

    override func tearDown() async throws {
        MockURLProtocol.reset()
        try await super.tearDown()
    }

    private func stub(status: Int, data: Data) {
        MockURLProtocol.mockData = data
        MockURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: "https://test.example.com/api")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )
    }

    func testPingSuccess() async throws {
        stub(status: 200, data: #"{"res":"pong"}"#.data(using: .utf8)!)

        let result: ServerPingDTO = try await apiClient.send(.init(path: "/server/ping"))
        XCTAssertEqual(result.res, "pong")
    }

    func testUnauthorizedError() async throws {
        stub(status: 401, data: Data())

        do {
            let _: LoginResponseDTO = try await apiClient.send(.init(path: "/auth/login", method: .post))
            XCTFail("Should throw unauthorized")
        } catch let error as APIError {
            if case .unauthorized = error {
                // Success
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    func testServerError() async throws {
        stub(status: 400, data: #"{"message":"Invalid credentials"}"#.data(using: .utf8)!)

        do {
            let _: LoginResponseDTO = try await apiClient.send(.init(path: "/auth/login", method: .post))
            XCTFail("Should throw server error")
        } catch let error as APIError {
            if case .server(let status, let msg) = error {
                XCTAssertEqual(status, 400)
                XCTAssertEqual(msg, "Invalid credentials")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    func testDecodingError() async throws {
        stub(status: 200, data: #"{"invalid":"json""#.data(using: .utf8)!)

        do {
            let _: ServerPingDTO = try await apiClient.send(.init(path: "/server/ping"))
            XCTFail("Should throw decoding error")
        } catch let error as APIError {
            if case .decoding = error {
                // Success
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    func testRawDataSuccess() async throws {
        let expectedData = Data([1, 2, 3, 4, 5])
        stub(status: 200, data: expectedData)

        let result = try await apiClient.rawData(.init(path: "/assets/123/thumbnail"))
        XCTAssertEqual(result, expectedData)
    }

    func testAuthHeadersAttached() async throws {
        mockSession.testAuthHeaders = ["Authorization": "Bearer test-token"]
        stub(status: 200, data: #"{"res":"pong"}"#.data(using: .utf8)!)

        let _: ServerPingDTO = try await apiClient.send(.init(path: "/server/ping"))

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
    }

    func testRequestURLBuiltFromBase() async throws {
        stub(status: 200, data: #"{"res":"pong"}"#.data(using: .utf8)!)

        let _: ServerPingDTO = try await apiClient.send(.init(
            path: "/server/ping",
            query: [URLQueryItem(name: "foo", value: "bar")]))

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        let url = try XCTUnwrap(request.url)
        XCTAssertTrue(url.absoluteString.hasPrefix("https://test.example.com/api/server/ping"))
        XCTAssertTrue(url.query?.contains("foo=bar") ?? false)
    }

    func testMissingBaseURLThrowsInvalidURL() async throws {
        let session = MockSessionManager() // no setServer -> baseURL nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = APIClient(session: session, urlSession: URLSession(configuration: config))

        do {
            let _: ServerPingDTO = try await client.send(.init(path: "/server/ping"))
            XCTFail("Should throw invalidURL")
        } catch let error as APIError {
            if case .invalidURL = error {
                // Success
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
}

final class MockURLProtocol: URLProtocol {
    static var mockData: Data?
    static var mockResponse: URLResponse?
    static var mockError: Error?
    static var lastRequest: URLRequest?

    static func reset() {
        mockData = nil
        mockResponse = nil
        mockError = nil
        lastRequest = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastRequest = request

        if let error = Self.mockError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        if let response = Self.mockResponse {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }

        if let data = Self.mockData {
            client?.urlProtocol(self, didLoad: data)
        }

        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
