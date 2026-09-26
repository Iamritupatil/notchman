import Foundation

/// Turns messy chat/web/email text into something that sounds natural when spoken.
///
/// The output is plain text with one block (paragraph, list item, heading) per
/// line. Line breaks are meaningful: the speech engine pauses between them.
struct TextCleaner {
    struct Options: Equatable, Sendable {
        var skipCodeBlocks: Bool = true
        var cleanMarkdown: Bool = true
        /// Fenced blocks with at most this many non-empty lines are read aloud
        /// even when skipping is on (e.g. a one-line shell command).
        var maxSpokenCodeLines: Int = 1
    }

    var options: Options

    init(options: Options = Options()) {
        self.options = options
    }

    static let genericCodeBlockNotice = "This response contains a code block, which I've skipped."
    static let additionalCodeBlockNotice = "There's another code block here, which I've skipped."
    static let linkNotice = "There is a link here."

    /// Prefixes code lines that are read aloud so block processing leaves them
    /// verbatim (no merging, no added periods). Stripped in `finalize`.
    private static let codeLineMarker = "\u{E000}"

    func clean(_ input: String) -> String {
        var text = Self.normalizeCharacters(input)
        text = processCodeBlocks(text)
        if options.cleanMarkdown {
            text = Self.stripHTML(text)
            text = Self.processBlocks(text)
            text = Self.processInline(text)
        }
        text = Self.processURLs(text)
        text = Self.speakableSymbols(text)
        return Self.finalize(text)
    }

