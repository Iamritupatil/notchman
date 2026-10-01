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
        manager.records = ContentRecordStore(defaults: defaults)
        manager.pending = PendingRequestStore(defaults: defaults)
        manager.pasteboard = pasteboard
    }

    override func tearDown() async throws {
        if let pasteboard { UIPasteboard.remove(withName: pasteboard.name) }
    }

    // MARK: - Freshness

    private func record(for text: String, action: NotchmanAction = .tldr) -> ContentRecord {
        ContentRecord(rawHash: ContentHash.of(text), kind: .text, detectedAt: Date(), consumedAt: Date(),
                      source: "Copied text", resolvedURL: nil, resolvedTextHash: ContentHash.of(text),
                      requestedAction: action, itemID: UUID())
    }

    /// Copy in ChatGPT, listen, go to LinkedIn without copying, tap again: the
    /// ChatGPT text is the current content (a replay), never new content.
    func testPlayedClipboardIsTheCurrentContentNotNew() {
        pasteboard.string = chatGPTAnswer
        guard case .new(let clip, let change) = manager.acquireClipboard(isForeground: true) else {
            return XCTFail("Expected the fresh copy")
        }
        XCTAssertEqual(clip.text, chatGPTAnswer)
        manager.markUsed(record(for: clip.text), clipboardChange: change)

        guard case .current(let current) = manager.acquireClipboard(isForeground: true) else {
            return XCTFail("Old ChatGPT text must not come back as new content")
        }
        XCTAssertEqual(current.rawHash, ContentHash.of(chatGPTAnswer))
    }

    /// Copy A, use it; copy B → B; copy link C → C.
    func testEachNewCopyReplacesTheCurrentContent() {
        pasteboard.string = chatGPTAnswer
        guard case .new(let a, let changeA) = manager.acquireClipboard(isForeground: true) else { return XCTFail() }
        manager.markUsed(record(for: a.text), clipboardChange: changeA)

        let whatsapp = "[29/09/26, 10:15 PM] Ritu: The meeting moved to 6 because the client is running late today."
        pasteboard.string = whatsapp
        guard case .new(let b, let changeB) = manager.acquireClipboard(isForeground: true) else { return XCTFail("B is new") }
        XCTAssertEqual(b.text, whatsapp)
        manager.markUsed(record(for: b.text), clipboardChange: changeB)

        let link = "https://www.linkedin.com/posts/jane_ai-activity-7123456789012345678-abcd"
        pasteboard.string = link
        guard case .new(let c, _) = manager.acquireClipboard(isForeground: true) else { return XCTFail("C is new") }
        XCTAssertEqual(c.url?.absoluteString, link)
    }

    /// In the background iOS returns nothing from the clipboard: that's reported
    /// as hidden, not as "nothing copied", and nothing old is replayed.
    func testEmptyClipboardInTheBackgroundIsReportedAsHidden() {
        guard case .hiddenByIOS = manager.acquireClipboard(isForeground: false) else {
            return XCTFail("Expected hiddenByIOS")
        }
        guard case .nothing = manager.acquireClipboard(isForeground: true) else { return XCTFail() }
    }

    /// Only a tap makes a request, and it's only acted on right after the tap:
    /// opening Notchman later never processes the clipboard.
    func testPendingRequestIsKeptBriefly() {
        let store = PendingRequestStore(defaults: defaults)
        let now = Date()
        store.save(PendingRequest(action: .tldr, triggeredAt: now, clipboardChange: 4))
        XCTAssertEqual(store.take(now: now.addingTimeInterval(5))?.action, .tldr)
        XCTAssertNil(store.take(now: now.addingTimeInterval(6)), "Taken once")
        store.save(PendingRequest(action: .read, triggeredAt: now, clipboardChange: 4))
        XCTAssertNil(store.take(now: now.addingTimeInterval(600)), "Too old to act on")
    }

    /// TEST E: an old link still on the clipboard is never processed as new.
    func testLinkCopiedLongAgoIsStaleNotNew() {
        let link = "https://x.com/jane/status/1234567890"
        pasteboard.string = link
        let start = Date()
        manager.observeClipboard() // Notchman saw this copy...
        guard case .staleClipboard = manager.acquireClipboard(isForeground: true, now: start.addingTimeInterval(3600)) else {
            return XCTFail("...an hour ago, so it's stale")
        }
    }

    /// Copying the same message again is a new request (served from the cache),
    /// but tapping again without copying is "nothing new".
    func testRecopyingTheSameMessageIsNewButNotCopyingIsNot() {
        pasteboard.string = chatGPTAnswer
        guard case .new(let clip, let change) = manager.acquireClipboard(isForeground: true) else { return XCTFail() }
        manager.markUsed(record(for: clip.text), clipboardChange: change)
        guard case .current = manager.acquireClipboard(isForeground: true) else { return XCTFail("Nothing new") }
        pasteboard.string = chatGPTAnswer // copied again
        guard case .new = manager.acquireClipboard(isForeground: true) else { return XCTFail("A fresh copy") }
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

    func testShortCopiesAreIgnored() {
        pasteboard.string = "ok thanks"
        guard case .nothing = manager.acquireClipboard(isForeground: true) else { return XCTFail("Too short to read") }
    }

    // MARK: - Source attribution (evidence only)

    func testCopiedTextWithoutEvidenceIsNotAttributedToAnApp() async throws {
        let prepared = try await ListenPipelineTests.pipeline().prepare(.init(text: chatGPTAnswer, url: nil), action: .read)
        XCTAssertEqual(prepared.content.sourceType, .text)
        XCTAssertEqual(prepared.content.sourceName, "Copied text")
        XCTAssertNil(prepared.content.evidence)
        XCTAssertEqual(prepared.content.method, "clipboard")
    }

    func testLinksAttributeByDomain() {
        let linkedIn = SourceResolver.resolve(text: "x", url: URL(string: "https://www.linkedin.com/posts/jane_ai-activity-7123456789012345678-abcd")!)
        XCTAssertEqual(linkedIn.source, .linkedin)
        XCTAssertEqual(linkedIn.evidence, "Link to www.linkedin.com")

        let chat = SourceResolver.resolve(text: "See https://chatgpt.com/share/abc for the answer we discussed", url: nil)
        XCTAssertEqual(chat.source, .chatGPT)
        XCTAssertNotNil(chat.evidence)
    }

    func testCopiedWhatsAppMessagesDropDatesAndShowWhatsApp() async throws {
        let chat = "[29/09/26, 10:15:02\u{202F}PM] Ritu: The meeting moved to 6 because the client is late.\n[29/09/26, 10:16 PM] Sam Kumar: Okay, I'll bring the contract and the pricing sheet."
        let prepared = try await ListenPipelineTests.pipeline().prepare(.init(text: chat, url: nil), action: .read)
        XCTAssertEqual(prepared.content.sourceName, "WhatsApp")
        XCTAssertNotNil(prepared.content.evidence)
        XCTAssertEqual(prepared.content.text, "Ritu: The meeting moved to 6 because the client is late.\nSam Kumar: Okay, I'll bring the contract and the pricing sheet.")
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
