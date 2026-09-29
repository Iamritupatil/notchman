import Foundation

/// Reads a LinkedIn post from its link ("Copy link to post" or Share).
///
/// What's possible: LinkedIn's app doesn't let other apps read what's on
/// screen, and its API doesn't give apps like Notchman post text. But a
/// *public* post's page carries its full text in structured data (JSON-LD
/// `articleBody`), and LinkedIn serves an embed page for public posts. Posts
/// that are only visible when signed in can't be read by any app: that's
/// reported plainly (`ExtractionError.loginRequired`), never guessed.
struct LinkedInExtractor {
    var session: URLSession = .shared

    func extract(url: URL) async throws -> ExtractedContent {
        var sawLoginWall = false
        for candidate in Self.candidates(for: url) {
            guard let (html, finalURL) = try? await fetch(candidate) else { continue }
            if Self.isLoginWall(html: html, url: finalURL) {
                sawLoginWall = true
                continue
            }
            if let post = Self.parse(html: html) {
                return ExtractedContent(text: post.text, title: post.author.map { "Post by \($0)" },
                                        sourceType: .linkedin, sourceName: "LinkedIn", url: url,
                                        method: "link", evidence: "Link to linkedin.com")
            }
        }
        // Last resort: let WebKit build the embed page, as Safari would.
        if let id = Self.activityID(in: url),
           let rendered = try? await RenderedPageReader.read(Self.embedURL(activity: id), timeout: 10),
           let text = rendered.replies.last ?? Optional(rendered.pageText),
           text.count > 40, !text.localizedCaseInsensitiveContains("sign in") {
            return ExtractedContent(text: text, title: nil, sourceType: .linkedin, sourceName: "LinkedIn", url: url,
                                    method: "link", evidence: "Link to linkedin.com")
        }
        if sawLoginWall { throw ExtractionError.loginRequired("LinkedIn") }
        throw ExtractionError.emptyContent
    }

    // MARK: - Parsing (pure, unit-tested)

    struct Post: Equatable {
        let text: String
        let author: String?
    }

    /// The post itself, then LinkedIn's public embed page for it.
    static func candidates(for url: URL) -> [URL] {
        var urls = [url]
        if let id = activityID(in: url) { urls.append(embedURL(activity: id)) }
        return urls
    }

    static func embedURL(activity id: String) -> URL {
        URL(string: "https://www.linkedin.com/embed/feed/update/urn:li:activity:\(id)")!
    }

    /// The numeric activity ID in `/posts/…-activity-123…` or `urn:li:activity:123`.
    static func activityID(in url: URL) -> String? {
        let text = url.absoluteString.removingPercentEncoding ?? url.absoluteString
        for pattern in [#"urn:li:(?:activity|share|ugcPost):(\d{10,})"#, #"-activity-(\d{10,})"#] {
            if let groups = RegexKit.firstMatch(pattern, in: text), let id = groups[1] { return id }
        }
        return nil
    }

    static func isLoginWall(html: String, url: URL) -> Bool {
        let path = url.path.lowercased()
        if path.contains("authwall") || path.hasPrefix("/login") || path.contains("/checkpoint") { return true }
        let head = String(html.prefix(4_000)).lowercased()
        return head.contains("<title>sign up | linkedin</title>") || head.contains("<title>linkedin login")
            || head.contains("<title>sign in")
    }

    static func parse(html: String) -> Post? {
        // 1. Structured data: the full post text, as LinkedIn publishes it for public posts.
        let scripts = RegexKit.allMatches(#"(?is)<script[^>]+type\s*=\s*["']application/ld\+json["'][^>]*>(.*?)</script>"#, in: html)
        for json in scripts {
            guard let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let post = findPost(in: object) { return post }
        }
        // 2. The embed page's post text.
        let segments = RegexKit.allMatches(#"(?is)<[^>]+class\s*=\s*["'][^"']*attributed-text-segment-list__content[^"']*["'][^>]*>(.*?)</(?:p|div|span)>"#, in: html)
            .map { HTMLEntities.decode(RegexKit.replace("(?s)<br\\s*/?>", in: $0, with: "\n")) }
            .map { RegexKit.replace("(?s)<[^>]+>", in: $0, with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let longest = segments.max(by: { $0.count < $1.count }), longest.count >= 40 {
            return Post(text: longest, author: nil)
        }
        return nil
    }

    private static func findPost(in object: Any) -> Post? {
        if let dictionary = object as? [String: Any] {
            if let body = (dictionary["articleBody"] ?? dictionary["text"]) as? String,
               body.trimmingCharacters(in: .whitespacesAndNewlines).count >= 40 {
                let author = (dictionary["author"] as? [String: Any])?["name"] as? String
                    ?? ((dictionary["author"] as? [[String: Any]])?.first?["name"] as? String)
                return Post(text: HTMLEntities.decode(body).trimmingCharacters(in: .whitespacesAndNewlines), author: author)
            }
            for value in dictionary.values {
                if let post = findPost(in: value) { return post }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let post = findPost(in: value) { return post }
            }
        }
        return nil
    }

    private func fetch(_ url: URL) async throws -> (String, URL) {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ExtractionError.network("LinkedIn returned \(http.statusCode).")
        }
        return (String(decoding: data, as: UTF8.self), response.url ?? url)
    }
}
