import CryptoKit
import XCTest
@testable import ImmichApp

final class OIDCLoginTests: XCTestCase {
    func testPKCEChallengeMatchesVerifier() throws {
        let request = try OIDCLoginRequest()
        let digest = Data(SHA256.hash(data: Data(request.codeVerifier.utf8)))
        let expected = digest.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(request.codeChallenge, expected)
        XCTAssertNotEqual(request.state, request.codeVerifier)
    }

    func testCallbackKeepsThreeSlashRedirectAndQuery() throws {
        let request = try OIDCLoginRequest()
        let callback = URL(string: "app.immich:/oauth-callback?code=abc&state=\(request.state)")!
        XCTAssertEqual(
            try request.callbackURL(callback),
            "app.immich:///oauth-callback?code=abc&state=\(request.state)")
    }

    func testRejectsWrongStateAndSchemeBeforeExchange() throws {
        let request = try OIDCLoginRequest()
        let wrongState = URL(string: "app.immich:///oauth-callback?code=abc&state=wrong")!
        XCTAssertThrowsError(try request.callbackURL(wrongState)) { error in
            guard case OIDCLoginError.stateMismatch = error else {
                return XCTFail("Expected state mismatch")
            }
        }
        let wrongScheme = URL(string: "selfphotos:///oauth-callback?code=abc&state=\(request.state)")!
        XCTAssertThrowsError(try request.callbackURL(wrongScheme))
    }
}
