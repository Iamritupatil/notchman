import ActivityKit
import Foundation

/// Shared between the app (which starts/updates the activity) and the widget
/// extension (which renders it).
struct NotchmanActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var isPlaying: Bool
        /// Seconds spoken so far, as of `updatedAt`.
        var elapsed: TimeInterval
        /// Estimated total seconds at the current speed.
        var duration: TimeInterval
        var updatedAt: Date

        var progress: Double { duration > 0 ? min(1, max(0, elapsed / duration)) : 0 }
        var remaining: TimeInterval { max(0, duration - elapsed) }

        /// When playback "started" if it had run uninterrupted; lets the widget
        /// use self-updating timer text without per-second updates from the app.
        var timelineStart: Date { updatedAt.addingTimeInterval(-min(elapsed, duration)) }
        var timelineEnd: Date { timelineStart.addingTimeInterval(max(duration, 1)) }
    }

    var itemID: String
    var title: String
    var sourceName: String
    var sourceSymbol: String
}
