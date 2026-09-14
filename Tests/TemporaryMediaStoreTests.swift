import Foundation
import XCTest
@testable import ImmichApp

final class TemporaryMediaStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "temporary-media-store-tests-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testShareFileIsUniqueAndRemovedExplicitly() throws {
        let first = try TemporaryMediaStore.createShareFile(
            data: Data("one".utf8),
            suggestedFilename: "../photo.jpg")
        let second = try TemporaryMediaStore.createShareFile(
            data: Data("two".utf8),
            suggestedFilename: "photo.jpg")
        defer { TemporaryMediaStore.remove([first, second]) }

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.lastPathComponent.hasSuffix("-photo.jpg"))
        XCTAssertEqual(try Data(contentsOf: first), Data("one".utf8))

        TemporaryMediaStore.remove(first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testCleanupRemovesOnlyStaleRegularFiles() throws {
        let stale = directory.appendingPathComponent("old-video.mov")
        let fresh = directory.appendingPathComponent("fresh-photo.jpg")
        let nested = directory.appendingPathComponent("nested", isDirectory: true)
        try Data("old".utf8).write(to: stale)
        try Data("fresh".utf8).write(to: fresh)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let now = Date()
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-7_200)],
            ofItemAtPath: stale.path)
        try FileManager.default.setAttributes(
            [.modificationDate: now],
            ofItemAtPath: fresh.path)

        TemporaryMediaStore.cleanupStaleFiles(
            in: directory,
            olderThan: now.addingTimeInterval(-3_600))

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
    }

    func testCleanupPreservesBackgroundBackupFiles() throws {
        let multipart = directory.appendingPathComponent("upload-old.multipart")
        let source = directory.appendingPathComponent("backup-source-old.mov")
        try Data("body".utf8).write(to: multipart)
        try Data("source".utf8).write(to: source)

        let oldDate = Date().addingTimeInterval(-7_200)
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate],
            ofItemAtPath: multipart.path)
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate],
            ofItemAtPath: source.path)

        TemporaryMediaStore.cleanupStaleFiles(
            in: directory,
            olderThan: Date().addingTimeInterval(-3_600))

        XCTAssertTrue(FileManager.default.fileExists(atPath: multipart.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testColdLaunchCleanupRemovesMeasuredNestedTemporaryFiles() throws {
        let tmp = directory.appendingPathComponent("tmp")
        let cutoff = Date().addingTimeInterval(-86_400)
        for suffix in ["A7Toxm", "twrESE"] {
            let folder = tmp.appendingPathComponent("NSIRD_ImmichApp_\(suffix)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent(".old-working-file")
            try Data(repeating: 1, count: 12_000).write(to: file)
            for url in [file, folder] {
                try FileManager.default.setAttributes(
                    [.modificationDate: cutoff.addingTimeInterval(-60)], ofItemAtPath: url.path)
            }
        }
        XCTAssertGreaterThan(AppStorageUsage.scan(home: directory, shared: nil).temporaryFiles, 0)
        TemporaryMediaStore.cleanupStaleWorkingDirectories(in: tmp, olderThan: cutoff)
        XCTAssertEqual(AppStorageUsage.scan(home: directory, shared: nil).temporaryFiles, 0)
        // Repeated launches remain harmless.
        TemporaryMediaStore.cleanupStaleWorkingDirectories(in: tmp, olderThan: cutoff)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: tmp.path).isEmpty)
    }

    func testWorkingDirectoryCleanupPreservesRecentProtectedAndUnrelatedFiles() throws {
        let cutoff = Date().addingTimeInterval(-86_400)
        for (folderName, fileName, recent) in [
            ("NSIRD_ImmichApp_recent", "working", true),
            ("NSIRD_ImmichApp_backup", "upload-active.multipart", false),
            ("NSIRD_ImmichApp_source", "backup-source-video.mov", false),
            ("unrelated-directory", "working", false),
        ] {
            let folder = directory.appendingPathComponent(folderName)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent(fileName)
            try Data([1]).write(to: file)
            try FileManager.default.setAttributes(
                [.modificationDate: recent ? Date() : cutoff.addingTimeInterval(-60)], ofItemAtPath: file.path)
            try FileManager.default.setAttributes(
                [.modificationDate: cutoff.addingTimeInterval(-60)], ofItemAtPath: folder.path)
            TemporaryMediaStore.cleanupStaleWorkingDirectories(in: directory, olderThan: cutoff)
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), folderName)
        }
    }

    func testWorkingDirectoryCleanupDoesNotFollowSymbolicLinks() throws {
        let target = directory.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let file = target.appendingPathComponent("preserve")
        try Data([1]).write(to: file)
        let link = directory.appendingPathComponent("NSIRD_ImmichApp_link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        TemporaryMediaStore.cleanupStaleWorkingDirectories(in: directory, olderThan: .distantFuture)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
    }
}
