import Foundation

/// Plain text from the share sheet, Shortcuts, or the developer test screen.
struct SharedTextExtractor: ContentExtractor {
    func canHandle(_ input: ExtractionInput) -> Bool {
        if case .sharedText = input { return true }
        return false
    }

    func extract(_ input: ExtractionInput) async throws -> ExtractedContent {
        guard case .sharedText(let raw, let suggested) = input else { throw ExtractionError.unsupportedInput }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Some apps share a bare link as "text". Read the page instead of the URL.
        if let url = Self.standaloneURL(in: text) {
            return try await URLExtractor().extract(.url(url))
        }

        let type = suggested ?? SourceDetector.detect(text: text)
        return ExtractedContent(text: text, title: nil, sourceType: type, sourceName: type.displayName, url: nil)
    }

    static func standaloneURL(in text: String) -> URL? {
        guard !text.contains(where: \.isWhitespace),
              let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host != nil else { return nil }
        return url
    }
}
