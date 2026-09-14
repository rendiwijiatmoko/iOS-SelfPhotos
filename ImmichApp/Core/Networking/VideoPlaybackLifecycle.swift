import AVFoundation

/// Release playback ownership when a video leaves the screen. A user pause is
/// intentionally different: it keeps the item so playback can resume in place.
@MainActor
enum VideoPlaybackLifecycle {
    static func stop(_ player: AVPlayer?) {
        guard let player else { return }
        let item = player.currentItem
        player.pause()
        item?.cancelPendingSeeks()
        player.replaceCurrentItem(with: nil)
        item?.asset.cancelLoading()
        NetworkResponseCache.clear()
    }
}
