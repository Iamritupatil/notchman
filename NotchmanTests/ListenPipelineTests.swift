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
                        stages: ((PlaybackPreparationState) -> Void)? = nil,
                        resolveError: Error? = nil, cache: GenerationCache? = nil) -> ListenPipeline {
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
            onStage: { stages?($0) },
            cache: cache)
    }

    private let postURL = URL(string: "https://www.linkedin.com/posts/jane_ai-activity-7123456789012345678-abcd")!

    // TEST 3: LinkedIn link + TL;DR → fetch → summarize → the SUMMARY is spoken.
    func testTLDROfACopiedLinkFetchesThenSpeaksTheSummary() async throws {
        var summarizedInput: String?
        var stages: [PlaybackPreparationState] = []
        let prepared = try await Self.pipeline(summarized: { summarizedInput = $0 }, stages: { stages.append($0) })
            .prepare(.init(text: postURL.absoluteString, url: postURL), action: .tldr)

        XCTAssertEqual(prepared.action, .tldr, "The action must survive fetching the link")
        XCTAssertEqual(summarizedInput, Self.linkedInPost, "The fetched post is what gets summarized")
        XCTAssertEqual(prepared.spokenText, Self.summaryText, "TL;DR speaks the summary, not the whole post")
        XCTAssertEqual(prepared.content.text, Self.linkedInPost, "The original is kept for Read later")
        XCTAssertEqual(stages, [.resolvingURL, .preparingText])
        XCTAssertEqual(prepared.record.kind, .url)
        XCTAssertEqual(prepared.record.requestedAction, .tldr)
        XCTAssertEqual(prepared.record.rawHash, ContentHash.of(postURL.absoluteString))
    }

    // TEST 4: LinkedIn link + Read → fetch → the original post is spoken, no summary.
    func testReadOfACopiedLinkSpeaksTheOriginalPost() async throws {
        var summarized = false
        var stages: [PlaybackPreparationState] = []
        let prepared = try await Self.pipeline(summarized: { _ in summarized = true }, stages: { stages.append($0) })
            .prepare(.init(text: postURL.absoluteString, url: postURL), action: .read)

        XCTAssertEqual(prepared.action, .read)
        XCTAssertFalse(summarized, "Read never summarizes")
        XCTAssertNil(prepared.summary)
        XCTAssertEqual(prepared.spokenText, Self.linkedInPost)
        XCTAssertEqual(stages, [.resolvingURL, .preparingText])
    }

    // TESTS 1 & 2: copied text (WhatsApp, ChatGPT) + TL;DR → summarized directly, nothing fetched.
    func testTLDROfCopiedTextSummarizesWithoutFetching() async throws {
        let message = "[29/09/26, 10:15 PM] Ritu: The meeting moved to 6 because the client is late, bring the contract."
        var summarizedInput: String?
        var stages: [PlaybackPreparationState] = []
        let prepared = try await Self.pipeline(summarized: { summarizedInput = $0 }, stages: { stages.append($0) },
                                               resolveError: ExtractionError.emptyContent)
            .prepare(.init(text: message, url: nil), action: .tldr)

        XCTAssertEqual(stages, [.preparingText], "Text is never fetched")
        XCTAssertEqual(summarizedInput, "Ritu: The meeting moved to 6 because the client is late, bring the contract.")
        XCTAssertEqual(prepared.spokenText, Self.summaryText)
        XCTAssertEqual(prepared.content.sourceName, "WhatsApp")
        XCTAssertEqual(prepared.record.kind, .text)
    }

    // TEST F: the same text again reuses the TL;DR; Groq isn't called.
    func testDuplicateTLDRReusesTheCachedSummary() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        let cache = GenerationCache(defaults: defaults)
        let message = "The launch moves to Friday at 10am. Priya finishes screenshots by Wednesday; Sam checks India pricing."
        cache.save(GenerationCache.Entry(rawHash: "other", textHash: ContentHash.of(message), action: .tldr,
                                         summaryVersion: GenerationCache.summaryVersion, summary: "Cached TL;DR.",
                                         itemID: nil, summaryItemID: nil, source: "Copied text", resolvedURL: nil,
                                         createdAt: Date(), lastGeneratedAt: Date()))
        var calls = 0
        let prepared = try await Self.pipeline(summarized: { _ in calls += 1 }, cache: cache)
            .prepare(.init(text: message, url: nil), action: .tldr)
        XCTAssertEqual(calls, 0, "No Groq call for a TL;DR made before")
        XCTAssertTrue(prepared.summaryFromCache)
        XCTAssertEqual(prepared.spokenText, "Cached TL;DR.")

        // A new summary version makes a new TL;DR.
        var old = try XCTUnwrap(cache.entry(textHash: ContentHash.of(message), action: .tldr))
        old.summaryVersion = "tldr-0"
        cache.removeAll()
        cache.save(old)
        _ = try await Self.pipeline(summarized: { _ in calls += 1 }, cache: cache).prepare(.init(text: message, url: nil), action: .tldr)
        XCTAssertEqual(calls, 1)
    }

    func testGenerationKeyChangesWithVoiceActionAndVersion() {
        let text = "Ship on Friday."
        let base = GenerationCache.generationKey(text: text, action: .tldr, voiceID: "a")
        XCTAssertEqual(base, GenerationCache.generationKey(text: "  ship   on friday. ", action: .tldr, voiceID: "a"),
                       "Whitespace and case don't matter")
        XCTAssertNotEqual(base, GenerationCache.generationKey(text: text, action: .read, voiceID: "a"))
        XCTAssertNotEqual(base, GenerationCache.generationKey(text: text, action: .tldr, voiceID: "b"))
        XCTAssertNotEqual(base, GenerationCache.generationKey(text: text, action: .tldr, voiceID: "a", summaryVersion: "x"))
    }

    func testStageTextIsHumanAndFollowsTheAction() {
        XCTAssertEqual(PlaybackPreparationState.acquiringContent.text(for: .tldr), "Getting the message…")
        XCTAssertEqual(PlaybackPreparationState.resolvingURL.text(for: .tldr, isLink: true), "Getting the post…")
        XCTAssertEqual(PlaybackPreparationState.preparingText.text(for: .tldr), "Finding what matters…")
        XCTAssertEqual(PlaybackPreparationState.summarizing.text(for: .tldr), "Finding what matters…")
        XCTAssertEqual(PlaybackPreparationState.preparingText.text(for: .read), "Creating your audio…")
        XCTAssertEqual(PlaybackPreparationState.generatingSpeech.text(for: .read), "Creating your audio…")
        XCTAssertEqual(PlaybackPreparationState.playing.text(for: .tldr), "Playing")
    }

    /// One state for every surface: a request in progress wins, and nothing is
    /// "playing" or seekable before sound.
    func testSharedPlayerState() {
        func make(_ stage: PlaybackPreparationState, active: Bool, _ status: PlaybackManager.Status,
                  item: Bool = true, atStart: Bool = false) -> PlayerState {
            PlayerState.make(stage: stage, sessionActive: active, status: status, hasItem: item, atStart: atStart)
        }
        XCTAssertEqual(make(.generatingSpeech, active: true, .playing), .generatingVoice,
                       "The previous item playing doesn't hide the new request's step")
        XCTAssertEqual(make(.summarizing, active: true, .idle, item: false), .summarizing)
        XCTAssertEqual(make(.idle, active: false, .buffering), .buffering)
        XCTAssertFalse(PlayerState.buffering.isSeekable)
        XCTAssertTrue(PlayerState.buffering.isWorking)
        XCTAssertEqual(make(.idle, active: false, .paused, atStart: true), .ready)
        XCTAssertEqual(make(.idle, active: false, .paused), .paused)
        XCTAssertTrue(PlayerState.paused.isSeekable)
        XCTAssertEqual(make(.idle, active: false, .playing, item: false), .idle)
        XCTAssertEqual(PlayerState.buffering.text(isTLDR: true), "Buffering audio…")
        XCTAssertEqual(make(.failed(.nothingNew), active: true, .idle), .failed("Nothing new copied"))
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
