import SwiftUI

/// Full-screen, Apple Podcasts–style player presented as a sheet.
struct PlayerView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @Environment(PlaybackManager.self) private var playback

    @State private var scrubProgress: Double?
    @State private var textItem: ListeningItem?

    var body: some View {
        Group {
            if let nowPlaying = playback.nowPlaying {
                player(nowPlaying, item: env.history.item(id: nowPlaying.itemID))
            } else {
                ContentUnavailableView("Nothing playing", systemImage: "headphones",
                                       description: Text("Share something long to Notchman."))
            }
        }
        .presentationDragIndicator(.visible)
        .sheet(item: $textItem) { TextViewerView(item: $0) }
        .appAlert()
    }

    @ViewBuilder
    private func player(_ nowPlaying: PlaybackManager.NowPlaying, item: ListeningItem?) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)

            artwork(nowPlaying)

            Spacer(minLength: 20)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    SourceBadge(type: nowPlaying.sourceType, name: nowPlaying.sourceName)
                    if nowPlaying.isQuickListen { QuickBadge() }
                    Spacer()
                }
                Text(nowPlaying.title)
                    .font(.title2.weight(.bold))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            scrubber
                .padding(.top, 22)

            controls
                .padding(.top, 18)

            SpeedPicker(selection: playback.speed) { speed in
                Haptics.tap()
                playback.setSpeed(speed)
            }
            .padding(.top, 24)

            Spacer(minLength: 20)

            if let item {
                actions(item)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private func artwork(_ nowPlaying: PlaybackManager.NowPlaying) -> some View {
        RoundedRectangle(cornerRadius: 32, style: .continuous)
            .fill(nowPlaying.sourceType.tint.opacity(0.12))
            .overlay {
                NotchmanMark(size: 150, isListening: playback.isPlaying)
            }
            .overlay(alignment: .bottomTrailing) {
                WaveformView(isAnimating: playback.isPlaying, color: nowPlaying.sourceType.tint)
                    .frame(width: 30, height: 24)
                    .padding(20)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1.25, contentMode: .fit)
            .scaleEffect(playback.isPlaying ? 1 : 0.94)
            .animation(.spring(response: 0.45, dampingFraction: 0.75), value: playback.isPlaying)
    }

    private var scrubber: some View {
        let shown = scrubProgress ?? playback.progress
        return VStack(spacing: 6) {
            Slider(value: Binding(get: { shown }, set: { scrubProgress = $0 }), in: 0...1, onEditingChanged: { editing in
                if !editing, let target = scrubProgress {
                    playback.seek(toProgress: target)
                    scrubProgress = nil
                }
            })
            .tint(Color.primary)
            .accessibilityLabel("Playback position")

            HStack {
                Text(TimeFormatter.clock(shown * playback.duration))
                Spacer()
                Text("-" + TimeFormatter.clock((1 - shown) * playback.duration))
            }
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 44) {
            Button {
                Haptics.tap()
                playback.skip(by: -PlaybackManager.skipInterval)
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 30, weight: .medium))
            }
            .accessibilityLabel("Back 15 seconds")

            Button {
                Haptics.tap()
                playback.togglePlayPause()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(Color(.systemBackground))
                    .frame(width: 78, height: 78)
                    .background(Color.primary, in: Circle())
            }
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")

            Button {
                Haptics.tap()
                playback.skip(by: PlaybackManager.skipInterval)
            } label: {
                Image(systemName: "goforward.15")
                    .font(.system(size: 30, weight: .medium))
            }
            .accessibilityLabel("Forward 15 seconds")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
    }

    private func actions(_ item: ListeningItem) -> some View {
        HStack(spacing: 0) {
            PlayerAction(title: "Read Full", systemImage: "text.alignleft") {
                env.readFull(item)
            }
            PlayerAction(title: "Quick Listen", systemImage: "bolt.fill",
                         isLoading: router.isPreparingQuickListen) {
                env.quickListen(to: item)
            }
            PlayerAction(title: "View Text", systemImage: "doc.plaintext") {
                textItem = item
            }
            PlayerAction(title: item.isSaved ? "Saved" : "Save",
                         systemImage: item.isSaved ? "bookmark.fill" : "bookmark") {
                env.history.toggleSaved(item)
            }
        }
    }
}

private struct PlayerAction: View {
    let title: String
    let systemImage: String
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    if isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: 19, weight: .medium))
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .frame(width: 50, height: 50)
                .background(Color(.secondarySystemFill), in: Circle())

                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

struct SpeedPicker: View {
    let selection: Double
    let onSelect: (Double) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PlaybackSpeed.options, id: \.self) { speed in
                let isSelected = abs(speed - selection) < 0.01
                Button {
                    onSelect(speed)
                } label: {
                    Text(PlaybackSpeed.label(speed))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(isSelected ? Color(.systemBackground) : Color.primary)
                        .background(isSelected ? Color.primary : Color(.secondarySystemFill), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Speaking speed")
    }
}
