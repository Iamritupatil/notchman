import AppIntents
import Foundation

/// "Listen with Notchman" for Shortcuts, Siri, the Action button, and the
/// Shortcuts share sheet: a supported way to send text or a link from anywhere.
struct ListenWithNotchmanIntent: AppIntent {
    static let title: LocalizedStringResource = "Listen with Notchman"
    static let description = IntentDescription("Reads text or a web page aloud with Notchman.")
    static let openAppWhenRun = true

    @Parameter(title: "Text or Link")
    var text: String

    init() {}

    init(text: String) {
        self.text = text
    }

    func perform() async throws -> some IntentResult {
        let content = try await ContentExtractionPipeline.standard.extract(.sharedText(text))
        await MainActor.run {
            AppEnvironment.shared.ingest(content, action: .read)
        }
        return .result()
    }
}

/// "TL;DR with Notchman": summarizes text or a link and speaks the summary,
/// in the background (the app doesn't open). In Shortcuts, set Text to
/// **Clipboard**, then put the shortcut on Back Tap, the Action Button or
/// Control Center: copy in any app, tap, and it plays in the Dynamic Island.
/// (Shortcuts can read the clipboard for us; iOS hides it from apps that
/// aren't on screen.)
struct TLDRTextIntent: AudioPlaybackIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "TL;DR with Notchman"
    static let description = IntentDescription(
        "Summarizes text or a link (a post or article is fetched first) and speaks the summary, without opening Notchman. Set Text to Clipboard.")
    static let openAppWhenRun = false

    @Parameter(title: "Text or Link")
    var text: String

    init() {}

    init(text: String) {
        self.text = text
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await AppEnvironment.shared.runProvidedAction(.tldr, text: text)
        return .result()
    }
}

/// "Read with Notchman": speaks text, or the post or article behind a link, in full.
struct ReadTextIntent: AudioPlaybackIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Read with Notchman"
    static let description = IntentDescription(
        "Reads text or a link (a post or article is fetched first) aloud in full, without opening Notchman. Set Text to Clipboard.")
    static let openAppWhenRun = false

    @Parameter(title: "Text or Link")
    var text: String

    init() {}

    init(text: String) {
        self.text = text
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await AppEnvironment.shared.runProvidedAction(.read, text: text)
        return .result()
    }
}

/// "TL;DR My Screen": the iPhone version of tapping the notch. Pair it with
/// Shortcuts' "Take Screenshot" action and assign that shortcut to the Action
/// button or Back Tap. It runs in the background: you stay in ChatGPT (or
/// wherever you are) and the TL;DR plays in the Dynamic Island.
struct TLDRScreenIntent: AudioPlaybackIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "TL;DR My Screen"
    static let description = IntentDescription(
        "Finds the main message in a screenshot and plays its TL;DR without leaving the app you're in.")
    static let openAppWhenRun = false

    @Parameter(title: "Screenshot", supportedTypeIdentifiers: ["public.image"])
    var screenshot: IntentFile

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let data = screenshot.data
        try await AppEnvironment.shared.tldrScreenInBackground(imageData: data)
        return .result()
    }
}

/// "Pick & TL;DR My Screen": opens Notchman with glass borders on each message
/// so you can choose which one to hear.
struct PickTLDRScreenIntent: AppIntent {
    static let title: LocalizedStringResource = "Pick & TL;DR My Screen"
    static let description = IntentDescription(
        "Shows the screenshot with a glass border on each message; tap one (or wait 3 seconds) to hear its TL;DR.")
    static let openAppWhenRun = true

    @Parameter(title: "Screenshot", supportedTypeIdentifiers: ["public.image"])
    var screenshot: IntentFile

    init() {}

    func perform() async throws -> some IntentResult {
        let data = screenshot.data
        await MainActor.run {
            AppEnvironment.shared.presentPicker(imageData: data)
        }
        return .result()
    }
}

struct NotchmanShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ListenWithNotchmanIntent(),
                    phrases: ["Listen with \(.applicationName)", "Read this with \(.applicationName)"],
                    shortTitle: "Listen",
                    systemImageName: "headphones")
        AppShortcut(intent: TLDRTextIntent(),
                    phrases: ["TL;DR with \(.applicationName)"],
                    shortTitle: "TL;DR",
                    systemImageName: "text.bubble.fill")
        AppShortcut(intent: ReadTextIntent(),
                    phrases: ["Read with \(.applicationName)"],
                    shortTitle: "Read",
                    systemImageName: "text.book.closed.fill")
        AppShortcut(intent: TogglePlaybackIntent(),
                    phrases: ["Pause \(.applicationName)", "Resume \(.applicationName)"],
                    shortTitle: "Play or Pause",
                    systemImageName: "playpause.fill")
    }
}
