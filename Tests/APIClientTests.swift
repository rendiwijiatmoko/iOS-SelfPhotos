import XCTest
@testable import ImmichApp

class MockSessionManager: SessionManager {
    private(set) var testToken: String?
    private(set) var testBaseURL: URL?

    func setTestToken(_ token: String) {
        testToken = token
    }

    func setTestBaseURL(_ url: URL) {
        testBaseURL = url
        baseURL = url
    }

    override nonisolated var authHeaders: [String: String] {
        MainActor.assumeIsolated {
            guard let testToken else { return [:] }
            return ["Authorization": "Bearer \(testToken)"]
        }
    }
}

class APIClientTests: XCTestCase {
    var mockSession: MockSessionManager!
    var mockURLSession: URLSession!
    var apiClient: APIClient!

    override func setUp() {
        super.setUp()
        mockSession = MockSessionManager()
        mockSession.setTestBaseURL(URL(string: "https://test.example.com/api")!)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        mockURLSession = URLSession(configuration: config)
        apiClient = APIClient(session: mockSession, urlSession: mockURLSession)
    }

    func testPingSuccess() async throws {
        let expectedData = #"{"res":"pong"}"#.data(using: .utf8)!
        MockURLProtocol.mockData = expectedData
        MockURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: "https://test.example.com/api/server/ping")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )

        let result: ServerPingDTO = try await apiClient.send(.init(path: "/server/ping"))
        XCTAssertEqual(result.res, "pong")
    }

    func testUnauthorizedError() async throws {
        MockURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: "https://test.example.com/api/auth/login")!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: nil
        )
        MockURLProtocol.mockData = Data()

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
        let errorData = #"{"message":"Invalid credentials"}"#.data(using: .utf8)!
        MockURLProtocol.mockData = errorData
        MockURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: "https://test.example.com/api/auth/login")!,
            statusCode: 400,
            httpVersion: nil,
            headerFields: nil
        )

        do {
            let _: LoginResponseDTO = try await apiClient.send(.init(path: "/auth/login", method: .post))
            XCTFail("Should throw server error")
        } catch let error as APIError {
            if case .server(let status, let msg) = error {
                XCTAssertEqual(status, 400)
                XCTAssertEqual(msg, "Invalid credentials")
            } else {
                XCTFail("Wrong error type")
            }
        }
    }

    func testDecodingError() async throws {
        let invalidData = #"{"invalid":"json""#.data(using: .utf8)!
        MockURLProtocol.mockData = invalidData
        MockURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: "https://test.example.com/api/server/ping")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )

        do {
            let _: ServerPingDTO = try await apiClient.send(.init(path: "/server/ping"))
            XCTFail("Should throw decoding error")
        } catch let error as APIError {
            if case .decoding = error {
                // Success
            } else {
                XCTFail("Wrong error type")
            }
        }
    }

    func testRawDataSuccess() async throws {
        let expectedData = Data([1, 2, 3, 4, 5])
        MockURLProtocol.mockData = expectedData
        MockURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: "https://test.example.com/api/assets/123/thumbnail")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )

        let result = try await apiClient.rawData(.init(path: "/assets/123/thumbnail"))
        XCTAssertEqual(result, expectedData)
    }

    func testAuthHeadersAttached() async throws {
        mockSession.setTestToken("test-token")

        let expectedData = #"{"res":"pong"}"#.data(using: .utf8)!
        MockURLProtocol.mockData = expectedData
        MockURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: "https://test.example.com/api/server/ping")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        MockURLProtocol.captureRequest = true

        let _: ServerPingDTO = try await apiClient.send(.init(path: "/server/ping"))

        if let request = MockURLProtocol.lastRequest {
            let authHeader = request.value(forHTTPHeaderField: "Authorization")
            XCTAssertEqual(authHeader, "Bearer test-token")
        }
    }
}

class MockURLProtocol: URLProtocol {
    static var mockData: Data?
    static var mockResponse: URLResponse?
    static var mockError: Error?
    static var lastRequest: URLRequest?
    static var captureRequest = false

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        if Self.captureRequest {
            Self.lastRequest = request
        }

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
