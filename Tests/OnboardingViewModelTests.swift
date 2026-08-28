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
        XCTAssertNil(viewModel.features)
        XCTAssertFalse(viewModel.canConnect)
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

    func testConnectThenEmailSignIn() async {
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

        let connected = await viewModel.connectToServer()
        XCTAssertTrue(connected)

        // Tahap server tidak pernah mengirim kredensial.
        XCTAssertFalse(mockSession.isLoggedIn)
        XCTAssertEqual(mockSession.loginPasswordCallCount, 0)
        let signedIn = await viewModel.signIn()
        XCTAssertTrue(signedIn)

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
        mockSession.shouldSucceedPing = true
        mockSession.shouldSucceedLogin = true
        viewModel.serverText = "https://immich.example.com"
        viewModel.email = "user@example.com"
        viewModel.password = "password123"

        let connected = await viewModel.connectToServer()
        XCTAssertTrue(connected)
        XCTAssertNil(UserDefaults.standard.string(forKey: "onboarding.lastServer"))
        let signedIn = await viewModel.signIn()
        XCTAssertTrue(signedIn)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "onboarding.lastServer"),
            "https://immich.example.com")
    }

    func testEditingServerAfterValidationLocksCredentialsAgain() async {
        mockSession.shouldSucceedPing = true
        viewModel.serverText = "https://immich.example.com"
        viewModel.email = "user@example.com"
        viewModel.password = "password123"

        let connected = await viewModel.connectToServer()
        XCTAssertTrue(connected)
        XCTAssertTrue(viewModel.canSubmit)

        viewModel.serverText = "https://another.example.com"

        XCTAssertNil(viewModel.features)
        XCTAssertNil(viewModel.validatedServerText)
        XCTAssertFalse(viewModel.canSubmit)
    }

    func testUnreachableServerReportsFailure() async {
        mockSession.shouldSucceedPing = false

        viewModel.serverText = "https://unreachable.example.com"
        viewModel.email = "user@example.com"
        viewModel.password = "password123"

        let connected = await viewModel.connectToServer()
        XCTAssertFalse(connected)

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

        let connected = await viewModel.connectToServer()
        XCTAssertTrue(connected)
        let signedIn = await viewModel.signIn()
        XCTAssertFalse(signedIn)

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

        let connected = await viewModel.connectToServer()
        XCTAssertFalse(connected)

        XCTAssertFalse(mockSession.isLoggedIn)
        XCTAssertEqual(mockSession.loginPasswordCallCount, 0)
        if case .failed(let message) = viewModel.phase {
            XCTAssertTrue(message.localizedCaseInsensitiveContains("server"))
        } else {
            XCTFail("Expected compatibility failure")
        }
    }

    func testServerNewerThanAppNeverReceivesCredentials() async {
        mockSession.shouldSucceedPing = true
        mockSession.shouldSucceedLogin = true
        mockSession.mockVersion = ServerVersionDTO(major: 4, minor: 0, patch: 0)

        viewModel.serverText = "https://immich.example.com"
        viewModel.email = "user@example.com"
        viewModel.password = "secret-password"

        let connected = await viewModel.connectToServer()
        XCTAssertFalse(connected)

        XCTAssertFalse(mockSession.isLoggedIn)
        XCTAssertEqual(mockSession.loginPasswordCallCount, 0)
        if case .failed(let message) = viewModel.phase {
            XCTAssertTrue(message.localizedCaseInsensitiveContains("app"))
        } else {
            XCTFail("Expected compatibility failure")
        }
    }

    func testDisabledPasswordCapabilityStopsBeforeCredentials() async {
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

        let connected = await viewModel.connectToServer()
        XCTAssertFalse(connected)

        XCTAssertEqual(mockSession.loginPasswordCallCount, 0)
        XCTAssertNil(viewModel.validatedServerText)
        XCTAssertFalse(viewModel.canSubmit)
        if case .failed(let message) = viewModel.phase {
            XCTAssertTrue(message.localizedCaseInsensitiveContains("password"))
        } else {
            XCTFail("Expected password-login compatibility failure")
        }
    }
}
