import Foundation

// MARK: - Shared state

/// What Notchman last played from the clipboard (or a shortcut): enough to
/// tell a new copy from the current content, and to replay the current
/// content when Read or TL;DR is pressed again. Kept in the app group so the
/// island's intents, the app and the extensions all see the same state.
struct ContentRecord: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case text, url
    }

    /// `ContentHash` of the raw copied value (the text, or the link).
    var rawHash: String
    var kind: Kind
    var detectedAt: Date
    var consumedAt: Date?
    /// Where it came from, by evidence ("LinkedIn", "WhatsApp", "Copied text").
    var source: String
    /// The page a copied link resolved to.
    var resolvedURL: URL?
    /// `ContentHash` of the text that was actually read or summarized.
    var resolvedTextHash: String?
    var requestedAction: NotchmanAction
    /// The saved original, for replays.
    var itemID: UUID?
    /// The saved TL;DR of it, when one was made.
    var summaryItemID: UUID?
}

struct ContentRecordStore {
    var defaults: UserDefaults = AppGroup.defaults
    private static let key = "content.current"

    /// The current content: the last thing played. Anything with a different
    /// hash on the clipboard is new.
    var current: ContentRecord? {
        get {
            defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(ContentRecord.self, from: $0) }
        }
        nonmutating set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Self.key)
            } else {
                defaults.removeObject(forKey: Self.key)
            }
        }
    }
}

/// Whether the "Read / TL;DR with Notchman" shortcut has run on this iPhone,
/// so the island can point to it rather than to setup.
enum ShortcutSetup {
    private static let key = "shortcut.hasRun"
    static var hasRun: Bool {
        get { AppGroup.defaults.bool(forKey: key) }
        set { AppGroup.defaults.set(newValue, forKey: key) }
    }
}

// MARK: - Pipeline

/// What to play, with the action the user chose.
struct PreparedListen {
    /// The original content (a copied message, or a fetched page or post).
    let content: ExtractedContent
    let action: NotchmanAction
    /// The TL;DR, made only when `action` is `.tldr`.
    let summary: QuickListenService.Result?
    let record: ContentRecord
    /// The TL;DR came from the generation cache (no Groq call).
    var summaryFromCache = false

    /// The text that goes to the voice: the summary for TL;DR, the original for Read.
    var spokenText: String { summary?.text ?? content.text }
}

/// Turns copied text or a copied link into what's played, carrying the
/// requested action through every step:
///
///     text  ──────────────────────────────┐
///     link  → resolve & extract ──────────┴→ TL;DR: cached summary, or summarize
///                                            Read:  original
///
/// Dependencies are injected so the whole flow is unit-tested offline.
@MainActor
struct ListenPipeline {
    var resolve: (URL) async throws -> ExtractedContent
    var summarize: (String) async throws -> QuickListenService.Result
    /// Cleans text before it's summarized (markdown, links, symbols).
    var clean: (String) -> String
    var onStage: (PlaybackPreparationState) -> Void = { _ in }
    /// Earlier TL;DRs; the same text is never summarized twice.
    var cache: GenerationCache?

    func prepare(_ clip: ClipboardReader.Contents, action: NotchmanAction, now: Date = Date()) async throws -> PreparedListen {
        let content: ExtractedContent
        if let url = clip.url {
            onStage(.resolvingURL)
            content = try await resolve(url)
        } else {
            let resolution = SourceResolver.resolve(text: clip.text, url: nil)
            let text = WhatsAppChat.isChat(clip.text) ? WhatsAppChat.spoken(clip.text) : clip.text
            content = ExtractedContent(text: text, title: nil, sourceType: resolution.source,
                                       sourceName: resolution.name, url: nil, method: AcquisitionMethod.clipboard.rawValue,
                                       evidence: resolution.evidence, acquiredAt: now)
        }
        let textHash = ContentHash.of(content.text)

        var summary: QuickListenService.Result?
        var fromCache = false
        onStage(.preparingText)
        if action == .tldr {
            if let cached = cache?.entry(textHash: textHash, action: .tldr)?.summary, !cached.isEmpty {
                summary = QuickListenService.Result(text: cached, audio: nil, usage: nil)
                fromCache = true
            } else {
                // The server first understands the whole text, then writes the
                // TL;DR; the second step is shown once the first has had time.
                let words = content.text.split(whereSeparator: \.isWhitespace).count
                let onStage = onStage
                let next = Task { @MainActor in
                    try await Task.sleep(for: .seconds(words > 160 ? 4 : 1.5))
                    onStage(.summarizing)
                }
                defer { next.cancel() }
                summary = try await summarize(clean(content.text))
            }
        }

        let record = ContentRecord(rawHash: ContentHash.of(clip.text), kind: clip.url == nil ? .text : .url,
                                   detectedAt: now, consumedAt: nil, source: content.sourceName,
                                   resolvedURL: content.url, resolvedTextHash: textHash,
                                   requestedAction: action)
        return PreparedListen(content: content, action: action, summary: summary, record: record,
                              summaryFromCache: fromCache)
    }
}
