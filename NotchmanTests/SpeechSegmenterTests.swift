import XCTest
@testable import Notchman

final class SpeechSegmenterTests: XCTestCase {
    func testParagraphsBecomeSegments() {
        let text = "First paragraph.\nSecond one.\n\nThird." as NSString
        let segments = SpeechSegmenter.segments(in: text).map { text.substring(with: $0) }
        XCTAssertEqual(segments, ["First paragraph.", "Second one.", "Third."])
    }

    func testLongParagraphsSplitAtSentencesWithinLimit() {
        let sentence = "This sentence has a handful of words in it. "
        let text = String(repeating: sentence, count: 30) as NSString
        let segments = SpeechSegmenter.segments(in: text, maxLength: 200)
        XCTAssertGreaterThan(segments.count, 1)
        XCTAssertTrue(segments.allSatisfy { $0.length <= 200 })
        // Segments cover the text in order without overlap.
        for (a, b) in zip(segments, segments.dropFirst()) {
            XCTAssertLessThanOrEqual(NSMaxRange(a), b.location)
        }
    }

    func testRunOnSentenceIsHardSplit() {
        let text = String(repeating: "word ", count: 200) as NSString
        let segments = SpeechSegmenter.segments(in: text, maxLength: 100)
        XCTAssertTrue(segments.allSatisfy { $0.length <= 100 })
    }

    func testWordStartSnapsBackward() {
        let text = "Hello wonderful world" as NSString
        XCTAssertEqual(SpeechSegmenter.wordStart(at: 9, in: text), 6)
        XCTAssertEqual(SpeechSegmenter.wordStart(at: 6, in: text), 6)
        XCTAssertEqual(SpeechSegmenter.wordStart(at: 0, in: text), 0)
    }
}
