import XCTest
@testable import Notchman

final class LogoStoreTests: XCTestCase {
    func testPrefersLargestAppleTouchIcon() {
        let html = """
        <head>
          <link rel="icon" href="/favicon-32.png" sizes="32x32">
          <link rel="apple-touch-icon" href="/touch-120.png" sizes="120x120">
          <link rel="apple-touch-icon" href="/touch-180.png" sizes="180x180">
          <link rel="mask-icon" href="/mask.svg">
          <link rel="stylesheet" href="/app.css">
        </head>
        """
        XCTAssertEqual(LogoStore.bestIconHref(in: html), "/touch-180.png")
    }

    func testFallsBackToPlainIcon() {
        XCTAssertEqual(LogoStore.bestIconHref(in: #"<link href="/f.ico" rel="shortcut icon">"#), "/f.ico")
        XCTAssertNil(LogoStore.bestIconHref(in: "<head></head>"))
    }

    func testAppStoreMatchIsExact() {
        let results: [[String: Any]] = [
            ["trackName": "ChatGPT Plus Helper", "artistName": "Someone"],
            ["trackName": "ChatGPT", "artistName": "OpenAI"],
        ]
        XCTAssertEqual(LogoStore.bestAppMatch(results, for: "ChatGPT", term: "ChatGPT")?["artistName"] as? String, "OpenAI")
        XCTAssertNil(LogoStore.bestAppMatch([["trackName": "Chat Assistant AI"]], for: "ChatGPT", term: "ChatGPT"))
    }

    func testAppStoreMatchHandlesSubtitlesAndBylines() {
        XCTAssertNotNil(LogoStore.bestAppMatch([["trackName": "Reddit: Community & Chat"]], for: "Reddit", term: "Reddit"))
        XCTAssertNotNil(LogoStore.bestAppMatch([["trackName": "Claude by Anthropic"]], for: "Claude", term: "Claude"))
        XCTAssertNotNil(LogoStore.bestAppMatch([["trackName": "Google Gemini"]], for: "Gemini", term: "Google Gemini"))
    }

    func testAppleAppsMustBeByApple() {
        XCTAssertNil(LogoStore.bestAppMatch([["trackName": "Messages", "artistName": "Clone Inc"]], for: "Messages", term: "Messages"))
        XCTAssertNotNil(LogoStore.bestAppMatch([["trackName": "Mail", "artistName": "Apple"]], for: "Mail", term: "Mail"))
    }

    func testCacheKeyDependsOnDomainOrName() {
        XCTAssertEqual(LogoStore.Query(name: "A", domain: "x.com").cacheKey, LogoStore.Query(name: "B", domain: "X.com").cacheKey)
        XCTAssertNotEqual(LogoStore.Query(name: "Slack").cacheKey, LogoStore.Query(name: "Discord").cacheKey)
    }
}
