import XCTest
@testable import Notchman

/// The Read / TL;DR pipeline, offline: the requested action must survive
/// fetching a link, and TL;DR must speak the summary, never the whole post.
@MainActor
final class ListenPipelineTests: XCTestCase {
    static let linkedInPost = """
    We shipped our AI assistant today after 14 months. Three lessons. First, talk to users every week, not every quarter. \
    Second, cut scope early: we dropped 40% of the roadmap in March and launched two months sooner. Third, measure \
    retention, not signups: our day-30 retention is 38%, and that is the number we now report to the board.
    """
    static let summaryText = "Launched after 14 months. Three lessons: weekly user calls, cut 40% of scope, track day-30 retention (38%)."

    /// A pipeline with a fake link resolver and summarizer that record their calls.
    static func pipeline(resolved: [URL]? = nil, summarized: ((String) -> Void)? = nil,
                        stages: ((ListenStage) -> Void)? = nil,
                        resolveError: Error? = nil) -> ListenPipeline {
        ListenPipeline(
            resolve: { url in
                if let resolveError { throw resolveError }
                return ExtractedContent(text: linkedInPost, title: "Post by Jane Doe", sourceType: .linkedin,
                                        sourceName: "LinkedIn", url: url, method: "link", evidence: "Link to www.linkedin.com")
            },
            summarize: { text in
                summarized?(text)
                return QuickListenService.Result(text: summaryText, audio: nil, usage: nil)
            },
            clean: { $0 },
            onStage: { stages?($0) })
    }

    private let postURL = URL(string: "https://www.linkedin.com/posts/jane_ai-activity-7123456789012345678-abcd")!

    // TEST 3: LinkedIn link + TL;DR → fetch → summarize → the SUMMARY is spoken.
    func testTLDROfACopiedLinkFetchesThenSpeaksTheSummary() async throws {
        var summarizedInput: String?
        var stages: [ListenStage] = []
        let prepared = try await Self.pipeline(summarized: { summarizedInput = $0 }, stages: { stages.append($0) })
            .prepare(.init(text: postURL.absoluteString, url: postURL), action: .tldr)

        XCTAssertEqual(prepared.action, .tldr, "The action must survive fetching the link")
        XCTAssertEqual(summarizedInput, Self.linkedInPost, "The fetched post is what gets summarized")
        XCTAssertEqual(prepared.spokenText, Self.summaryText, "TL;DR speaks the summary, not the whole post")
        XCTAssertEqual(prepared.content.text, Self.linkedInPost, "The original is kept for Read later")
        XCTAssertEqual(stages, [.fetching(.linkedin), .summarizing])
        XCTAssertEqual(prepared.record.kind, .url)
        XCTAssertEqual(prepared.record.requestedAction, .tldr)
        XCTAssertEqual(prepared.record.rawHash, ContentHash.of(postURL.absoluteString))
    }

    // TEST 4: LinkedIn link + Read → fetch → the original post is spoken, no summary.
    func testReadOfACopiedLinkSpeaksTheOriginalPost() async throws {
        var summarized = false
        var stages: [ListenStage] = []
        let prepared = try await Self.pipeline(summarized: { _ in summarized = true }, stages: { stages.append($0) })
            .prepare(.init(text: postURL.absoluteString, url: postURL), action: .read)

        XCTAssertEqual(prepared.action, .read)
        XCTAssertFalse(summarized, "Read never summarizes")
        XCTAssertNil(prepared.summary)
        XCTAssertEqual(prepared.spokenText, Self.linkedInPost)
        XCTAssertEqual(stages, [.fetching(.linkedin)])
    }

