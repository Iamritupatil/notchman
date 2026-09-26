import ActivityKit
import Foundation
import os

/// Starts, updates and ends the playback Live Activity (Dynamic Island + Lock Screen).
///
/// Updates are sent only on state changes (play, pause, seek, speed); the widget
/// animates elapsed time itself using timer-based text.
@MainActor
final class LiveActivityManager {
    private var activity: Activity<NotchmanActivityAttributes>?
    private var lastState: NotchmanActivityAttributes.ContentState?
    private let log = Logger(subsystem: "com.notchman", category: "LiveActivity")

    var isEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start(itemID: UUID, title: String, sourceName: String, sourceSymbol: String,
               state: NotchmanActivityAttributes.ContentState) {
        if let activity, activity.attributes.itemID == itemID.uuidString, activity.activityState == .active {
            update(state)
            return
        }
        endAll()
        guard isEnabled else { return }

        let attributes = NotchmanActivityAttributes(
            itemID: itemID.uuidString, title: title, sourceName: sourceName, sourceSymbol: sourceSymbol)
        do {
            activity = try Activity.request(attributes: attributes,
                                            content: ActivityContent(state: state, staleDate: nil),
                                            pushType: nil)
            lastState = state
        } catch {
            log.error("Live Activity request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func update(_ state: NotchmanActivityAttributes.ContentState) {
        guard let activity, state != lastState else { return }
        lastState = state
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    /// Ends the current activity immediately (playback finished or stopped).
    func end() {
        guard let activity else { return }
        let finalState = lastState
        self.activity = nil
        lastState = nil
        Task {
            await activity.end(finalState.map { ActivityContent(state: $0, staleDate: nil) },
                               dismissalPolicy: .immediate)
        }
    }

    /// Also cleans up activities left over from a previous launch.
    func endAll() {
        end()
        for stale in Activity<NotchmanActivityAttributes>.activities {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
