import AVFoundation
import SwiftData
import XCTest
@testable import Notchman

/// A stand-in for the voice service: silent audio whose length matches how long
/// the piece would take to say (~15 characters a second), so seeking, speed and
/// timing run through the real engine and real `AVAudioPlayer`s, offline.
struct FakeVoiceSource: VoiceSource {
    var fails = false

    func speak(text: String, previousText: String?, nextText: String?, voiceID: String) async throws -> Data {
        if fails { throw CloudError.server("offline") }
        try await Task.sleep(for: .milliseconds(15))
        return try Self.silence(seconds: max(0.5, Double(text.utf16.count) / 15))
    }

    static func silence(seconds: Double) throws -> Data {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1)!
        let frames = AVAudioFrameCount(seconds * 8_000)
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
            buffer.frameLength = frames
            try file.write(from: buffer)
        } // The file is finished when it goes out of scope.
        defer { try? FileManager.default.removeItem(at: url) }
        return try Data(contentsOf: url)
    }
}

@MainActor
final class CloudPlaybackTests: XCTestCase {
    /// ~40 sentences → several pieces (160, 600, then 1,400 characters).
    private let text = (1...40).map { "Sentence number \($0) explains one more important detail about the plan." }
        .joined(separator: " ")

    /// Generous: the first test in a run also waits for the simulator's audio to start up.
    private func waitUntil(_ timeout: TimeInterval = 15, _ condition: () -> Bool,
                           file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("Timed out", file: file, line: line); return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    // MARK: - Engine

    func testSeekIntoALaterPieceStartsThere() async throws {
        let engine = CloudVoiceEngine(text: text, voiceID: CloudVoice.default.id, caches: false, source: FakeVoiceSource())
        XCTAssertGreaterThanOrEqual(engine.pieces.count, 3)
        let piece = engine.pieces[2]
        let target = piece.range.location + piece.range.length / 2

        engine.speak(text, from: target, configuration: SpeechConfiguration(rate: 0.5, voice: nil, speed: 1))
        await waitUntil { engine.player != nil }

        XCTAssertEqual(engine.current, 2)
        let player = try XCTUnwrap(engine.player)
        XCTAssertEqual(player.currentTime / player.duration, 0.5, accuracy: 0.05)
    }

    func testSpeedChangesOnThePlayingAudioWithoutRestarting() async throws {
        let engine = CloudVoiceEngine(text: text, voiceID: CloudVoice.default.id, caches: false, source: FakeVoiceSource())
        engine.speak(text, from: 0, configuration: SpeechConfiguration(rate: 0.5, voice: nil, speed: 1))
        await waitUntil { engine.player != nil }
        let player = try XCTUnwrap(engine.player)

        for speed in PlaybackSpeed.options {
            XCTAssertTrue(engine.setSpeed(speed))
            XCTAssertTrue(engine.player === player, "Changing speed must not replace the player")
            XCTAssertEqual(Double(player.rate), speed, accuracy: 0.001)
        }
    }

    func testReplayUsesSavedPiecesWithoutTheNetwork() async throws {
        let voiceA = "voiceA\(UUID().uuidString.prefix(8))"
        let voiceB = "voiceB\(UUID().uuidString.prefix(8))"
        defer { VoiceCache.remove(voice: voiceA); VoiceCache.remove(voice: voiceB) }
        let first = CloudVoiceEngine(text: text, voiceID: voiceA, source: FakeVoiceSource())
        first.speak(text, from: 0, configuration: SpeechConfiguration(rate: 0.5, voice: nil, speed: 1))
        await waitUntil { first.player != nil }
        first.stop()

        let offline = CloudVoiceEngine(text: text, voiceID: voiceA, source: FakeVoiceSource(fails: true))
        offline.speak(text, from: 0, configuration: SpeechConfiguration(rate: 0.5, voice: nil, speed: 1))
        await waitUntil { offline.player != nil }

        // A different voice is not served from the first voice's cache.
        var failed = false
        let otherVoice = CloudVoiceEngine(text: text, voiceID: voiceB, source: FakeVoiceSource(fails: true))
        otherVoice.onEvent = { if case .failed = $0 { failed = true } }
        otherVoice.speak(text, from: 0, configuration: SpeechConfiguration(rate: 0.5, voice: nil, speed: 1))
        await waitUntil(8) { failed }
    }

    /// TEST B: nothing claims to play before sound comes out.
    func testStartedIsReportedOnlyOnceSoundPlays() async throws {
        let engine = CloudVoiceEngine(text: text, voiceID: CloudVoice.default.id, caches: false, source: FakeVoiceSource())
        var events: [SpeechService.Event] = []
        engine.onEvent = { events.append($0) }
        engine.speak(text, from: 0, configuration: SpeechConfiguration(rate: 0.5, voice: nil, speed: 1))
        XCTAssertFalse(events.contains(.started), "Not before the first piece is voiced")
        await waitUntil { events.contains(.started) }
        let player = try XCTUnwrap(engine.player)
        XCTAssertTrue(player.isPlaying)
        XCTAssertGreaterThan(player.currentTime, 0)
    }

    // MARK: - PlaybackManager (the single source of truth)

    /// Kept for the whole test so saved items outlive `makeManager()`.
    private var container: ModelContainer?

    private func makeManager() throws -> (PlaybackManager, HistoryStore) {
        let container = try ModelContainer(for: ListeningItem.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        self.container = container
        let history = HistoryStore(context: container.mainContext)
        let manager = PlaybackManager(history: history)
        manager.voiceSource = FakeVoiceSource()
        return (manager, history)
    }

    private func addItem(_ history: HistoryStore) -> ListeningItem {
        history.addItem(from: ExtractedContent(text: text, title: "Plan", sourceType: .chatGPT,
                                               sourceName: "ChatGPT", url: nil),
                        options: AppSettings().textCleanerOptions)
    }

    func testSkipMovesFifteenSecondsAndTheEngineFollows() async throws {
        try XCTSkipUnless(NotchmanCloud.isAvailable, "Cloud voice isn't configured in this build")
        let (manager, history) = try makeManager()
        defer { manager.stop() }
        let item = addItem(history)
        manager.play(item, fromStart: true)
        await waitUntil { manager.isPlaying }
        let cps = manager.charactersPerSecond
        XCTAssertGreaterThan(cps, 0)

        let before = manager.offset
        manager.skip(by: 15)
        XCTAssertEqual(manager.offset, before + Int(15 * cps), accuracy: 2)
        XCTAssertTrue(manager.isPlayingOrBuffering)

        manager.skip(by: -15)
        XCTAssertEqual(manager.offset, before, accuracy: 2)

        manager.skip(by: -60) // clamps at the start
        XCTAssertEqual(manager.offset, 0)
    }

    func testSkipWhilePausedMovesAndResumesFromThere() async throws {
        try XCTSkipUnless(NotchmanCloud.isAvailable, "Cloud voice isn't configured in this build")
        let (manager, history) = try makeManager()
        defer { manager.stop() }
        manager.play(addItem(history), fromStart: true)
        await waitUntil { manager.isPlaying }
        manager.pause()
        let before = manager.offset
        manager.skip(by: 15)
        XCTAssertEqual(manager.status, .paused)
        XCTAssertGreaterThan(manager.offset, before)
        let target = manager.offset
        manager.resume()
        XCTAssertTrue(manager.isPlayingOrBuffering)
        XCTAssertEqual(manager.offset, target, accuracy: 2)
        await waitUntil { manager.isPlaying }
    }

    func testSpeedUpdatesTimeWithoutRestarting() async throws {
        try XCTSkipUnless(NotchmanCloud.isAvailable, "Cloud voice isn't configured in this build")
        let (manager, history) = try makeManager()
        defer { manager.stop() }
        manager.play(addItem(history), fromStart: true)
        await waitUntil { manager.isPlaying }
        let baseDuration = manager.duration
        let offset = manager.offset

        manager.setSpeed(2.0)
        XCTAssertEqual(manager.speed, 2.0)
        XCTAssertEqual(manager.duration, baseDuration / 2, accuracy: 0.5)
        XCTAssertEqual(manager.offset, offset, accuracy: 20, "Speed change must not jump position")
        manager.setSpeed(1.0)
    }

    /// TEST B through the manager: `.buffering` until sound, never `.playing` early.
    func testFirstPlaybackIsBufferingUntilSoundStarts() async throws {
        try XCTSkipUnless(NotchmanCloud.isAvailable, "Cloud voice isn't configured in this build")
        let (manager, history) = try makeManager()
        defer { manager.stop() }
        var audible: UUID?
        manager.onAudible = { audible = $0 }
        let item = addItem(history)
        manager.play(item, fromStart: true)
        XCTAssertEqual(manager.status, .buffering)
        XCTAssertFalse(manager.isPlaying)
        await waitUntil { manager.isPlaying }
        XCTAssertEqual(audible, item.id)
    }

    func testStopClearsEverything() async throws {
        try XCTSkipUnless(NotchmanCloud.isAvailable, "Cloud voice isn't configured in this build")
        let (manager, history) = try makeManager()
        defer { manager.stop() }
        manager.play(addItem(history), fromStart: true)
        await waitUntil { manager.isPlaying }

        PlaybackCommandCenter.send(.stop) // what the island's Stop button does
        XCTAssertNil(manager.nowPlaying)
        XCTAssertEqual(manager.status, .idle)
    }

    func testChangingVoiceIsUsedStraightAway() async throws {
        try XCTSkipUnless(NotchmanCloud.isAvailable, "Cloud voice isn't configured in this build")
        let saved = CloudVoice.selected
        defer { CloudVoice.selected = saved }
        let (manager, history) = try makeManager()
        defer { manager.stop() }
        manager.play(addItem(history), fromStart: true)
        await waitUntil { manager.isPlaying }

        let george = try XCTUnwrap(CloudVoice.all.first { $0.name == "George" })
        manager.setVoice(george)
        XCTAssertEqual(manager.voiceID, george.id)
        XCTAssertEqual(CloudVoice.selected, george)
        XCTAssertEqual(manager.status, .buffering, "Honest: the new voice isn't heard yet")
        await waitUntil { manager.isPlaying }
    }
}
