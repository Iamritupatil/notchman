import Foundation

/// Text pulled out of whatever the user shared, before speech cleaning.
struct ExtractedContent: Codable, Equatable, Sendable {
    /// Raw text; may still contain markdown. `TextCleaner` makes it speakable.
    var text: String
    var title: String?
    var sourceType: SourceType
    /// Human label shown in the UI, e.g. "ChatGPT", "r/swift", "nytimes.com".
    var sourceName: String
    var url: URL?
}

/// Page data produced by the Safari extension or the Share Extension's
/// JavaScript preprocessing (see `Extensions/SafariExtension/Resources/extractors.js`).
struct WebPagePayload: Codable, Equatable, Sendable {
    var url: String?
    var title: String?
    /// The user's text selection, if any. Always wins.
    var selection: String?
    /// Site-specific message blocks (assistant replies, post, comment), as markdown.
    var messages: [String]?
    /// Which message the user was looking at (most visible in the viewport).
    var focusIndex: Int?
    /// Generic article text for pages without a site extractor.
    var content: String?
    /// "chatgpt", "claude", "reddit" or "generic".
    var site: String?

    init(url: String? = nil, title: String? = nil, selection: String? = nil, messages: [String]? = nil,
         focusIndex: Int? = nil, content: String? = nil, site: String? = nil) {
        self.url = url
        self.title = title
        self.selection = selection
        self.messages = messages
        self.focusIndex = focusIndex
        self.content = content
        self.site = site
    }

    /// Builds a payload from the loosely-typed dictionary JavaScript hands over.
    init(dictionary: [String: Any]) {
        url = dictionary["url"] as? String
        title = dictionary["title"] as? String
        selection = dictionary["selection"] as? String
        messages = (dictionary["messages"] as? [Any])?.compactMap { $0 as? String }
        focusIndex = (dictionary["focusIndex"] as? NSNumber)?.intValue
        content = dictionary["content"] as? String
        site = dictionary["site"] as? String
    }
}

enum ExtractionInput: Sendable {
    case sharedText(String, suggestedSource: SourceType? = nil)
    case url(URL)
    case webPage(WebPagePayload)
}

enum ExtractionError: LocalizedError, Equatable {
    case unsupportedInput
    case emptyContent
    case network(String)
    case clientRenderedPage

    var errorDescription: String? {
        switch self {
        case .unsupportedInput:
            "Notchman can't read this kind of content yet."
        case .emptyContent:
            "There's no readable text here."
        case .network(let message):
            "Couldn't load the page. \(message)"
        case .clientRenderedPage:
            "This page builds its text in the browser. Open it in Safari, then use Share → Listen with Notchman."
        }
    }
}

/// One way of turning input into text. Add new integrations by adding an
/// extractor and registering it in `ContentExtractionPipeline.standard`.
protocol ContentExtractor: Sendable {
    func canHandle(_ input: ExtractionInput) -> Bool
    func extract(_ input: ExtractionInput) async throws -> ExtractedContent
}

struct ContentExtractionPipeline: Sendable {
    let extractors: [any ContentExtractor]

    static let standard = ContentExtractionPipeline(extractors: [
        SafariMessageExtractor(),
        SharedTextExtractor(),
        URLExtractor(),
    ])

    func extract(_ input: ExtractionInput) async throws -> ExtractedContent {
        guard let extractor = extractors.first(where: { $0.canHandle(input) }) else {
            throw ExtractionError.unsupportedInput
        }
        var content = try await extractor.extract(input)
        content.text = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.text.isEmpty else { throw ExtractionError.emptyContent }
        return content
    }
}
