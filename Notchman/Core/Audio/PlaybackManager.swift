import AVFoundation
import Foundation
import Observation

/// App-wide playback state and control. One instance lives in `AppEnvironment`
/// and is injected into SwiftUI, so playback survives navigation, sheets and
/// backgrounding.
///
/// Time model: the synthesizer reports character offsets, not time. Elapsed and
/// total time are derived from a characters-per-second rate that starts from a
/// stored estimate and is recalibrated from real speech while playing.
@MainActor
@Observable
final class PlaybackManager {
    struct NowPlaying: Equatable {
        let itemID: UUID
        let title: String
        let sourceName: String
        let sourceType: SourceType
        let text: String
        /// Length in UTF-16 units, matching speech offsets.
        let length: Int
        let isQuickListen: Bool
    }

    enum Status: Equatable {
        case idle, playing, paused, finished
    }

    static let skipInterval: TimeInterval = 15
    /// ElevenLabs' typical pace at 1x, until the first piece gives the real one.
    static let cloudVoiceCharactersPerSecond = 15.0

    private(set) var nowPlaying: NowPlaying?
    private(set) var status: Status = .idle
    /// Current position in `nowPlaying.text`, UTF-16 units.
    private(set) var offset: Int = 0
    private(set) var speed: Double
    /// Measured speaking rate at the current speed.
    private(set) var charactersPerSecond: Double

    var isPlaying: Bool { status == .playing }
    var isActive: Bool { nowPlaying != nil }

    var progress: Double {
        guard let length = nowPlaying?.length, length > 0 else { return 0 }
        return min(1, Double(offset) / Double(length))
    }

    /// The sentence currently being spoken, for the player's live quote.
    var currentSentence: String {
        guard let nowPlaying else { return "" }
        return SentenceLocator.sentence(at: offset, in: nowPlaying.text as NSString, ranges: sentenceRanges)
    }

    var elapsed: TimeInterval { Double(offset) / charactersPerSecond }
    var duration: TimeInterval { Double(nowPlaying?.length ?? 0) / charactersPerSecond }
    var remaining: TimeInterval { max(0, duration - elapsed) }

    private let speech: SpeechService
    /// The active engine: live speech, or a recorded clip for TL;DRs with a cloud voice.
    @ObservationIgnored private var engine: SpeechEngine
    @ObservationIgnored private var isClip = false
    /// Shows a message to the user when playback can't continue (set by AppEnvironment).
    @ObservationIgnored var onError: ((String) -> Void)?
    private let audioSession = AudioSessionController()
    private let liveActivity = LiveActivityManager()
    private let nowPlayingInfo = NowPlayingController()
    private let history: HistoryStore
    @ObservationIgnored private var voice: AVSpeechSynthesisVoice?
    @ObservationIgnored private var sentenceRanges: [NSRange] = []

    @ObservationIgnored private var calibrationAnchor: (date: Date, offset: Int)?
    @ObservationIgnored private var lastPersist = Date.distantPast
    @ObservationIgnored private var lastExternalSync = Date.distantPast
    @ObservationIgnored private var resumeAfterInterruption = false

    init(history: HistoryStore) {
        self.history = history
        let speech = SpeechService()
        self.speech = speech
        engine = speech
        let settings = AppSettings()
        speed = settings.defaultSpeed
        charactersPerSecond = ReadingEstimator.baseCharactersPerSecond() * settings.defaultSpeed
        wireUp()
    }

    // MARK: - Public controls

    /// Plays an item, resuming from its saved progress unless `fromStart`.
    /// Tapping the item that's already loaded just resumes it.
    func play(_ item: ListeningItem, fromStart: Bool = false) {
        if let current = nowPlaying, current.itemID == item.id, !fromStart, status != .finished {
            if status == .paused { resume() }
            return
        }

        persistProgress()
        let text = item.spokenText
        let length = (text as NSString).length
        guard length > 0 else { return }

        let settings = AppSettings()
        nowPlaying = NowPlaying(itemID: item.id, title: item.title, sourceName: item.source,
                                sourceType: item.sourceType, text: text, length: length,
                                isQuickListen: item.isQuickListen)
        voice = VoiceCatalog.voice(for: text, identifier: settings.voiceIdentifier, language: settings.language)
        sentenceRanges = SentenceLocator.ranges(in: text as NSString)
        speed = settings.defaultSpeed
        engine.stop()
        if let url = item.audioURL, let clip = AudioClipEngine(url: url, textLength: length) {
            // A recorded voice has an exact duration, so no rate estimation is needed.
            engine = clip
            isClip = true
            charactersPerSecond = Double(length) / clip.clipDuration * speed
        } else if NotchmanCloud.isAvailable {
            // The ElevenLabs voice, made piece by piece while it plays. Its real
            // pace arrives with the first piece (`.rate`).
            let cloudVoice = CloudVoiceEngine(text: text)
            let itemID = item.id
            cloudVoice.onComplete = { [weak self] audio in
                self?.history.attachAudio(audio, to: itemID)
            }
            engine = cloudVoice
            isClip = true
            charactersPerSecond = Self.cloudVoiceCharactersPerSecond * speed
        } else {
            engine = speech
            isClip = false
            charactersPerSecond = ReadingEstimator.baseCharactersPerSecond() * speed
        }
        engine.onEvent = { [weak self] event in self?.handleSpeech(event) }

        let restart = fromStart || item.completed || item.currentProgress >= 0.98
        let startOffset = restart ? 0 : Int(item.currentProgress * Double(length))
        item.completed = false
        item.lastPlayedAt = .now
        history.save()

        audioSession.activate()
        startSpeaking(from: startOffset)
        liveActivity.start(itemID: item.id, title: item.title, sourceName: item.source,
                           sourceSymbol: item.sourceType.symbolName, state: activityState())
    }

