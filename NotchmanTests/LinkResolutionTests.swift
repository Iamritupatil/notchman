import XCTest
@testable import Notchman

/// Serves canned responses so link resolution runs offline.
final class StubURLProtocol: URLProtocol {
    static var responses: [String: (Int, String)] = [:]
    static var requested: [URL] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.requested.append(url)
        let match = Self.responses.keys.filter { url.absoluteString.hasPrefix($0) }.max { $0.count < $1.count }
        let (status, body) = match.flatMap { Self.responses[$0] } ?? (404, "")
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

/// TEST D: X links resolve to the real content, or fail honestly.
final class LinkResolutionTests: XCTestCase {
    override func setUp() {
        StubURLProtocol.responses = [:]
        StubURLProtocol.requested = []
    }

    private func oEmbed(_ paragraph: String, author: String = "Jane Doe") -> String {
        let html = "<blockquote class=\\\"twitter-tweet\\\"><p lang=\\\"en\\\" dir=\\\"ltr\\\">\(paragraph)</p>&mdash; \(author) (@jane)</blockquote>"
        return #"{"author_name":"\#(author)","html":"\#(html)"}"#
    }

    func testPostThatSharesAnArticleResolvesToTheArticle() async throws {
        StubURLProtocol.responses["https://publish.twitter.com/oembed"] =
            (200, oEmbed(#"Why we left the cloud <a href=\"https://t.co/abc123\">example.com/essay</a>"#))
        let article = ExtractedContent(text: "We moved inference to our own GPUs and cut costs by 40%.", title: "Leaving the cloud",
                                       sourceType: .webpage, sourceName: "example.com", url: URL(string: "https://example.com/essay"))
        var extracted: URL?
        let resolver = URLContentResolver(session: StubURLProtocol.session,
                                          extract: { url in extracted = url; return article },
                                          expand: { url in url.host == "t.co" ? URL(string: "https://example.com/essay?utm_source=twitter")! : url })

        let content = try await resolver.resolve(URL(string: "https://x.com/jane/status/1790000000000000000?s=20")!)
        XCTAssertEqual(extracted?.absoluteString, "https://example.com/essay", "Follows the link, without tracking")
        XCTAssertEqual(content.text, article.text, "The article, not the one-line post")
        XCTAssertEqual(content.evidence, "Article linked from an X post by Jane Doe")
    }

    func testPostWithItsOwnTextIsThePost() async throws {
        let long = String(repeating: "We cut our AWS bill by 42% and kept latency flat. ", count: 5)
        StubURLProtocol.responses["https://publish.twitter.com/oembed"] =
            (200, oEmbed(#"\#(long)<a href=\"https://t.co/abc123\">example.com/details</a>"#))
        var extracted = false
        let resolver = URLContentResolver(session: StubURLProtocol.session, extract: { _ in extracted = true; throw ExtractionError.emptyContent },
                                          expand: { $0 })
        let content = try await resolver.resolve(URL(string: "https://x.com/jane/status/1790000000000000000")!)
        XCTAssertFalse(extracted)
        XCTAssertEqual(content.sourceName, "X")
        XCTAssertTrue(content.text.hasPrefix("We cut our AWS bill"))
    }

    func testXArticleIsFetchedWithItsText() async throws {
        StubURLProtocol.responses["https://api.fxtwitter.com/status/1790000000000000001"] = (200, #"""
        {"code":200,"tweet":{"text":"","author":{"name":"Jane Doe"},"article":{"title":"Three lessons from 40 services","preview_text":"Short preview","content":{"blocks":[{"type":"unstyled","text":"First, operational cost grows with every service."},{"type":"unstyled","text":"Second, latency went from 180 ms to 520 ms."}]}}}}
        """#)
        let resolver = URLContentResolver(session: StubURLProtocol.session, expand: { $0 })
        let content = try await resolver.resolve(URL(string: "https://x.com/jane/article/1790000000000000001")!)
        XCTAssertEqual(content.title, "Three lessons from 40 services")
        XCTAssertEqual(content.text, "First, operational cost grows with every service.\n\nSecond, latency went from 180 ms to 520 ms.")
        XCTAssertEqual(content.sourceName, "X Article")
    }

    func testUnreachableXArticleFailsHonestly() async {
        let resolver = URLContentResolver(session: StubURLProtocol.session, expand: { $0 })
        do {
            _ = try await resolver.resolve(URL(string: "https://x.com/i/article/1790000000000000999")!)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? URLContentResolver.ResolveError, .xArticleInaccessible)
        }
    }

    func testPostThatCantBeEmbeddedFailsHonestly() async {
        StubURLProtocol.responses["https://publish.twitter.com/oembed"] = (404, "")
        let resolver = URLContentResolver(session: StubURLProtocol.session, expand: { $0 })
        do {
            _ = try await resolver.resolve(URL(string: "https://x.com/jane/status/1790000000000000002")!)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? URLContentResolver.ResolveError, .inaccessible(site: "X", isPost: true))
        }
    }

    func testTrackingParametersAreRemoved() {
        XCTAssertEqual(URLContentResolver.withoutTracking(URL(string: "https://x.com/jane/status/1?s=20&t=abc")!).absoluteString,
                       "https://x.com/jane/status/1")
        XCTAssertEqual(URLContentResolver.withoutTracking(URL(string: "https://example.com/a?id=7&utm_source=x&fbclid=1")!).absoluteString,
                       "https://example.com/a?id=7")
    }

    func testOEmbedLinksExcludeMedia() throws {
        let json = oEmbed(#"Read this <a href=\"https://t.co/abc\">example.com/essay</a> <a href=\"https://t.co/pic\">pic.twitter.com/xyz</a>"#)
        let post = try XCTUnwrap(XPost.parse(oEmbed: Data(json.utf8)))
        XCTAssertEqual(post.links.map(\.absoluteString), ["https://t.co/abc"])
        XCTAssertTrue(post.isMostlyLink)
    }

    func testXURLShapes() {
        XCTAssertEqual(XPost.articlePostID(in: URL(string: "https://x.com/jane/article/123")!), "123")
        XCTAssertNil(XPost.articlePostID(in: URL(string: "https://x.com/i/article/123")!))
        XCTAssertTrue(XPost.isArticle(URL(string: "https://x.com/i/article/123")!))
        XCTAssertEqual(XPost.statusID(in: URL(string: "https://twitter.com/jane/status/42")!), "42")
    }
}
