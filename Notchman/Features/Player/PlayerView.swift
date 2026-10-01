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
            Theme.sky.ignoresSafeArea()

            // A Read / TL;DR being prepared shows its real step until sound is
            // heard; a failure shows what happened and what to do next.
            if let failure = env.session.failure {
                ListenFailureView(failure: failure)
            } else if env.session.isActive {
                ListenPreparingView()
            } else if let nowPlaying = playback.nowPlaying {
                player(nowPlaying, item: env.history.item(id: nowPlaying.itemID))
            } else {
                VStack(spacing: 20) {
                    ShibaSprite().frame(width: 120)
                    Text("Nothing playing")
                        .font(.title2.weight(.bold))
                    Text("Share something long to Notchman.")
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .presentationDragIndicator(.hidden)
        .sheet(item: $textItem) { TextViewerView(item: $0).preferredColorScheme(.light) }
        .appAlert()
    }

    // MARK: - Layout

    private func player(_ nowPlaying: PlaybackManager.NowPlaying, item: ListeningItem?) -> some View {
        VStack(spacing: 0) {
            topBar(nowPlaying, item: item)
                .padding(.top, 8)

            // Artwork shrinks on smaller screens so nothing below gets cut.
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height, 320)
                artwork(nowPlaying, side: side)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minHeight: 140)
            .padding(.vertical, 20)

            VStack(alignment: .leading, spacing: 6) {
                Text(nowPlaying.title)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    SourceBadge(type: nowPlaying.sourceType, name: nowPlaying.sourceName)
                    Text("· \(statusTitle)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.secondaryText)
                        .contentTransition(.opacity)
                    Spacer(minLength: 0)
                }
                Text(quote(nowPlaying))
                    .font(.subheadline)
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(2, reservesSpace: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                    .animation(.easeInOut(duration: 0.25), value: playback.currentSentence)
            }

            scrubber
                .padding(.top, 20)

            controls
                .padding(.top, 18)

            if let item {
                actions(item)
                    .padding(.top, 26)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    /// The Shiba as album art: a rounded square with a soft amber glow inside.
    private func artwork(_ nowPlaying: PlaybackManager.NowPlaying, side: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Theme.skyTop, Theme.skyLow],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
            MascotStage(sign: nowPlaying.isQuickListen ? "TL;DR" : nil,
                        isActive: playback.isPlaying, width: side * 0.62)
                .frame(width: side * 0.8, height: side * 0.8)
        }
        .frame(width: side, height: side)
        .scaleEffect(playback.isPlaying ? 1 : 0.94)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: playback.isPlaying)
    }

    private var statusTitle: String {
        switch playback.status {
        case .buffering: "Buffering…"
        case .playing: "Reading"
        case .paused: "Paused"
        case .finished: "All done"
        case .idle: "Ready"
        }
    }

    private func quote(_ nowPlaying: PlaybackManager.NowPlaying) -> String {
        let sentence = playback.currentSentence
        guard !sentence.isEmpty else { return nowPlaying.title }
        var body = sentence
        while let last = body.last, ".!?".contains(last) { body.removeLast() }
        let lead = body.hasPrefix("…") ? "" : "…"
        let trail = body.hasSuffix("…") ? "" : "…"
        return "“\(lead)\(body)\(trail)”"
    }

    // MARK: - Top bar

    private func topBar(_ nowPlaying: PlaybackManager.NowPlaying, item: ListeningItem?) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 44, height: 44)
                    .background(Theme.cardRaised, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close player")

            Spacer()

            Text(nowPlaying.isQuickListen ? "TL;DR" : "FULL READ")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Theme.secondaryText)

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
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 44, height: 44)
                    .background(Theme.cardRaised, in: Circle())
            }
            .accessibilityLabel("More")
        }
    }

    // MARK: - Scrubber

    private var scrubber: some View {
        let shown = scrubProgress ?? playback.progress
        return VStack(spacing: 6) {
            AmberScrubber(value: shown) { value in
                scrubProgress = value
            } onCommit: { value in
                playback.seek(toProgress: value)
                scrubProgress = nil
            }

            HStack {
                Text(TimeFormatter.clock(shown * playback.duration))
                Spacer()
                Text("-" + TimeFormatter.clock(max(0, playback.duration - shown * playback.duration)))
            }
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: - Controls

    /// All three controls share one size and sit on one centre line.
    private static let controlSize: CGFloat = 64

    private var controls: some View {
        HStack(alignment: .center, spacing: 40) {
            skipButton(seconds: -PlaybackManager.skipInterval, symbol: "gobackward.15")

            Button {
                Haptics.tap()
                playback.togglePlayPause()
            } label: {
                Group {
                    if playback.isBuffering {
                        // Honest: no sound yet, so no pause icon.
                        ProgressView().tint(Theme.onAccent)
                    } else {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Theme.onAccent)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .frame(width: Self.controlSize, height: Self.controlSize)
                .background(Theme.amber, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playback.isBuffering ? "Buffering, tap to pause" : playback.isPlaying ? "Pause" : "Play")

            skipButton(seconds: PlaybackManager.skipInterval, symbol: "goforward.15")
        }
        .frame(maxWidth: .infinity)
    }

    private func skipButton(seconds: TimeInterval, symbol: String) -> some View {
        Button {
            Haptics.tap()
            playback.skip(by: seconds)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .frame(width: Self.controlSize, height: Self.controlSize)
                .background(Theme.cardRaised, in: Circle())
                .overlay(Circle().stroke(Theme.stroke, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(seconds < 0 ? "Back 15 seconds" : "Forward 15 seconds")
    }

    // MARK: - Actions

    private func actions(_ item: ListeningItem) -> some View {
        HStack(spacing: 12) {
            pill("Text", systemImage: "doc.text") { textItem = item }

            if router.isPreparingQuickListen {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.cardRaised, in: Capsule())
            } else if item.isQuickListen {
                pill("Full read", systemImage: "text.alignleft") { env.readFull(item) }
            } else {
                pill("TL;DR", systemImage: "bolt.fill") { env.quickListen(to: item) }
            }
        }
    }

    private func pill(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(Theme.primaryText)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.cardRaised, in: Capsule())
                .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
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
            let knob: CGFloat = isDragging ? 20 : 14
            let width = proxy.size.width
            let track = max(1, width - knob)
            let x = track * min(max(value, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.primaryText.opacity(0.12)).frame(height: 5)
                Capsule().fill(Theme.amber).frame(width: x + knob / 2, height: 5)
                Circle()
                    .fill(.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: Theme.primaryText.opacity(0.3), radius: 3)
                    .offset(x: x)
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        onChange(min(max((drag.location.x - knob / 2) / track, 0), 1))
                    }
                    .onEnded { drag in
                        isDragging = false
                        onCommit(min(max((drag.location.x - knob / 2) / track, 0), 1))
                    }
            )
            .animation(.snappy(duration: 0.15), value: isDragging)
        }
        .frame(height: 24)
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
