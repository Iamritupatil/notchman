import SwiftUI

/// Full-screen player from the Notchman design: mascot, live quote, amber
/// scrubber, pixel play button, and full-text / TL;DR actions.
struct PlayerView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @Environment(PlaybackManager.self) private var playback
    @Environment(\.dismiss) private var dismiss

    @State private var scrubProgress: Double?
    @State private var textItem: ListeningItem?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if let nowPlaying = playback.nowPlaying {
                player(nowPlaying, item: env.history.item(id: nowPlaying.itemID))
            } else {
                VStack(spacing: 20) {
                    ShibaSprite(pose: .head).frame(width: 120)
                    Text("Nothing playing")
                        .font(.title2.weight(.bold))
                    Text("Share something long to Notchman.")
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .presentationDragIndicator(.hidden)
        .sheet(item: $textItem) { TextViewerView(item: $0).preferredColorScheme(.dark) }
        .appAlert()
    }

    // MARK: - Layout

    private func player(_ nowPlaying: PlaybackManager.NowPlaying, item: ListeningItem?) -> some View {
        VStack(spacing: 0) {
            topBar(nowPlaying, item: item)
                .padding(.top, 12)

            Spacer(minLength: 8)

            MascotStage(pose: .paws, sign: nowPlaying.isQuickListen ? "TL;DR" : "FULL",
                        isActive: playback.isPlaying, width: 150)
                .frame(height: 250)

            Spacer(minLength: 8)

            VStack(spacing: 12) {
                SourceBadge(type: nowPlaying.sourceType, name: nowPlaying.sourceName)

                Text(statusTitle)
                    .font(.system(size: 38, weight: .bold))
                    .contentTransition(.opacity)

                Text(quote(nowPlaying))
                    .font(.title3)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
                    .animation(.easeInOut(duration: 0.25), value: playback.currentSentence)
                    .padding(.horizontal, 12)
            }

            scrubber
                .padding(.top, 26)

            controls
                .padding(.top, 24)

            Spacer(minLength: 16)

            if let item {
                actions(item)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private var statusTitle: String {
        switch playback.status {
        case .playing: "Reading"
        case .paused: "Paused"
        case .finished: "All done"
        case .idle: "Ready"
        }
    }

    private func quote(_ nowPlaying: PlaybackManager.NowPlaying) -> String {
        let sentence = playback.currentSentence
        guard !sentence.isEmpty else { return nowPlaying.title }
        return "“\(sentence.hasPrefix("…") ? "" : "…")\(sentence)\(sentence.hasSuffix("…") ? "" : "…")”"
    }

    // MARK: - Top bar

    private func topBar(_ nowPlaying: PlaybackManager.NowPlaying, item: ListeningItem?) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(CircleIconButtonStyle())
            .accessibilityLabel("Close player")

            Spacer()

            Text(nowPlaying.isQuickListen ? "TL;DR" : "Full read")
                .font(.headline)

            Spacer()

            Menu {
                Picker("Speed", selection: Binding(get: { playback.speed }, set: { playback.setSpeed($0) })) {
                    ForEach(PlaybackSpeed.options, id: \.self) { speed in
                        Text(PlaybackSpeed.label(speed)).tag(speed)
                    }
                }
                .pickerStyle(.menu)

                if let item {
                    Button {
                        env.history.toggleSaved(item)
                    } label: {
                        Label(item.isSaved ? "Remove from Saved" : "Save", systemImage: item.isSaved ? "bookmark.fill" : "bookmark")
                    }
                    if nowPlaying.isQuickListen {
                        Button { env.readFull(item) } label: { Label("Read the full message", systemImage: "text.alignleft") }
                    } else {
                        Button { env.listen(to: item, fromStart: true) } label: {
                            Label("Start over", systemImage: "arrow.counterclockwise")
                        }
                    }
                    ShareLink(item: item.originalText) { Label("Share text", systemImage: "square.and.arrow.up") }
                }

                Button(role: .destructive) {
                    playback.stop()
                    dismiss()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Theme.cardRaised, in: Circle())
            }
            .accessibilityLabel("More")
        }
    }

    // MARK: - Scrubber

    private var scrubber: some View {
        let shown = scrubProgress ?? playback.progress
        return VStack(spacing: 10) {
            AmberScrubber(value: shown) { value in
                scrubProgress = value
            } onCommit: { value in
                playback.seek(toProgress: value)
                scrubProgress = nil
            }

            HStack {
                Text(TimeFormatter.clock(shown * playback.duration))
                Spacer()
                Text(TimeFormatter.clock(playback.duration))
            }
            .font(.subheadline.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(alignment: .top, spacing: 0) {
            skipButton(seconds: -PlaybackManager.skipInterval, symbol: "gobackward.15", label: "-15")
                .frame(maxWidth: .infinity)

            Button {
                Haptics.tap()
                playback.togglePlayPause()
            } label: {
                ZStack {
                    PixelShape(step: 7, steps: 4)
                        .fill(Color(red: 0.62, green: 0.36, blue: 0.02))
                        .offset(y: 6)
                    PixelShape(step: 7, steps: 4)
                        .fill(Theme.amberGradient)
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 40, weight: .black))
                        .foregroundStyle(Color(red: 0.14, green: 0.08, blue: 0.02))
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 112, height: 112)
                .shadow(color: Theme.amber.opacity(0.35), radius: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")

            skipButton(seconds: PlaybackManager.skipInterval, symbol: "goforward.15", label: "+15")
                .frame(maxWidth: .infinity)
        }
    }

    private func skipButton(seconds: TimeInterval, symbol: String, label: String) -> some View {
        Button {
            Haptics.tap()
            playback.skip(by: seconds)
        } label: {
            VStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .medium))
                    .frame(width: 92, height: 92)
                    .background(Theme.cardRaised, in: Circle())
                Text(label)
                    .font(.title3)
                    .foregroundStyle(Theme.secondaryText)
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(seconds < 0 ? "Back 15 seconds" : "Forward 15 seconds")
    }

    // MARK: - Actions

    private func actions(_ item: ListeningItem) -> some View {
        HStack(spacing: 14) {
            Button {
                textItem = item
            } label: {
                Label("View full text", systemImage: "doc.text")
                    .font(.body.weight(.medium))
            }
            .buttonStyle(.notchmanSecondary)

            Button {
                Haptics.tap()
                if item.isQuickListen {
                    env.listen(to: item, fromStart: true)
                } else {
                    env.quickListen(to: item)
                }
            } label: {
                Group {
                    if router.isPreparingQuickListen {
                        ProgressView()
                    } else {
                        Label(item.isQuickListen ? "Replay TL;DR" : "Play TL;DR",
                              systemImage: item.isQuickListen ? "arrow.counterclockwise" : "bolt.fill")
                            .font(.body.weight(.medium))
                    }
                }
            }
            .buttonStyle(.notchmanSecondary)
            .disabled(router.isPreparingQuickListen)
        }
    }
}

/// Amber progress track with a white knob and pixel tick marks underneath.
private struct AmberScrubber: View {
    let value: Double
    let onChange: (Double) -> Void
    let onCommit: (Double) -> Void

    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let x = width * min(max(value, 0), 1)
            VStack(spacing: 12) {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14)).frame(height: 8)
                    Capsule().fill(Theme.amber).frame(width: max(8, x), height: 8)
                    Circle()
                        .fill(.white)
                        .frame(width: isDragging ? 30 : 24, height: isDragging ? 30 : 24)
                        .shadow(color: .black.opacity(0.4), radius: 4)
                        .offset(x: x - (isDragging ? 15 : 12))
                }
                .frame(height: 30)

                HStack {
                    ForEach(0..<9, id: \.self) { _ in
                        Rectangle().fill(Color.white.opacity(0.2)).frame(width: 4, height: 4)
                        Spacer(minLength: 0)
                    }
                    Rectangle().fill(Color.white.opacity(0.2)).frame(width: 4, height: 4)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        onChange(min(max(drag.location.x / width, 0), 1))
                    }
                    .onEnded { drag in
                        isDragging = false
                        onCommit(min(max(drag.location.x / width, 0), 1))
                    }
            )
            .animation(.snappy(duration: 0.15), value: isDragging)
        }
        .frame(height: 46)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Int(value * 100)) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onCommit(min(1, value + 0.05))
            case .decrement: onCommit(max(0, value - 0.05))
            @unknown default: break
            }
        }
    }
}
