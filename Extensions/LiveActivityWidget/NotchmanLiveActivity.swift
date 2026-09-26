import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

private enum Palette {
    static let accent = Color(red: 1.0, green: 0.36, blue: 0.23)
}

/// Dynamic Island + Lock Screen presentation of the current listen.
///
/// Controls use `LiveActivityIntent`s, which iOS runs in the app's process, so
/// pause/resume/skip work without opening the app. Tapping elsewhere opens
/// the player via the `notchman://player` URL.
struct NotchmanLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NotchmanActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activitySystemActionForegroundColor(.primary)
                .widgetURL(URL(string: "notchman://player"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text("Notchman").font(.caption.weight(.semibold))
                    } icon: {
                        Image(systemName: "headphones").foregroundStyle(Palette.accent)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Label(context.attributes.sourceName, systemImage: context.attributes.sourceSymbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        Text(context.attributes.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        PlaybackProgress(state: context.state)
                        Controls(isPlaying: context.state.isPlaying)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.isPlaying ? "headphones" : "pause.fill")
                    .foregroundStyle(Palette.accent)
            } compactTrailing: {
                RemainingTime(state: context.state)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "headphones")
                    .foregroundStyle(Palette.accent)
            }
            .widgetURL(URL(string: "notchman://player"))
            .keylineTint(Palette.accent)
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<NotchmanActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "headphones")
                    .foregroundStyle(Palette.accent)
                Text("Notchman")
                    .font(.caption.weight(.semibold))
                Text("·").foregroundStyle(.secondary)
                Label(context.attributes.sourceName, systemImage: context.attributes.sourceSymbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            Text(context.attributes.title)
                .font(.headline)
                .lineLimit(1)
            PlaybackProgress(state: context.state)
            Controls(isPlaying: context.state.isPlaying)
        }
        .padding(16)
    }
}

/// Progress bar plus "1:40 / 4:20". While playing, both animate on their own
/// from the timeline in the content state; while paused they're static.
private struct PlaybackProgress: View {
    let state: NotchmanActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 4) {
            if state.isPlaying {
                ProgressView(timerInterval: state.timelineStart...state.timelineEnd, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(Palette.accent)
            } else {
                ProgressView(value: state.progress)
                    .tint(Palette.accent)
            }
            HStack(spacing: 0) {
                if state.isPlaying {
                    Text(timerInterval: state.timelineStart...state.timelineEnd, countsDown: false)
                        .frame(maxWidth: 60, alignment: .leading)
                } else {
                    Text(Self.clock(state.elapsed))
                }
                Text(" / " + Self.clock(state.duration))
                Spacer()
            }
            .font(.caption2.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct RemainingTime: View {
    let state: NotchmanActivityAttributes.ContentState

    var body: some View {
        if state.isPlaying {
            Text(timerInterval: state.updatedAt...max(state.updatedAt, state.timelineEnd), countsDown: true)
                .multilineTextAlignment(.trailing)
        } else {
            Text(PlaybackProgress.clock(state.remaining))
        }
    }
}

private struct Controls: View {
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 36) {
            Button(intent: SkipBackwardIntent()) {
                Image(systemName: "gobackward.15")
                    .font(.title3.weight(.semibold))
            }
            .accessibilityLabel("Back 15 seconds")

            Button(intent: TogglePlaybackIntent()) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .frame(width: 48, height: 48)
                    .background(Palette.accent.opacity(0.2), in: Circle())
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            Button(intent: SkipForwardIntent()) {
                Image(systemName: "goforward.15")
                    .font(.title3.weight(.semibold))
            }
            .accessibilityLabel("Forward 15 seconds")
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}
