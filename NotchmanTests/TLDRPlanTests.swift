import XCTest
@testable import Notchman

final class FreeAllowanceTests: XCTestCase {
    private var stored: String?

    private func allowance() -> FreeAllowance {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return FreeAllowance(load: { self.stored }, save: { self.stored = $0 }, calendar: calendar)
    }

    private let september = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21 UTC
    private let october = Date(timeIntervalSince1970: 1_791_900_000)   // 2026-10-13 UTC

    func testTenPerMonthThenBlocked() throws {
        let free = allowance()
        for _ in 0..<FreeAllowance.monthlyLimit { try free.consume(now: september) }
        XCTAssertEqual(free.usage(now: september).remaining, 0)
        XCTAssertThrowsError(try free.consume(now: september)) { error in
            guard case CloudError.quotaExceeded(let usage) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(usage.limit, 10)
            XCTAssertEqual(usage.planName, "Free")
        }
    }

    func testNewMonthStartsFresh() throws {
        let free = allowance()
        for _ in 0..<FreeAllowance.monthlyLimit { try free.consume(now: september) }
        XCTAssertEqual(try free.consume(now: october).remaining, 9)
    }

    func testRefundGivesOneBack() throws {
        let free = allowance()
        try free.consume(now: september)
        try free.consume(now: september)
        free.refund(now: september)
        XCTAssertEqual(free.usage(now: september).used, 1)
    }

    func testResetsOnTheFirstOfNextMonth() {
        let reset = allowance().resetDate(now: september)
        XCTAssertEqual(reset, ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z"))
    }
}

final class MultilingualTLDRTests: XCTestCase {
    func testSpanishSummaryHasNoEnglishFraming() async throws {
        let sentences = (0..<60).map { index in
            "Esta es la frase número \(index) del mensaje y explica algo que no es muy importante para nadie."
        }
        let text = sentences.joined(separator: " ")
        let summary = try await MockSummarizationProvider().summarizeForListening(text, targetDuration: .thirtySeconds)
        XCTAssertTrue(summary.hasPrefix("Bien, esta es la versión corta."), summary)
        XCTAssertFalse(summary.contains("quick version"))
    }

    func testUntranslatedLanguageGetsNoFraming() {
        let japanese = "これは長いメッセージです。重要なポイントがいくつかあります。締め切りは金曜日です。"
        XCTAssertNil(MockSummarizationProvider.SpokenPhrases.matching(japanese))
    }

    func testPromptAsksForTheMessagesLanguage() {
        XCTAssertTrue(SummarizationPrompt.instructions.contains("same language as the message"))
        XCTAssertTrue(SummarizationPrompt.request(for: "Hola", targetWords: 75).contains("same language as the message"))
        let complete = SummarizationPrompt.completeRequest(for: "Hola")
        XCTAssertTrue(complete.contains("same language as the message"))
        XCTAssertTrue(complete.contains("do not target a fixed duration"))
        XCTAssertFalse(complete.contains("about"))
    }
}

final class MessageChooserTests: XCTestCase {
    func testReadsTheNumberFromTheReply() {
        XCTAssertEqual(MessageChooser.number(in: "2"), 2)
        XCTAssertEqual(MessageChooser.number(in: "Block [3] is the answer."), 3)
        XCTAssertNil(MessageChooser.number(in: "none"))
    }

    func testPromptNumbersAndTrimsBlocks() {
        let long = TextLine(text: String(repeating: "b", count: 900), box: CGRect(x: 0, y: 0.3, width: 1, height: 0.02))
        let short = TextLine(text: "What is a TL;DR?", box: CGRect(x: 0, y: 0.1, width: 1, height: 0.02))
        let prompt = MessageChooser.prompt(for: [
            MessageBlock(id: 0, lines: [long], box: .zero),
            MessageBlock(id: 1, lines: [short], box: .zero),
        ])
        XCTAssertTrue(prompt.contains("[1] " + String(repeating: "b", count: MessageChooser.charactersPerBlock) + "\n"))
        XCTAssertTrue(prompt.contains("[2] What is a TL;DR?"))
    }

    func testSingleBlockSkipsTheModel() async {
        let block = MessageBlock(id: 7, lines: [TextLine(text: "Only one", box: .zero)], box: .zero)
        let chosen = await MessageChooser.choose(from: [block])
        XCTAssertEqual(chosen?.id, 7)
    }
}

final class DeepLinkTLDRTests: XCTestCase {
    func testTLDRLinkRoundTrips() {
        XCTAssertEqual(DeepLink(url: URL(string: "notchman://tldr")!), .tldrClipboard)
        XCTAssertEqual(DeepLink.tldrClipboard.url.absoluteString, "notchman://tldr")
        XCTAssertEqual(DeepLink(url: URL(string: "notchman://read")!), .readClipboard)
    }
}
