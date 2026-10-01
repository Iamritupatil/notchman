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
                copiedActions
                PasteSetupRow()

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
        // Room for the floating tab bar and mini player, so the last row scrolls into view.
        .contentMargins(.bottom, TabBarSpace.height, for: .scrollContent)
        .background(Theme.sky.ignoresSafeArea())
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
                    .foregroundStyle(Theme.primaryText)
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

    /// What the island's buttons do, from inside the app.
    private var copiedActions: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.tap()
                env.requestFromTap(.tldr)
            } label: {
                Label("TL;DR copied", systemImage: "sparkles")
            }
            .buttonStyle(.notchmanPrimary)
            Button {
                Haptics.tap()
                env.requestFromTap(.read)
            } label: {
                Label("Read copied", systemImage: "play.fill")
            }
            .buttonStyle(.notchmanSecondary)
        }
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

/// One-time setup, shown until done: let Notchman read what you copy
/// without iOS asking every time.
private struct PasteSetupRow: View {
    @Environment(\.openURL) private var openURL
    @AppStorage("island.pasteSetUp", store: AppGroup.defaults) private var pasteSetUp = false

    var body: some View {
        if !pasteSetUp {
            HStack(spacing: 12) {
                Image(systemName: "doc.on.clipboard")
                    .font(.headline)
                    .foregroundStyle(Theme.amber)
                Text("Allow pasting so Notchman doesn't ask each time.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Set up") {
                    Haptics.tap()
                    pasteSetUp = true
                    // Reading the clipboard once makes "Paste from Other Apps"
                    // appear in Notchman's Settings page.
                    if UIPasteboard.general.hasStrings { _ = UIPasteboard.general.string }
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.amber)
            }
            .padding(14)
            .card()
        }
    }
}
