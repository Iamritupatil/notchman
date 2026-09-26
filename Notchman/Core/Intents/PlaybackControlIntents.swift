import AppIntents
import Foundation

/// Commands that can arrive from outside the app's UI (Live Activity buttons,
/// Shortcuts, Siri). Compiled into both the app and the widget extension.
enum PlaybackCommand: String, Sendable {
    case toggle, play, pause, skipForward, skipBackward
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
