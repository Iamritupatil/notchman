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

/// "TL;DR My Screen": the iPhone version of tapping the notch. Pair it with
/// Shortcuts' "Take Screenshot" action and assign that shortcut to Back Tap
/// (Settings → Accessibility → Touch → Back Tap) or the Action button.
struct TLDRScreenIntent: AppIntent {
    static let title: LocalizedStringResource = "TL;DR My Screen"
    static let description = IntentDescription(
        "Finds the long message in a screenshot, lets you pick it within 3 seconds, and plays its TL;DR.")
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
        AppShortcut(intent: TogglePlaybackIntent(),
                    phrases: ["Pause \(.applicationName)", "Resume \(.applicationName)"],
                    shortTitle: "Play or Pause",
                    systemImageName: "playpause.fill")
    }
}
