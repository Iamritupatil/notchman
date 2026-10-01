import XCTest
@testable import Notchman

/// Text is shaped for the ear before it reaches the voice.
final class NarrationFormatterTests: XCTestCase {
    func testReportOpenersAndSemicolonsBecomeSpokenSentences() {
        XCTAssertEqual(NarrationFormatter.format("TL;DR: the launch moved to Friday; Priya owns the screenshots"),
                       "The launch moved to Friday. Priya owns the screenshots.")
    }

    func testDashesBecomePausesAndRangesBecomeWords() {
        XCTAssertEqual(NarrationFormatter.format("The fix — a shared cache — cut costs by 40% in 2–3 weeks"),
                       "The fix, a shared cache, cut costs by 40% in 2 to 3 weeks.")
    }

    func testSlashesBetweenWords() {
        XCTAssertEqual(NarrationFormatter.format("Reply by email and/or chat with read/write access."),
                       "Reply by email or chat with read or write access.")
    }

    func testMissingSpaceBetweenSentences() {
        XCTAssertEqual(NarrationFormatter.format("It shipped.Next we test it."), "It shipped. Next we test it.")
    }

    func testRunOnSentenceIsSplitWhereItTurns() {
        let runOn = "The team moved inference to its own GPUs last quarter and cut cloud costs by a third across every region, "
            + "but the migration took four months longer than planned and delayed two customer launches that were promised for June."
        let result = NarrationFormatter.format(runOn)
        XCTAssertEqual(result, "The team moved inference to its own GPUs last quarter and cut cloud costs by a third across every region. "
            + "But the migration took four months longer than planned and delayed two customer launches that were promised for June.")
        for sentence in NarrationFormatter.sentences(in: result) {
            XCTAssertLessThanOrEqual(NarrationFormatter.wordCount(sentence), NarrationFormatter.maxWords)
        }
    }

    func testShortSentencesAndNumbersAreUntouched() {
        let text = "Revenue was ₹38.2 crore, up 22%. Runway is 26 months."
        XCTAssertEqual(NarrationFormatter.format(text), text)
    }

    func testParagraphPausesAreKept() {
        XCTAssertEqual(NarrationFormatter.format("First topic.\n\n\n\nSecond topic"), "First topic.\n\nSecond topic.")
    }

    func testFormattingTwiceChangesNothing() {
        let samples = [
            "TL;DR: the launch moved to Friday; Priya owns the screenshots",
            "The fix — a shared cache — cut costs by 40% in 2–3 weeks",
            "Okay, here's what matters. The plan works, but only if the API stays under 200 ms, and the team ships the cache layer before the board meeting on 3 March, so start this week.",
        ]
        for sample in samples {
            let once = NarrationFormatter.format(sample)
            XCTAssertEqual(NarrationFormatter.format(once), once)
        }
    }
}
