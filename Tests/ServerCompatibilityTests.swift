import XCTest
@testable import ImmichApp

final class ServerCompatibilityTests: XCTestCase {
    func testCurrentMajorIsCompatible() {
        let status = ServerCompatibilityPolicy.evaluate(
            ServerVersionDTO(major: 3, minor: 1, patch: 0))

        XCTAssertEqual(status, .compatible)
        XCTAssertTrue(status.allowsAuthentication)
    }

    func testPreviousMajorIsCompatibleLegacy() {
        let status = ServerCompatibilityPolicy.evaluate(
            ServerVersionDTO(major: 2, minor: 7, patch: 4))

        XCTAssertEqual(status, .compatibleLegacy)
        XCTAssertTrue(status.allowsAuthentication)
    }

    func testOlderMajorRequiresServerUpgrade() {
        let status = ServerCompatibilityPolicy.evaluate(
            ServerVersionDTO(major: 1, minor: 143, patch: 0))

        XCTAssertEqual(status, .serverUpgradeRequired)
        XCTAssertFalse(status.allowsAuthentication)
    }

    func testFutureMajorRequiresAppUpgrade() {
        let status = ServerCompatibilityPolicy.evaluate(
            ServerVersionDTO(major: 4, minor: 0, patch: 0))

        XCTAssertEqual(status, .appUpgradeRequired)
        XCTAssertFalse(status.allowsAuthentication)
    }

    func testPrereleaseVersionFormatting() {
        let version = ServerVersionDTO(major: 3, minor: 2, patch: 0, prerelease: 3)
        XCTAssertEqual(version.displayName, "v3.2.0-3")
    }

    func testDecodesOfficialV3VersionResponse() throws {
        let json = Data(#"{"major":3,"minor":1,"patch":0,"prerelease":null}"#.utf8)
        let version = try JSONDecoder().decode(ServerVersionDTO.self, from: json)

        XCTAssertEqual(version, ServerVersionDTO(major: 3, minor: 1, patch: 0))
    }

    func testDecodesV2ResponseWithoutPrereleaseField() throws {
        let json = Data(#"{"major":2,"minor":7,"patch":4}"#.utf8)
        let version = try JSONDecoder().decode(ServerVersionDTO.self, from: json)

        XCTAssertEqual(version, ServerVersionDTO(major: 2, minor: 7, patch: 4))
    }
}
