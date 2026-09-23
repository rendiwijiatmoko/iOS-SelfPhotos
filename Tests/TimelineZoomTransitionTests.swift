import XCTest
import UIKit
@testable import ImmichApp

@MainActor
final class TimelineZoomTransitionTests: XCTestCase {
    func testCancellationRemovesOverlayAndRestoresSourceExactlyOnce() async throws {
        let window = try makeWindow()
        let originalSubviews = window.subviews.count
        var sourceHidden = true
        var completions = 0
        let transition = animatePhotoMatchZoom(
            image: makeImage(),
            fromScreenFrame: CGRect(x: 20, y: 120, width: 240, height: 180),
            toScreenFrame: CGRect(x: 120, y: 300, width: 80, height: 80),
            in: window,
            sourceCornerRadius: 18
        ) {
            sourceHidden = false
            completions += 1
        }

        if !UIAccessibility.isReduceMotionEnabled {
            XCTAssertEqual(window.subviews.count, originalSubviews + 1)
        }
        transition.cancel()
        transition.cancel()

        XCTAssertEqual(window.subviews.count, originalSubviews)
        XCTAssertFalse(sourceHidden)
        XCTAssertEqual(completions, 1)

        // The queued animation-start callback must not resurrect a cancelled
        // overlay or call its completion for a second time.
        await nextMainQueueTurn()
        XCTAssertEqual(window.subviews.count, originalSubviews)
        XCTAssertEqual(completions, 1)
    }

    func testCancellationAfterAnimationStartsCompletesOnlyOnce() async throws {
        let window = try makeWindow()
        let originalSubviews = window.subviews.count
        var completions = 0
        let transition = animatePhotoMatchZoom(
            image: makeImage(),
            fromScreenFrame: CGRect(x: 20, y: 120, width: 240, height: 180),
            toScreenFrame: CGRect(x: 120, y: 300, width: 80, height: 80),
            in: window,
            sourceCornerRadius: 18
        ) {
            completions += 1
        }

        await nextMainQueueTurn()
        transition.cancel()
        transition.cancel()
        try? await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(window.subviews.count, originalSubviews)
        XCTAssertEqual(completions, 1)
    }

    func testInvalidFrameCompletesImmediatelyAndRepeatedCancelIsHarmless() throws {
        let window = try makeWindow()
        let originalSubviews = window.subviews.count
        var completions = 0
        let transition = animatePhotoMatchZoom(
            image: makeImage(),
            fromScreenFrame: .zero,
            toScreenFrame: CGRect(x: 120, y: 300, width: 80, height: 80),
            in: window,
            sourceCornerRadius: 18
        ) {
            completions += 1
        }

        XCTAssertEqual(completions, 1)
        transition.cancel()
        transition.cancel()
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(window.subviews.count, originalSubviews)
    }

    func testNormalCompletionRemovesOverlayAndLaterCancelDoesNotRepeatIt() async throws {
        let window = try makeWindow()
        let originalSubviews = window.subviews.count
        let completed = expectation(description: "Match animation completes")
        var completions = 0
        let transition = animatePhotoMatchZoom(
            image: makeImage(),
            fromScreenFrame: CGRect(x: 20, y: 120, width: 240, height: 180),
            toScreenFrame: CGRect(x: 120, y: 300, width: 80, height: 80),
            in: window,
            sourceCornerRadius: 18
        ) {
            completions += 1
            completed.fulfill()
        }

        await fulfillment(of: [completed], timeout: 2)
        transition.cancel()
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(window.subviews.count, originalSubviews)
    }

    private func makeWindow() throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        return window
    }

    private func makeImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
    }

    private func nextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
