import AVFoundation
import XCTest
@testable import ImmichApp

final class VideoPlaybackLifecycleTests: XCTestCase {
    private final class TrackingAsset: AVURLAsset, @unchecked Sendable {
        var cancellationCount = 0

        override func cancelLoading() {
            cancellationCount += 1
            super.cancelLoading()
        }
    }

    @MainActor
    func testLeavingPlaybackDetachesItemAndCancelsAssetLoading() {
        let asset = TrackingAsset(url: URL(fileURLWithPath: "/nonexistent-test-video.mov"))
        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        VideoPlaybackLifecycle.stop(player)
        XCTAssertNil(player.currentItem)
        XCTAssertEqual(player.rate, 0)
        XCTAssertGreaterThanOrEqual(asset.cancellationCount, 1)
    }

    @MainActor
    func testRepeatedCleanupAndAbsentPlayerAreSafe() {
        let player = AVPlayer()
        VideoPlaybackLifecycle.stop(player)
        VideoPlaybackLifecycle.stop(player)
        VideoPlaybackLifecycle.stop(nil)
        XCTAssertNil(player.currentItem)
    }

    @MainActor
    func testStoppingOnePlayerDoesNotDetachAnotherPlayer() {
        let first = AVPlayer(playerItem: AVPlayerItem(url: URL(fileURLWithPath: "/first-test-video.mov")))
        let secondItem = AVPlayerItem(url: URL(fileURLWithPath: "/second-test-video.mov"))
        let second = AVPlayer(playerItem: secondItem)
        VideoPlaybackLifecycle.stop(first)
        XCTAssertNil(first.currentItem)
        XCTAssertTrue(second.currentItem === secondItem)
        VideoPlaybackLifecycle.stop(second)
    }
}
