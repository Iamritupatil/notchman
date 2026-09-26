import XCTest
@testable import Notchman

final class MessageBlockDetectorTests: XCTestCase {
    /// A line of `chars` characters at vertical position `y` (normalized).
    private func line(_ y: CGFloat, x: CGFloat = 0.08, width: CGFloat = 0.8, chars: Int = 40, text: String? = nil) -> TextLine {
        TextLine(text: text ?? String(repeating: "a", count: chars), box: CGRect(x: x, y: y, width: width, height: 0.02))
    }

    func testGroupsConsecutiveLinesAndSeparatesBubbles() {
        let lines = [
            // Short message (left bubble).
            line(0.10, width: 0.4, chars: 20), line(0.125, width: 0.4, chars: 20),
            // Long answer, separated by a big gap.
            line(0.25), line(0.275), line(0.30), line(0.325), line(0.35),
        ]
        let blocks = MessageBlockDetector.blocks(from: lines, options: .init(minimumCharacters: 10))
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[1].lines.count, 5)
        XCTAssertEqual(MessageBlockDetector.defaultBlock(in: blocks)?.id, blocks[1].id)
    }

    func testSideBySideColumnsStaySeparate() {
        let lines = [
            line(0.20, x: 0.05, width: 0.35), line(0.20, x: 0.60, width: 0.35),
            line(0.225, x: 0.05, width: 0.35), line(0.225, x: 0.60, width: 0.35),
        ]
        XCTAssertEqual(MessageBlockDetector.blocks(from: lines, options: .init(minimumCharacters: 10)).count, 2)
    }

    func testStatusBarAndShortLabelsAreIgnored() {
        let lines = [line(0.01, text: "9:41"), line(0.5, chars: 12)]
        XCTAssertTrue(MessageBlockDetector.blocks(from: lines).isEmpty)
    }

    func testParagraphBreakInsideBlockBecomesNewline() {
        let block = MessageBlock(id: 0, lines: [line(0.2, text: "First."), line(0.24, text: "Second.")],
                                 box: .zero)
        XCTAssertEqual(block.text, "First.\nSecond.")
        let wrapped = MessageBlock(id: 0, lines: [line(0.2, text: "Hello"), line(0.222, text: "world")], box: .zero)
        XCTAssertEqual(wrapped.text, "Hello world")
    }

    func testGuessesSourceFromScreenText() {
        XCTAssertEqual(MessageBlockDetector.guessSource(from: [line(0.05, text: "ChatGPT 5")]), .chatGPT)
        XCTAssertEqual(MessageBlockDetector.guessSource(from: [line(0.05, text: "Messages")]), .text)
    }
}
