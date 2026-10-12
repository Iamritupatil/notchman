import XCTest
@testable import Notchman

/// The animated Shiba's timing: calm by default, a short wave, steady talking.
final class ShibaBuddyTests: XCTestCase {
    func testHelloWavesThenIdles() {
        XCTAssertEqual(ShibaBuddy.frame(for: .hello, at: 0), "ShibaWave1")
        XCTAssertEqual(ShibaBuddy.frame(for: .hello, at: 0.35), "ShibaWave2")
        XCTAssertEqual(ShibaBuddy.frame(for: .hello, at: 3), "ShibaIdle")
    }

    func testIdleIsMostlyStill() {
        let frames = stride(from: 0.0, to: 42.0, by: 0.1).map { ShibaBuddy.frame(for: .idle, at: $0) }
        let still = frames.filter { $0 == "ShibaIdle" }.count
        XCTAssertGreaterThan(Double(still) / Double(frames.count), 0.7, "idle should mostly sit still")
        XCTAssertTrue(frames.contains("ShibaBlink"))
        XCTAssertTrue(frames.contains("ShibaWag"))
    }

    func testTalkingAlternatesMouths() {
        XCTAssertEqual(ShibaBuddy.frame(for: .talking, at: 0.05), "ShibaTalk1")
        XCTAssertEqual(ShibaBuddy.frame(for: .talking, at: 0.25), "ShibaTalk2")
    }
}
