import AppIntents
import Foundation

/// Commands that can arrive from outside the app's UI (Live Activity buttons,
/// Shortcuts, Siri). Compiled into both the app and the widget extension.
enum PlaybackCommand: String, Sendable {
    case toggle, play, pause, skipForward, skipBackward, stop
}

/// The app installs a handler at launch. `LiveActivityIntent`s always run in
/// the app's process, so the widget extension never needs one.
@MainActor
enum PlaybackCommandCenter {
    static var handler: ((PlaybackCommand) -> Void)?

    static func send(_ command: PlaybackCommand) {
        handler?(command)
    }
}

struct TogglePlaybackIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static let description = IntentDescription("Pauses or resumes what Notchman is reading.")

    init() {}

    func perform() async throws -> some IntentResult {
        await MainActor.run { PlaybackCommandCenter.send(.toggle) }
        return .result()
    }
}

struct SkipForwardIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip Forward 15 Seconds"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await MainActor.run { PlaybackCommandCenter.send(.skipForward) }
        return .result()
    }
}

struct SkipBackwardIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip Back 15 Seconds"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await MainActor.run { PlaybackCommandCenter.send(.skipBackward) }
        return .result()
    }
}

/// Stops playback and returns the island to rest, without opening Notchman.
struct StopPlaybackIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Notchman"
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        PlaybackCommandCenter.send(.stop)
        return .result()
    }
}

// MARK: - Island actions

/// TL;DR or Read from the Dynamic Island, without opening Notchman.
enum IslandAction: String, Sendable {
    case tldr, read
}

/// The app installs the handler at launch; `LiveActivityIntent`s run in the
/// app's process, so the widget extension never needs one.
@MainActor
enum IslandActionCenter {
    static var handler: ((IslandAction) async -> Void)?
}

/// "TL;DR" in the expanded island: finds the message (your newest screenshot,
/// or what you copied) and plays its TL;DR, all in the background.
struct IslandTLDRIntent: AudioPlaybackIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "TL;DR"
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await IslandActionCenter.handler?(.tldr)
        return .result()
    }
}

/// "Read" in the expanded island: reads the whole message aloud.
struct IslandReadIntent: AudioPlaybackIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Read"
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await IslandActionCenter.handler?(.read)
        return .result()
    }
}
