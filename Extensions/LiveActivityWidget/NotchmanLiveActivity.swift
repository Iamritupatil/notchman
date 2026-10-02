import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

private enum Palette {
    /// The new design's sky blue.
    static let accent = Color(red: 0.29, green: 0.65, blue: 1.0)
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
/// Resting: the Shiba sits in the island. Its TL;DR and Read buttons open
/// Notchman's player (`notchman://tldr`, `notchman://read`), which reads what was
/// copied while Notchman is on screen (iOS shows the clipboard only then) and
/// shows each step honestly. A tap anywhere else just opens Notchman. Listening: the player, with controls
/// that are `LiveActivityIntent`s (they run in the app's process, so they work
/// without opening the app).
struct NotchmanLiveActivity: Widget {
    static let tldrURL = URL(string: "notchman://tldr")!
    static let readURL = URL(string: "notchman://read")!
    static let playerURL = URL(string: "notchman://player")!
    static let homeURL = URL(string: "notchman://home")!

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
            .widgetURL(context.state.mode == .resting ? Self.homeURL : Self.playerURL)
        } dynamicIsland: { context in
            let resting = context.state.mode == .resting
            return DynamicIsland {
                // Everything must fit the expanded island's ~160 pt: a header row
                // (artwork · title/source · Stop), then one progress line and
                // one row of 40 pt controls.
                DynamicIslandExpandedRegion(.leading) {
                    if resting {
                        HStack(spacing: 6) {
                            Shiba().frame(width: 22, height: 18)
                            Text("Notchman").font(.caption.weight(.semibold))
                        }
                        .padding(.leading, 4)
                    } else {
                        IslandArtwork()
                            .padding(.leading, 2)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if !resting {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(context.state.title.isEmpty ? "Notchman" : context.state.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Label(context.state.sourceName, systemImage: context.state.sourceSymbol)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !resting {
                        StopButton()
                            .padding(.trailing, 2)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if resting {
                        RestingPrompt(hint: context.state.hint)
                    } else {
                        VStack(spacing: 6) {
                            if context.state.isSeekable {
                                InlineProgress(state: context.state)
                            } else {
                                Text(context.state.status.isEmpty ? "Buffering audio…" : context.state.status)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Controls(isPlaying: context.state.isPlaying)
                        }
                        .padding(.horizontal, 6)
                    }
                }
            } compactLeading: {
                // Tiny and quiet: there if you look for it, so the island
                // stays its normal size and tapping it becomes muscle memory.
                Shiba()
                    .frame(width: 16, height: 14)
                    .padding(.leading, 2)
            } compactTrailing: {
                if resting {
                    // iOS always gives the island a trailing side; a faint dot keeps
                    // it as narrow and quiet as possible, like a music app at rest.
                    Circle()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 4, height: 4)
                        .frame(width: 8, height: 14)
                } else {
                    RemainingTime(state: context.state)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .frame(maxWidth: 44)
                }
            } minimal: {
                Shiba().frame(width: 14, height: 12)
            }
            .widgetURL(resting ? Self.homeURL : Self.playerURL)
            .keylineTint(resting ? Color.white.opacity(0.15) : Palette.accent)
        }
    }
}

/// Expanded island while resting. Each button opens Notchman's player for that
/// action; the player reads what you copied and shows every step.
private struct RestingPrompt: View {
    let hint: String

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Link(destination: NotchmanLiveActivity.tldrURL) {
                    Label("TL;DR", systemImage: "sparkles")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(Palette.accent, in: Capsule())
                }
                Link(destination: NotchmanLiveActivity.readURL) {
                    Label("Read", systemImage: "play.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(Color.white.opacity(0.14), in: Capsule())
                }
            }
            .buttonStyle(.plain)

            Text(hint.isEmpty ? "Opens Notchman and plays the message or link you copied." : hint)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(hint.isEmpty ? 0.45 : 0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 4)
    }
}

private struct RestingLockScreenView: View {
    var body: some View {
        HStack(spacing: 12) {
            Shiba().frame(width: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("Notchman").font(.headline)
                Text("Copy a long message, then press and hold the island and tap TL;DR or Read.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
    }
}

/// The Lock Screen card. Apple's Now Playing card right above it already has
/// the full playback controls, so this one stays light: what's playing, its
/// mode, the shared status (from `PlayerState`), and Stop.
private struct LockScreenView: View {
    let state: NotchmanActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            Artwork()
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(state.isTLDR ? "TL;DR" : "Full read")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Palette.accent.opacity(0.18), in: Capsule())
                    Text(state.sourceName.isEmpty ? "Notchman" : state.sourceName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Text(state.title.isEmpty ? "Notchman" : state.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !state.status.isEmpty {
                    Text(state.status)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            StopButton()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

/// The Shiba as album art.
private struct Artwork: View {
    var body: some View {
        Shiba()
            .padding(4)
            .frame(width: 52, height: 52)
            .background(
                LinearGradient(colors: [Color(red: 0.12, green: 0.27, blue: 0.48), Color(red: 0.06, green: 0.12, blue: 0.24)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 0.5))
    }
}

private enum Clock {
    static func string(_ seconds: TimeInterval) -> String {
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
            Text(Clock.string(state.remaining))
        }
    }
}

private struct Controls: View {
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 40) {
            Button(intent: SkipBackwardIntent()) {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("Back 15 seconds")

            Button(intent: TogglePlaybackIntent()) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Palette.accent, in: Circle())
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            Button(intent: SkipForwardIntent()) {
                Image(systemName: "goforward.15")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("Forward 15 seconds")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
    }
}

/// The Shiba as album art in the expanded island.
private struct IslandArtwork: View {
    var body: some View {
        Shiba()
            .padding(3)
            .frame(width: 40, height: 40)
            .background(Color(red: 0.07, green: 0.16, blue: 0.3), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Stops playback without opening Notchman (runs in the app's process).
private struct StopButton: View {
    var body: some View {
        Button(intent: StopPlaybackIntent()) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.16), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop")
    }
}

/// One line: elapsed · bar · remaining. Timer-based while playing, so the
/// island animates without per-second updates from the app.
private struct InlineProgress: View {
    let state: NotchmanActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if state.isPlaying {
                    Text(timerInterval: state.timelineStart...state.timelineEnd, countsDown: false)
                } else {
                    Text(Clock.string(state.elapsed))
                }
            }
            .frame(width: 36, alignment: .leading)

            Group {
                if state.isPlaying {
                    ProgressView(timerInterval: state.timelineStart...state.timelineEnd, countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                } else {
                    ProgressView(value: state.progress)
                }
            }
            .tint(Palette.accent)

            RemainingTime(state: state)
                .frame(width: 40, alignment: .trailing)
        }
        .font(.caption2.weight(.medium))
        .monospacedDigit()
        .foregroundStyle(.white.opacity(0.55))
    }
}
