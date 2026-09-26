import Foundation

/// Splits cleaned text into utterance-sized ranges.
///
/// Short utterances let us pause naturally between paragraphs and list items,
/// and let seeking/speed changes restart close to the current position.
/// Ranges are in UTF-16 units, matching `AVSpeechSynthesizer` callbacks.
enum SpeechSegmenter {
    static let maxSegmentLength = 400

    static func segments(in text: NSString, maxLength: Int = maxSegmentLength) -> [NSRange] {
        var result: [NSRange] = []
        var paragraphStart = 0
        let length = text.length

        while paragraphStart < length {
            let newline = text.range(of: "\n", options: [], range: NSRange(location: paragraphStart, length: length - paragraphStart))
            let paragraphEnd = newline.location == NSNotFound ? length : newline.location
            let paragraph = NSRange(location: paragraphStart, length: paragraphEnd - paragraphStart)
            if paragraph.length > 0, !isBlank(text.substring(with: paragraph)) {
                result += split(paragraph, in: text, maxLength: maxLength)
            }
            paragraphStart = paragraphEnd + 1
        }
        return result
    }

    private static func split(_ paragraph: NSRange, in text: NSString, maxLength: Int) -> [NSRange] {
        guard paragraph.length > maxLength else { return [paragraph] }

        var sentences: [NSRange] = []
        let string = text as String
        guard let range = Range(paragraph, in: string) else { return [paragraph] }
        string.enumerateSubstrings(in: range, options: [.bySentences, .substringNotRequired]) { _, sentenceRange, _, _ in
            sentences.append(NSRange(sentenceRange, in: string))
        }
        if sentences.isEmpty { sentences = [paragraph] }

        // Pack sentences into chunks up to maxLength; hard-split any run-on sentence at spaces.
        var chunks: [NSRange] = []
        var current: NSRange?
        for sentence in sentences.flatMap({ hardSplit($0, in: text, maxLength: maxLength) }) {
            if let existing = current, NSMaxRange(sentence) - existing.location <= maxLength {
                current = NSRange(location: existing.location, length: NSMaxRange(sentence) - existing.location)
            } else {
                if let existing = current { chunks.append(existing) }
                current = sentence
            }
        }
        if let current { chunks.append(current) }
        return chunks
    }

    private static func hardSplit(_ range: NSRange, in text: NSString, maxLength: Int) -> [NSRange] {
        guard range.length > maxLength else { return [range] }
        var pieces: [NSRange] = []
        var start = range.location
        let end = NSMaxRange(range)
        while end - start > maxLength {
            let window = NSRange(location: start, length: maxLength)
            let space = text.range(of: " ", options: .backwards, range: window)
            let cut = space.location == NSNotFound || space.location <= start ? start + maxLength : space.location + 1
            pieces.append(NSRange(location: start, length: cut - start))
            start = cut
        }
        pieces.append(NSRange(location: start, length: end - start))
        return pieces
    }

    /// Moves an offset back to the start of the word containing it, so resuming
    /// never begins mid-word.
    static func wordStart(at offset: Int, in text: NSString) -> Int {
        var index = min(max(0, offset), text.length)
        let whitespace = CharacterSet.whitespacesAndNewlines
        while index > 0, let scalar = UnicodeScalar(text.character(at: index - 1)), !whitespace.contains(scalar) {
            index -= 1
        }
        return index
    }

    private static func isBlank(_ string: String) -> Bool {
        string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
