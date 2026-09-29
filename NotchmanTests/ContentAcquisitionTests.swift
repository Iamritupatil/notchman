import UIKit
import XCTest
@testable import Notchman

@MainActor
final class ContentAcquisitionTests: XCTestCase {
    private var defaults: UserDefaults!
    private var pasteboard: UIPasteboard!
    private var manager: ContentAcquisitionManager!

    private let chatGPTAnswer = "Here is the plan: ship on Friday at 10am, finish screenshots by Wednesday, and check India pricing before launch."

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")
        pasteboard = UIPasteboard(name: UIPasteboard.Name("test.\(UUID().uuidString)"), create: true)
        manager = ContentAcquisitionManager()
        manager.ledger = ClipboardLedger(defaults: defaults)
        manager.pasteboard = pasteboard
    }

    override func tearDown() async throws {
        if let pasteboard { UIPasteboard.remove(withName: pasteboard.name) }
    }

    // MARK: - Freshness

    /// The reported bug: copy in ChatGPT, listen, go to LinkedIn without copying,
    /// tap TL;DR. The ChatGPT text must not be presented again as new.
    func testAlreadyHeardClipboardIsNeverReplayedAsNew() async throws {
        pasteboard.string = chatGPTAnswer
        guard case .content(let content, let change) = try await manager.acquireForIsland() else {
            return XCTFail("Expected the fresh copy")
        }
        XCTAssertEqual(content.text, chatGPTAnswer)
        manager.markUsed(content, clipboardChange: change)

        // Nothing new copied (e.g. the user is now in LinkedIn).
        guard case .nothingNew = try await manager.acquireForIsland() else {
            return XCTFail("Old ChatGPT text must not come back as new content")
        }
    }

    func testANewCopyAfterwardsIsFresh() async throws {
        pasteboard.string = chatGPTAnswer
        guard case .content(let first, let change) = try await manager.acquireForIsland() else { return XCTFail() }
        manager.markUsed(first, clipboardChange: change)

        let next = "A completely different long message that the user copied next, with enough words to be read."
        pasteboard.string = next
        guard case .content(let content, _) = try await manager.acquireForIsland() else { return XCTFail() }
        XCTAssertEqual(content.text, next)
    }

    func testCopySeenLongAgoIsStale() {
        let ledger = ClipboardLedger(defaults: defaults)
        let start = Date()
        ledger.observe(changeCount: 7, now: start)
        XCTAssertEqual(ledger.freshness(changeCount: 7, now: start.addingTimeInterval(60)), .fresh)
        XCTAssertEqual(ledger.freshness(changeCount: 7, now: start.addingTimeInterval(11 * 60)), .stale(since: start))
        // A new copy resets it.
        XCTAssertEqual(ledger.freshness(changeCount: 8, now: start.addingTimeInterval(11 * 60)), .fresh)
    }

    func testFirstSeenTimeIsKept() {
        let ledger = ClipboardLedger(defaults: defaults)
        let start = Date()
        ledger.observe(changeCount: 3, now: start)
        ledger.observe(changeCount: 3, now: start.addingTimeInterval(600)) // seen again later
        XCTAssertEqual(ledger.freshness(changeCount: 3, now: start.addingTimeInterval(11 * 60)), .stale(since: start))
    }

    // MARK: - Reading the clipboard

    /// ChatGPT's Copy button may provide Markdown or HTML rather than plain text.
    func testReadsMarkdownOnlyClipboard() {
        let markdown = "## Plan\n\n- Ship on **Friday**\n- Screenshots by Wednesday"
        pasteboard.setData(Data(markdown.utf8), forPasteboardType: "net.daringfireball.markdown")
        XCTAssertEqual(ClipboardReader.read(pasteboard)?.text, markdown)
    }

    func testReadsHTMLOnlyClipboard() {
        pasteboard.setData(Data("<p>Ship on <b>Friday</b> at 10am.</p>".utf8), forPasteboardType: "public.html")
        XCTAssertEqual(ClipboardReader.read(pasteboard)?.text, "Ship on Friday at 10am.")
    }

    func testShortCopiesAreIgnored() async throws {
        pasteboard.string = "ok thanks"
        guard case .nothing = try await manager.acquireForIsland() else { return XCTFail("Too short to read") }
    }

    // MARK: - Source attribution (evidence only)

    func testCopiedTextWithoutEvidenceIsNotAttributedToAnApp() async throws {
        pasteboard.string = chatGPTAnswer
        guard case .content(let content, _) = try await manager.acquireForIsland() else { return XCTFail() }
        XCTAssertEqual(content.source, .text)
        XCTAssertEqual(content.sourceName, "Copied text")
        XCTAssertNil(content.evidence)
        XCTAssertEqual(content.method, .clipboard)
    }

    func testLinksAttributeByDomain() {
        let linkedIn = SourceResolver.resolve(text: "x", url: URL(string: "https://www.linkedin.com/posts/jane_ai-activity-7123456789012345678-abcd")!)
        XCTAssertEqual(linkedIn.source, .linkedin)
        XCTAssertEqual(linkedIn.evidence, "Link to www.linkedin.com")

        let chat = SourceResolver.resolve(text: "See https://chatgpt.com/share/abc for the answer we discussed", url: nil)
        XCTAssertEqual(chat.source, .chatGPT)
        XCTAssertNotNil(chat.evidence)
    }

    func testContentHashIgnoresWhitespaceAndCase() {
        XCTAssertEqual(ContentHash.of("Ship on  Friday\n"), ContentHash.of("ship on friday"))
        XCTAssertNotEqual(ContentHash.of("Ship on Friday"), ContentHash.of("Ship on Monday"))
    }

    // MARK: - LinkedIn

    func testLinkedInPublicPostFromStructuredData() {
        let html = """
        <html><head><title>Jane on LinkedIn</title>
        <script type="application/ld+json">{"@context":"http://schema.org","@type":"SocialMediaPosting",
        "author":{"@type":"Person","name":"Jane Doe"},
        "articleBody":"We shipped our AI assistant today. Three lessons: talk to users weekly, cut scope early, and measure retention not signups."}</script>
        </head><body></body></html>
        """
        let post = LinkedInExtractor.parse(html: html)
        XCTAssertEqual(post?.author, "Jane Doe")
        XCTAssertTrue(post?.text.hasPrefix("We shipped our AI assistant today.") == true)
    }

    func testLinkedInEmbedPageText() {
        let html = """
        <div><p class="attributed-text-segment-list__content text-color-text" dir="ltr">Hiring: two iOS engineers in Bengaluru.<br>Remote friendly, strong Swift required, apply by Friday.</p></div>
        """
        XCTAssertEqual(LinkedInExtractor.parse(html: html)?.text,
                       "Hiring: two iOS engineers in Bengaluru.\nRemote friendly, strong Swift required, apply by Friday.")
    }

    func testLinkedInLoginWallIsDetected() {
        XCTAssertTrue(LinkedInExtractor.isLoginWall(html: "", url: URL(string: "https://www.linkedin.com/authwall?trk=x")!))
        XCTAssertTrue(LinkedInExtractor.isLoginWall(html: "<html><head><title>Sign Up | LinkedIn</title>",
                                                    url: URL(string: "https://www.linkedin.com/feed/")!))
        XCTAssertFalse(LinkedInExtractor.isLoginWall(html: "<title>Jane on LinkedIn</title>",
                                                     url: URL(string: "https://www.linkedin.com/posts/x")!))
    }

    func testLinkedInActivityIDs() {
        XCTAssertEqual(LinkedInExtractor.activityID(in: URL(string: "https://www.linkedin.com/posts/jane_ai-activity-7123456789012345678-abcd")!),
                       "7123456789012345678")
        XCTAssertEqual(LinkedInExtractor.activityID(in: URL(string: "https://www.linkedin.com/feed/update/urn:li:activity:7123456789012345678/")!),
                       "7123456789012345678")
        XCTAssertNil(LinkedInExtractor.activityID(in: URL(string: "https://www.linkedin.com/in/jane")!))
    }
}
