import ActivityKit
import SwiftUI
import UIKit
import UserNotifications

/// First run: agree to the terms, then learn Notchman by doing it for real.
/// Put the Shiba in the Dynamic Island, allow pasting, copy a sample message
/// and TL;DR it from the island. Each step moves on once it's actually done.
struct OnboardingView: View {
    var onFinish: () -> Void

    enum Step: Int, CaseIterable { case agree, island, paste, tryIt }

    @Environment(AppEnvironment.self) private var env
    @Environment(PlaybackManager.self) private var playback
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboarding.step", store: AppGroup.defaults) private var stepValue = 0

    private var step: Step { Step(rawValue: stepValue) ?? .agree }

    var body: some View {
        ZStack {
            PixelSkyBackground()

            VStack(spacing: 0) {
                header
                Group {
                    switch step {
                    case .agree: AgreeStep { next() }
                    case .island: IslandStep { next() }
                    case .paste: PasteStep { next() }
                    case .tryIt: TryItStep(finish: finish)
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
                .id(step)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? Theme.amber : Theme.primaryText.opacity(0.12))
                    .frame(height: 5)
            }
            if step != .agree {
                Button("Skip") { step == .tryIt ? finish() : next() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.leading, 10)
            }
        }
        .frame(height: 30)
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .animation(.snappy, value: step)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
    }

    private func next() {
        Haptics.tap()
        withAnimation(.smooth) { stepValue = min(step.rawValue + 1, Step.tryIt.rawValue) }
    }

    private func finish() {
        Task {
            // Lets Notchman say when something shared to it is ready.
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            stepValue = 0
            onFinish()
        }
    }
}

// MARK: - Step layout

/// Illustration on top, a title, one short line, then the actions.
private struct StepPage<Illustration: View, Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var illustration: Illustration
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 0) {
            illustration
                .frame(maxHeight: .infinity)
            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 30, weight: .bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
            actions
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
    }
}

// MARK: - 1. Agree

private struct AgreeStep: View {
    var next: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                MascotStage(isActive: true, width: 120)
                    .frame(height: 130)
                    .padding(.top, 16)
                VStack(spacing: 8) {
                    Text("Welcome to Notchman")
                        .font(.system(size: 30, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text("Read less. Listen instead.")
                        .font(.body)
                        .foregroundStyle(Theme.secondaryText)
                }
                AgreementPanel(onAgree: next)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - 2. Dynamic Island

private struct IslandStep: View {
    var next: () -> Void
    @Environment(PlaybackManager.self) private var playback
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled

    var body: some View {
        StepPage(title: "Keep Notchman in your Dynamic Island",
                 subtitle: "It waits at the top of your screen, ready for whatever you copy.") {
            IslandMock()
        } actions: {
            if activitiesEnabled {
                Button {
                    Haptics.success()
                    playback.setRestsInDynamicIsland(true)
                    next()
                } label: { Text("Turn On") }
                .buttonStyle(.notchmanPrimary)
            } else {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: { Text("Allow Live Activities") }
                .buttonStyle(.notchmanPrimary)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled }
        }
    }
}

// MARK: - 3. Pasting

private struct PasteStep: View {
    var next: () -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("island.pasteSetUp", store: AppGroup.defaults) private var pasteSetUp = false
    @State private var tapped = false
    @State private var wentToSettings = false

    var body: some View {
        StepPage(title: "Allow pasting",
                 subtitle: "In Settings, set Paste from Other Apps to Allow, then come back.") {
            SettingsRowMock()
        } actions: {
            Button {
                pasteSetUp = true
                tapped = true
                // Reading the clipboard once makes "Paste from Other Apps"
                // appear on Notchman's page in Settings.
                if UIPasteboard.general.hasStrings { _ = UIPasteboard.general.string }
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: { Text("Open Settings") }
            .buttonStyle(.notchmanPrimary)
        }
        .onChange(of: scenePhase) { _, phase in
            // The paste prompt can blink the app inactive; only a real trip
            // to Settings (the app in the background) counts.
            if phase == .background, tapped { wentToSettings = true }
            if phase == .active, wentToSettings { next() }
        }
    }
}

// MARK: - 4. Try it

private struct TryItStep: View {
    var finish: () -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(PlaybackManager.self) private var playback
    @Environment(\.scenePhase) private var scenePhase
    @State private var copied = false
    @State private var leftApp = false
    @State private var tapped = false
    @State private var heard = false

    private let hasIsland: Bool = {
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        return (window?.safeAreaInsets.top ?? 0) >= 51
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Text(heard ? "That's it!" : "Try it now")
                        .font(.system(size: 30, weight: .bold))
                    Text(heard ? "Copy anything, then tap TL;DR in the island." : "TL;DR this message from the island.")
                        .font(.body)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 12)

                SampleMessage(copied: copied)
                if hasIsland { ExpandedIslandMock() }

                VStack(spacing: 10) {
                    checkRow(1, "Copy the message", done: copied)
                    if hasIsland {
                        checkRow(2, "Go to your Home Screen", done: leftApp || heard)
                        checkRow(3, "Press and hold the Shiba in the island", done: tapped)
                        checkRow(4, "Tap TL;DR", done: tapped)
                    } else {
                        checkRow(2, "Tap TL;DR below", done: tapped)
                    }
                }
                if let failure = env.session.failure, !heard {
                    Text(failure.message)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) { actions.padding(.horizontal, 24).padding(.bottom, 20) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, copied { withAnimation { leftApp = true } }
        }
        .onChange(of: env.session.isActive) { _, active in
            if active { withAnimation { tapped = true } }
        }
        .onChange(of: playback.isActive) { _, playing in
            guard playing, !heard else { return }
            Haptics.success()
            withAnimation(.smooth) { heard = true }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if heard {
            Button(action: finish) { Text("Start Using Notchman") }
                .buttonStyle(.notchmanPrimary)
        } else if !copied {
            Button {
                UIPasteboard.general.string = SampleMessage.text
                Haptics.success()
                withAnimation(.snappy) { copied = true }
            } label: { Label("Copy Message", systemImage: "doc.on.doc") }
            .buttonStyle(.notchmanPrimary)
        } else if tapped && env.session.failure == nil {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 58)
        } else if !hasIsland {
            Button { env.requestFromTap(.tldr) } label: { Label("TL;DR", systemImage: "sparkles") }
                .buttonStyle(.notchmanPrimary)
        } else {
            Label("Copied. Now swipe up to go Home.", systemImage: "arrow.up")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 58)
        }
    }

    private func checkRow(_ number: Int, _ text: String, done: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(done ? Theme.amber : Theme.cardRaised)
                    .overlay(Circle().strokeBorder(done ? Color.clear : Theme.stroke, lineWidth: 1))
                if done {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(width: 30, height: 30)
            Text(text)
                .font(.body.weight(.medium))
                .foregroundStyle(done ? Theme.secondaryText : Theme.primaryText)
                .strikethrough(done, color: Theme.secondaryText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
        .animation(.snappy, value: done)
    }
}

/// A long message to practise on.
private struct SampleMessage: View {
    static let text = """
    Hey! Quick update for Saturday. We're meeting at Cafe Mocha at 11:30, not 11, because Rohan's train gets in late. \
    Bring ₹500 each for lunch; I've already paid the deposit. After lunch we'll walk to the lake if it doesn't rain, \
    otherwise it's bowling at 2. Also, Meera's birthday is on Sunday, so let's split a gift: I'm thinking the blue \
    headphones she wanted, about ₹3,000. Reply by tonight so I can confirm the table!
    """

    let copied: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "message.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.green.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text("Priya")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if copied {
                    Label("Copied", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.amber)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            Text(Self.text)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(4)
        }
        .padding(16)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
                .strokeBorder(copied ? Theme.amber : Theme.stroke, lineWidth: copied ? 2 : 1)
        )
    }
}

// MARK: - Illustrations

/// The Dynamic Island as Notchman leaves it: the tiny Shiba on the left and
/// a faint dot on the right (NotchmanLiveActivity's compact view, 1.6× size).
private struct IslandMock: View {
    @State private var pulse = false

