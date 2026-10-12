import SwiftUI

/// A TL;DR's key points, exactly what the voice reads, or the original message.
struct TextViewerView: View {
    enum Mode: String, Identifiable {
        case keyPoints = "Key Points"
        case spoken = "TL;DR"
        case original = "Original"
        var id: String { rawValue }
    }

    let item: ListeningItem
    @State private var mode: Mode
    @Environment(\.dismiss) private var dismiss

    init(item: ListeningItem) {
        self.item = item
        _mode = State(initialValue: item.keyPoints.isEmpty ? .original : .keyPoints)
    }

    /// Key points only when there are some; "TL;DR" only for a TL;DR.
    private var modes: [Mode] {
        if !item.keyPoints.isEmpty { return [.keyPoints, .spoken, .original] }
        return item.isQuickListen ? [.spoken, .original] : [.original]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if mode == .keyPoints {
                        keyPoints
                    } else {
                        Text(mode == .original ? item.originalText : item.spokenText)
                            .font(.body)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .toolbar {
                if modes.count > 1 {
                    ToolbarItem(placement: .principal) {
                        Picker("Text", selection: $mode) {
                            ForEach(modes) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: modes.count > 2 ? 270 : 200)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                if let link = item.url.flatMap(URL.init(string:)) {
                    ToolbarItem(placement: .topBarLeading) {
                        Link(destination: link) { Image(systemName: "safari") }
                            .accessibilityLabel("Open original")
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// The key points as a list, easy to scan and to learn from.
    private var keyPoints: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(item.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(item.keyPoints.enumerated()), id: \.offset) { index, point in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.footnote.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.amber)
                            .frame(width: 22, alignment: .trailing)
                        Text(point)
                            .font(.body)
                            .foregroundStyle(Theme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    if index < item.keyPoints.count - 1 {
                        Divider().overlay(Theme.stroke).padding(.leading, 48)
                    }
                }
            }
            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous).stroke(Theme.stroke))
            .textSelection(.enabled)
        }
    }
}
