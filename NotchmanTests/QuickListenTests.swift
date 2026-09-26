import XCTest
@testable import Notchman

final class QuickListenTests: XCTestCase {
    func testShortTextIsReturnedWhole() async throws {
        let text = "Just one short sentence."
        let summary = try await MockSummarizationProvider().summarizeForListening(text, targetDuration: .oneMinute)
        XCTAssertTrue(summary.hasSuffix(text))
    }

    func testLongTextIsCondensedToBudgetAndKeepsNumbers() async throws {
        var sentences: [String] = []
        for index in 0..<80 {
            sentences.append("This is filler sentence number word \(index % 2 == 0 ? "alpha" : "beta") that adds little.")
        }
        sentences.insert("The deadline is Friday and the budget is 4,500 dollars.", at: 40)
        let text = sentences.joined(separator: " ")

        let summary = try await MockSummarizationProvider().summarizeForListening(text, targetDuration: .thirtySeconds)
        XCTAssertTrue(summary.hasPrefix("Okay, here's the quick version."))
        XCTAssertTrue(summary.contains("4,500 dollars"))
        XCTAssertLessThan(ReadingEstimator.wordCount(summary), 110)
    }

    func testDetailedBudgetScalesWithSource() {
        XCTAssertEqual(QuickListenDuration.detailed.targetWords(forSourceWords: 100), 300)
        XCTAssertEqual(QuickListenDuration.detailed.targetWords(forSourceWords: 2000), 700)
        XCTAssertEqual(QuickListenDuration.detailed.targetWords(forSourceWords: 10_000), 900)
    }
}

final class ReadingEstimatorTests: XCTestCase {
    func testWordCount() {
        XCTAssertEqual(ReadingEstimator.wordCount("Read less. Listen instead."), 4)
    }

    func testDurationScalesWithSpeed() {
        let text = String(repeating: "a", count: 1450)
        XCTAssertEqual(ReadingEstimator.duration(of: text, speed: 1, charactersPerSecond: 14.5), 100, accuracy: 0.001)
        XCTAssertEqual(ReadingEstimator.duration(of: text, speed: 2, charactersPerSecond: 14.5), 50, accuracy: 0.001)
    }

    func testFormatting() {
        XCTAssertEqual(TimeFormatter.clock(260), "4:20")
        XCTAssertEqual(TimeFormatter.clock(3725), "1:02:05")
        XCTAssertEqual(TimeFormatter.approximate(30), "<1 min")
        XCTAssertEqual(TimeFormatter.approximate(250), "~4 min")
    }

    func testSpeedMappingIsMonotonic() {
        let rates = PlaybackSpeed.options.map(PlaybackSpeed.utteranceRate(for:))
        XCTAssertEqual(rates, rates.sorted())
        XCTAssertEqual(PlaybackSpeed.utteranceRate(for: 1.0), 0.5, accuracy: 0.001)
        XCTAssertEqual(PlaybackSpeed.label(1.0), "1x")
        XCTAssertEqual(PlaybackSpeed.label(1.5), "1.5x")
    }
}
