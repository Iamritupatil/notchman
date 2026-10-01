import SwiftUI

/// Compact player floating above the tab bar while something is loaded. The
/// shell positions it and reserves its space; it only draws itself.
struct MiniPlayerView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(PlaybackManager.self) private var playback
    @Environment(AppRouter.self) private var router

    var body: some View {
        if let nowPlaying = playback.nowPlaying {
            let state = env.playerState
            HStack(spacing: Spacing.sm) {
                ShibaSprite(isActive: state == .playing)
                    .frame(width: 34)
                    .frame(width: 44, height: 44)
                    .background(Theme.skyLow, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(nowPlaying.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: Spacing.xs) {
                        ModeBadge(isTLDR: nowPlaying.isQuickListen)
                        Text(detail(nowPlaying, state: state))
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: Spacing.xxs)

                Button {
                    Haptics.tap()
                    playback.togglePlayPause()
                } label: {
                    Group {
                        if state.isWorking {
                            ProgressView().tint(Theme.onAccent)
                        } else {
                            Image(systemName: state == .playing ? "pause.fill" : "play.fill")
                                .font(.system(size: 17, weight: .black))
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 42, height: 42)
                    .background(Theme.amberGradient, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(state.isWorking ? "Loading, tap to pause" : state == .playing ? "Pause" : "Play")
            }
            .padding(.leading, Spacing.xs)
            .padding(.trailing, 10)
            .padding(.vertical, Spacing.xs)
            .overlay(alignment: .bottom) {
                if state.isSeekable {
                    ProgressCapsule(value: playback.progress, height: 2)
                        .padding(.horizontal, CornerRadius.floating)
                        .padding(.bottom, 1)
                }
            }
            .glass(RoundedRectangle(cornerRadius: CornerRadius.floating, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { router.sheet = .player }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the player")
        }
    }

    /// Source, then either how long is left or the shared status.
    private func detail(_ nowPlaying: PlaybackManager.NowPlaying, state: PlayerState) -> String {
        switch state {
        case .playing, .paused, .ready:
            "\(nowPlaying.sourceName) · \(TimeFormatter.clock(playback.remaining)) left"
        default:
            "\(nowPlaying.sourceName) · \(state.text(isTLDR: nowPlaying.isQuickListen))"
        }
    }
}
