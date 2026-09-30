import Foundation

/// Fetches a copied link and returns the useful text behind it: the post or
/// article, not the page chrome. Runs in the background (from the island or a
/// shortcut); nothing opens.
///
/// - Short links (lnkd.in, t.co) are expanded first.
/// - X / Twitter posts: X's public embed endpoint (oEmbed).
/// - LinkedIn (public post data, then its embed page), Reddit (post and top
///   comments), and any other page (article extraction, then a hidden web view
///   for pages built with JavaScript): `URLExtractor`.
///
/// When a site refuses anonymous access (sign-in walls, bot checks) the error
/// says so plainly: the link was valid, it just couldn't be opened.
struct URLContentResolver {
    var session: URLSession = .shared
    var extract: (URL) async throws -> ExtractedContent = { try await URLExtractor().extract(.url($0)) }

    enum ResolveError: LocalizedError, Equatable {
        /// The site wouldn't show the content without signing in.
        case inaccessible(site: String, isPost: Bool)

        var errorDescription: String? {
            switch self {
            case .inaccessible(let site, let isPost):
                isPost ? "Couldn't access this \(site) post automatically." : "Couldn't access this page automatically."
            }
        }
    }

    func resolve(_ url: URL) async throws -> ExtractedContent {
        let url = await expandShortLink(url)
        let type = SourceDetector.detect(url: url) ?? .webpage
        let content: ExtractedContent
        do {
            if XPost.isPost(url) {
                content = try await XPost(session: session).fetch(url)
            } else {
                content = try await extract(url)
            }
        } catch ExtractionError.loginRequired(let site) {
            throw ResolveError.inaccessible(site: site, isPost: true)
        } catch ExtractionError.clientRenderedPage {
            throw ResolveError.inaccessible(site: SourceDetector.sourceName(for: url, type: type), isPost: false)
        } catch ExtractionError.emptyContent where type == .linkedin {
            // A valid post link that yielded no text: LinkedIn served a
            // sign-in or bot-check page instead of the post.
            throw ResolveError.inaccessible(site: "LinkedIn", isPost: true)
        }
        var result = content
        result.method = AcquisitionMethod.link.rawValue
        result.evidence = result.evidence ?? "Link to \(url.host ?? "the web")"
        result.acquiredAt = Date()
        return result
    }

    /// lnkd.in and t.co links point elsewhere; follow them to the real page.
    func expandShortLink(_ url: URL) async -> URL {
        guard let host = url.host?.lowercased(), ["lnkd.in", "t.co"].contains(host) else { return url }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request) else { return url }
        if let final = response.url, final.host?.lowercased() != host { return final }
        // lnkd.in sometimes answers with a "you're leaving LinkedIn" page.
        return Self.interstitialTarget(in: String(decoding: data, as: UTF8.self)) ?? url
    }

    /// The destination on LinkedIn's or X's redirect page.
    static func interstitialTarget(in html: String) -> URL? {
        let patterns = [
            #"(?is)<a[^>]+data-tracking-control-name\s*=\s*["']external_url_click["'][^>]+href\s*=\s*["'](https?://[^"']+)["']"#,
            #"(?is)<a[^>]+href\s*=\s*["'](https?://[^"']+)["'][^>]+data-tracking-control-name\s*=\s*["']external_url_click["']"#,
            #"(?is)<meta[^>]+http-equiv\s*=\s*["']refresh["'][^>]+url=([^"'>\s]+)"#,
            #"(?is)<title>\s*(https?://[^<\s]+)\s*</title>"#,
        ]
        for pattern in patterns {
            if let groups = RegexKit.firstMatch(pattern, in: html), let value = groups[1],
               let url = URL(string: HTMLEntities.decode(value)) {
                return url
            }
        }
        return nil
    }
}

/// An X (Twitter) post, via X's public oEmbed endpoint (no sign-in needed).
struct XPost {
    var session: URLSession = .shared

    static func isPost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let hosts = ["x.com", "www.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com", "mobile.x.com"]
        return hosts.contains(host) && url.path.contains("/status/")
    }

    func fetch(_ url: URL) async throws -> ExtractedContent {
        var components = URLComponents(string: "https://publish.twitter.com/oembed")!
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString),
                                 URLQueryItem(name: "omit_script", value: "1"),
                                 URLQueryItem(name: "dnt", value: "true")]
        let (data, response) = try await session.data(for: URLRequest(url: components.url!, timeoutInterval: 12))
        if let http = response as? HTTPURLResponse, http.statusCode == 403 || http.statusCode == 404 {
            // Protected, deleted or age-restricted posts aren't embeddable.
            throw ExtractionError.loginRequired("X")
        }
        guard let post = Self.parse(oEmbed: data) else { throw ExtractionError.loginRequired("X") }
        return ExtractedContent(text: post.text, title: post.author.map { "Post by \($0)" }, sourceType: .webpage,
                                sourceName: "X", url: url, method: AcquisitionMethod.link.rawValue,
                                evidence: "Link to \(url.host ?? "x.com")")
    }

    struct Post: Equatable {
        let text: String
        let author: String?
    }

    /// The post text from oEmbed's `html` (a blockquote whose first paragraph is the post).
    static func parse(oEmbed data: Data) -> Post? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let html = object["html"] as? String,
              let groups = RegexKit.firstMatch(#"(?is)<p[^>]*>(.*?)</p>"#, in: html), let paragraph = groups[1] else { return nil }
        let withBreaks = RegexKit.replace(#"(?i)<br\s*/?>"#, in: paragraph, with: "\n")
        let text = HTMLEntities.decode(RegexKit.replace(#"(?s)<[^>]+>"#, in: withBreaks, with: ""))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return Post(text: text, author: object["author_name"] as? String)
    }
}
