import SwiftData
import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @Environment(PlaybackManager.self) private var playback

    @Query(HomeView.recentDescriptor) private var recent: [ListeningItem]

    static var recentDescriptor: FetchDescriptor<ListeningItem> {
        var descriptor = FetchDescriptor<ListeningItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 4
        return descriptor
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                topBar
                hero
                OnePressCard()
                ShareTipCard()

                Button {
                    Haptics.tap()
                    env.tldrCopiedText()
                } label: {
                    Label("TL;DR what I copied", systemImage: "doc.on.clipboard")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)

                if !recent.isEmpty {
                    recentSection
                }

                #if DEBUG
                Button {
                    router.sheet = .tryNotchman
                } label: {
                    Label("Try Notchman (developer)", systemImage: "text.badge.plus")
                }
                .buttonStyle(.notchmanSecondary)
                #endif
            }
            .padding(.horizontal, Theme.horizontalPadding)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            ShibaSprite(isActive: playback.isPlaying)
                .frame(width: 38)
            Text("Notchman")
                .font(.pixel(24))
                .foregroundStyle(Theme.amber)
            Spacer()
            NavigationLink(value: Route.settings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Theme.cardRaised, in: Circle())
            }
            .accessibilityLabel("Settings")
        }
        .padding(.top, 12)
    }

    private var hero: some View {
        HStack(spacing: 16) {
            MascotStage(isActive: playback.isPlaying, width: 84)
                .frame(width: 92, height: 92)
            VStack(alignment: .leading, spacing: 6) {
                Text("Read less.\nListen instead.")
                    .font(.title2.weight(.bold))
                Text("Long message? Notchman gives you the TL;DR out loud.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .card()
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Button("See All") {
                    withAnimation(.snappy) { router.tab = .history }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.amber)
            }
            .padding(.horizontal, 6)

            VStack(spacing: 0) {
                ForEach(recent) { item in
                    Button {
                        Haptics.tap()
                        env.listen(to: item)
                    } label: {
                        HistoryRow(item: item, isCurrent: playback.nowPlaying?.itemID == item.id && playback.isPlaying)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu { HistoryItemMenu(item: item) }

                    if item.id != recent.last?.id {
                        Divider().overlay(Theme.stroke).padding(.leading, 88)
                    }
                }
            }
            .card()
        }
    }
}

/// The main way to use Notchman on iPhone: one press on any screen.
///
/// iOS doesn't let an app capture another app's screen, so the press runs a
/// tiny shortcut (Take Screenshot → TL;DR My Screen). Notchman then shows the
/// screen with glass borders on each message, picks the main one after 3
/// seconds, and plays its TL;DR. On Apple Intelligence iPhones, a normal
/// screenshot also offers "TL;DR with Notchman" in Visual Intelligence.
private struct OnePressCard: View {
    @State private var showsGuide = false
    @Environment(\.openURL) private var openURL

    private static var shortcutURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "NotchmanShortcutURL") as? String,
              value.hasPrefix("https://") else { return nil }
        return URL(string: value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "button.vertical.right.press.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.amber)
                    .frame(width: 52, height: 52)
                    .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("One press, any app")
                        .font(.headline)
                    Text("Press the Action Button on a long message. The TL;DR plays right there, no switching apps.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 0)
            }

            Button {
                Haptics.tap()
                if let url = Self.shortcutURL {
                    openURL(url)
                }
                showsGuide = true
            } label: {
                Text(Self.shortcutURL == nil ? "Set Up One-Press TL;DR" : "Add the Shortcut")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.notchmanPrimary)
        }
        .padding(16)
        .card()
        .sheet(isPresented: $showsGuide) {
            OnePressGuide(hasLink: Self.shortcutURL != nil)
                .presentationDetents([.medium, .large])
                .preferredColorScheme(.dark)
        }
    }
}

private struct OnePressGuide: View {
    let hasLink: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Action Button (iPhone 15 Pro and newer)", steps: hasLink ? [
                        "Tap Add Shortcut in the Shortcuts app that just opened.",
                        "Settings → Action Button → swipe to Shortcut → choose \"TL;DR My Screen\".",
                        "On any long message, press the Action Button.",
                    ] : [
                        "Open Shortcuts → + → add \"Take Screenshot\", then \"TL;DR My Screen\" (Notchman). Name it TL;DR My Screen.",
                        "Settings → Action Button → swipe to Shortcut → choose it.",
                        "On any long message, press the Action Button.",
                    ])
                    section("Other iPhones: Back Tap", steps: [
                        "Settings → Accessibility → Touch → Back Tap → Double Tap → \"TL;DR My Screen\".",
                        "Double-tap the back of your iPhone on any long message.",
                    ])
                    section("No setup (Apple Intelligence iPhones)", steps: [
                        "Take a screenshot (side button + volume up) and tap the preview.",
                        "Tap the Visual Intelligence button, highlight the message, choose TL;DR with Notchman.",
                    ])
                    Text("You stay in the app you're in: Notchman finds the main message and plays its TL;DR in the Dynamic Island. Want to choose the message yourself? Use \"Pick & TL;DR My Screen\" in the shortcut instead, and Notchman shows glass borders to tap. The screenshot is read on your iPhone and never uploaded.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("One-Press TL;DR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    private func section(_ title: String, steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, text in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(width: 22, height: 22)
                        .background(Theme.amber, in: Circle())
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct ShareTipCard: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "square.and.arrow.up")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.amber)
                .frame(width: 52, height: 52)
                .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Share → Listen with Notchman")
                    .font(.headline)
                Text("Works from ChatGPT, Claude, Reddit, Safari, Mail and more.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .card()
    }
}
