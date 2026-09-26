import SwiftUI

/// Persistent bar shown above the home screen while something is loaded.
struct MiniPlayerView: View {
    @Environment(PlaybackManager.self) private var playback
    @Environment(AppRouter.self) private var router

    var body: some View {
        if let nowPlaying = playback.nowPlaying {
            HStack(spacing: 12) {
                WaveformView(isAnimating: playback.isPlaying, color: nowPlaying.sourceType.tint)
                    .frame(width: 22, height: 18)
                    .frame(width: 40, height: 40)
                    .background(nowPlaying.sourceType.tint.opacity(0.13),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(nowPlaying.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(subtitle(nowPlaying))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer(minLength: 4)

                Button {
                    Haptics.tap()
                    playback.togglePlayPause()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .bottom) {
                ProgressCapsule(value: playback.progress, height: 2)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 1)
            }
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            .contentShape(Rectangle())
            .onTapGesture { router.sheet = .player }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the player")
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }

    private func subtitle(_ nowPlaying: PlaybackManager.NowPlaying) -> String {
        switch playback.status {
        case .finished: "\(nowPlaying.sourceName) · Finished"
        default: "\(nowPlaying.sourceName) · \(TimeFormatter.clock(playback.remaining)) left"
        }
    }
}
