import SwiftUI
import UserNotifications

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
                    Text("GOT IT →")
                }
                .buttonStyle(.pixel)
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
                    .font(.system(size: 38, weight: .bold))
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
        OnboardingPage(title: "Tap your notch.\nStart listening.",
                       subtitle: "Share any long message to Notchman. It sums it up and reads it out loud, right from your notch.") {
            PhoneNotchIllustration()
        }
    }
}

private struct SharePage: View {
    var body: some View {
        OnboardingPage(title: "Share it.\nHear it.",
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
            ShibaSprite(pose: .head, isActive: true)
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
        OnboardingPage(title: "TL;DR, or the\nwhole thing.",
                       subtitle: "Hear the short version in under a minute, or let Notchman read every word.") {
            MascotStage(pose: .paws, sign: "TL;DR", width: 150)
        }
    }
}

private struct NotificationsPage: View {
    let granted: Bool
    let request: () -> Void

    var body: some View {
        OnboardingPage(title: "Ready when\nyou are.",
                       subtitle: "Allow notifications so Notchman can tell you when something you shared is ready to play.") {
            VStack(spacing: 30) {
                ZStack {
                    ExcitementMarks().frame(width: 260, height: 90)
                    ShibaSprite(pose: .collar, isActive: true).frame(width: 150)
                }
                Button(action: request) {
                    Label(granted ? "Notifications On" : "Enable Notifications",
                          systemImage: granted ? "checkmark" : "bell.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.notchmanSecondary)
                .disabled(granted)
                .padding(.horizontal, 40)
            }
        }
    }
}

/// The top of an iPhone with the Shiba peeking over its edge, and a pixel
/// arrow pointing up at the notch.
private struct PhoneNotchIllustration: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let edgeY = proxy.size.height * 0.46
            ZStack(alignment: .top) {
                PixelSparkles(count: 10)
                    .frame(width: width, height: edgeY)

                // Shiba behind the phone edge; paws rest on top of it.
                ZStack {
                    ExcitementMarks()
                        .frame(width: 230, height: 70)
                    ShibaSprite(pose: .paws, isActive: true)
                        .frame(width: 136)
                }
                .offset(y: edgeY - 108)

                // Phone body.
                RoundedRectangle(cornerRadius: 56, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.11), Theme.background],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: 56, style: .continuous)
                            .stroke(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.2)],
                                                   startPoint: .top, endPoint: .bottom), lineWidth: 5)
                    )
                    .frame(width: width + 40, height: proxy.size.height)
                    .offset(y: edgeY)

                // Notch with camera.
                UnevenRoundedRectangle(bottomLeadingRadius: 22, bottomTrailingRadius: 22, style: .continuous)
                    .fill(Color.black)
                    .frame(width: width * 0.42, height: 44)
                    .overlay(alignment: .trailing) {
                        Circle()
                            .fill(Color(red: 0.12, green: 0.2, blue: 0.4))
                            .frame(width: 14, height: 14)
                            .padding(.trailing, 22)
                    }
                    .offset(y: edgeY + 2)

                PixelUpArrow()
                    .frame(width: 44, height: 100)
                    .offset(y: edgeY + 70)
            }
            .frame(width: width)
        }
        .clipped()
    }
}

/// Amber pixel arrow with dashes, pointing at the notch.
private struct PixelUpArrow: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { context in
            let bob = CGFloat(sin(context.date.timeIntervalSinceReferenceDate * 3)) * 4
            Canvas { gfx, size in
                let unit = size.width / 11
                let color = GraphicsContext.Shading.color(Theme.amber)
                // Arrow head rows: widths 1, 3, 5, 7, 9, 11 (in units).
                for row in 0..<6 {
                    let w = CGFloat(row * 2 + 1)
                    gfx.fill(Path(CGRect(x: (11 - w) / 2 * unit, y: CGFloat(row) * unit, width: w * unit, height: unit)),
                             with: color)
                }
                // Stem.
                gfx.fill(Path(CGRect(x: 4 * unit, y: 6 * unit, width: 3 * unit, height: 5 * unit)), with: color)
                // Dashes.
                for i in 0..<3 {
                    gfx.fill(Path(CGRect(x: 3.5 * unit, y: (12 + CGFloat(i) * 2) * unit, width: 4 * unit, height: unit)),
                             with: color)
                }
            }
            .offset(y: bob)
        }
        .accessibilityHidden(true)
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 14) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Theme.amber : Color.white.opacity(0.25))
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
        .preferredColorScheme(.dark)
}
