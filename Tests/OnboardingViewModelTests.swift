import XCTest
@testable import ImmichApp

class OnboardingViewModelTests: XCTestCase {
    var mockSession: MockSessionManager!
    var viewModel: OnboardingViewModel!

    override func setUp() {
        super.setUp()
        mockSession = MockSessionManager()
        viewModel = OnboardingViewModel(session: mockSession)
    }

    override func tearDown() {
        super.tearDown()
        mockSession = nil
        viewModel = nil
    }

    func testInitialState() {
        XCTAssertEqual(viewModel.step, .server)
        XCTAssertTrue(viewModel.serverText.isEmpty)
        XCTAssertTrue(viewModel.email.isEmpty)
        XCTAssertTrue(viewModel.password.isEmpty)
        XCTAssertTrue(viewModel.apiKey.isEmpty)
        XCTAssertNil(viewModel.features)
        XCTAssertFalse(viewModel.showApiKeyTab)
        if case .idle = viewModel.phase {
            // Success
        } else {
            XCTFail("Expected idle phase")
        }
    }

    func testConnectToServer() async throws {
        mockSession.shouldSucceedPing = true
        mockSession.mockFeatures = ServerFeaturesDTO(
            smartSearch: true,
            facialRecognition: true,
            oauth: false,
            passwordLogin: true,
            search: true
        )

        viewModel.serverText = "https://immich.example.com"
        await viewModel.connect()

        XCTAssertEqual(viewModel.step, .login)
        XCTAssertNotNil(viewModel.features)
        XCTAssertTrue(viewModel.features?.passwordLogin ?? false)
    }

    func testConnectWithInvalidURL() async {
        viewModel.serverText = "not-a-url"
        await viewModel.connect()

        if case .failed = viewModel.phase {
            XCTAssertEqual(viewModel.step, .server)
        } else {
            XCTFail("Expected failed phase")
        }
    }

    func testLoginWithPassword() async throws {
        mockSession.shouldSucceedLogin = true
        mockSession.mockUser = UserResponseDTO(
            id: "user-123",
            email: "user@example.com",
            name: "Test User",
            profileImagePath: nil,
            storageLabel: nil
        )

        viewModel.serverText = "https://immich.example.com"
        viewModel.email = "user@example.com"
        viewModel.password = "password123"
        viewModel.step = .login

        await viewModel.loginPassword()

        XCTAssertTrue(mockSession.isLoggedIn)
    }

    func testLoginWithInvalidCredentials() async {
        mockSession.shouldSucceedLogin = false

        viewModel.email = "user@example.com"
        viewModel.password = "wrongpassword"
        viewModel.step = .login

        await viewModel.loginPassword()

        if case .failed(let msg) = viewModel.phase {
            XCTAssertFalse(msg.isEmpty)
        } else {
            XCTFail("Expected failed phase")
        }
    }

    func testLoginWithApiKey() async throws {
        mockSession.shouldSucceedApiKey = true
        mockSession.mockUser = UserResponseDTO(
            id: "user-123",
            email: "user@example.com",
            name: "Test User",
            profileImagePath: nil,
            storageLabel: nil
        )

        viewModel.apiKey = "valid-api-key-123"
        viewModel.step = .login

        await viewModel.loginApiKey()

        XCTAssertTrue(mockSession.isLoggedIn)
    }

    func testReset() {
        viewModel.serverText = "https://example.com"
        viewModel.email = "user@example.com"
        viewModel.password = "pass"
        viewModel.apiKey = "key"
        viewModel.step = .login

        viewModel.reset()

        XCTAssertEqual(viewModel.step, .server)
        XCTAssertTrue(viewModel.serverText.isEmpty)
        XCTAssertTrue(viewModel.email.isEmpty)
        XCTAssertTrue(viewModel.password.isEmpty)
        XCTAssertTrue(viewModel.apiKey.isEmpty)
        XCTAssertNil(viewModel.features)
    }
}

class MockSessionManager: SessionManager {
    var shouldSucceedPing = false
    var shouldSucceedLogin = false
    var shouldSucceedApiKey = false
    var mockUser: UserResponseDTO?
    var mockFeatures: ServerFeaturesDTO?

    override func setServer(_ raw: String) throws {
        try super.setServer(raw)
    }

    override func ping() async throws {
        if !shouldSucceedPing {
            throw APIError.invalidURL
        }
    }

    override func features() async throws -> ServerFeaturesDTO {
        if let features = mockFeatures {
            return features
        }
        throw APIError.unknown
    }

    override func loginPassword(email: String, password: String) async throws {
        if !shouldSucceedLogin {
            throw APIError.unauthorized
        }
        if let user = mockUser {
            currentUser = user
            isLoggedIn = true
        }
    }

    override func loginApiKey(_ key: String) async throws {
        if !shouldSucceedApiKey {
            throw APIError.unauthorized
        }
        if let user = mockUser {
            currentUser = user
            isLoggedIn = true
        }
    }
}
