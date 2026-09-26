import Foundation

/// Content captured in Safari, either by the web extension's "Listen" button
/// or by the Share Extension's JavaScript preprocessing.
///
/// Priority: the user's selection, then the message they were looking at,
/// then the page's main article text.
struct SafariMessageExtractor: ContentExtractor {
    /// Selections shorter than this are probably accidental.
    static let minimumSelectionLength = 20

    func canHandle(_ input: ExtractionInput) -> Bool {
        if case .webPage = input { return true }
        return false
    }

    func extract(_ input: ExtractionInput) async throws -> ExtractedContent {
        guard case .webPage(let page) = input else { throw ExtractionError.unsupportedInput }
        let url = page.url.flatMap(URL.init(string:))
        let type = Self.sourceType(site: page.site, url: url)
        let name = SourceDetector.sourceName(for: url, type: type)

        if let selection = page.selection?.trimmingCharacters(in: .whitespacesAndNewlines),
           selection.count >= Self.minimumSelectionLength {
            return ExtractedContent(text: selection, title: nil, sourceType: type, sourceName: name, url: url)
        }

        if let messages = page.messages?.filter({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
           !messages.isEmpty {
            let index = page.focusIndex.flatMap { messages.indices.contains($0) ? $0 : nil } ?? messages.count - 1
            // Chat titles are just "ChatGPT"; derive one from the message instead.
            let title = type == .reddit ? page.title : nil
            return ExtractedContent(text: messages[index], title: title, sourceType: type, sourceName: name, url: url)
        }

        if let content = page.content?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty {
            return ExtractedContent(text: content, title: page.title, sourceType: type, sourceName: name, url: url)
        }

        // Nothing usable in the page payload: fall back to fetching the URL ourselves.
        if let url { return try await URLExtractor().extract(.url(url)) }
        throw ExtractionError.emptyContent
    }

    static func sourceType(site: String?, url: URL?) -> SourceType {
        switch site?.lowercased() {
        case "chatgpt": return .chatGPT
        case "claude": return .claude
        case "reddit": return .reddit
        case "gemini": return .gemini
        default: return SourceDetector.detect(url: url) ?? .webpage
        }
    }
}
