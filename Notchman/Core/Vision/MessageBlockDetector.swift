import CoreGraphics
import Foundation

/// One recognized line of text. `box` is normalized (0...1) with a top-left origin.
struct TextLine: Equatable, Sendable {
    var text: String
    var box: CGRect
    var confidence: Float = 1
}

/// A group of lines that reads as one message: a chat bubble, an answer, a paragraph.
struct MessageBlock: Identifiable, Equatable, Sendable {
    let id: Int
    var lines: [TextLine]
    var box: CGRect

    var text: String {
        var result = ""
        for (index, line) in lines.enumerated() {
            if index > 0 {
                let previous = lines[index - 1]
                let gap = line.box.minY - previous.box.maxY
                // A visibly larger gap means a new paragraph inside the same message.
                result += gap > previous.box.height * 0.9 ? "\n" : " "
            }
            result += line.text
        }
        return result
    }

    var characterCount: Int { lines.reduce(0) { $0 + $1.text.count } }
}

/// Groups OCR lines from a screenshot into message blocks using layout only
/// (vertical rhythm and horizontal alignment). Pure and synchronous, so it's
/// unit-testable without Vision.
enum MessageBlockDetector {
    struct Options {
        /// Ignore the status bar and home-indicator areas.
        var topInset: CGFloat = 0.06
        var bottomInset: CGFloat = 0.04
        /// Blocks shorter than this aren't worth a TL;DR (names, timestamps, buttons).
        var minimumCharacters = 60
    }

    static func blocks(from lines: [TextLine], options: Options = Options()) -> [MessageBlock] {
        let content = lines
            .filter { $0.box.minY >= options.topInset && $0.box.maxY <= 1 - options.bottomInset }
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.box.minY != $1.box.minY ? $0.box.minY < $1.box.minY : $0.box.minX < $1.box.minX }

        var groups: [[TextLine]] = []
        for line in content {
            if let index = groups.lastIndex(where: { belongs(line, to: $0) }) {
                groups[index].append(line)
            } else {
                groups.append([line])
            }
        }

        return groups
            .enumerated()
            .map { index, lines in
                MessageBlock(id: index, lines: lines, box: lines.map(\.box).reduce(lines[0].box) { $0.union($1) })
            }
            .filter { $0.characterCount >= options.minimumCharacters }
    }

    /// The block Notchman picks when the user doesn't: the one with the most text.
    static func defaultBlock(in blocks: [MessageBlock]) -> MessageBlock? {
        blocks.max { $0.characterCount < $1.characterCount }
    }

    private static func belongs(_ line: TextLine, to group: [TextLine]) -> Bool {
        guard let last = group.last else { return false }
        let lineHeight = max(last.box.height, line.box.height)
        let gap = line.box.minY - last.box.maxY
        // Next line must sit just below: within ~1.6 line heights, and not far above.
        guard gap < lineHeight * 1.6, gap > -lineHeight * 0.5 else { return false }

        // And be horizontally aligned with the block (same bubble / column).
        let blockLeft = group.map(\.box.minX).min() ?? last.box.minX
        let overlap = min(line.box.maxX, last.box.maxX) - max(line.box.minX, last.box.minX)
        let alignedLeft = abs(line.box.minX - blockLeft) < 0.04
        let overlapsEnough = overlap > min(line.box.width, last.box.width) * 0.3
        return alignedLeft || overlapsEnough
    }

    /// Guesses the app from text elsewhere on screen (e.g. "ChatGPT" in the header).
    static func guessSource(from lines: [TextLine]) -> SourceType {
        let all = lines.map { $0.text.lowercased() }.joined(separator: " ")
        if all.contains("chatgpt") { return .chatGPT }
        if all.contains("claude") { return .claude }
        if all.contains("gemini") { return .gemini }
        if all.contains("reddit") || all.contains("r/") { return .reddit }
        if all.contains("inbox") || all.contains("reply all") || all.contains("subject") { return .email }
        return .text
    }
}
