import AppIntents
import SwiftUI
import WidgetKit

/// One press → TL;DR of whatever you copied. Runs from the Action button,
/// Control Center or the Lock Screen (iOS 18+), with no Shortcuts to build.
/// iOS doesn't let apps read other apps' screens or react to taps on the
/// Dynamic Island, so "copy, then press" is the fastest supported gesture.
@available(iOS 18.0, *)
struct TLDRCopiedTextIntent: AppIntent {
    static let title: LocalizedStringResource = "TL;DR What I Copied"
    static let description = IntentDescription("Opens Notchman and plays a TL;DR of the text or link you copied.")

    init() {}

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "notchman://tldr")!))
    }
}

@available(iOS 18.0, *)
struct TLDRControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.notchman.tldr") {
            ControlWidgetButton(action: TLDRCopiedTextIntent()) {
                Label("TL;DR", systemImage: "text.bubble.fill")
            }
        }
        .displayName("Notchman TL;DR")
        .description("TL;DR of whatever you copied.")
    }
}
