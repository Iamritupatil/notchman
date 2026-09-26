import Foundation

/// A small, dependency-free "reader mode" for HTML.
///
/// It drops page chrome (nav, header, footer, forms, scripts), prefers the
/// `<article>` or `<main>` region, and converts the remaining structure to
/// light markdown that `TextCleaner` understands (headings, lists, code, links).
enum GenericWebExtractor {
    struct Page: Equatable {
        var title: String?
        var text: String
    }

    static func extract(html: String) -> Page {
        let title = metaTitle(in: html)
        var body = html

        body = RegexKit.replace("(?s)<!--.*?-->", in: body, with: "")
        body = RegexKit.replace(
            #"(?is)<(script|style|noscript|svg|nav|header|footer|aside|form|button|iframe|template|select|dialog|menu)\b[^>]*>.*?</\1\s*>"#,
            in: body, with: " ")

        body = mainRegion(of: body)
        body = htmlToMarkdown(body)
        return Page(title: title, text: body)
    }

    // MARK: - Helpers

    private static func metaTitle(in html: String) -> String? {
        let candidates = [
            #"(?is)<meta[^>]+property\s*=\s*["']og:title["'][^>]*content\s*=\s*["']([^"']+)["']"#,
            #"(?is)<meta[^>]+content\s*=\s*["']([^"']+)["'][^>]*property\s*=\s*["']og:title["']"#,
            #"(?is)<title[^>]*>(.*?)</title>"#,
        ]
        for pattern in candidates {
            if let groups = RegexKit.firstMatch(pattern, in: html), let raw = groups[1] {
                let title = HTMLEntities.decode(stripTags(raw)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty { return title }
            }
        }
        return nil
    }

    /// The longest `<article>`, else `<main>`, else `<body>`, else everything.
    private static func mainRegion(of html: String) -> String {
        for tag in ["article", "main", "body"] {
            let pattern = "(?is)<\(tag)\\b[^>]*>(.*)</\(tag)\\s*>"
            // Greedy so nested blocks stay inside; for <article> also try lazy matches
            // and keep the longest, which handles pages listing several articles.
            var best: String?
            if tag == "article" {
                let lazy = "(?is)<article\\b[^>]*>(.*?)</article\\s*>"
                let re = RegexKit.regex(lazy)
                let ns = html as NSString
                for match in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
                    let candidate = ns.substring(with: match.range(at: 1))
                    if textLength(candidate) > (best.map(textLength) ?? 0) { best = candidate }
                }
            } else if let groups = RegexKit.firstMatch(pattern, in: html) {
                best = groups[1]
            }
            if let best, textLength(best) > 200 { return best }
        }
        return html
    }

    private static func textLength(_ html: String) -> Int {
        stripTags(html).trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    static func stripTags(_ html: String) -> String {
        RegexKit.replace("<[^>]+>", in: html, with: "")
    }

    static func htmlToMarkdown(_ html: String) -> String {
        var t = html
        // Preformatted code keeps its line breaks inside a fence.
        t = RegexKit.replace(#"(?is)<pre\b[^>]*>(.*?)</pre\s*>"#, in: t) { groups in
            let inner = groups[1] ?? ""
            let language = RegexKit.firstMatch(#"(?i)class\s*=\s*["'][^"']*language-([\w+#-]+)"#, in: inner)?[1] ?? ""
            let code = HTMLEntities.decode(stripTags(RegexKit.replace(#"(?i)<br\s*/?>"#, in: inner, with: "\n")))
            return "\n\n```\(language)\n\(code)\n```\n\n"
        }
        // Collapse source whitespace (outside of code fences, which are now protected by newlines).
        t = collapseWhitespaceOutsideFences(t)
        t = RegexKit.replace(#"(?is)<a\s[^>]*href\s*=\s*["'](https?://[^"']+)["'][^>]*>(.*?)</a>"#, in: t, with: "[$2]($1)")
        t = RegexKit.replace(#"(?i)<h([1-6])\b[^>]*>"#, in: t, with: "\n\n# ")
        t = RegexKit.replace(#"(?i)<li\b[^>]*>"#, in: t, with: "\n- ")
        t = RegexKit.replace(#"(?i)<br\s*/?>"#, in: t, with: "\n")
        t = RegexKit.replace(#"(?i)<(td|th)\b[^>]*>"#, in: t, with: " | ")
        t = RegexKit.replace(#"(?i)<tr\b[^>]*>"#, in: t, with: "\n")
        t = RegexKit.replace(
            #"(?i)</?(p|div|section|h[1-6]|ul|ol|li|blockquote|table|tr|figure|figcaption|dl|dt|dd)\b[^>]*>"#,
            in: t, with: "\n\n")
        t = RegexKit.replace(#"(?i)<code\b[^>]*>(.*?)</code>"#, in: t, with: "`$1`")
        t = stripTags(t)
        t = HTMLEntities.decode(t)

        let lines = t.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let joined = lines.joined(separator: "\n")
        return RegexKit.replace(#"\n{3,}"#, in: joined, with: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func collapseWhitespaceOutsideFences(_ text: String) -> String {
        let parts = text.components(separatedBy: "```")
        return parts.enumerated().map { index, part in
            index.isMultiple(of: 2) ? RegexKit.replace(#"\s+"#, in: part, with: " ") : part
        }.joined(separator: "```")
    }
}
