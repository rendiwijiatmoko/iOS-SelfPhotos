import Foundation
import XCTest
@testable import ImmichApp

@MainActor
final class BackgroundUploadQueueTests: XCTestCase {
    func testQueueSurvivesProcessRelaunchWithUploadingTask() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let queue = BackupQueueStore(fileURL: fixture.queueURL)
        try queue.bind(to: BackupQueueOwner(server: "https://immich.test/api", userID: "user-1"))
        try queue.enqueue(["local-a", "local-b"], now: Date(timeIntervalSince1970: 10))
        try queue.markPreparing("local-a", phase: .primaryAsset)
        try queue.markUploading(
            "local-a",
            phase: .primaryAsset,
            checksum: "sha1-a",
            taskIdentifier: 42)

        let restored = BackupQueueStore(fileURL: fixture.queueURL)

        XCTAssertEqual(restored.snapshot.total, 2)
        XCTAssertEqual(restored.snapshot.active, 1)
        XCTAssertEqual(restored.snapshot.queued, 1)
        XCTAssertEqual(restored.item(id: "local-a")?.taskIdentifier, 42)
        XCTAssertEqual(restored.owner?.userID, "user-1")
    }

    func testCompletedBatchNotificationIsConsumedAcrossRelaunch() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let queue = BackupQueueStore(fileURL: fixture.queueURL)
        try queue.enqueue(["local-a"])
        try queue.markCompleted("local-a")

        XCTAssertTrue(queue.snapshot.completionNotificationPending)
        try queue.consumeCompletionNotification()

        let restored = BackupQueueStore(fileURL: fixture.queueURL)
        XCTAssertEqual(restored.snapshot.completed, 1)
        XCTAssertFalse(restored.snapshot.completionNotificationPending)
    }

    func testNewBatchRearmsCompletionNotification() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let queue = BackupQueueStore(fileURL: fixture.queueURL)
        try queue.enqueue(["first"])
        try queue.markCompleted("first")
        try queue.consumeCompletionNotification()

        try queue.enqueue(["second"])

        XCTAssertEqual(queue.snapshot.completed, 0)
        XCTAssertEqual(queue.snapshot.queued, 1)
        XCTAssertTrue(queue.snapshot.completionNotificationPending)
    }

    func testRediscoveringSameFailedItemDoesNotReplayCompletion() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let queue = BackupQueueStore(fileURL: fixture.queueURL)
        try queue.enqueue(["failed"])
        try queue.markFailed("failed", error: "invalid asset")
        try queue.consumeCompletionNotification()

        // Automatic scans rediscover failed local assets on every launch.
        try queue.enqueue(["failed"])

        XCTAssertFalse(queue.snapshot.completionNotificationPending)
        XCTAssertEqual(queue.snapshot.failed, 1)
    }

    func testStalePreparingItemBecomesRetryInsteadOfHangingForever() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let queue = BackupQueueStore(fileURL: fixture.queueURL)
        let started = Date(timeIntervalSince1970: 100)
        try queue.enqueue(["local-a"], now: started)
        try queue.markPreparing("local-a", phase: .primaryAsset, now: started)

        try queue.reconcile(
            activeTasks: [],
            now: Date(timeIntervalSince1970: 1_000),
            staleAfter: 600)

        XCTAssertEqual(queue.snapshot.retryScheduled, 1)
        XCTAssertEqual(queue.readyItems(now: Date(timeIntervalSince1970: 1_000)).map(\.id), ["local-a"])
    }

    func testBackgroundTaskWithoutQueueRecordIsAdoptedAfterUpgrade() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let queue = BackupQueueStore(fileURL: fixture.queueURL)
        let context = BackupUploadTaskContext(
            phase: .livePhotoMotion,
            localIdentifier: "legacy-live",
            checksum: "motion-sha1",
            bodyPath: "/tmp/legacy.multipart")

        try queue.reconcile(activeTasks: [
            BackupActiveTask(taskIdentifier: 7, context: context, isSuspended: true),
        ])

        XCTAssertEqual(queue.snapshot.active, 1)
        XCTAssertEqual(queue.item(id: "legacy-live")?.phase, .livePhotoMotion)
        XCTAssertEqual(queue.item(id: "legacy-live")?.taskIdentifier, 7)
    }

    func testNetworkAndAuthenticationWaitsResumeWithoutBackupView() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let queue = BackupQueueStore(fileURL: fixture.queueURL)
        try queue.enqueue(["network", "auth"])
        try queue.markRetry(
            "network",
            state: .waitingForNetwork,
            error: "offline",
            retryAt: .distantFuture)
        try queue.markRetry(
            "auth",
            state: .waitingForAuthentication,
            error: "expired",
            retryAt: nil)

        XCTAssertEqual(queue.snapshot.waitingForNetwork, 1)
        XCTAssertEqual(queue.snapshot.waitingForAuthentication, 1)
        XCTAssertEqual(queue.snapshot.presentation?.title, "Backup Needs Sign In")

        try queue.releaseNetworkWaits()
        try queue.releaseAuthenticationWaits()

        XCTAssertEqual(Set(queue.readyItems().map(\.id)), Set(["network", "auth"]))
        XCTAssertEqual(queue.snapshot.queued, 2)
    }

    func testQueueCannotCrossIntoAnotherAccount() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let queue = BackupQueueStore(fileURL: fixture.queueURL)
        try queue.bind(to: BackupQueueOwner(server: "https://immich.test/api", userID: "user-1"))
        try queue.enqueue(["private-asset"])

        let replaced = try queue.bind(
            to: BackupQueueOwner(server: "https://immich.test/api", userID: "user-2"))

        XCTAssertTrue(replaced)
        XCTAssertEqual(queue.snapshot.total, 0)
        XCTAssertEqual(queue.owner?.userID, "user-2")
    }

    func testCorruptQueueIsQuarantinedAndRebuildable() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        try FileManager.default.createDirectory(
            at: fixture.queueURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: fixture.queueURL)

        let queue = BackupQueueStore(fileURL: fixture.queueURL)

        XCTAssertNotNil(queue.persistenceWarning)
        XCTAssertEqual(queue.snapshot.total, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.queueURL.path))
        try queue.enqueue(["rediscovered"])
        XCTAssertEqual(queue.snapshot.queued, 1)
    }

    private struct Fixture {
        let directory: URL
        var queueURL: URL { directory.appendingPathComponent("queue.json") }

        func cleanup() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func makeFixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("background-queue-tests-\(UUID().uuidString)", isDirectory: true)
        return Fixture(directory: directory)
    }
}

final class BackgroundUploadFailureClassificationTests: XCTestCase {
    func testConnectivityFailuresStayRetryable() {
        XCTAssertEqual(
            BackupUploadFailureDisposition.classify(URLError(.networkConnectionLost)),
            .retryNetwork)
        XCTAssertEqual(
            BackupUploadFailureDisposition.classify(URLError(.cannotConnectToHost)),
            .retryNetwork)
    }

    func testExpiredTokenWaitsForAuthentication() {
        XCTAssertEqual(
            BackupUploadFailureDisposition.classify(
                APIError.server(status: 401, message: "expired")),
            .authenticationRequired)
    }

    func testServerErrorsRetryButInvalidAssetDoesNotLoopForever() {
        XCTAssertEqual(
            BackupUploadFailureDisposition.classify(
                APIError.server(status: 503, message: "unavailable")),
            .retryServer)
        XCTAssertEqual(
            BackupUploadFailureDisposition.classify(
                APIError.server(status: 400, message: "invalid asset")),
            .permanent)
    }
}
