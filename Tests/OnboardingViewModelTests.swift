import XCTest
@testable import ImmichApp

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    var mockSession: MockSessionManager!
    var viewModel: OnboardingViewModel!

    override func setUp() async throws {
        try await super.setUp()
        // Alamat terakhir disimpan di UserDefaults dan diisikan ulang di init;
        // dibersihkan supaya urutan test tidak saling memengaruhi.
        UserDefaults.standard.removeObject(forKey: "onboarding.lastServer")
        mockSession = MockSessionManager()
        viewModel = OnboardingViewModel(session: mockSession)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "onboarding.lastServer")
        mockSession = nil
        viewModel = nil
        try await super.tearDown()
    }

    func testInitialState() {
        XCTAssertTrue(viewModel.serverText.isEmpty)
        XCTAssertTrue(viewModel.email.isEmpty)
        XCTAssertTrue(viewModel.password.isEmpty)
        XCTAssertTrue(viewModel.apiKey.isEmpty)
        XCTAssertNil(viewModel.features)
        XCTAssertEqual(viewModel.method, .password)
        XCTAssertFalse(viewModel.canSubmit)
        if case .idle = viewModel.phase {} else {
            XCTFail("Expected idle phase")
        }
    }

    func testCannotSubmitWithoutServer() {
        viewModel.email = "user@example.com"
        viewModel.password = "password123"
        XCTAssertFalse(viewModel.canSubmit)
    }

    func testCannotSubmitWithoutCredentials() {
        viewModel.serverText = "https://immich.example.com"
        XCTAssertFalse(viewModel.canSubmit)
    }

    func testApiKeyMethodIgnoresEmailFields() {
        viewModel.serverText = "https://immich.example.com"
        viewModel.method = .apiKey
        XCTAssertFalse(viewModel.canSubmit)

        viewModel.apiKey = "key-123"
        XCTAssertTrue(viewModel.canSubmit)
    }

    func testSubmitConnectsAndSignsIn() async {
        mockSession.shouldSucceedPing = true
        mockSession.shouldSucceedLogin = true
        mockSession.mockFeatures = ServerFeaturesDTO(
            smartSearch: true,
            facialRecognition: true,
            oauth: false,
            passwordLogin: true,
            search: true)

        viewModel.serverText = "https://immich.example.com"
        viewModel.email = "user@example.com"
        viewModel.password = "password123"

        await viewModel.submit()

        XCTAssertTrue(mockSession.isLoggedIn)
        XCTAssertEqual(mockSession.pingCallCount, 1)
        XCTAssertEqual(mockSession.versionCallCount, 1)
        XCTAssertEqual(mockSession.featuresCallCount, 1)
        XCTAssertEqual(mockSession.loginPasswordCallCount, 1)
    }

    /// Alamat server hanya disimpan kalau seluruh alurnya berhasil — menyimpan
    /// alamat yang baru saja gagal dihubungi hanya akan mengisikannya lagi lain
    /// kali.
    func testServerRememberedOnlyAfterSuccess() async {
        mockSession.shouldSucceedPing = false
        viewModel.serverText = "https://unreachable.example.com"
        viewModel.email = "user@example.com"
        viewModel.password = "password123"

        await viewModel.submit()

        XCTAssertNil(UserDefaults.standard.string(forKey: "onboarding.lastServer"))
    }

    func testUnreachableServerReportsFailure() async {
        mockSession.shouldSucceedPing = false

        viewModel.serverText = "https://unreachable.example.com"
        viewModel.email = "user@example.com"
        viewModel.password = "password123"

        await viewModel.submit()

        XCTAssertFalse(mockSession.isLoggedIn)
        if case .failed(let msg) = viewModel.phase {
            XCTAssertFalse(msg.isEmpty)
        } else {
            XCTFail("Expected failed phase")
        }
    }

    func testInvalidCredentialsReportFailure() async {
        mockSession.shouldSucceedPing = true
        mockSession.shouldSucceedLogin = false

        viewModel.serverText = "https://immich.example.com"
        viewModel.email = "user@example.com"
        viewModel.password = "wrongpassword"

        await viewModel.submit()

        XCTAssertFalse(mockSession.isLoggedIn)
        if case .failed(let msg) = viewModel.phase {
            XCTAssertFalse(msg.isEmpty)
        } else {
            XCTFail("Expected failed phase")
        }
    }

    func testSubmitWithApiKey() async {
        mockSession.shouldSucceedPing = true
        mockSession.shouldSucceedApiKey = true

        viewModel.serverText = "https://immich.example.com"
        viewModel.method = .apiKey
        viewModel.apiKey = "valid-api-key-123"

        await viewModel.submit()

        XCTAssertTrue(mockSession.isLoggedIn)
        XCTAssertEqual(mockSession.loginApiKeyCallCount, 1)
    }

    func testInvalidApiKeyReportsFailure() async {
        mockSession.shouldSucceedPing = true
        mockSession.shouldSucceedApiKey = false

        viewModel.serverText = "https://immich.example.com"
        viewModel.method = .apiKey
        viewModel.apiKey = "bad-key"

        await viewModel.submit()

        XCTAssertFalse(mockSession.isLoggedIn)
        if case .failed(let msg) = viewModel.phase {
            XCTAssertFalse(msg.isEmpty)
        } else {
            XCTFail("Expected failed phase")
        }
    }

    func testServerOlderThanCompatibilityWindowNeverReceivesCredentials() async {
        mockSession.shouldSucceedPing = true
        mockSession.shouldSucceedLogin = true
        mockSession.mockVersion = ServerVersionDTO(major: 1, minor: 143, patch: 0)

        viewModel.serverText = "https://immich.example.com"
        viewModel.email = "user@example.com"
        viewModel.password = "password123"

        await viewModel.submit()

        XCTAssertFalse(mockSession.isLoggedIn)
        XCTAssertEqual(mockSession.loginPasswordCallCount, 0)
        if case .failed(let message) = viewModel.phase {
            XCTAssertTrue(message.localizedCaseInsensitiveContains("server"))
        } else {
            XCTFail("Expected compatibility failure")
        }
    }

    func testServerNewerThanAppNeverReceivesApiKey() async {
        mockSession.shouldSucceedPing = true
        mockSession.shouldSucceedApiKey = true
        mockSession.mockVersion = ServerVersionDTO(major: 4, minor: 0, patch: 0)

        viewModel.serverText = "https://immich.example.com"
        viewModel.method = .apiKey
        viewModel.apiKey = "secret-key"

        await viewModel.submit()

        XCTAssertFalse(mockSession.isLoggedIn)
        XCTAssertEqual(mockSession.loginApiKeyCallCount, 0)
        if case .failed(let message) = viewModel.phase {
            XCTAssertTrue(message.localizedCaseInsensitiveContains("app"))
        } else {
            XCTFail("Expected compatibility failure")
        }
    }

    func testDisabledPasswordCapabilityNeverCallsPasswordLogin() async {
        mockSession.shouldSucceedPing = true
        mockSession.shouldSucceedLogin = true
        mockSession.mockFeatures = ServerFeaturesDTO(
            smartSearch: true,
            facialRecognition: true,
            oauth: true,
            passwordLogin: false,
            search: true)

        viewModel.serverText = "https://immich.example.com"
        viewModel.email = "user@example.com"
        viewModel.password = "password123"

        await viewModel.submit()

        XCTAssertEqual(mockSession.loginPasswordCallCount, 0)
        if case .failed(let message) = viewModel.phase {
            XCTAssertTrue(message.localizedCaseInsensitiveContains("API key"))
        } else {
            XCTFail("Expected unavailable password failure")
        }
    }
}