    // TESTS 1 & 2: copied text (WhatsApp, ChatGPT) + TL;DR → summarized directly, nothing fetched.
    func testTLDROfCopiedTextSummarizesWithoutFetching() async throws {
        let message = "[29/09/26, 10:15 PM] Ritu: The meeting moved to 6 because the client is late, bring the contract."
        var summarizedInput: String?
        var stages: [ListenStage] = []
        let prepared = try await Self.pipeline(summarized: { summarizedInput = $0 }, stages: { stages.append($0) },
                                               resolveError: ExtractionError.emptyContent)
            .prepare(.init(text: message, url: nil), action: .tldr)

        XCTAssertEqual(stages, [.summarizing], "Text is never fetched")
        XCTAssertEqual(summarizedInput, "Ritu: The meeting moved to 6 because the client is late, bring the contract.")
        XCTAssertEqual(prepared.spokenText, Self.summaryText)
        XCTAssertEqual(prepared.content.sourceName, "WhatsApp")
        XCTAssertEqual(prepared.record.kind, .text)
    }

    func testABlockedPostIsReportedTruthfully() async {
        let pipeline = Self.pipeline(resolveError: URLContentResolver.ResolveError.inaccessible(site: "LinkedIn", isPost: true))
        do {
            _ = try await pipeline.prepare(.init(text: postURL.absoluteString, url: postURL), action: .tldr)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Couldn't access this LinkedIn post automatically.")
        }
    }

    // MARK: - Link resolver

    func testLinkedInPostWithNoTextIsReportedAsInaccessible() async {
        let resolver = URLContentResolver(extract: { _ in throw ExtractionError.emptyContent })
        do {
            _ = try await resolver.resolve(postURL)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? URLContentResolver.ResolveError, .inaccessible(site: "LinkedIn", isPost: true))
        }
    }

    func testResolvedLinksAreMarkedAsLinks() async throws {
        let article = URL(string: "https://example.com/blog/post")!
        let resolver = URLContentResolver(extract: { url in
            ExtractedContent(text: "An article body that is long enough to read aloud.", title: "Post",
                             sourceType: .webpage, sourceName: "example.com", url: url)
        })
        let content = try await resolver.resolve(article)
        XCTAssertEqual(content.method, "link")
        XCTAssertEqual(content.evidence, "Link to example.com")
    }

    func testXPostTextFromOEmbed() throws {
        let json = #"{"author_name":"Jane Doe","html":"<blockquote class=\"twitter-tweet\"><p lang=\"en\" dir=\"ltr\">We cut our AWS bill by 42% &amp; kept latency flat.<br>Thread below <a href=\"https://t.co/x\">pic.twitter.com/x</a></p>&mdash; Jane Doe (@jane) <a href=\"https://twitter.com/jane/status/1\">May 1, 2026</a></blockquote>"}"#
        let post = try XCTUnwrap(XPost.parse(oEmbed: Data(json.utf8)))
        XCTAssertEqual(post.author, "Jane Doe")
        XCTAssertEqual(post.text, "We cut our AWS bill by 42% & kept latency flat.\nThread below pic.twitter.com/x")
        XCTAssertTrue(XPost.isPost(URL(string: "https://x.com/jane/status/1234567890")!))
        XCTAssertFalse(XPost.isPost(URL(string: "https://x.com/jane")!))
    }

    func testShortLinkInterstitialTarget() {
        let html = #"<a class="artdeco-button" data-tracking-control-name="external_url_click" href="https://www.linkedin.com/posts/jane_ai-activity-7123456789012345678-abcd">Continue</a>"#
        XCTAssertEqual(URLContentResolver.interstitialTarget(in: html)?.absoluteString,
                       "https://www.linkedin.com/posts/jane_ai-activity-7123456789012345678-abcd")
    }

    // MARK: - TL;DR prompt

    func testTLDRPromptAsksForASummaryNotARetelling() {
        let request = SummarizationPrompt.completeRequest(for: "Hello")
        XCTAssertTrue(request.hasPrefix("Summarize the following message"))
        XCTAssertTrue(request.contains("as short as possible without losing any materially important information"))
        XCTAssertTrue(request.contains("do not target a fixed duration"))
        XCTAssertFalse(request.contains("Rewrite"))
    }
}
