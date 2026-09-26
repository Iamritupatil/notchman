import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @Environment(PlaybackManager.self) private var playback

    @Query(HomeView.recentDescriptor) private var recent: [ListeningItem]

    static var recentDescriptor: FetchDescriptor<ListeningItem> {
        var descriptor = FetchDescriptor<ListeningItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 5
        return descriptor
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header

                if recent.isEmpty {
                    EmptyHomeCard()
                } else {
                    recentSection
                }

                ShareTipCard()

                Button {
                    router.sheet = .tryNotchman
                } label: {
                    Label("Try Notchman", systemImage: "text.badge.plus")
                }
                .buttonStyle(.notchmanSecondary)
            }
            .padding(.horizontal, Theme.horizontalPadding)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Color(.systemBackground))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NotchmanMark(size: 40, isListening: playback.isPlaying)
                    .frame(width: 44, height: 36)
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.settings) {
                    Image(systemName: "gearshape")
                        .accessibilityLabel("Settings")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Read less.\nListen instead.")
                .font(.display(38))
                .fixedSize(horizontal: false, vertical: true)
            Text("Turn long messages into something you can listen to.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent")
                    .font(.title3.weight(.bold))
                Spacer()
                NavigationLink("See All", value: Route.history)
                    .font(.subheadline.weight(.semibold))
            }

            VStack(spacing: 0) {
                ForEach(recent) { item in
                    Button {
                        Haptics.tap()
                        env.listen(to: item)
                    } label: {
                        HistoryRow(item: item, isCurrent: playback.nowPlaying?.itemID == item.id)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu { HistoryItemMenu(item: item) }

                    if item.id != recent.last?.id {
                        Divider().padding(.leading, 70)
                    }
                }
            }
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
    }
}

private struct EmptyHomeCard: View {
    var body: some View {
        VStack(spacing: 14) {
            NotchmanMark(size: 110)
                .padding(.top, 8)
            Text("Nothing here yet")
                .font(.headline)
            Text("Long message? Let Notchman read it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

private struct ShareTipCard: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "square.and.arrow.up")
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text("Share → Listen with Notchman")
                    .font(.subheadline.weight(.semibold))
                Text("Works from ChatGPT, Claude, Reddit, Safari, Mail and more.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

#Preview {
    NavigationStack { HomeView() }
        .environment(AppEnvironment.shared)
        .environment(AppEnvironment.shared.router)
        .environment(AppEnvironment.shared.playback)
        .modelContainer(AppEnvironment.shared.modelContainer)
}