    func togglePlayPause() {
        switch status {
        case .playing: pause()
        case .paused, .finished: resume()
        case .idle: break
        }
    }

    func pause() {
        guard status == .playing else { return }
        engine.pause()
        status = .paused
        calibrationAnchor = nil
        persistProgress()
        syncExternal(force: true)
    }

    func resume() {
        guard let nowPlaying else { return }
        resumeAfterInterruption = false
        switch status {
        case .finished:
            audioSession.activate()
            startSpeaking(from: 0)
            liveActivity.start(itemID: nowPlaying.itemID, title: nowPlaying.title, sourceName: nowPlaying.sourceName,
                               sourceSymbol: nowPlaying.sourceType.symbolName, state: activityState())
        case .paused:
            audioSession.activate()
            if engine.resume() {
                status = .playing
                calibrationAnchor = nil
                syncExternal(force: true)
            } else {
                // The queue was torn down (seek while paused, interruption, speed change).
                startSpeaking(from: offset)
            }
        case .playing, .idle:
            break
        }
    }

    func skip(by seconds: TimeInterval) {
        seek(toOffset: offset + Int(seconds * charactersPerSecond))
    }

    func seek(toProgress fraction: Double) {
        guard let length = nowPlaying?.length else { return }
        seek(toOffset: Int(min(max(fraction, 0), 1) * Double(length)))
    }

    func seek(toTime seconds: TimeInterval) {
        seek(toOffset: Int(max(0, seconds) * charactersPerSecond))
    }

    func setSpeed(_ newSpeed: Double) {
        guard newSpeed != speed, newSpeed > 0 else { return }
        let baseRate = charactersPerSecond / speed
        speed = newSpeed
        charactersPerSecond = baseRate * newSpeed
        AppGroup.defaults.set(newSpeed, forKey: SettingsKey.defaultSpeed)

        // Utterance rate is fixed per utterance, so re-queue from the current word.
        if status == .playing {
            startSpeaking(from: offset)
        } else if status == .paused {
            engine.stop()
            syncExternal(force: true)
        }
    }

    func stop() {
        persistProgress()
        engine.stop()
        liveActivity.end()
        nowPlayingInfo.clear()
        audioSession.deactivate()
        nowPlaying = nil
        status = .idle
        offset = 0
    }

