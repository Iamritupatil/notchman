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
            VStack(alignment: .leading, spacing: Spacing.md) {
                topBar
                hero
                HowToListenCard()
                ShareCard()

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
            .padding(.horizontal, Spacing.page)
            .padding(.bottom, Spacing.lg)
        }
        .scrollIndicators(.hidden)
        .background(Theme.sky.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            ShibaSprite(isActive: playback.isPlaying)
                .frame(width: 38)
            Text("Notchman")
                .font(.brand(24))
                .foregroundStyle(Theme.amber)
            Spacer()
            NavigationLink(value: Route.settings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 44, height: 44)
                    .glass(Circle())
            }
            .accessibilityLabel("Settings")
        }
        .padding(.top, Spacing.sm)
    }

    /// The mascot stays, smaller, so the message gets the width it needs.
    private var hero: some View {
        HStack(spacing: Spacing.md) {
            // The plain mascot: sparkles here would run into the text.
            ShibaSprite(isActive: playback.isPlaying)
                .frame(width: 62)
                .frame(width: 66, height: 60)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Read less. Listen instead.")
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Long message? Notchman gives you the TL;DR out loud.")
                    .font(.metadata)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .card()
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent")
                    .font(.sectionTitle)
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

/// The whole workflow at a glance: three steps and whether it's ready.
private struct HowToListenCard: View {
    @Environment(\.openURL) private var openURL
    @AppStorage("island.pasteSetUp", store: AppGroup.defaults) private var pasteSetUp = false
    @State private var showsGuide = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xxs) {
                step("doc.on.doc", "Copy")
                arrow
                step("hand.tap", "Hold Notchman")
                arrow
                step("sparkles", "TL;DR or Read")
            }

            HStack(spacing: Spacing.xs) {
                Circle()
                    .fill(pasteSetUp ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                if pasteSetUp {
                    Text("Ready").font(.metadata.weight(.medium))
                } else {
                    Button("Allow pasting") { allowPasting() }
                        .font(.metadata.weight(.semibold))
                        .foregroundStyle(Theme.amber)
                }
                Spacer(minLength: 0)
                Button("How it works") { showsGuide = true }
                    .font(.metadata)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(Spacing.md)
        .card()
        .sheet(isPresented: $showsGuide) {
            HowItWorksSheet()
                .presentationDetents([.medium])
                .preferredColorScheme(.light)
        }
    }

    private func step(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: Spacing.xxs) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.amber)
                .frame(height: 26)
            Text(title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }

    private var arrow: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(Theme.tertiaryText)
    }

    private func allowPasting() {
        Haptics.tap()
        pasteSetUp = true
        // Reading the clipboard once makes "Paste from Other Apps" appear in
        // Notchman's Settings page.
        if UIPasteboard.general.hasStrings { _ = UIPasteboard.general.string }
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}

/// A short explanation, only when asked for.
private struct HowItWorksSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.md) {
                row(1, "Copy a message or a link in any app.")
                row(2, "Press and hold the Shiba in the Dynamic Island.")
                row(3, "Tap TL;DR for what matters, or Read for every word.")
                Text("Links to posts and articles are opened for you. In Settings, set Paste from Other Apps to Allow so iOS doesn't ask each time.")
                    .font(.metadata)
                    .foregroundStyle(Theme.secondaryText)
                Spacer(minLength: 0)
            }
            .padding(Spacing.page)
            .background(Theme.sky.ignoresSafeArea())
            .navigationTitle("How it works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    private func row(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 22, height: 22)
                .background(Theme.amber, in: Circle())
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The other way in: the Share sheet.
private struct ShareCard: View {
    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "square.and.arrow.up")
                .font(.headline)
                .foregroundStyle(Theme.amber)
                .frame(width: 40, height: 40)
                .background(Theme.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: CornerRadius.tile, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Or share to Notchman")
                    .font(.headline)
                Text("From ChatGPT, Claude, Reddit, Safari, Mail and more.")
                    .font(.metadata)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .card()
    }
}
