import XCTest
@testable import Notchman

/// The animated Shiba head's timing: calm by default, a short happy hello,
/// an ear that listens, steady talking.
final class ShibaBuddyTests: XCTestCase {
    func testHelloIsHappyThenIdles() {
        XCTAssertEqual(ShibaBuddy.frame(for: .hello, at: 0), "ShibaHeadHappy")
        XCTAssertEqual(ShibaBuddy.frame(for: .hello, at: 0.45), "ShibaHeadIdle")
        XCTAssertEqual(ShibaBuddy.frame(for: .hello, at: 3), "ShibaHeadIdle")
    }

    func testIdleIsMostlyStill() {
        let frames = stride(from: 0.0, to: 42.0, by: 0.1).map { ShibaBuddy.frame(for: .idle, at: $0) }
        let still = frames.filter { $0 == "ShibaHeadIdle" }.count
        XCTAssertGreaterThan(Double(still) / Double(frames.count), 0.7, "idle should mostly sit still")
        XCTAssertTrue(frames.contains("ShibaHeadBlink"))
        XCTAssertTrue(frames.contains("ShibaHeadListen2"), "an ear twitches now and then")
    }

    func testListeningPerksAnEar() {
        XCTAssertEqual(ShibaBuddy.frame(for: .listening, at: 0.1), "ShibaHeadListen1")
        let frames = stride(from: 0.0, to: 6.0, by: 0.05).map { ShibaBuddy.frame(for: .listening, at: $0) }
        XCTAssertTrue(frames.contains("ShibaHeadListen2"))
    }

    func testTalkingAlternatesMouths() {
        XCTAssertEqual(ShibaBuddy.frame(for: .talking, at: 0.05), "ShibaHeadTalk1")
        XCTAssertEqual(ShibaBuddy.frame(for: .talking, at: 0.25), "ShibaHeadTalk2")
    }

    func testEveryFrameIsInTheAssetCatalog() {
        let moods: [ShibaBuddy.Mood] = [.idle, .hello, .listening, .talking, .thinking]
        let names = Set(moods.flatMap { mood in stride(from: 0.0, to: 20.0, by: 0.05).map { ShibaBuddy.frame(for: mood, at: $0) } })
        for name in names {
            XCTAssertNotNil(UIImage(named: name), "\(name) is missing from Assets.xcassets")
        }
    }
}
