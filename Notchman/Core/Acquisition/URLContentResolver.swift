import Foundation
import os

/// Fetches a copied link and returns the useful text behind it: the post or
/// article, not the page chrome.
///
/// 1. Clean: tracking parameters (utm_…, fbclid, X's `s`/`t`) are removed.
/// 2. Expand: short links (t.co, lnkd.in, bit.ly, …) are followed to their
///    final destination, including "you're leaving" interstitial pages.
/// 3. Detect the source from the final URL, then fetch and extract:
///    - X posts: X's public embed (oEmbed), or FxTwitter's public API when
///      that fails. A post that is mostly a link is resolved to what it links
///      to: an X Article (via FxTwitter) or an outside article (extracted like
///      any page). A post with its own text is the post.
///    - X Articles: FxTwitter's public API (X shows them only when signed in).
///    - LinkedIn, Reddit and any other page: `URLExtractor`.
///
/// When a site refuses anonymous access (sign-in walls, bot checks) the error
/// says so plainly: the link was valid, it just couldn't be opened.
struct URLContentResolver {
    var session: URLSession = .shared
    var extract: (URL) async throws -> ExtractedContent = { try await URLExtractor().extract(.url($0)) }
    /// Follows a short link; injectable for tests.
    var expand: ((URL) async -> URL)?

    private static let log = Logger(subsystem: "com.notchman", category: "Links")

    enum ResolveError: LocalizedError, Equatable {
        /// The site wouldn't show the content without signing in.
        case inaccessible(site: String, isPost: Bool)
        /// The post links to an article that couldn't be opened.
        case linkedArticleInaccessible(site: String)
        /// An X Article (long-form post) that couldn't be fetched.
        case xArticleInaccessible

        var errorDescription: String? {
            switch self {
            case .inaccessible(let site, let isPost):
                isPost ? "Couldn't access this \(site) post automatically." : "Couldn't access this page automatically."
            case .linkedArticleInaccessible(let site):
                "Couldn't open the article this post links to (\(site))."
            case .xArticleInaccessible:
                "Couldn't access this X article. It may be private or need signing in."
            }
        }
    }

