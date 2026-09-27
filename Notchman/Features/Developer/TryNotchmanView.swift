import SwiftUI

/// Developer test screen: paste or pick text and read it, exercising the same
/// ingest path as the Share Extension. Not the main product surface.
struct TryNotchmanView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var source: SourceType = .chatGPT
    @State private var showsSpokenPreview = false
    @FocusState private var editorFocused: Bool

    private var spokenPreview: String {
        TextCleaner(options: AppSettings().textCleanerOptions).clean(text)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .font(.callout)
                        .frame(minHeight: 200)
                        .focused($editorFocused)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("Paste a long message…")
                                    .font(.callout)
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    HStack {
                        Text("Text")
                        Spacer()
                        PasteButton(payloadType: String.self) { strings in
                            if let first = strings.first { text = first }
                        }
                        .labelStyle(.titleAndIcon)
                        .buttonBorderShape(.capsule)
                        .controlSize(.mini)
                    }
                } footer: {
                    if !text.isEmpty {
                        Text(TimeFormatter.summary(words: ReadingEstimator.wordCount(spokenPreview),
                                                   seconds: ReadingEstimator.duration(of: spokenPreview)))
                    }
                }

                Section("Samples") {
                    ForEach(DeveloperSamples.all) { sample in
                        Button(sample.name) {
                            text = sample.text
                            source = sample.source
                        }
                    }
                }

                Section {
                    Picker("Source", selection: $source) {
                        ForEach(SourceType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.symbolName).tag(type)
                        }
                    }
                    DisclosureGroup("Preview spoken text", isExpanded: $showsSpokenPreview) {
                        Text(spokenPreview.isEmpty ? "—" : spokenPreview)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Try Notchman")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .keyboard) {
                    Button("Done") { editorFocused = false }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button {
                        Haptics.tap()
                        ingest(.quickListen)
                    } label: {
                        Label("TL;DR", systemImage: "sparkles")
                    }
                    .buttonStyle(.notchmanSecondary)

                    Button {
                        Haptics.tap()
                        ingest(.read)
                    } label: {
                        Label("Read", systemImage: "play.fill")
                    }
                    .buttonStyle(.notchmanPrimary)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .background(.bar)
            }
        }
    }

    private func ingest(_ action: PendingListen.Action) {
        let content = ExtractedContent(text: text, title: nil, sourceType: source,
                                       sourceName: source.displayName, url: nil)
        env.ingest(content, action: action)
    }
}