    /// Puts the resting Shiba in the Dynamic Island (needs the app in the foreground).
    /// A status line in the resting island; cleared after a few seconds.
    func showIslandHint(_ hint: String, clearAfter seconds: Double? = 6) {
        liveActivity.showHint(hint)
        guard let seconds else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, self.nowPlaying == nil || self.status == .finished else { return }
            self.liveActivity.showHint("")
        }
    }

    func showInDynamicIsland() {
        guard nowPlaying == nil else { return }
        liveActivity.rest()
    }

    /// Turns the resting Shiba on or off.
    func setRestsInDynamicIsland(_ on: Bool) {
        AppGroup.defaults.set(on, forKey: SettingsKey.restInDynamicIsland)
        if on {
            showInDynamicIsland()
        } else if nowPlaying == nil {
            liveActivity.endAll()
        }
    }

    /// Called when an item is deleted from history.
    func stopIfPlaying(itemID: UUID) {
        if nowPlaying?.itemID == itemID { stop() }
    }

    /// Saves the current position; called periodically and when backgrounding.
    func persistProgress() {
        guard let nowPlaying else { return }
        lastPersist = Date()
        history.updateProgress(id: nowPlaying.itemID, progress: progress, completed: status == .finished)
    }

    func handle(_ command: PlaybackCommand) {
        switch command {
        case .toggle: togglePlayPause()
        case .play: resume()
        case .pause: pause()
        case .skipForward: skip(by: Self.skipInterval)
        case .skipBackward: skip(by: -Self.skipInterval)
        }
    }

    // MARK: - Internals

    private func wireUp() {
        engine.onEvent = { [weak self] event in self?.handleSpeech(event) }

        audioSession.onInterruptionBegan = { [weak self] in
            guard let self, status == .playing else { return }
            resumeAfterInterruption = true
            pause()
        }
        audioSession.onInterruptionEnded = { [weak self] shouldResume in
            guard let self, resumeAfterInterruption else { return }
            resumeAfterInterruption = false
            if shouldResume { resume() }
        }
        audioSession.onOutputDeviceLost = { [weak self] in
            guard let self else { return }
            resumeAfterInterruption = false
            pause()
        }

        nowPlayingInfo.onCommand = { [weak self] command in
            guard let self else { return }
            switch command {
            case .play: resume()
            case .pause: pause()
            case .toggle: togglePlayPause()
            case .skipForward: skip(by: Self.skipInterval)
            case .skipBackward: skip(by: -Self.skipInterval)
            case .seek(let time): seek(toTime: time)
            }
        }
        nowPlayingInfo.registerCommands(skipInterval: Self.skipInterval)

        PlaybackCommandCenter.handler = { [weak self] command in self?.handle(command) }
    }

    private func startSpeaking(from startOffset: Int) {
        guard let nowPlaying else { return }
        offset = min(max(0, startOffset), nowPlaying.length)
        status = .playing
        calibrationAnchor = nil
        let configuration = SpeechConfiguration(rate: PlaybackSpeed.utteranceRate(for: speed), voice: voice, speed: speed)
        engine.speak(nowPlaying.text, from: offset, configuration: configuration)
        syncExternal(force: true)
    }

    private func seek(toOffset target: Int) {
        guard let nowPlaying else { return }
        let clamped = min(max(0, target), nowPlaying.length)
        if clamped >= nowPlaying.length {
            engine.stop()
            finish()
            return
        }
        switch status {
        case .playing:
            startSpeaking(from: clamped)
        case .paused, .finished:
            engine.stop()
            offset = clamped
            if status == .finished {
                status = .paused
                liveActivity.start(itemID: nowPlaying.itemID, title: nowPlaying.title,
                                   sourceName: nowPlaying.sourceName,
                                   sourceSymbol: nowPlaying.sourceType.symbolName, state: activityState())
            }
            persistProgress()
            syncExternal(force: true)
        case .idle:
            break
        }
    }

    private func handleSpeech(_ event: SpeechService.Event) {
        switch event {
        case .progress(let newOffset):
            guard nowPlaying != nil, status != .finished else { return }
            offset = newOffset
            calibrate()
            if Date().timeIntervalSince(lastPersist) > 5 { persistProgress() }
        case .finished:
            finish()
        case .rate(let charactersPerSecondAtOneX):
            guard charactersPerSecondAtOneX > 0 else { return }
            charactersPerSecond = charactersPerSecondAtOneX * speed
            syncExternal(force: true)
        case .failed(let message):
            guard nowPlaying != nil else { return }
            engine.stop()
            status = .paused
            persistProgress()
            syncExternal(force: true)
            onError?(message)
        }
    }

    private func finish() {
        guard let nowPlaying else { return }
        offset = nowPlaying.length
        status = .finished
        calibrationAnchor = nil
        history.updateProgress(id: nowPlaying.itemID, progress: 1, completed: true)
        lastPersist = Date()
        liveActivity.end()
        nowPlayingInfo.update(title: nowPlaying.title, source: nowPlaying.sourceName,
                              elapsed: duration, duration: duration, isPlaying: false)
        audioSession.deactivate()
    }

    /// Refines characters-per-second from real speech so displayed times,
    /// skip distances and the Live Activity timer match what the user hears.
    private func calibrate() {
        // A recorded clip's timing is exact; only live speech needs calibrating.
        guard !isClip, status == .playing else {
            calibrationAnchor = nil
            return
        }
        let now = Date()
        guard let anchor = calibrationAnchor else {
            calibrationAnchor = (now, offset)
            return
        }
        let seconds = now.timeIntervalSince(anchor.date)
        let characters = offset - anchor.offset
        guard seconds >= 5, characters > 40 else {
            if characters < 0 { calibrationAnchor = (now, offset) }
            return
        }
        let observed = Double(characters) / seconds
        let blended = charactersPerSecond * 0.6 + observed * 0.4
        charactersPerSecond = min(max(blended, 4 * speed), 40 * speed)
        calibrationAnchor = (now, offset)
        AppGroup.defaults.set(charactersPerSecond / speed, forKey: SettingsKey.calibratedCharactersPerSecond)
        syncExternal(force: false)
    }

    private func activityState() -> NotchmanActivityAttributes.ContentState {
        NotchmanActivityAttributes.ContentState(isPlaying: status == .playing, elapsed: min(elapsed, duration),
                                                duration: duration, updatedAt: Date())
    }

    /// Pushes state to the Live Activity and Now Playing. Forced on user-visible
    /// changes; otherwise throttled, since both extrapolate time on their own.
    private func syncExternal(force: Bool) {
        guard let nowPlaying else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastExternalSync) > 20 else { return }
        lastExternalSync = now
        liveActivity.update(activityState())
        nowPlayingInfo.update(title: nowPlaying.title, source: nowPlaying.sourceName,
                              elapsed: min(elapsed, duration), duration: duration, isPlaying: status == .playing)
    }
}
