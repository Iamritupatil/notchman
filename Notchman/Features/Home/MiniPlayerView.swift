import SwiftUI

/// Compact player shown above the tab bar while something is loaded.
struct MiniPlayerView: View {
    @Environment(PlaybackManager.self) private var playback
    @Environment(AppRouter.self) private var router

    var body: some View {
        if let nowPlaying = playback.nowPlaying {
            HStack(spacing: 12) {
                ShibaSprite(pose: .head, isActive: playback.isPlaying)
                    .frame(width: 34)
                    .frame(width: 44, height: 44)
                    .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(nowPlaying.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if nowPlaying.isQuickListen { TLDRBadge() }
                    }
                    Text(subtitle(nowPlaying))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .monospacedDigit()
                }

                Spacer(minLength: 4)

                Button {
                    Haptics.tap()
                    playback.togglePlayPause()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 42, height: 42)
                        .background(PixelShape(step: 3, steps: 2).fill(Theme.amberGradient))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
            }
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .padding(.vertical, 8)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .bottom) {
                ProgressCapsule(value: playback.progress, height: 2)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 1)
            }
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.stroke))
            .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
            .contentShape(Rectangle())
            .onTapGesture { router.sheet = .player }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the player")
            .padding(.horizontal, 16)
        }
    }

    private func subtitle(_ nowPlaying: PlaybackManager.NowPlaying) -> String {
        switch playback.status {
        case .finished: "\(nowPlaying.sourceName) · Finished"
        default: "\(nowPlaying.sourceName) · \(TimeFormatter.clock(playback.remaining)) left"
        }
    }
}
