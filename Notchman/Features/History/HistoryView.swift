import SwiftData
import SwiftUI

struct HistoryView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case saved = "Saved"
        var id: String { rawValue }
    }

    @Environment(AppEnvironment.self) private var env
    @Environment(PlaybackManager.self) private var playback
    @Query(sort: \ListeningItem.createdAt, order: .reverse) private var items: [ListeningItem]
    @State private var filter: Filter = .all

    private var visibleItems: [ListeningItem] {
        filter == .saved ? items.filter(\.isSaved) : items
    }

    var body: some View {
        List {
            ForEach(visibleItems) { item in
                Button {
                    Haptics.tap()
                    env.listen(to: item)
                } label: {
                    HistoryRow(item: item, isCurrent: playback.nowPlaying?.itemID == item.id)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        env.delete(item)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        env.history.toggleSaved(item)
                    } label: {
                        Label(item.isSaved ? "Unsave" : "Save", systemImage: item.isSaved ? "bookmark.slash" : "bookmark")
                    }
                    .tint(.accentColor)
                    Button {
                        env.listen(to: item, fromStart: true)
                    } label: {
                        Label("Replay", systemImage: "arrow.counterclockwise")
                    }
                    .tint(.gray)
                }
                .contextMenu { HistoryItemMenu(item: item) }
            }
        }
        .listStyle(.plain)
        .overlay {
            if visibleItems.isEmpty {
                ContentUnavailableView(
                    filter == .saved ? "No saved listens" : "No history yet",
                    systemImage: filter == .saved ? "bookmark" : "headphones",
                    description: Text(filter == .saved
                        ? "Save anything you want to come back to."
                        : "Share a long message to Notchman to start listening."))
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
    }
}
