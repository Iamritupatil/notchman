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

        let (html, finalURL) = try await fetchHTML(url)
        let finalType = SourceDetector.detect(url: finalURL) ?? type
        let page = GenericWebExtractor.extract(html: html)
        // Chat share pages (ChatGPT, Claude, Gemini) build their text with
        // JavaScript, so render them on device and read the AI's latest reply.
        if [.chatGPT, .claude, .gemini].contains(finalType), page.text.count < 400 || Self.isChatShare(finalURL) {
            let rendered = try await RenderedPageReader.read(finalURL)
            let text = rendered.replies.last ?? rendered.pageText
            guard !text.isEmpty else { throw ExtractionError.clientRenderedPage }
            return ExtractedContent(text: text, title: Self.chatTitle(rendered.title), sourceType: finalType,
                                    sourceName: finalType.displayName, url: finalURL)
        }
        guard !page.text.isEmpty else { throw ExtractionError.emptyContent }
        return ExtractedContent(text: page.text, title: page.title, sourceType: type,
                                sourceName: SourceDetector.sourceName(for: finalURL, type: type), url: finalURL)
    }

    static func isChatShare(_ url: URL) -> Bool {
        url.pathComponents.contains("share") || url.pathComponents.contains("s")
    }

    /// "ChatGPT - Trip plan" → "Trip plan".
    static func chatTitle(_ raw: String?) -> String? {
        guard var title = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        for prefix in ["ChatGPT - ", "Claude - ", "Gemini - ", "‎Gemini - "] where title.hasPrefix(prefix) {
            title.removeFirst(prefix.count)
        }
        return title.isEmpty ? nil : title
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
