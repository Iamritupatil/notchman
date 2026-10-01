import Foundation

/// The one state every surface shows: the full player, the mini player, the
/// generation screen, the Dynamic Island and the Lock Screen. It's derived in
/// one place (`AppEnvironment.playerState`) from the request being prepared
/// (`ListenSession`) and what's loaded in `PlaybackManager`, so no screen
/// decides on its own whether something is "playing".
enum PlayerState: Equatable, Sendable {
    case idle
    case acquiringContent
    case resolvingURL
    case summarizing
    case generatingVoice
    /// Audio requested, nothing heard yet.
    case buffering
    /// Loaded and ready, not started.
    case ready
    case playing
    case paused
    case finished
    case failed(String)

    /// Combines the request being prepared with playback. A request in
    /// progress wins: its item isn't audible yet.
    static func make(stage: PlaybackPreparationState, sessionActive: Bool,
                     status: PlaybackManager.Status, hasItem: Bool, atStart: Bool) -> PlayerState {
        if sessionActive {
            switch stage {
            case .failed(let failure): return .failed(failure.title)
            case .acquiringContent: return .acquiringContent
            case .resolvingURL: return .resolvingURL
            case .preparingText, .summarizing: return .summarizing
            case .generatingSpeech: return .generatingVoice
            case .buffering: return .buffering
            case .idle, .playing, .paused: break
            }
        }
        guard hasItem else { return .idle }
        switch status {
        case .idle: return .idle
        case .buffering: return .buffering
        case .playing: return .playing
        case .paused: return atStart ? .ready : .paused
        case .finished: return .finished
        }
    }

    /// Something is being made or loaded; no sound yet.
    var isWorking: Bool {
        switch self {
        case .acquiringContent, .resolvingURL, .summarizing, .generatingVoice, .buffering: true
        default: false
        }
    }

    /// Real, seekable audio is loaded: the timeline and skip buttons apply.
    var isSeekable: Bool {
        switch self {
        case .ready, .playing, .paused, .finished: true
        default: false
        }
    }

    /// The status line (separate from the source and title).
    func text(isTLDR: Bool, isLink: Bool = false) -> String {
        switch self {
        case .idle: ""
        case .acquiringContent, .resolvingURL: isLink ? "Getting the post…" : "Getting the message…"
        case .summarizing: isTLDR ? "Finding what matters…" : "Creating your audio…"
        case .generatingVoice: "Creating your audio…"
        case .buffering: "Buffering audio…"
        case .ready: "Ready to play"
        case .playing: "Playing"
        case .paused: "Paused"
        case .finished: "Finished"
        case .failed(let title): title
        }
    }
}
