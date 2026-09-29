import Foundation

/// Fetches a URL and extracts readable text. Reddit uses its JSON API; everything
/// else goes through `GenericWebExtractor`.
struct URLExtractor: ContentExtractor {
    var session: URLSession = .shared

    func canHandle(_ input: ExtractionInput) -> Bool {
        if case .url = input { return true }
        return false
    }

    func extract(_ input: ExtractionInput) async throws -> ExtractedContent {
        guard case .url(let url) = input else { throw ExtractionError.unsupportedInput }
        let type = SourceDetector.detect(url: url) ?? .webpage

        if type == .reddit, let content = try? await RedditExtractor(session: session).extract(url: url) {
            return content
        }
        if type == .linkedin {
            return try await LinkedInExtractor(session: session).extract(url: url)
        }

        let html: String
        let finalURL: URL
        do {
            (html, finalURL) = try await fetchHTML(url)
        } catch {
            // Some sites refuse plain downloads; let WebKit load it like Safari.
            return try await renderedPage(url, type: type)
        }
        let finalType = SourceDetector.detect(url: finalURL) ?? type
        let page = GenericWebExtractor.extract(html: html)
        // Pages that build their text with JavaScript come back nearly empty:
        // load them in an invisible web view, as Safari would.
        if page.text.count < Self.minimumReadableCharacters,
           let rendered = try? await renderedPage(finalURL, type: finalType),
           rendered.text.count > page.text.count {
            return rendered
        }
        guard !page.text.isEmpty else { throw ExtractionError.emptyContent }
        return ExtractedContent(text: page.text, title: page.title, sourceType: finalType,
                                sourceName: SourceDetector.sourceName(for: finalURL, type: finalType), url: finalURL)
    }

    /// Less than this after a plain download usually means a JavaScript-built page.
    static let minimumReadableCharacters = 300

    private func renderedPage(_ url: URL, type: SourceType) async throws -> ExtractedContent {
        let rendered = try await RenderedPageReader.read(url)
        let text = (rendered.replies.last ?? rendered.pageText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 40 else { throw ExtractionError.emptyContent }
        return ExtractedContent(text: text, title: rendered.title, sourceType: type,
                                sourceName: SourceDetector.sourceName(for: url, type: type), url: url)
    }

    private func fetchHTML(_ url: URL) async throws -> (String, URL) {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ExtractionError.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ExtractionError.network("The server returned \(http.statusCode).")
        }
        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return (html, response.url ?? url)
    }
}
