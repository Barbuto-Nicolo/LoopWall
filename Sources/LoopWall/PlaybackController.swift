import AVFoundation
import AppKit

enum PlaybackError: LocalizedError {
    case notPlayable(URL)

    var errorDescription: String? {
        switch self {
        case .notPlayable(let url):
            return "AVFoundation cannot play \(url.lastPathComponent)."
        }
    }
}

/// Owns the player objects for one wallpaper: AVQueuePlayer + AVPlayerLooper
/// (gap-free looping) and the AVPlayerLayer that renders the frames.
/// Decoding goes through VideoToolbox (hardware) automatically for H.264/HEVC.
@MainActor
final class PlaybackController {
    let layer: AVPlayerLayer
    private let player: AVQueuePlayer
    private let looper: AVPlayerLooper

    /// Validates the file asynchronously, then builds the player stack.
    init(url: URL) async throws {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable) else {
            throw PlaybackError.notPlayable(url)
        }
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true                 // muted by default
        queuePlayer.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: queuePlayer, templateItem: AVPlayerItem(asset: asset))
        player = queuePlayer

        let playerLayer = AVPlayerLayer(player: queuePlayer)
        playerLayer.videoGravity = .resizeAspectFill
        layer = playerLayer
    }

    private var reasons: Set<PauseReason> = []

    /// Adds or removes a pause reason; the video plays only while no reason is active.
    func setPaused(_ reason: PauseReason, _ active: Bool) {
        if active { reasons.insert(reason) } else { reasons.remove(reason) }
        if reasons.isEmpty { player.play() } else { player.pause() }
    }

    func setMuted(_ muted: Bool) { player.isMuted = muted }

    /// Stops playback permanently before the controller is discarded.
    func stop() { player.pause() }
}
