import XCTest
@testable import Notchman

final class ExtractionTests: XCTestCase {
    func testSourceDetectionFromURL() {
        XCTAssertEqual(SourceDetector.detect(url: URL(string: "https://chatgpt.com/c/123")), .chatGPT)
        XCTAssertEqual(SourceDetector.detect(url: URL(string: "https://claude.ai/chat/abc")), .claude)
        XCTAssertEqual(SourceDetector.detect(url: URL(string: "https://old.reddit.com/r/swift/comments/x")), .reddit)
        XCTAssertEqual(SourceDetector.detect(url: URL(string: "https://www.nytimes.com/article")), .webpage)
        XCTAssertEqual(SourceDetector.sourceName(for: URL(string: "https://www.nytimes.com/a"), type: .webpage), "nytimes.com")
    }

    func testSourceDetectionFromEmailHeaders() {
        XCTAssertEqual(SourceDetector.detect(text: "From: Sam\nTo: Team\nSubject: Launch\n\nHi"), .email)
        XCTAssertEqual(SourceDetector.detect(text: "Just some text"), .text)
    }

    func testSharedTextExtractor() async throws {
        let content = try await SharedTextExtractor().extract(.sharedText("Hello there", suggestedSource: .claude))
        XCTAssertEqual(content.sourceType, .claude)
        XCTAssertEqual(content.sourceName, "Claude")
        XCTAssertEqual(content.text, "Hello there")
    }

    func testStandaloneURLDetection() {
        XCTAssertNotNil(SharedTextExtractor.standaloneURL(in: "https://example.com/a"))
        XCTAssertNil(SharedTextExtractor.standaloneURL(in: "see https://example.com/a"))
        XCTAssertNil(SharedTextExtractor.standaloneURL(in: "ftp://example.com"))
    }

    func testSafariSelectionWinsOverMessages() async throws {
        let payload = WebPagePayload(url: "https://chatgpt.com/c/1", title: "ChatGPT",
                                     selection: "This is the part I selected on purpose.",
                                     messages: ["First answer", "Second answer"], site: "chatgpt")
        let content = try await SafariMessageExtractor().extract(.webPage(payload))
        XCTAssertEqual(content.text, "This is the part I selected on purpose.")
        XCTAssertEqual(content.sourceType, .chatGPT)
    }

    func testSafariUsesFocusedMessage() async throws {
        let payload = WebPagePayload(url: "https://claude.ai/chat/1", messages: ["First", "Second", "Third"],
                                     focusIndex: 1, site: "claude")
        let content = try await SafariMessageExtractor().extract(.webPage(payload))
        XCTAssertEqual(content.text, "Second")
        XCTAssertEqual(content.sourceName, "Claude")
    }

    func testSafariFallsBackToLastMessage() async throws {
        let payload = WebPagePayload(messages: ["First", "Last"], focusIndex: -1, site: "chatgpt")
        let content = try await SafariMessageExtractor().extract(.webPage(payload))
        XCTAssertEqual(content.text, "Last")
    }

    func testWebPagePayloadFromDictionary() {
        let payload = WebPagePayload(dictionary: [
            "url": "https://reddit.com/r/a", "messages": ["one", 2, "three"], "focusIndex": NSNumber(value: 1), "site": "reddit",
        ])
        XCTAssertEqual(payload.messages, ["one", "three"])
        XCTAssertEqual(payload.focusIndex, 1)
    }

    func testGenericWebExtractorPrefersArticleAndDropsChrome() {
        let html = """
        <html><head><title>Fallback</title><meta property="og:title" content="Real Title"></head>
        <body>
          <nav>Home | About | Login</nav>
          <header>Site header</header>
          <article>
            <h1>Big News</h1>
            <p>The first paragraph has plenty of words so that it clearly counts as the main article content on the page.</p>
            <p>Second paragraph with a <a href="https://example.com/x">useful link</a> &amp; more text to push the length over the threshold.</p>
            <ul><li>Point one</li><li>Point two</li></ul>
            <pre><code class="language-python">print("hi")
        print("bye")</code></pre>
          </article>
          <footer>Copyright</footer>
          <script>var tracking = true;</script>
        </body></html>
        """
        let page = GenericWebExtractor.extract(html: html)
        XCTAssertEqual(page.title, "Real Title")
        XCTAssertTrue(page.text.contains("# Big News"))
        XCTAssertTrue(page.text.contains("[useful link](https://example.com/x) & more"))
        XCTAssertTrue(page.text.contains("- Point one"))
        XCTAssertTrue(page.text.contains("```python\nprint(\"hi\")\nprint(\"bye\")\n```"))
        XCTAssertFalse(page.text.contains("Login"))
        XCTAssertFalse(page.text.contains("Copyright"))
        XCTAssertFalse(page.text.contains("tracking"))
    }

    func testRedditJSONParsingForPost() throws {
        let json = """
        [{"data":{"children":[{"data":{"title":"My first app","selftext":"It took **18 months**.","subreddit_name_prefixed":"r/iOSProgramming"}}]}},
         {"data":{"children":[]}}]
        """
        let url = URL(string: "https://www.reddit.com/r/iOSProgramming/comments/abc123/my_first_app/")!
        let content = try RedditExtractor.parse(Data(json.utf8), url: url)
        XCTAssertEqual(content.sourceName, "r/iOSProgramming")
        XCTAssertEqual(content.title, "My first app")
        XCTAssertEqual(content.text, "My first app.\n\nIt took **18 months**.")
    }

    func testRedditJSONParsingForCommentPermalink() throws {
        let json = """
        [{"data":{"children":[{"data":{"title":"Post","selftext":"","subreddit_name_prefixed":"r/swift"}}]}},
         {"data":{"children":[{"data":{"body":"Great comment.","author":"sam"}}]}}]
        """
        let url = URL(string: "https://www.reddit.com/r/swift/comments/abc123/post/def456/")!
        let content = try RedditExtractor.parse(Data(json.utf8), url: url)
        XCTAssertEqual(content.text, "Comment by sam.\n\nGreat comment.")
    }

    func testRedditJSONURL() {
        let url = URL(string: "https://old.reddit.com/r/swift/comments/abc/title/?utm=1")!
        XCTAssertEqual(RedditExtractor.jsonURL(for: url)?.absoluteString,
                       "https://www.reddit.com/r/swift/comments/abc/title.json?raw_json=1&limit=1")
    }

    func testDeepLinkRoundTrip() {
        let id = UUID()
        XCTAssertEqual(DeepLink(url: DeepLink.listen(id: id).url), .listen(id: id))
        XCTAssertEqual(DeepLink(url: URL(string: "notchman://player")!), .player)
        XCTAssertNil(DeepLink(url: URL(string: "https://example.com")!))
        XCTAssertEqual(DeepLink(url: DeepLink.pick(file: "a.png").url), .pick(file: "a.png"))
        XCTAssertNil(DeepLink(url: URL(string: "notchman://pick?file=../secret.png")!))
    }
}