    var body: some View {
        HStack {
            ShibaSprite()
                .frame(width: 26, height: 22)
                .padding(.leading, 18)
            Spacer()
            Circle()
                .fill(Color.white.opacity(0.35))
                .frame(width: 6, height: 6)
                .padding(.trailing, 20)
        }
        .frame(width: 250, height: 60)
        .background(Color.black, in: Capsule())
        .scaleEffect(pulse ? 1.03 : 1)
        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
        .onAppear { pulse = true }
        .accessibilityHidden(true)
    }
}

/// The island after a press and hold, as NotchmanLiveActivity shows it:
/// Notchman at the top left, then TL;DR and Read.
private struct ExpandedIslandMock: View {
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ShibaSprite().frame(width: 22, height: 18)
                Text("Notchman").font(.caption.weight(.semibold))
            }
            .padding(.leading, 4)
            HStack(spacing: 10) {
                Label("TL;DR", systemImage: "sparkles")
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(Theme.accentLight, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(pulse ? 0.9 : 0), lineWidth: 2))
                Label("Read", systemImage: "play.fill")
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(Color.white.opacity(0.14), in: Capsule())
            }
            .font(.subheadline.weight(.bold))
            Text("TL;DR or Read what you copied.")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 40, style: .continuous))
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
        .onAppear { pulse = true }
        .accessibilityHidden(true)
    }
}

/// Notchman's page in iOS Settings, with Paste from Other Apps set to Allow.
private struct SettingsRowMock: View {
    var body: some View {
        VStack(spacing: 0) {
            row("Paste from Other Apps", value: "Allow", highlighted: true)
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
                .strokeBorder(Theme.amber, lineWidth: 2)
        )
        .padding(.horizontal, 32)
        .accessibilityHidden(true)
    }

    private func row(_ title: String, value: String, highlighted: Bool) -> some View {
        HStack {
            Image(systemName: "doc.on.clipboard")
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.gray.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(title).font(.body)
            Spacer()
            Text(value).font(.body.weight(.semibold)).foregroundStyle(Theme.amber)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.tertiaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

#Preview {
    OnboardingView {}
        .environment(AppEnvironment.shared)
        .environment(AppEnvironment.shared.playback)
        .preferredColorScheme(.light)
}
