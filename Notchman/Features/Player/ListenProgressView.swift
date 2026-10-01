import SwiftUI

/// The player while a Read or TL;DR is being prepared: the real step it's on
/// (never a fake "playing"), in one compact block that feels fast and alive.
struct ListenPreparingView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let session = env.session
        let state = env.playerState
        VStack(spacing: 0) {
            header(session.action)

            Spacer(minLength: Spacing.md)

            VStack(spacing: Spacing.md) {
                // The mascot stays clean; the mode is in the header.
                MascotStage(isActive: true, width: 130)
                    .frame(height: 104)

                VStack(spacing: Spacing.xxs) {
                    if let title = session.title ?? session.sourceName {
                        Text(title)
                            .font(.headline)
                            .lineLimit(2)
                    }
                    Text(state.text(isTLDR: session.action == .tldr, isLink: session.isLink))
                        .font(.title3.weight(.bold))
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.25), value: state)
                }
                .multilineTextAlignment(.center)

                LiveWaveform()
                    .frame(height: 36)
                    .padding(.horizontal, Spacing.xl)

                steps(session)
                    .padding(Spacing.md)
                    .card()
            }

            Spacer(minLength: Spacing.md)

            Button("Cancel") {
                env.session.cancel()
                dismiss()
            }
            .buttonStyle(.notchmanSecondary)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.md)
        .accessibilityElement(children: .contain)
    }

    private func header(_ action: NotchmanAction) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 38, height: 38)
                    .glass(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close player")
            Spacer()
            ModeBadge(isTLDR: action == .tldr)
            Spacer()
            Color.clear.frame(width: 38, height: 38)
        }
        .frame(height: 44)
        .padding(.top, Spacing.xs)
    }

    /// A few human steps, not the internal pipeline.
    private func steps(_ session: ListenSession) -> some View {
        let all = Self.steps(for: session.action, isLink: session.isLink)
        let current = Self.stepIndex(of: session.stage, action: session.action)
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(Array(all.enumerated()), id: \.offset) { index, title in
                HStack(spacing: Spacing.sm) {
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
                        .foregroundStyle(index <= current ? Theme.primaryText : Theme.secondaryText)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    static func steps(for action: NotchmanAction, isLink: Bool = false) -> [String] {
        let first = isLink ? "Getting the post" : "Getting the message"
        return action == .tldr
            ? [first, "Finding what matters", "Creating your audio"]
            : [first, "Creating your audio"]
    }

    static func stepIndex(of stage: PlaybackPreparationState, action: NotchmanAction) -> Int {
        switch (stage, action) {
        case (.acquiringContent, _), (.resolvingURL, _): 0
        case (.preparingText, .tldr), (.summarizing, .tldr): 1
        case (.generatingSpeech, .tldr), (.buffering, .tldr): 2
        case (_, .read): 1
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
