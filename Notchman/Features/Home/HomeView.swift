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

/// The main way to use Notchman on iPhone: copy in any app, one press.
///
/// iOS shows the clipboard only to the app on screen, so from inside another
/// app the press runs a one-step shortcut ("TL;DR with Notchman", Text set to
/// Clipboard): Shortcuts reads the clipboard and Notchman plays in the
/// Dynamic Island without opening.
private struct OnePressCard: View {
    @State private var showsGuide = false
    @Environment(\.openURL) private var openURL

    private func openSettings() {
        // Reading the clipboard once makes "Paste from Other Apps" appear in
        // Notchman's Settings page.
        if UIPasteboard.general.hasStrings { _ = UIPasteboard.general.string }
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    @AppStorage("island.pasteSetUp", store: AppGroup.defaults) private var pasteSetUp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "capsule.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.amber)
                    .frame(width: 52, height: 52)
                    .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Copy → Back Tap → TL;DR")
                        .font(.headline)
                    Text("Copy a message (any Copy button) or a link, then double-tap the back of your iPhone. It plays in the Dynamic Island and you never leave the app.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 0)
            }

            if pasteSetUp {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Ready")
                        .font(.subheadline.weight(.medium))
                    Spacer(minLength: 0)
                    Button("Paste setting") { openSettings() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                    Button("How it works") { showsGuide = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.amber)
                }
            } else {
                Text("One-time setup (about a minute): iOS hides the clipboard from apps in the background, so a one-step shortcut hands it to Notchman.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                Button {
                    Haptics.tap()
                    pasteSetUp = true
                    showsGuide = true
                } label: {
                    Text("Set it up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.notchmanPrimary)
            }
        }
        .padding(16)
        .card()
        .sheet(isPresented: $showsGuide) {
            OnePressGuide()
                .presentationDetents([.medium, .large])
                .preferredColorScheme(.dark)
        }
    }
}

private struct OnePressGuide: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Back Tap (any iPhone)", steps: [
                        "Open Shortcuts → + → search Notchman → add \"TL;DR with Notchman\".",
                        "Tap Text in that action and choose Clipboard. Name the shortcut Notchman TL;DR.",
                        "Settings → Accessibility → Touch → Back Tap → Double Tap → Notchman TL;DR. For Triple Tap, make a second one with \"Read with Notchman\".",
                        "In any app, copy a message or a link, then double-tap the back of your iPhone.",
                    ])
                    section("Action Button or Control Center", steps: [
                        "Settings → Action Button → Shortcut → Notchman TL;DR.",
                        "Or open Control Center → + → Add a Control → Shortcut → Notchman TL;DR.",
                    ])
                    section("Dynamic Island", steps: [
                        "Press and hold the Shiba, then tap TL;DR or Read.",
                        "iOS only shows the clipboard to the app on screen, so while you're in another app the island can't see what you copied, and it says so. Back Tap works from anywhere.",
                    ])
                    Text("Links are fetched for you: LinkedIn and X posts, Reddit threads, articles and blogs. TL;DR speaks a summary that keeps every important point; Read speaks the whole thing. If iOS asks whether Shortcuts may paste, choose Allow (Settings → Apps → Shortcuts → Paste from Other Apps).")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Copy → TL;DR")
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