    func resolve(_ copied: URL) async throws -> ExtractedContent {
        let url = Self.withoutTracking(await expandLink(Self.withoutTracking(copied)))
        if url != copied { Self.log.info("Resolved \(copied.absoluteString, privacy: .private) → \(url.absoluteString, privacy: .private)") }
        let type = SourceDetector.detect(url: url) ?? .webpage
        var content: ExtractedContent
        do {
            if let articlePost = XPost.articlePostID(in: url) {
                content = try await XPost(session: session).article(postID: articlePost, url: url)
            } else if XPost.isArticle(url) {
                throw ResolveError.xArticleInaccessible
            } else if XPost.isPost(url) {
                content = try await xPost(url)
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
        content.method = AcquisitionMethod.link.rawValue
        content.evidence = content.evidence ?? "Link to \(url.host ?? "the web")"
        content.acquiredAt = Date()
        return content
    }

    // MARK: - X

    /// An X post, or what it links to when the post is little more than a link.
    private func xPost(_ url: URL) async throws -> ExtractedContent {
        let x = XPost(session: session)
        let post = try await x.post(url)
        guard post.isMostlyLink, let link = post.links.first else { return post.content(url: url) }

        let target = Self.withoutTracking(await expandLink(link))
        Self.log.info("X post links to \(target.absoluteString, privacy: .private)")
        if XPost.isArticle(target) {
            // The post *is* an X Article: its text lives with the post.
            guard let id = XPost.statusID(in: url) else { throw ResolveError.xArticleInaccessible }
            return try await x.article(postID: id, url: target)
        }
        if XPost.isPost(target) {
            // Quoting another post: read the post as written.
            return post.content(url: url)
        }
        do {
            var article = try await extract(target)
            let author = post.author.map { " by \($0)" } ?? ""
            article.evidence = "Article linked from an X post\(author)"
            return article
        } catch {
            throw ResolveError.linkedArticleInaccessible(site: target.host.map(Self.siteName) ?? "the web")
        }
    }

    // MARK: - Short links and tracking

    static let shortLinkHosts: Set<String> = [
        "t.co", "lnkd.in", "bit.ly", "buff.ly", "ow.ly", "tinyurl.com", "goo.gl", "dlvr.it", "trib.al", "is.gd",
        "cutt.ly", "rebrand.ly", "shorturl.at", "tiny.cc", "rb.gy", "bl.ink", "fb.me", "amzn.to", "spr.ly", "hubs.ly",
    ]

    private func expandLink(_ url: URL) async -> URL {
        if let expand { return await expand(url) }
        return await expandShortLink(url)
    }

    /// Short links point elsewhere; follow them (redirects, then any
    /// "you're leaving" page) to the real page. Up to three hops.
    func expandShortLink(_ url: URL) async -> URL {
        var current = url
        for _ in 0..<3 {
            guard let host = current.host?.lowercased(), Self.shortLinkHosts.contains(host) else { return current }
            var request = URLRequest(url: current, timeoutInterval: 10)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                             forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await session.data(for: request) else { return current }
            if let final = response.url, final.host?.lowercased() != host {
                current = final
            } else if let target = Self.interstitialTarget(in: String(decoding: data, as: UTF8.self)) {
                current = target
            } else {
                return current
            }
        }
        return current
    }

    /// The destination on LinkedIn's or X's redirect page.
    static func interstitialTarget(in html: String) -> URL? {
        let patterns = [
            #"(?is)<a[^>]+data-tracking-control-name\s*=\s*["']external_url_click["'][^>]+href\s*=\s*["'](https?://[^"']+)["']"#,
            #"(?is)<a[^>]+href\s*=\s*["'](https?://[^"']+)["'][^>]+data-tracking-control-name\s*=\s*["']external_url_click["']"#,
            #"(?is)<meta[^>]+http-equiv\s*=\s*["']refresh["'][^>]+url=([^"'>\s]+)"#,
            #"(?is)location\.replace\(\s*["'](https?:[^"']+)["']"#,
            #"(?is)<title>\s*(https?://[^<\s]+)\s*</title>"#,
        ]
        for pattern in patterns {
            if let groups = RegexKit.firstMatch(pattern, in: html), let value = groups[1],
               let url = URL(string: HTMLEntities.decode(value).replacingOccurrences(of: "\\/", with: "/")) {
                return url
            }
        }
        return nil
    }

    /// Removes tracking parameters, which change nothing about the page.
    static func withoutTracking(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems, !items.isEmpty else { return url }
        let host = url.host?.lowercased() ?? ""
        let isX = XPost.hosts.contains(host)
        let kept = items.filter { item in
            let name = item.name.lowercased()
            if name.hasPrefix("utm_") { return false }
            if ["fbclid", "gclid", "igshid", "mc_cid", "mc_eid", "ref_src", "ref_url", "trk", "trackingid", "rcm", "si"].contains(name) { return false }
            if isX, ["s", "t", "ref"].contains(name) { return false }
            return true
        }
        components.queryItems = kept.isEmpty ? nil : kept
        return components.url ?? url
    }

    static func siteName(_ host: String) -> String {
        host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// X (Twitter) posts and Articles, without signing in.
struct XPost {
    var session: URLSession = .shared

    static let hosts: Set<String> = ["x.com", "www.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com", "mobile.x.com"]

    static func isX(_ url: URL) -> Bool {
        url.host.map { hosts.contains($0.lowercased()) } ?? false
    }

    static func isPost(_ url: URL) -> Bool {
        isX(url) && url.path.contains("/status/")
    }

    /// An X Article: `x.com/i/article/<id>` or `x.com/<user>/article/<id>`.
    static func isArticle(_ url: URL) -> Bool {
        isX(url) && url.pathComponents.contains("article")
    }

    /// The post ID in `x.com/<user>/status/<id>`.
    static func statusID(in url: URL) -> String? {
        let parts = url.pathComponents
        guard let index = parts.firstIndex(of: "status"), index + 1 < parts.count else { return nil }
        let id = parts[index + 1]
        return id.allSatisfy(\.isNumber) ? id : nil
    }

    /// `x.com/<user>/article/<id>` links carry the post's ID (`/i/article/<id>` doesn't).
    static func articlePostID(in url: URL) -> String? {
        let parts = url.pathComponents
        guard isX(url), let index = parts.firstIndex(of: "article"), index + 1 < parts.count,
              index >= 2, parts[index - 1] != "i" else { return nil }
        let id = parts[index + 1]
        return id.allSatisfy(\.isNumber) ? id : nil
    }

    struct Post: Equatable {
        let text: String
        let author: String?
        /// Links in the post (t.co), excluding attached media.
        var links: [URL] = []
        /// The post's own words, without links or media.
        var ownText: String? = nil

        /// Few words of its own: the post exists to share a link.
        var isMostlyLink: Bool {
            guard !links.isEmpty else { return false }
            let own = ownText ?? RegexKit.replace(#"(?:https?://|pic\.twitter\.com/|pic\.x\.com/)\S+"#, in: text, with: "")
            return own.trimmingCharacters(in: .whitespacesAndNewlines).count < 140
        }

        func content(url: URL) -> ExtractedContent {
            ExtractedContent(text: text, title: author.map { "Post by \($0)" }, sourceType: .webpage,
                             sourceName: "X", url: url, method: AcquisitionMethod.link.rawValue,
                             evidence: "Link to \(url.host ?? "x.com")")
        }
    }

    /// The post's text and links: X's oEmbed first, FxTwitter if that fails.
    func post(_ url: URL) async throws -> Post {
        if let post = try? await oEmbed(url) { return post }
        guard let id = Self.statusID(in: url), let object = try? await fxTwitter(id),
              let post = Self.parse(fxTwitter: object) else {
            throw ExtractionError.loginRequired("X")
        }
        return post
    }

    func oEmbed(_ url: URL) async throws -> Post {
        var components = URLComponents(string: "https://publish.twitter.com/oembed")!
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString),
                                 URLQueryItem(name: "omit_script", value: "1"),
                                 URLQueryItem(name: "dnt", value: "true")]
        let (data, response) = try await session.data(for: URLRequest(url: components.url!, timeoutInterval: 12))
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            // Protected, deleted or age-restricted posts aren't embeddable.
            throw ExtractionError.loginRequired("X")
        }
        guard let post = Self.parse(oEmbed: data) else { throw ExtractionError.loginRequired("X") }
        return post
    }

    /// An X Article's full text, via FxTwitter's public API.
    func article(postID: String, url: URL) async throws -> ExtractedContent {
        guard let object = try? await fxTwitter(postID), let article = Self.parseArticle(fxTwitter: object) else {
            throw URLContentResolver.ResolveError.xArticleInaccessible
        }
        return ExtractedContent(text: article.text, title: article.title, sourceType: .webpage,
                                sourceName: "X Article", url: url, method: AcquisitionMethod.link.rawValue,
                                evidence: "X Article\(article.author.map { " by \($0)" } ?? "")")
    }

    private func fxTwitter(_ id: String) async throws -> [String: Any] {
        let request = URLRequest(url: URL(string: "https://api.fxtwitter.com/status/\(id)")!, timeoutInterval: 12)
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ExtractionError.loginRequired("X")
        }
        return object
    }

    // MARK: - Parsing

    /// The post from oEmbed's `html` (a blockquote whose first paragraph is the post).
    static func parse(oEmbed data: Data) -> Post? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let html = object["html"] as? String,
              let groups = RegexKit.firstMatch(#"(?is)<p[^>]*>(.*?)</p>"#, in: html), let paragraph = groups[1] else { return nil }
        // Links to other pages; "pic.twitter.com/…" anchors are attached media.
        var links: [URL] = []
        let anchor = RegexKit.regex(#"(?is)<a[^>]+href\s*=\s*["'](https?://[^"']+)["'][^>]*>(.*?)</a>"#)
        let ns = paragraph as NSString
        for match in anchor.matches(in: paragraph, range: NSRange(location: 0, length: ns.length)) {
            let href = HTMLEntities.decode(ns.substring(with: match.range(at: 1)))
            let label = ns.substring(with: match.range(at: 2))
            guard !label.contains("pic.twitter.com"), !label.contains("pic.x.com"), !label.hasPrefix("@"), !label.hasPrefix("#"),
                  let url = URL(string: href) else { continue }
            links.append(url)
        }
        func plain(_ html: String) -> String {
            let withBreaks = RegexKit.replace(#"(?i)<br\s*/?>"#, in: html, with: "\n")
            return HTMLEntities.decode(RegexKit.replace(#"(?s)<[^>]+>"#, in: withBreaks, with: ""))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let text = plain(paragraph)
        guard !text.isEmpty else { return nil }
        let own = plain(RegexKit.replace(#"(?is)<a[^>]+href\s*=\s*["']https?://t\.co/[^>]*>.*?</a>"#, in: paragraph, with: ""))
        return Post(text: text, author: object["author_name"] as? String, links: links, ownText: own)
    }

    /// FxTwitter's `{ tweet: { text, author: { name }, raw_text: { facets }, … } }`.
    static func parse(fxTwitter object: [String: Any]) -> Post? {
        guard let tweet = object["tweet"] as? [String: Any] else { return nil }
        let text = (tweet["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let author = (tweet["author"] as? [String: Any])?["name"] as? String
        // Expanded links appear in the text; take outside ones.
        let links = RegexKit.allMatches(#"(https?://[^\s]+)"#, in: text).compactMap(URL.init(string:))
            .filter { !isX($0) || isArticle($0) }
        if text.isEmpty, tweet["article"] == nil { return nil }
        return Post(text: text, author: author, links: links)
    }

    struct Article: Equatable {
        let title: String?
        let text: String
        let author: String?
    }

    /// FxTwitter's `tweet.article`: a title, and the body as content blocks (or a preview).
    static func parseArticle(fxTwitter object: [String: Any]) -> Article? {
        guard let tweet = object["tweet"] as? [String: Any], let article = tweet["article"] as? [String: Any] else { return nil }
        let title = (article["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        var paragraphs: [String] = []
        if let content = article["content"] {
            collectText(content, into: &paragraphs)
        }
        var body = paragraphs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        if body.isEmpty, let preview = article["preview_text"] as? String { body = preview }
        guard !body.isEmpty else { return nil }
        let author = (tweet["author"] as? [String: Any])?["name"] as? String
        return Article(title: title?.isEmpty == false ? title : nil, text: body, author: author)
    }

    /// Every `text` value in a block structure, in order.
    private static func collectText(_ value: Any, into out: inout [String]) {
        if let dictionary = value as? [String: Any] {
            if let text = dictionary["text"] as? String { out.append(text) }
            for key in dictionary.keys.sorted() where key != "text" {
                if let child = dictionary[key], child is [Any] || child is [String: Any] { collectText(child, into: &out) }
            }
        } else if let array = value as? [Any] {
            for child in array { collectText(child, into: &out) }
        }
    }
}
