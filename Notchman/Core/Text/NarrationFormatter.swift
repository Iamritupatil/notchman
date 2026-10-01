import Foundation

/// The last step before text goes to the voice: makes it sound spoken, not
/// read. `TextCleaner` has already removed markdown, links and symbols; this
/// shapes rhythm:
///
/// - sentence boundaries a voice can hear (a space after every full stop,
///   semicolons become full stops, every line ends with punctuation);
/// - pauses instead of typography (spaced dashes become commas, `and/or`
///   becomes words, "5–10" becomes "5 to 10");
/// - no run-on sentences: one longer than a breath is split where it already
///   turns (", but", ", so", ", and"), so each sentence carries one idea;
/// - no report-style openers ("TL;DR:", "In summary,").
///
/// It never adds or removes information, and applying it twice changes nothing.
enum NarrationFormatter {
    /// Longer sentences are split where they already turn.
    static let maxWords = 30

    static func format(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n").map { raw -> String in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return "" }
            let shaped = sentences(in: inline(line)).flatMap(splitRunOn).joined(separator: " ")
            return TextCleaner.ensureTerminal(tidy(shaped))
        }
        return RegexKit.replace(#"\n{3,}"#, in: lines.joined(separator: "\n"), with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Within a line

    static func inline(_ line: String) -> String {
        var t = line
        // Report-style openers; the voice just starts explaining.
        t = RegexKit.replace(#"^(?i)(?:tl;?\s?dr|summary|in summary|to summari[sz]e|here'?s (?:a|the) summary)\s*[:,\-–—]\s*"#,
                             in: t) { _ in "" }
        t = capitalizedFirst(t)
        // Numeric ranges: "5–10" → "5 to 10".
        t = RegexKit.replace(#"(?<=\d)\s?[–—]\s?(?=\d)"#, in: t, with: " to ")
        // Spaced dashes between words are pauses: "the fix — a cache — worked" → commas.
        t = RegexKit.replace(#"(?<=[\p{L}\p{N}%)”"'’])\s+[—–-]\s+(?=[\p{L}\p{N}“"‘(])"#, in: t, with: ", ")
        t = RegexKit.replace(#"(?<=\p{L})—(?=\p{L})"#, in: t, with: ", ")
        // Semicolons: a full stop the voice can hear.
        t = RegexKit.replace(#"\s*;\s+(\S)"#, in: t) { groups in ". " + capitalizedFirst(groups[1] ?? "") }
        // Slashes between plain words.
        t = RegexKit.replace(#"(?i)\band/or\b"#, in: t, with: "or")
        t = RegexKit.replace(#"\b([a-z]{2,})/([a-z]{2,})\b"#, in: t, with: "$1 or $2")
        // A missing space after a sentence ("done.Next") runs two sentences together.
        t = RegexKit.replace(#"(?<=\p{Ll}[.!?])(?=\p{Lu}\p{Ll})"#, in: t, with: " ")
        return tidy(t)
    }

    private static func tidy(_ text: String) -> String {
        var t = RegexKit.replace(#"[ \t]{2,}"#, in: text, with: " ")
        t = RegexKit.replace(#",\s*,"#, in: t, with: ",")
        t = RegexKit.replace(#",\s*([.!?])"#, in: t, with: "$1")
        t = RegexKit.replace(#"\s+([,.!?])"#, in: t, with: "$1")
        return t.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Sentences

    /// Splits a line into sentences at `.`, `!`, `?` or `…` followed by a capital or digit.
    static func sentences(in line: String) -> [String] {
        let ns = line as NSString
        let boundaries = RegexKit.regex(#"(?<=[.!?…])\s+(?=["“'‘(]?[\p{Lu}\d])"#)
            .matches(in: line, range: NSRange(location: 0, length: ns.length))
        var result: [String] = []
        var start = 0
        for match in boundaries {
            result.append(ns.substring(with: NSRange(location: start, length: match.range.location - start)))
            start = match.range.location + match.range.length
        }
        result.append(ns.substring(from: start))
        return result.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// A sentence longer than `maxWords` is split at the turn closest to its
    /// middle (", but" → ". But"), as long as both halves are real sentences.
    static func splitRunOn(_ sentence: String) -> [String] {
        let words = wordCount(sentence)
        guard words > maxWords else { return [sentence] }
        let ns = sentence as NSString
        let turns = RegexKit.regex(#",\s+(but|so|and|yet|which means|and that means)\s+"#, .caseInsensitive)
            .matches(in: sentence, range: NSRange(location: 0, length: ns.length))
        let middle = ns.length / 2
        let candidates = turns.filter { match in
            let before = ns.substring(to: match.range.location)
            let after = ns.substring(from: match.range.location + 1)
            return wordCount(before) >= 6 && wordCount(after) >= 6
        }
        guard let best = candidates.min(by: { abs($0.range.location - middle) < abs($1.range.location - middle) }) else {
            return [sentence]
        }
        let first = TextCleaner.ensureTerminal(ns.substring(to: best.range.location))
        // The turn word starts the next sentence: "…, but the cost…" → "… But the cost…".
        let rest = capitalizedFirst(ns.substring(from: best.range.location + 1).trimmingCharacters(in: .whitespaces))
        return splitRunOn(first) + splitRunOn(rest)
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first, first.isLowercase else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
