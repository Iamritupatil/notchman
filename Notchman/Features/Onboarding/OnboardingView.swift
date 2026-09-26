import SwiftUI
import UserNotifications

struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var page = 0
    @State private var notificationsGranted = false

    private let pageCount = 3

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                WelcomePage().tag(0)
                ListenPage().tag(1)
                SharePage().tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.smooth, value: page)

            PageDots(count: pageCount, current: page)
                .padding(.bottom, 24)

            VStack(spacing: 10) {
                if page == pageCount - 1 {
                    Button {
                        Task { await requestNotifications() }
                    } label: {
                        Label(notificationsGranted ? "Notifications On" : "Enable Notifications",
                              systemImage: notificationsGranted ? "checkmark" : "bell")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.notchmanSecondary)
                    .disabled(notificationsGranted)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Button("Continue") {
                    Haptics.tap()
                    if page < pageCount - 1 {
                        withAnimation(.smooth) { page += 1 }
                    } else {
                        onFinish()
                    }
                }
                .buttonStyle(.notchmanPrimary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .animation(.smooth, value: page)
        }
        .background(Color(.systemBackground))
        .task { await refreshNotificationStatus() }
    }

    private func requestNotifications() async {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
        withAnimation { notificationsGranted = granted }
        if granted { Haptics.success() }
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsGranted = settings.authorizationStatus == .authorized
    }
}

// MARK: - Pages

private struct OnboardingPage<Illustration: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var illustration: Illustration

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            illustration
                .frame(height: 260)
            Spacer()
            VStack(spacing: 12) {
                Text(title)
                    .font(.display(34))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }
}

private struct WelcomePage: View {
    var body: some View {
        OnboardingPage(title: "Long message?\nJust listen.",
                       subtitle: "Turn long messages into audio.") {
            VStack(spacing: 18) {
                NotchmanMark(size: 190, isListening: true)
                Text("Notchman")
                    .font(.system(.title2, design: .rounded).weight(.heavy))
            }
        }
    }
}

private struct ListenPage: View {
    @State private var animate = false

    var body: some View {
        OnboardingPage(title: "Read less.\nListen instead.",
                       subtitle: "ChatGPT answers, Reddit threads, emails and articles, read aloud while you do something else.") {
            HStack(spacing: 22) {
                // A long message…
                VStack(alignment: .leading, spacing: 9) {
                    ForEach([1.0, 0.85, 0.95, 0.6, 0.9, 0.75, 0.4], id: \.self) { width in
                        Capsule()
                            .fill(Color(.tertiaryLabel))
                            .frame(width: 96 * width, height: 8)
                    }
                }
                .padding(18)
                .background(Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .opacity(animate ? 0.55 : 1)

                Image(systemName: "arrow.right")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .offset(x: animate ? 6 : -2)

                // …becomes audio.
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.14))
                        .frame(width: 118, height: 118)
                        .scaleEffect(animate ? 1.08 : 0.95)
                    Image(systemName: "headphones")
                        .font(.system(size: 50, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .symbolEffect(.bounce, value: animate)
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { animate = true }
            }
        }
    }
}

private struct SharePage: View {
    var body: some View {
        OnboardingPage(title: "Share → Notchman",
                       subtitle: "Whenever you find something long, tap Share, then Listen with Notchman.") {
            VStack(spacing: 18) {
                HStack(spacing: 18) {
                    shareTarget(name: "Messages", symbol: "message.fill", color: .green)
                    shareTarget(name: "Mail", symbol: "envelope.fill", color: .blue)
                    notchmanTarget
                    shareTarget(name: "Notes", symbol: "note.text", color: .yellow)
                }
                .padding(.vertical, 22)
                .padding(.horizontal, 20)
                .background(Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 26, style: .continuous))

                Label("Also works as a Safari extension", systemImage: "safari")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var notchmanTarget: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
                .frame(width: 58, height: 58)
                .overlay { NotchmanMark(size: 42) }
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 2.5))
            Text("Listen with\nNotchman")
                .font(.caption2.weight(.semibold))
                .multilineTextAlignment(.center)
        }
    }

    private func shareTarget(name: String, symbol: String, color: Color) -> some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.gradient)
                .frame(width: 58, height: 58)
                .overlay {
                    Image(systemName: symbol)
                        .font(.title2)
                        .foregroundStyle(.white)
                }
            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(height: 28, alignment: .top)
        }
        .opacity(0.55)
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Color.primary : Color(.tertiaryLabel))
                    .frame(width: index == current ? 20 : 7, height: 7)
            }
        }
        .animation(.snappy, value: current)
        .accessibilityElement()
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

#Preview {
    OnboardingView {}
}
