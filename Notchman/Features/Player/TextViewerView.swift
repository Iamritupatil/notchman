import SwiftUI

/// Shows the original message, or exactly what the voice reads.
struct TextViewerView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case original = "Original"
        case spoken = "Spoken"
        var id: String { rawValue }
    }

    let item: ListeningItem
    @State private var mode: Mode = .original
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(mode == .original ? item.originalText : item.spokenText)
                    .font(.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Text", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
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
}
