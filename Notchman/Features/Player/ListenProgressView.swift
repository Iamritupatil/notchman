import SwiftUI

/// The player while a Read or TL;DR is being prepared: the real step it's on
/// (never a fake "playing"), with a live waveform so it's clearly working.
struct ListenPreparingView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let session = env.session
        VStack(spacing: 0) {
            header(session.action)
                .padding(.top, 8)

            Spacer(minLength: 16)

            MascotStage(sign: session.action == .tldr ? "TL;DR" : nil, isActive: true, width: 150)
                .frame(height: 170)

            VStack(spacing: 8) {
                Text(session.stage.text(for: session.action))
                    .font(.title3.weight(.bold))
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: session.stage)
                if let detail = session.stage.detail(for: session.action) {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .transition(.opacity)
                }
                if let source = session.sourceName {
                    Text(source)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.top, 28)

            LiveWaveform()
                .frame(height: 44)
                .padding(.top, 26)
                .padding(.horizontal, 40)

            steps(session)
                .padding(.top, 30)

            Spacer(minLength: 16)

            Button("Cancel") {
                env.session.cancel()
                dismiss()
            }
            .buttonStyle(.notchmanSecondary)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .accessibilityElement(children: .contain)
    }

    private func header(_ action: NotchmanAction) -> some View {
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
            Text(action == .tldr ? "TL;DR" : "FULL READ")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
    }

    /// The whole journey, with the current step highlighted.
    private func steps(_ session: ListenSession) -> some View {
        let all = Self.steps(for: session.action)
        let current = Self.stepIndex(of: session.stage, action: session.action)
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(all.enumerated()), id: \.offset) { index, title in
                HStack(spacing: 10) {
                    Group {
                        if index < current {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.amber)
                        } else if index == current {
                            ProgressView().controlSize(.small).tint(Theme.amber)
                        } else {
                            Image(systemName: "circle").foregroundStyle(Theme.tertiaryText)
                        }
                    }
                    .frame(width: 20)
                    Text(title)
                        .font(.subheadline.weight(index == current ? .semibold : .regular))
                        .foregroundStyle(index <= current ? Theme.primaryText : Theme.tertiaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }

    static func steps(for action: NotchmanAction) -> [String] {
        action == .tldr
            ? ["Getting content", "Understanding message", "Creating TL;DR", "Generating voice", "Playing"]
            : ["Getting content", "Preparing text", "Generating voice", "Playing"]
    }

    static func stepIndex(of stage: PlaybackPreparationState, action: NotchmanAction) -> Int {
        switch (stage, action) {
        case (.acquiringContent, _), (.resolvingURL, _): 0
        case (.preparingText, _): 1
        case (.summarizing, .tldr): 2
        case (.summarizing, .read): 1
        case (.generatingSpeech, .tldr), (.buffering, .tldr): 3
        case (.generatingSpeech, .read), (.buffering, .read): 2
        default: steps(for: action).count - 1
        }
    }
}

/// Why it stopped, and the one thing to do next (Retry, Play again, Use anyway).
struct ListenFailureView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let failure: ListenFailure

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ShibaSprite().frame(width: 110)
            Text(failure.title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text(failure.message)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            Spacer()
            VStack(spacing: 10) {
                if let title = primaryTitle {
                    Button(title) {
                        Haptics.tap()
                        env.session.recovery?()
                    }
                    .buttonStyle(.notchmanPrimary)
                }
                Button("Close") {
                    env.session.cancel()
                    dismiss()
                }
                .buttonStyle(.notchmanSecondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private var primaryTitle: String? {
        guard env.session.recovery != nil else { return nil }
        switch failure.recovery {
        case .retry: return "Retry"
        case .playAgain: return "Play it again"
        case .useAnyway: return "Use it anyway"
        case .none: return nil
        }
    }
}

/// Bars that move while work is happening.
struct LiveWaveform: View {
    var bars = 24

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                let spacing: CGFloat = 4
                let width = max(2, (proxy.size.width - spacing * CGFloat(bars - 1)) / CGFloat(bars))
                HStack(alignment: .center, spacing: spacing) {
                    ForEach(0..<bars, id: \.self) { index in
                        let phase = time * 3.2 + Double(index) * 0.45
                        let level = 0.25 + 0.75 * abs(sin(phase) * cos(phase * 0.37 + Double(index)))
                        Capsule()
                            .fill(Theme.amber.opacity(0.5 + 0.5 * level))
                            .frame(width: width, height: max(4, proxy.size.height * level))
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .accessibilityHidden(true)
    }
}
