import Foundation

/// Finds the sentence around a character offset (UTF-16), for showing what's
/// being read right now.
enum SentenceLocator {
    static func ranges(in text: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length),
                                 options: [.bySentences, .substringNotRequired]) { _, range, _, _ in
            ranges.append(range)
        }
        return ranges
    }

    static func sentence(at offset: Int, in text: NSString, ranges: [NSRange], maxLength: Int = 110) -> String {
        guard !ranges.isEmpty else { return "" }
        // Binary search for the last range starting at or before the offset.
        var low = 0
        var high = ranges.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if ranges[mid].location <= offset { low = mid } else { high = mid - 1 }
        }
        let sentence = text.substring(with: ranges[low]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard sentence.count > maxLength else { return sentence }
        // Long sentence: show a window around the current word.
        let local = max(0, offset - ranges[low].location)
        let characters = Array(sentence)
        let start = max(0, min(local - maxLength / 3, characters.count - maxLength))
        var window = String(characters[start..<min(characters.count, start + maxLength)])
        if start > 0 { window = "…" + window.drop(while: { $0 != " " }).trimmingCharacters(in: .whitespaces) }
        if start + maxLength < characters.count {
            if let lastSpace = window.lastIndex(of: " ") { window = String(window[..<lastSpace]) }
            window += "…"
        }
        return window
    }
}
