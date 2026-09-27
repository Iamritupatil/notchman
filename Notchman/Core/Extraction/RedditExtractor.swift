import Foundation

/// Reads Reddit posts and comment permalinks through Reddit's public JSON
/// endpoint, which is far more reliable than scraping its HTML.
struct RedditExtractor {
    var session: URLSession = .shared

    func extract(url: URL) async throws -> ExtractedContent {
        let canonical = try await resolveShareLink(url)
        guard let jsonURL = Self.jsonURL(for: canonical) else { throw ExtractionError.unsupportedInput }

        var request = URLRequest(url: jsonURL, timeoutInterval: 15)
        request.setValue("ios:app.notchman:v0.1 (listen-later reader)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ExtractionError.network("Reddit returned \(http.statusCode).")
        }
        return try Self.parse(data, url: canonical)
    }

    /// `/r/sub/s/abc123` share links and redd.it short links redirect to the real permalink.
    private func resolveShareLink(_ url: URL) async throws -> URL {
        let isShortLink = url.host?.hasSuffix("redd.it") == true || url.pathComponents.contains("s")
        guard isShortLink else { return url }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "HEAD"
        let (_, response) = try await session.data(for: request)
        return response.url ?? url
    }

    static func jsonURL(for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              url.pathComponents.contains("comments") else { return nil }
        components.host = "www.reddit.com"
        var path = components.path
        if path.hasSuffix("/") { path.removeLast() }
        components.path = path + ".json"
        components.queryItems = [URLQueryItem(name: "raw_json", value: "1"), URLQueryItem(name: "limit", value: "1")]
        return components.url
    }

    /// Parses the two-listing response: [post listing, comments listing].
    static func parse(_ data: Data, url: URL) throws -> ExtractedContent {
        guard let listings = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let post = Self.children(of: listings.first).first else {
            throw ExtractionError.emptyContent
        }

        let subreddit = post["subreddit_name_prefixed"] as? String ?? "Reddit"
        let title = (post["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        // A comment permalink: /r/sub/comments/<post>/<slug>/<comment>/
        let components = url.pathComponents.filter { $0 != "/" }
        let isCommentPermalink = components.firstIndex(of: "comments").map { components.count - $0 >= 4 } ?? false
        if isCommentPermalink, listings.count > 1,
           let comment = Self.children(of: listings[1]).first,
           let body = comment["body"] as? String, !body.isEmpty {
            let author = comment["author"] as? String
            let intro = author.map { "Comment by \($0)." } ?? "Comment."
            return ExtractedContent(text: intro + "\n\n" + body, title: title, sourceType: .reddit,
                                    sourceName: subreddit, url: url)
        }

        let selftext = (post["selftext"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var text = TextCleaner.ensureTerminal(title ?? "")
        text += selftext.isEmpty ? "\n\nThis is a link post with no text." : "\n\n" + selftext
        return ExtractedContent(text: text, title: title, sourceType: .reddit, sourceName: subreddit, url: url)
    }

    private static func children(of listing: [String: Any]?) -> [[String: Any]] {
        guard let data = listing?["data"] as? [String: Any],
              let children = data["children"] as? [[String: Any]] else { return [] }
        return children.compactMap { $0["data"] as? [String: Any] }
    }
}
