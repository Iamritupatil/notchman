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
                ShareCard()

                if !recent.isEmpty {
                    recentSection
                }

                #if DEBUG
                // Not on screenshots: they show the app as people get it.
                if DemoMode.screen == nil {
                    Button {
                        router.sheet = .tryNotchman
                    } label: {
                        Label("Try Notchman (developer)", systemImage: "text.badge.plus")
                    }
                    .buttonStyle(.notchmanSecondary)
                }
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
            Text("Read less. Listen instead.")
                .font(.title3.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
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
                Text("Share to Notchman")
                    .font(.headline)
                Text("From any app.")
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
