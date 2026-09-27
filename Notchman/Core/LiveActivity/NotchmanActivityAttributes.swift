import ActivityKit
import Foundation

/// Shared between the app (which starts/updates the activity) and the widget
/// extension (which renders it).
///
/// One activity lives in the Dynamic Island: while nothing plays, the Shiba
/// rests there and a tap TL;DRs whatever you copied; while listening, it shows
/// the player. Everything that changes is in `ContentState`, so the app can
/// switch between the two with an update (allowed in the background) instead
/// of starting a new activity (only allowed in the foreground).
struct NotchmanActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Mode: String, Codable, Hashable {
            /// Waiting in the island. Tap → TL;DR of the copied text.
            case resting
            /// Reading something.
            case listening
        }

        var mode: Mode = .listening
        var isPlaying: Bool
        /// Seconds spoken so far, as of `updatedAt`.
        var elapsed: TimeInterval
        /// Estimated total seconds at the current speed.
        var duration: TimeInterval
        var updatedAt: Date
        var title: String = ""
        var sourceName: String = ""
        var sourceSymbol: String = "text.bubble"

        static var resting: ContentState {
            ContentState(mode: .resting, isPlaying: false, elapsed: 0, duration: 0, updatedAt: .now)
        }

        var progress: Double { duration > 0 ? min(1, max(0, elapsed / duration)) : 0 }
        var remaining: TimeInterval { max(0, duration - elapsed) }

        /// When playback "started" if it had run uninterrupted; lets the widget
        /// use self-updating timer text without per-second updates from the app.
        var timelineStart: Date { updatedAt.addingTimeInterval(-min(elapsed, duration)) }
        var timelineEnd: Date { timelineStart.addingTimeInterval(max(duration, 1)) }
    }

    /// Constant; the activity is Notchman itself, not one item.
    var name: String = "Notchman"
}
