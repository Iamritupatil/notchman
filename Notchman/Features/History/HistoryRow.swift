import SwiftUI

struct HistoryRow: View {
    let item: ListeningItem
    var isCurrent = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SourceIcon(type: item.sourceType)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(item.source)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.sourceType.tint)
                        .lineLimit(1)
                    if item.isQuickListen { QuickBadge() }
                    Spacer(minLength: 4)
                    Text(RelativeDay.string(for: item.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(item.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    if isCurrent {
                        Image(systemName: "waveform")
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(statusText)
                    if item.isSaved {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(Color.accentColor)
                            .accessibilityLabel("Saved")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if item.hasStarted {
                    ProgressCapsule(value: item.currentProgress, height: 3)
                        .padding(.top, 2)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        if item.completed { return "Played · \(TimeFormatter.approximate(item.duration))" }
        if item.hasStarted { return "\(TimeFormatter.approximate(item.remainingDuration)) left" }
        return TimeFormatter.approximate(item.duration)
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
        Button { env.history.toggleSaved(item) } label: {
            Label(item.isSaved ? "Remove from Saved" : "Save", systemImage: item.isSaved ? "bookmark.slash" : "bookmark")
        }
        Divider()
        Button(role: .destructive) { env.delete(item) } label: { Label("Delete", systemImage: "trash") }
    }
}
