import SwiftUI

/// Row from the History design: source tile, source name + TL;DR pill,
/// quoted first line, duration and chevron.
struct HistoryRow: View {
    let item: ListeningItem
    var isCurrent = false

    var body: some View {
        HStack(spacing: 14) {
            SourceTile(type: item.sourceType, name: item.source, url: item.url, size: 56)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(item.source)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if item.isQuickListen { TLDRBadge() }
                    if item.isSaved {
                        Image(systemName: "bookmark.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.amber)
                            .accessibilityLabel("Saved")
                    }
                }
                Text("“\(item.title)…”")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                if item.hasStarted || isCurrent {
                    ProgressCapsule(value: item.currentProgress, height: 3)
                        .padding(.top, 3)
                }
            }

            Spacer(minLength: 4)

            if isCurrent {
                WaveformView(isAnimating: true)
                    .frame(width: 18, height: 16)
            } else {
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .monospacedDigit()
            }
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.tertiaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        let minutes = max(1, Int((item.hasStarted ? item.remainingDuration : item.duration) / 60 + 0.5))
        return item.completed ? "Played" : "\(minutes) min"
    }
}

/// Shared long-press menu for history items.
struct HistoryItemMenu: View {
    @Environment(AppEnvironment.self) private var env
    let item: ListeningItem

    var body: some View {
        if item.hasStarted {
            Button { env.listen(to: item) } label: { Label("Resume", systemImage: "play.fill") }
        }
        Button { env.listen(to: item, fromStart: true) } label: {
            Label("Play from Start", systemImage: "arrow.counterclockwise")
        }
        if !item.isQuickListen {
            Button { env.quickListen(to: item) } label: { Label("Play TL;DR", systemImage: "bolt.fill") }
        }
        Button { env.history.toggleSaved(item) } label: {
            Label(item.isSaved ? "Remove from Saved" : "Save", systemImage: item.isSaved ? "bookmark.slash" : "bookmark")
        }
        Divider()
        Button(role: .destructive) { env.delete(item) } label: { Label("Delete", systemImage: "trash") }
    }
}
