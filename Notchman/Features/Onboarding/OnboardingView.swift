import SwiftUI
import UserNotifications
import UIKit

struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var page = 0
    @State private var notificationsGranted = false

    private let pageCount = 4

    var body: some View {
        ZStack {
            PixelSkyBackground()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    NotchPage().tag(0)
                    SharePage().tag(1)
                    TLDRPage().tag(2)
                    NotificationsPage(granted: notificationsGranted) {
                        Task { await requestNotifications() }
                    }
                    .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                Button {
                    Haptics.tap()
                    if page < pageCount - 1 {
                        withAnimation(.smooth) { page += 1 }
                    } else {
                        onFinish()
                    }
                } label: {
                    Text("Got it →")
                        .font(.title3.weight(.bold))
                }
                .buttonStyle(.notchmanPrimary)
                .padding(.horizontal, 40)

                PageDots(count: pageCount, current: page)
                    .padding(.top, 34)
                    .padding(.bottom, 20)
            }
        }
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

// MARK: - Page scaffold

private struct OnboardingPage<Illustration: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var illustration: Illustration

    var body: some View {
        VStack(spacing: 0) {
            illustration
                .frame(maxHeight: .infinity)
            VStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 34, weight: .bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 36)
        }
    }
}

// MARK: - Pages

private struct NotchPage: View {
    var body: some View {
        OnboardingPage(title: "Copy it.\nHear it.",
                       subtitle: "Copy any long message or link. Press and hold the Shiba in your Dynamic Island, then tap TL;DR or Read.") {
            Image("OnboardingNotch")
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                .padding(.horizontal, 36)
                .accessibilityHidden(true)
        }
    }
}

private struct SharePage: View {
    var body: some View {
        OnboardingPage(title: "Or just\nshare it.",
                       subtitle: "In ChatGPT, Claude, Reddit, Mail or Safari, tap Share, then Listen with Notchman.") {
            VStack(spacing: 22) {
                HStack(spacing: 16) {
                    shareTarget("Messages", "message.fill", .green)
                    shareTarget("Mail", "envelope.fill", .blue)
                    notchmanTarget
                    shareTarget("Notes", "note.text", .yellow)
                }
                .padding(.vertical, 22)
                .padding(.horizontal, 18)
                .card()

                Label("Also works as a Safari extension", systemImage: "safari")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var notchmanTarget: some View {
        VStack(spacing: 8) {
            ShibaSprite(isActive: true)
                .frame(width: 44)
                .frame(width: 60, height: 60)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Theme.amber, lineWidth: 2.5))
            Text("Listen with\nNotchman")
                .font(.caption2.weight(.semibold))
                .multilineTextAlignment(.center)
        }
    }

    private func shareTarget(_ name: String, _ symbol: String, _ color: Color) -> some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(color.gradient)
                .frame(width: 60, height: 60)
                .overlay { Image(systemName: symbol).font(.title2).foregroundStyle(.white) }
            Text(name)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
                .frame(height: 28, alignment: .top)
        }
        .opacity(0.45)
    }
}

private struct TLDRPage: View {
    var body: some View {
        OnboardingPage(title: "TL;DR, or\nevery word.",
                       subtitle: "TL;DR explains what matters in plain words, without dropping anything important. Read speaks the whole thing.") {
            MascotStage(sign: "TL;DR", width: 190)
        }
    }
}

private struct NotificationsPage: View {
    let granted: Bool
    let request: () -> Void
    @Environment(\.openURL) private var openURL
    @AppStorage("island.pasteSetUp", store: AppGroup.defaults) private var pasteSetUp = false

    var body: some View {
        OnboardingPage(title: "Two quick\nsettings.",
                       subtitle: "Allow pasting so Notchman reads what you copy without asking, and notifications so it can tell you when something is ready.") {
            VStack(spacing: 14) {
                ShibaSprite(isActive: true, image: "MascotTalk")
                    .frame(width: 170)
                    .padding(.bottom, 10)
                Button {
                    pasteSetUp = true
                    // Reading the clipboard once makes "Paste from Other Apps"
                    // appear in Notchman's Settings page.
                    if UIPasteboard.general.hasStrings { _ = UIPasteboard.general.string }
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Label(pasteSetUp ? "Pasting: set in Settings" : "Allow Pasting",
                          systemImage: pasteSetUp ? "checkmark" : "doc.on.clipboard")
                }
                .buttonStyle(.notchmanSecondary)
                Button(action: request) {
                    Label(granted ? "Notifications On" : "Enable Notifications",
                          systemImage: granted ? "checkmark" : "bell.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.notchmanSecondary)
                .disabled(granted)
            }
            .padding(.horizontal, 40)
        }
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 14) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Theme.amber : Theme.primaryText.opacity(0.2))
                    .frame(width: 14, height: 14)
            }
        }
        .animation(.snappy, value: current)
        .accessibilityElement()
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

#Preview {
    OnboardingView {}
        .preferredColorScheme(.light)
}
