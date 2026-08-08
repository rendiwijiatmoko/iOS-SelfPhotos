import Foundation
import XCTest
@testable import ImmichApp

final class LivePhotoBackupTaskContextTests: XCTestCase {
    func testTaskContextRoundTripsMotionPhaseAcrossProcessRelaunch() throws {
        let original = BackupUploadTaskContext(
            phase: .livePhotoMotion,
            localIdentifier: "A1B2C3/L0/001",
            checksum: "motion-sha1",
            bodyPath: "/tmp/live photo.multipart")

        XCTAssertEqual(BackupUploadTaskContext.decode(original.encoded), original)
    }

    func testTaskContextStillDecodesLegacyPrimaryUpload() throws {
        let legacy = ["local-id", "old-checksum", "/tmp/old.multipart"]
            .joined(separator: "\u{1}")

        let decoded = try XCTUnwrap(BackupUploadTaskContext.decode(legacy))
        XCTAssertEqual(decoded.phase, .primaryAsset)
        XCTAssertEqual(decoded.localIdentifier, "local-id")
        XCTAssertEqual(decoded.checksum, "old-checksum")
        XCTAssertEqual(decoded.bodyPath, "/tmp/old.multipart")
    }

    func testMalformedTaskContextIsRejected() {
        XCTAssertNil(BackupUploadTaskContext.decode("not-a-valid-context"))
        XCTAssertNil(BackupUploadTaskContext.decode(nil))
    }
}

@MainActor
final class LivePhotoMultipartContractTests: XCTestCase {
    func testMotionUploadIsHiddenAndUsesOriginalDates() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let modifiedAt = Date(timeIntervalSince1970: 1_700_003_600)
        let prepared = try await fixture.repository.makeUploadRequest(
            fileURL: fixture.source,
            filename: "IMG_0042.MOV",
            checksum: "motion-checksum",
            deviceAssetId: "local-live-photo",
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            additionalFields: ["visibility": "hidden"])
        defer { try? FileManager.default.removeItem(at: prepared.bodyFile) }

        let body = try String(contentsOf: prepared.bodyFile, encoding: .utf8)
        XCTAssertEqual(
            prepared.request.value(forHTTPHeaderField: "x-immich-checksum"),
            "motion-checksum")
        XCTAssertTrue(body.contains("name=\"visibility\"\r\n\r\nhidden"))
        XCTAssertTrue(body.contains("name=\"fileCreatedAt\"\r\n\r\n2023-11-14T22:13:20Z"))
        XCTAssertTrue(body.contains("name=\"fileModifiedAt\"\r\n\r\n2023-11-14T23:13:20Z"))
        XCTAssertTrue(body.contains("filename=\"IMG_0042.MOV\""))
    }

    func testStillUploadCarriesMotionAssetRelationship() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let prepared = try await fixture.repository.makeUploadRequest(
            fileURL: fixture.source,
            filename: "IMG_0042.HEIC",
            checksum: "still-checksum",
            deviceAssetId: "local-live-photo",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_700_003_600),
            additionalFields: ["livePhotoVideoId": "server-motion-id"])
        defer { try? FileManager.default.removeItem(at: prepared.bodyFile) }

        let body = try String(contentsOf: prepared.bodyFile, encoding: .utf8)
        XCTAssertTrue(body.contains(
            "name=\"livePhotoVideoId\"\r\n\r\nserver-motion-id"))
        XCTAssertFalse(body.contains("name=\"visibility\""))
        XCTAssertTrue(body.contains("filename=\"IMG_0042.HEIC\""))
    }

    private struct Fixture {
        let repository: BackupRepository
        let source: URL

        func cleanup() {
            try? FileManager.default.removeItem(at: source)
        }
    }

    private func makeFixture() throws -> Fixture {
        let session = MockSessionManager()
        try session.setServer("https://immich.example.test")
        let repository = BackupRepository(api: APIClient(session: session))
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("live-photo-fixture-\(UUID().uuidString).bin")
        try Data("paired-resource".utf8).write(to: source, options: .atomic)
        return Fixture(repository: repository, source: source)
    }
}
