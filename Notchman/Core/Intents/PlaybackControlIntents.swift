import AppIntents
import Foundation
import UIKit

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

/// What the user asked for. It travels with the request through every step
/// (clipboard, fetching a link, summarizing, voice), so fetched content is
/// never silently switched to the other action.
enum NotchmanAction: String, Codable, Sendable {
    /// Summarize first, then speak the summary.
    case tldr
    /// Speak the original (cleaned) content.
    case read
}

/// The app installs the handler at launch; `LiveActivityIntent`s run in the
/// app's process, so the widget extension never needs one. `copied` is what
/// the island's own process read from the clipboard (nil if iOS gave nothing),
/// and `probe` says what it saw, for the island's status line.
@MainActor
enum IslandActionCenter {
    static var handler: ((NotchmanAction, _ copied: String?, _ probe: String?) async -> Void)?
}

/// What a process can see on the clipboard right now.
enum ClipboardProbe {
    static func read() -> (text: String?, summary: String) {
        let pasteboard = UIPasteboard.general
        let text = (pasteboard.string ?? pasteboard.url?.absoluteString)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = text.map { $0.isEmpty ? "empty" : "\($0.count) chars" } ?? "nothing"
        return (text?.isEmpty == false ? text : nil, summary)
    }
}

/// The island's TL;DR / Read buttons. These run in the island's own process
/// (the widget extension) the moment they're pressed, read the clipboard there,
/// and hand it to Notchman, which works in the background.
struct IslandPasteTLDRIntent: AppIntent {
    static let title: LocalizedStringResource = "TL;DR"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult & OpensIntent {
        let probe = ClipboardProbe.read()
        return .result(opensIntent: IslandTLDRIntent(copied: probe.text, probe: "Island saw \(probe.summary)"))
    }
}

struct IslandPasteReadIntent: AppIntent {
    static let title: LocalizedStringResource = "Read"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult & OpensIntent {
        let probe = ClipboardProbe.read()
        return .result(opensIntent: IslandReadIntent(copied: probe.text, probe: "Island saw \(probe.summary)"))
    }
}

/// TL;DR of what you copied (text or a link), in the background.
struct IslandTLDRIntent: AudioPlaybackIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "TL;DR"
    static let isDiscoverable = false

    @Parameter(title: "Copied")
    var copied: String?

    @Parameter(title: "Probe")
    var probe: String?

    init() {}

    init(copied: String?, probe: String?) {
        self.copied = copied
        self.probe = probe
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await IslandActionCenter.handler?(.tldr, copied, probe)
        return .result()
    }
}

/// Read of what you copied, in full, in the background.
struct IslandReadIntent: AudioPlaybackIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Read"
    static let isDiscoverable = false

    @Parameter(title: "Copied")
    var copied: String?

    @Parameter(title: "Probe")
    var probe: String?

    init() {}

    init(copied: String?, probe: String?) {
        self.copied = copied
        self.probe = probe
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await IslandActionCenter.handler?(.read, copied, probe)
        return .result()
    }
}
