import MediaPlayer

/// Lock Screen / Control Center / AirPods integration via MPNowPlayingInfoCenter
/// and MPRemoteCommandCenter.
@MainActor
final class NowPlayingController {
    enum Command {
        case play, pause, toggle, skipForward, skipBackward
        case seek(TimeInterval)
    }

    var onCommand: ((Command) -> Void)?

    private let center = MPRemoteCommandCenter.shared()
    private var isRegistered = false

    func registerCommands(skipInterval: TimeInterval) {
        guard !isRegistered else { return }
        isRegistered = true

        center.playCommand.addTarget { [weak self] _ in self?.dispatch(.play) ?? .commandFailed }
        center.pauseCommand.addTarget { [weak self] _ in self?.dispatch(.pause) ?? .commandFailed }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in self?.dispatch(.toggle) ?? .commandFailed }

        center.skipForwardCommand.preferredIntervals = [NSNumber(value: skipInterval)]
        center.skipForwardCommand.addTarget { [weak self] _ in self?.dispatch(.skipForward) ?? .commandFailed }
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipInterval)]
        center.skipBackwardCommand.addTarget { [weak self] _ in self?.dispatch(.skipBackward) ?? .commandFailed }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            return self?.dispatch(.seek(event.positionTime)) ?? .commandFailed
        }

        // Speech has no meaningful next/previous track.
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
    }

    /// Remote command handlers are invoked on the main thread.
    nonisolated private func dispatch(_ command: Command) -> MPRemoteCommandHandlerStatus {
        MainActor.assumeIsolated {
            onCommand?(command)
        }
        return .success
    }

    func update(title: String, source: String, elapsed: TimeInterval, duration: TimeInterval, isPlaying: Bool) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: source,
            MPMediaItemPropertyAlbumTitle: "Notchman",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
