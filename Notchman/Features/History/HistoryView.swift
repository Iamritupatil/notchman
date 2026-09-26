import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @Environment(PlaybackManager.self) private var playback
    @Environment(PremiumStore.self) private var premium
    @Query(sort: \ListeningItem.createdAt, order: .reverse) private var items: [ListeningItem]
    @State private var showsSavedOnly = false

    private var visibleItems: [ListeningItem] {
        showsSavedOnly ? items.filter(\.isSaved) : items
    }

    /// Items grouped under "Today", "Yesterday", "This Week", "Earlier", in order.
    private var sections: [(title: String, items: [ListeningItem])] {
        var result: [(title: String, items: [ListeningItem])] = []
        for item in visibleItems {
            let title = RelativeDay.section(for: item.createdAt)
            if let index = result.firstIndex(where: { $0.title == title }) {
                result[index].items.append(item)
            } else {
                result.append((title: title, items: [item]))
            }
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                StatusBanner(isReading: playback.isPlaying)

                if items.count > 0 {
                    Picker("Show", selection: $showsSavedOnly) {
                        Text("All").tag(false)
                        Text("Saved").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                if visibleItems.isEmpty {
                    emptyState
                } else {
                    ForEach(sections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.title)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(Theme.secondaryText)
                                .padding(.leading, 6)
                            VStack(spacing: 0) {
                                ForEach(section.items) { item in
                                    row(item)
                                    if item.id != section.items.last?.id {
                                        Divider().overlay(Theme.stroke).padding(.leading, 88)
                                    }
                                }
                            }
                            .card()
                        }
                    }
                }

                if !premium.isPremium {
                    Button {
                        router.sheet = .paywall
                    } label: {
                        Text("Go Premium ✨")
                            .font(.title3.weight(.semibold))
                    }
                    .buttonStyle(.notchmanPrimary)
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, Theme.horizontalPadding)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack {
            Text("History")
                .font(.system(size: 40, weight: .bold))
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

    private func row(_ item: ListeningItem) -> some View {
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
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: showsSavedOnly ? "bookmark" : "headphones")
                .font(.largeTitle)
                .foregroundStyle(Theme.amber)
            Text(showsSavedOnly ? "No saved listens" : "No history yet")
                .font(.headline)
            Text(showsSavedOnly
                 ? "Long-press anything in History to save it."
                 : "Share a long message to Notchman to start listening.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .card()
    }
}

/// "Notchman is ready 🐾" banner with the peeking Shiba.
struct StatusBanner: View {
    var isReading: Bool

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                ExcitementMarks(isActive: isReading)
                    .frame(width: 150, height: 52)
                ShibaSprite(isActive: isReading)
                    .frame(width: 96)
            }
            .frame(width: 140, height: 90)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(isReading ? "Notchman is reading" : "Notchman is ready")
                        .font(.headline)
                    Image(systemName: "pawprint.fill")
                        .foregroundStyle(Theme.amber)
                }
                Text(isReading ? "live in your Dynamic Island" : "share anything long to listen")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.trailing, 12)
        .card()
    }
}
