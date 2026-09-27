import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

private enum Palette {
    static let accent = Color(red: 1.0, green: 0.72, blue: 0.11)
    static let background = Color(red: 0.043, green: 0.043, blue: 0.051)
}

/// The pixel Shiba, crisp at any size.
private struct Shiba: View {
    var body: some View {
        Image("Mascot")
            .interpolation(.medium)
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }
}

/// Dynamic Island + Lock Screen presentation.
///
/// Resting: the Shiba sits in the island; a tap opens `notchman://tldr`, which
/// plays a TL;DR of whatever was copied. Listening: the player, with controls
/// that are `LiveActivityIntent`s (they run in the app's process, so they work
/// without opening the app).
struct NotchmanLiveActivity: Widget {
    static let tldrURL = URL(string: "notchman://tldr")!
    static let readURL = URL(string: "notchman://read")!
    static let playerURL = URL(string: "notchman://player")!

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NotchmanActivityAttributes.self) { context in
            Group {
                if context.state.mode == .resting {
                    RestingLockScreenView()
                } else {
                    LockScreenView(state: context.state)
                }
            }
            .activityBackgroundTint(Palette.background)
            .activitySystemActionForegroundColor(.white)
            .environment(\.colorScheme, .dark)
            .widgetURL(context.state.mode == .resting ? Self.tldrURL : Self.playerURL)
        } dynamicIsland: { context in
            let resting = context.state.mode == .resting
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Shiba().frame(width: 26)
                        Text("Notchman").font(.caption.weight(.semibold))
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !resting {
                        Label(context.state.sourceName, systemImage: context.state.sourceSymbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if resting {
                        RestingPrompt()
                    } else {
                        VStack(spacing: 10) {
                            Text(context.state.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            PlaybackProgress(state: context.state)
                            Controls(isPlaying: context.state.isPlaying)
                        }
                        .padding(.horizontal, 4)
                    }
                }
            } compactLeading: {
                Shiba().frame(width: 22)
            } compactTrailing: {
                if resting {
                    Text("TL;DR")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(Palette.accent)
                } else {
                    RemainingTime(state: context.state)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .frame(maxWidth: 44)
                }
            } minimal: {
                Shiba().frame(width: 20)
            }
            .widgetURL(resting ? Self.tldrURL : Self.playerURL)
            .keylineTint(Palette.accent)
        }
    }
}

/// Expanded island while resting: TL;DR or Read what was copied.
private struct RestingPrompt: View {
    var body: some View {
        HStack(spacing: 10) {
            Link(destination: NotchmanLiveActivity.tldrURL) {
                Label("TL;DR", systemImage: "sparkles")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Palette.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Link(destination: NotchmanLiveActivity.readURL) {
                Label("Read", systemImage: "play.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(.horizontal, 4)
    }
}

private struct RestingLockScreenView: View {
    var body: some View {
        HStack(spacing: 12) {
            Shiba().frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Notchman").font(.headline)
                Text("Copy a long message, then tap here for the TL;DR.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
    }
}

private struct LockScreenView: View {
    let state: NotchmanActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Shiba().frame(width: 24)
                Text("Notchman")
                    .font(.caption.weight(.semibold))
                Text("·").foregroundStyle(.secondary)
                Label(state.sourceName, systemImage: state.sourceSymbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            Text(state.title)
                .font(.headline)
                .lineLimit(1)
            PlaybackProgress(state: state)
            Controls(isPlaying: state.isPlaying)
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
                    .foregroundStyle(.black)
                    .frame(width: 48, height: 48)
                    .background(Palette.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
