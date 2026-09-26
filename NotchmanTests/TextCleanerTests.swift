import XCTest
@testable import Notchman

final class TextCleanerTests: XCTestCase {
    private let cleaner = TextCleaner()

    func testHeadingsBecomeSentences() {
        XCTAssertEqual(cleaner.clean("## Architecture"), "Architecture.")
        XCTAssertEqual(cleaner.clean("# Why this works:"), "Why this works:")
    }

    func testEmphasisAndInlineCodeMarkersAreRemoved() {
        let result = cleaner.clean("This is **bold**, __also bold__, *italic*, _this too_ and `code`.")
        XCTAssertEqual(result, "This is bold, also bold, italic, this too and code.")
    }

    func testSnakeCaseIsNotTreatedAsItalic() {
        XCTAssertEqual(cleaner.clean("Set max_retry_count to three."), "Set max_retry_count to three.")
    }

    func testBulletsBecomeSeparateSentences() {
        let result = cleaner.clean("""
        Options:
        - Fast
        - Cheap
        * Good enough
        1. First step
        2) Second step
        - [x] Done task
        """)
        XCTAssertEqual(result, "Options:\nFast.\nCheap.\nGood enough.\nFirst step.\nSecond step.\nDone task.")
    }

    func testLongURLOnItsOwnLineIsAnnounced() {
        let result = cleaner.clean("See:\nhttps://example.com/something/very/long/path?query=1")
        XCTAssertEqual(result, "See:\nThere is a link here.")
    }

    func testInlineURLsAreNotPronounced() {
        let result = cleaner.clean("Read https://example.com/docs/getting-started/install before you begin.")
        XCTAssertEqual(result, "Read a link before you begin.")
    }

    func testShortBareDomainIsReadAsDomain() {
        XCTAssertEqual(cleaner.clean("Visit https://www.apple.com today."), "Visit apple.com today.")
    }

    func testMarkdownLinkReadsLinkText() {
        let result = cleaner.clean("Check [Apple's audio guide](https://developer.apple.com/audio/) for details.")
        XCTAssertEqual(result, "Check Apple's audio guide for details.")
    }

    func testLargeCodeBlockIsSkippedByDefault() {
        let result = cleaner.clean("""
        Here's the code:

        ```swift
        let a = 1
        let b = 2
        print(a + b)
        ```

        That's all.
        """)
        XCTAssertEqual(result, "Here's the code:\nThis response contains a Swift code block, which I've skipped.\nThat's all.")
    }

    func testSecondCodeBlockUsesShorterNotice() {
        let result = cleaner.clean("```\na\nb\n```\nMiddle.\n```\nc\nd\n```")
        XCTAssertEqual(result, [
            TextCleaner.genericCodeBlockNotice, "Middle.", TextCleaner.additionalCodeBlockNotice,
        ].joined(separator: "\n"))
    }

    func testOneLineCodeBlockIsRead() {
        XCTAssertEqual(cleaner.clean("Run:\n```bash\nnpm install\n```"), "Run:\nnpm install")
    }

    func testCodeBlocksAreReadWhenSkippingIsOff() {
        let reader = TextCleaner(options: .init(skipCodeBlocks: false))
        XCTAssertEqual(reader.clean("```\nlet a = 1\nlet b = 2\n```"), "let a = 1\nlet b = 2")
    }

    func testTablesBecomeSentences() {
        let result = cleaner.clean("""
        | Option | Pros |
        |---|---|
        | Local | Free |
        """)
        XCTAssertEqual(result, "Option, Pros.\nLocal, Free.")
    }

    func testCitationsAndEmojiAreRemoved() {
        let result = cleaner.clean("It launched in 2023【4†source】[1] 🚀 and grew fast ([nytimes.com](https://nytimes.com/a)).")
        XCTAssertEqual(result, "It launched in 2023 and grew fast.")
    }

    func testSymbolsAreSpeakable() {
        XCTAssertEqual(cleaner.clean("Input -> output, ~3 steps, R&D, e.g. this."),
                       "Input to output, about 3 steps, R and D, for example, this.")
    }

    func testHardWrappedEmailLinesAreJoined() {
        let result = cleaner.clean("We're on track for launch but we need two\ndecisions by Friday or the date slips.")
        XCTAssertEqual(result, "We're on track for launch but we need two decisions by Friday or the date slips.")
    }

    func testBlockquotesAndRulesAreRemoved() {
        XCTAssertEqual(cleaner.clean("> Note: be careful.\n\n---\n\nNext part."), "Note: be careful.\nNext part.")
    }

    func testHTMLIsStripped() {
        XCTAssertEqual(cleaner.clean("<p>Hello &amp; welcome</p><p>Second <b>line</b></p>"), "Hello and welcome.\nSecond line.")
    }

    func testCleanMarkdownOffKeepsMarkers() {
        let raw = TextCleaner(options: .init(cleanMarkdown: false))
        XCTAssertEqual(raw.clean("**Bold** text"), "**Bold** text")
    }

    func testTitleUsesFirstMeaningfulLine() {
        let cleaned = cleaner.clean("```\na\nb\n```\n## A very useful heading\nBody text.")
        XCTAssertEqual(TextCleaner.title(from: cleaned), "A very useful heading")
    }

    func testTitleIsTruncatedAtWordBoundary() {
        let long = String(repeating: "word ", count: 40)
        let title = TextCleaner.title(from: long, maxLength: 20)
        XCTAssertTrue(title.hasSuffix("…"))
        XCTAssertLessThanOrEqual(title.count, 21)
    }
}
