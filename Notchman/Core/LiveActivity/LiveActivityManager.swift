import ActivityKit
import Foundation
import os

/// Owns Notchman's single Live Activity (Dynamic Island + Lock Screen).
///
/// - With "Keep Notchman in the Dynamic Island" on, the Shiba rests in the
///   island whenever the app has been opened; tapping it TL;DRs the copied text.
/// - While listening, the same activity shows the player and its controls.
///
/// Updates are sent only on state changes; the widget animates elapsed time
/// itself with timer-based text.
@MainActor
final class LiveActivityManager {
    private var activity: Activity<NotchmanActivityAttributes>?
    private var lastState: NotchmanActivityAttributes.ContentState?
    private var meta: (title: String, sourceName: String, sourceSymbol: String)?
    private let log = Logger(subsystem: "com.notchman", category: "LiveActivity")

    var isEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Whether the Shiba stays in the Dynamic Island between listens.
    var keepsResting: Bool {
        AppGroup.defaults.object(forKey: SettingsKey.restInDynamicIsland) as? Bool ?? true
    }

    /// Shows the resting Shiba if nothing else is showing. Starting an activity
    /// needs the app in the foreground, so call this when the app becomes active.
    func rest() {
        guard keepsResting, meta == nil else { return }
        adoptExisting()
        if activity?.activityState == .active {
            send(.resting)
        } else {
            request(.resting)
        }
    }

    func start(itemID: UUID, title: String, sourceName: String, sourceSymbol: String,
               state: NotchmanActivityAttributes.ContentState) {
        meta = (title, sourceName, sourceSymbol)
        adoptExisting()
        if activity?.activityState == .active {
            send(state)
        } else {
            request(state)
        }
    }

    /// Shows a short status line in the resting island (only while nothing plays).
    func showHint(_ hint: String) {
        guard meta == nil else { return }
        adoptExisting()
        guard activity?.activityState == .active else { return }
        send(.resting(hint: hint))
    }

    func update(_ state: NotchmanActivityAttributes.ContentState) {
        guard meta != nil else { return }
        send(state)
    }

    /// Playback finished or stopped: go back to resting, or leave the island.
    func end() {
        meta = nil
        guard let activity else { return }
        if keepsResting, activity.activityState == .active {
            send(.resting)
            return
        }
        self.activity = nil
        lastState = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// Removes the activity entirely (e.g. the setting was turned off).
    func endAll() {
        meta = nil
        activity = nil
        lastState = nil
        for existing in Activity<NotchmanActivityAttributes>.activities {
            Task { await existing.end(nil, dismissalPolicy: .immediate) }
        }
    }

    // MARK: - Internals

    /// Picks up an activity still running from a previous launch, and ends any extras.
    private func adoptExisting() {
        guard activity == nil || activity?.activityState != .active else { return }
        let running = Activity<NotchmanActivityAttributes>.activities.filter { $0.activityState == .active }
        activity = running.first
        for extra in running.dropFirst() {
            Task { await extra.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private func filled(_ state: NotchmanActivityAttributes.ContentState) -> NotchmanActivityAttributes.ContentState {
        guard state.mode == .listening, let meta else { return state }
        var state = state
        state.title = meta.title
        state.sourceName = meta.sourceName
        state.sourceSymbol = meta.sourceSymbol
        return state
    }

    private func send(_ state: NotchmanActivityAttributes.ContentState) {
        let state = filled(state)
        guard let activity, state != lastState else { return }
        lastState = state
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    private func request(_ state: NotchmanActivityAttributes.ContentState) {
        guard isEnabled else { return }
        let state = filled(state)
        do {
            activity = try Activity.request(attributes: NotchmanActivityAttributes(),
                                            content: ActivityContent(state: state, staleDate: nil),
                                            pushType: nil)
            lastState = state
        } catch {
            log.error("Live Activity request failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