    /// A short title for history: the first meaningful line of cleaned text.
    static func title(from cleanedText: String, maxLength: Int = 80) -> String {
        let notices: Set<String> = [genericCodeBlockNotice, additionalCodeBlockNotice, linkNotice]
        let line = cleanedText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !notices.contains($0) && !$0.hasSuffix("code block, which I've skipped.") }
            ?? ""
        var title = line
        while let last = title.last, ".:;,".contains(last) { title.removeLast() }
        if title.count > maxLength {
            let prefix = String(title.prefix(maxLength))
            let cut = prefix.lastIndex(of: " ").map { String(prefix[..<$0]) } ?? prefix
            title = cut.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–—")) + "…"
        }
        return title.isEmpty ? "Untitled" : title
    }

    // MARK: - Code blocks

    static func codeBlockNotice(language: String?) -> String {
        let names: [String: String] = [
            "swift": "Swift", "python": "Python", "py": "Python", "js": "JavaScript", "javascript": "JavaScript",
            "jsx": "JavaScript", "ts": "TypeScript", "typescript": "TypeScript", "tsx": "TypeScript",
            "bash": "shell", "sh": "shell", "shell": "shell", "zsh": "shell", "console": "shell",
            "json": "JSON", "yaml": "YAML", "yml": "YAML", "html": "HTML", "css": "CSS", "sql": "SQL",
            "java": "Java", "kotlin": "Kotlin", "go": "Go", "rust": "Rust", "rs": "Rust", "ruby": "Ruby",
            "rb": "Ruby", "c": "C", "cpp": "C++", "c++": "C++", "csharp": "C#", "cs": "C#", "php": "PHP",
            "xml": "XML", "dart": "Dart", "r": "R",
        ]
        guard let language, let name = names[language.lowercased()] else { return genericCodeBlockNotice }
        let article = ["HTML", "SQL", "XML", "R"].contains(name) ? "an" : "a"
        return "This response contains \(article) \(name) code block, which I've skipped."
    }

    private func processCodeBlocks(_ text: String) -> String {
        let pattern = #"(?m)^[ \t]*(`{3,}|~{3,})[ \t]*([A-Za-z0-9_+#.\-]*)[^\n]*\n([\s\S]*?)(?:^[ \t]*\1[ \t]*$|\z)"#
        var skipped = 0
        return RegexKit.replace(pattern, in: text) { groups in
            let body = groups[3] ?? ""
            let codeLines = body
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if options.skipCodeBlocks && codeLines.count > options.maxSpokenCodeLines {
                skipped += 1
                let notice = skipped == 1 ? Self.codeBlockNotice(language: groups[2]) : Self.additionalCodeBlockNotice
                return "\n\(notice)\n"
            }
            return "\n" + codeLines.map { Self.codeLineMarker + $0 }.joined(separator: "\n") + "\n"
        }
    }

    // MARK: - Normalization

    private static func normalizeCharacters(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
            .replacingOccurrences(of: "\t", with: "    ")
    }

    private static func stripHTML(_ text: String) -> String {
        guard RegexKit.matches("<[a-zA-Z/][^>]*>", in: text) else { return HTMLEntities.decode(text) }
        var result = text
        result = RegexKit.replace(#"(?is)<a\s[^>]*href\s*=\s*"([^"]*)"[^>]*>(.*?)</a>"#, in: result, with: "[$2]($1)")
        result = RegexKit.replace(#"(?i)<br\s*/?>"#, in: result, with: "\n")
        result = RegexKit.replace(#"(?i)<li\b[^>]*>"#, in: result, with: "\n- ")
        result = RegexKit.replace(#"(?i)</(p|div|li|h[1-6]|tr|blockquote|section|article)>"#, in: result, with: "\n")
        result = RegexKit.replace(
            #"(?i)</?(b|i|u|s|em|strong|span|p|div|sup|sub|code|kbd|mark|small|font|h[1-6]|ul|ol|table|tbody|thead|tr|td|th|blockquote|section|article)\b[^>]*>"#,
            in: result, with: "")
        return HTMLEntities.decode(result)
    }

    // MARK: - Block-level markdown

    private enum LineKind { case blank, block, plain }

    private static func processBlocks(_ text: String) -> String {
        var lines: [(kind: LineKind, text: String)] = []

        for rawLine in text.components(separatedBy: "\n") {
            var line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix(codeLineMarker) {
                lines.append((.block, line))
                continue
            }

            // Blockquote markers.
            line = RegexKit.replace(#"^(>\s?)+"#, in: line, with: "").trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                lines.append((.blank, ""))
                continue
            }
            // Reference-style link definitions: "[1]: https://…"
            if RegexKit.matches(#"^\[[^\]]+\]:\s+\S+"#, in: line) { continue }
            // Table separator rows: |---|:---:|
            if RegexKit.matches(#"^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?$"#, in: line) { continue }
            // Horizontal rules / setext underlines.
            if RegexKit.matches(#"^([-*_=])(\s*\1){2,}$"#, in: line) {
                lines.append((.blank, ""))
                continue
            }
            // Headings: "## Architecture" -> "Architecture."
            if let groups = RegexKit.firstMatch(#"^#{1,6}\s+(.*?)\s*#*$"#, in: line), let heading = groups[1] {
                lines.append((.block, ensureTerminal(heading)))
                continue
            }
            // Table rows: "| a | b |" -> "a, b."
            if line.hasPrefix("|"), line.hasSuffix("|"), line.count > 2 {
                let cells = line.split(separator: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                if !cells.isEmpty {
                    lines.append((.block, ensureTerminal(cells.joined(separator: ", "))))
                }
                continue
            }
            // Bullets, numbered items and task-list checkboxes become sentences.
            if let groups = RegexKit.firstMatch(#"^(?:[-*+•●▪◦‣]|\d{1,3}[.)])\s+(?:\[[ xX]\]\s+)?(.*)$"#, in: line),
               let item = groups[1] {
                let trimmed = item.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { lines.append((.block, ensureTerminal(trimmed))) }
                continue
            }
            // Hard-wrapped paragraphs (common in emails): join continuation lines.
            if let previous = lines.last, previous.kind == .plain,
               let lastChar = previous.text.last, !".!?:;\"”)".contains(lastChar),
               let firstChar = line.first, firstChar.isLowercase {
                lines[lines.count - 1].text += " " + line
                continue
            }
            lines.append((.plain, line))
        }

        return lines.map { entry in
            // Short standalone lines are usually labels or titles; give them a full stop.
            if entry.kind == .plain, entry.text.count < 60 { return ensureTerminal(entry.text) }
            return entry.text
        }.joined(separator: "\n")
    }

    /// Adds a period when a line ends mid-thought so the voice drops its pitch.
    static func ensureTerminal(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last else { return trimmed }
        if last.isLetter || last.isNumber || ")\"”'’%*`]_".contains(last) {
            return trimmed + "."
        }
        return trimmed
    }

    // MARK: - Inline markdown

    private static func processInline(_ text: String) -> String {
        var t = text
        // Citations: ChatGPT 【4†source】, footnotes [^1], numeric refs [1], source chips ([site](url)).
        t = RegexKit.replace("【[^】]*】", in: t, with: "")
        t = RegexKit.replace(#"\[\^[^\]]+\]"#, in: t, with: "")
        t = RegexKit.replace(#"\s?\(\[[^\]]+\]\(https?://[^)\s]+\)\)"#, in: t, with: "")
        t = RegexKit.replace(#"(?<=\S)\[\d{1,3}\](?!\()"#, in: t, with: "")
        // Images: keep alt text only.
        t = RegexKit.replace(#"!\[([^\]]*)\]\([^)]*\)"#, in: t, with: "$1")
        // Links: read the link text, never the URL.
        t = RegexKit.replace(#"\[([^\]]+)\]\(([^)\s]*)(?:\s+"[^"]*")?\)"#, in: t, with: "$1")
        t = RegexKit.replace(#"\[([^\]]+)\]\[[^\]]*\]"#, in: t, with: "$1")
        t = RegexKit.replace(#"<((?:https?://|mailto:)[^>\s]+)>"#, in: t, with: "$1")
        // Inline code.
        t = RegexKit.replace(#"`+([^`\n]+?)`+"#, in: t, with: "$1")
        // Emphasis.
        t = RegexKit.replace(#"(\*\*\*|___)(?=\S)(.+?)(?<=\S)\1"#, in: t, with: "$2")
        t = RegexKit.replace(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#, in: t, with: "$2")
        t = RegexKit.replace(#"(?<![\w*])\*(?=\S)([^*\n]+?)(?<=\S)\*(?![\w*])"#, in: t, with: "$1")
        t = RegexKit.replace(#"(?<![\w_])_(?=\S)([^_\n]+?)(?<=\S)_(?![\w_])"#, in: t, with: "$1")
        t = RegexKit.replace("~~(.+?)~~", in: t, with: "$1")
        // Leftover markers.
        t = t.replacingOccurrences(of: "**", with: "")
        t = t.replacingOccurrences(of: "__", with: "")
        t = t.replacingOccurrences(of: "`", with: "")
        t = RegexKit.replace(#"(?<=\s)\*(?=\s)"#, in: t, with: "")
        // Escaped markdown characters: \* -> *
        t = RegexKit.replace(#"\\([\\*_{}\[\]()#+\-.!>|])"#, in: t, with: "$1")
        // Emoji are read aloud literally ("rocket", "check mark button"); drop them.
        t = RegexKit.replace(#"[\p{Extended_Pictographic}\x{FE0F}\x{200D}\x{20E3}]"#, in: t, with: "")
        return t
    }

    // MARK: - URLs

    private static let urlPattern = #"(?<![\w@/])(?:https?://|www\.)[^\s<>()\[\]"]+[^\s<>()\[\]".,;:!?'’]"#

    private static func processURLs(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n").map { line -> String in
            // A URL on its own line gets a full sentence.
            let core = line.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)"))
            if RegexKit.matches(#"^(?:https?://|www\.)\S+$"#, in: core) {
                return linkNotice
            }
            // Inline URLs: short bare domains are read, anything else becomes "a link".
            return RegexKit.replace(urlPattern, in: line) { groups in
                spokenURL(groups[0] ?? "")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func spokenURL(_ raw: String) -> String {
        let normalized = raw.hasPrefix("www.") ? "https://" + raw : raw
        guard let url = URL(string: normalized), var host = url.host else { return "a link" }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let path = url.path
        if (path.isEmpty || path == "/") && url.query == nil && host.count <= 30 {
            return host
        }
        return "a link"
    }

    // MARK: - Symbols

    private static func speakableSymbols(_ text: String) -> String {
        var t = text
        t = RegexKit.replace(#"\s*(?:->|→|=>|⇒)\s*"#, in: t, with: " to ")
        t = RegexKit.replace(#"(?<=\w)\s*&\s*(?=\w)"#, in: t, with: " and ")
        t = RegexKit.replace(#"~(?=\d)"#, in: t, with: "about ")
        t = t.replacingOccurrences(of: "≈", with: " about ")
        t = t.replacingOccurrences(of: "≥", with: " at least ")
        t = t.replacingOccurrences(of: "≤", with: " at most ")
        t = t.replacingOccurrences(of: "±", with: " plus or minus ")
        t = t.replacingOccurrences(of: "←", with: " ")
        t = RegexKit.replace(#"(?<=\d)\s*×\s*(?=\d)"#, in: t, with: " times ")
        t = RegexKit.replace(#"(?<![\w&])#(\d+)\b"#, in: t, with: "number $1")
        t = RegexKit.replace(#"(?i)\be\.g\.,?"#, in: t, with: "for example,")
        t = RegexKit.replace(#"(?i)\bi\.e\.,?"#, in: t, with: "that is,")
        t = RegexKit.replace(#"(?im)\betc\.(?=\s*$)"#, in: t, with: "et cetera.")
        t = RegexKit.replace(#"(?i)\betc\."#, in: t, with: "et cetera")
        t = RegexKit.replace(#"(?i)\bvs\.?(?=\s)"#, in: t, with: "versus")
        t = RegexKit.replace(#"([!?])\1+"#, in: t, with: "$1")
        t = RegexKit.replace(#"\.{4,}"#, in: t, with: "...")
        return t
    }

    // MARK: - Final whitespace/punctuation pass

    private static func finalize(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n").compactMap { rawLine -> String? in
            var line = RegexKit.replace(#"[ \t]{2,}"#, in: rawLine.replacingOccurrences(of: codeLineMarker, with: ""), with: " ")
                .trimmingCharacters(in: .whitespaces)
            line = RegexKit.replace(#"\s+([,.;:!?])"#, in: line, with: "$1")
            line = RegexKit.replace(#"(?<!\.)\.\.(?!\.)"#, in: line, with: ".")
            line = RegexKit.replace(#"[,:;]\."#, in: line, with: ".")
            line = RegexKit.replace(#"^[,.;:!?\-–—•]+\s*"#, in: line, with: "")
            // Lines left with no letters or digits (e.g. a lone emoji bullet) carry nothing to say.
            guard line.rangeOfCharacter(from: .alphanumerics) != nil else { return nil }
            return line
        }
        return lines.joined(separator: "\n")
    }
}
