import XCTest
@testable import ImmichApp

final class SharedUploadStoreTests: XCTestCase {
    private var rootURL: URL!
    private var store: SharedUploadStore!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedUploadStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = SharedUploadStore(rootURL: rootURL)
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
        store = nil
        rootURL = nil
    }

    func testBatchSurvivesReloadAndIsScopedToOwner() async throws {
        let owner = SharedUploadOwner(server: "https://one.example/api", userID: "user-1")
        let otherOwner = SharedUploadOwner(server: "https://one.example/api", userID: "user-2")
        let batch = makeBatch(owner: owner, state: .uploading)

        try await store.save(batch)

        let reloaded = SharedUploadStore(rootURL: rootURL)
        let matching = try await reloaded.batches(for: owner)
        let other = try await reloaded.batches(for: otherOwner)
        XCTAssertEqual(matching, [batch])
        XCTAssertTrue(other.isEmpty)
    }

    func testRemovingBatchDeletesStagedFilesAndManifest() async throws {
        let batch = makeBatch(
            owner: SharedUploadOwner(server: "https://one.example/api", userID: "user-1"),
            state: .queued)
        let directory = try await store.makeBatchDirectory(id: batch.id)
        let fileURL = directory.appendingPathComponent(batch.items[0].relativePath)
        try Data("image".utf8).write(to: fileURL)
        try await store.save(batch)

        try await store.removeBatch(id: batch.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testFileURLRejectsPathTraversal() async throws {
        var batch = makeBatch(
            owner: SharedUploadOwner(server: "https://one.example/api", userID: "user-1"),
            state: .queued)
        let original = batch.items[0]
        batch.items[0] = SharedUploadItem(
            id: original.id,
            filename: original.filename,
            relativePath: "../outside.jpg",
            contentType: original.contentType,
            byteCount: original.byteCount,
            createdAt: original.createdAt,
            modifiedAt: original.modifiedAt,
            state: original.state,
            lastError: original.lastError)

        do {
            _ = try await store.fileURL(for: batch.items[0], batchID: batch.id)
            XCTFail("Path traversal should be rejected")
        } catch SharedUploadStoreError.invalidFilename {
            // Expected.
        }
    }

    private func makeBatch(
        owner: SharedUploadOwner,
        state: SharedUploadItemState
    ) -> SharedUploadBatch {
        let itemID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return SharedUploadBatch(
            id: UUID(),
            owner: owner,
            createdAt: now,
            items: [SharedUploadItem(
                id: itemID,
                filename: "shared.jpg",
                relativePath: "\(itemID.uuidString)-shared.jpg",
                contentType: "image/jpeg",
                byteCount: 5,
                createdAt: now,
                modifiedAt: now,
                state: state,
                lastError: nil)])
    }
}
