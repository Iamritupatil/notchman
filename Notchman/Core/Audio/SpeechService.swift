import AVFoundation

struct SpeechConfiguration {
    var rate: Float
    var voice: AVSpeechSynthesisVoice?
    /// User-facing speed multiplier (used by recorded clips).
    var speed: Double = 1
    /// Pause after each paragraph / list item.
    var paragraphPause: TimeInterval = 0.22
}

/// Thin, stateful wrapper around `AVSpeechSynthesizer`.
///
/// Text is spoken as a queue of short utterances (see `SpeechSegmenter`). The
/// service reports progress as a UTF-16 offset into the full text, which lets
/// `PlaybackManager` seek and change speed by re-queuing from any position.
@MainActor
final class SpeechService: NSObject {
    enum Event: Equatable {
        /// The synthesizer is about to speak the character at this offset.
        case progress(Int)
        /// The last utterance finished.
        case finished
    }

    var onEvent: ((Event) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var text: NSString = ""

    private struct UtteranceInfo {
        let baseOffset: Int
        let length: Int
        let isLast: Bool
    }

    /// Only utterances from the current `speak` call are tracked, so callbacks
    /// for cancelled utterances from a previous seek are ignored.
    private var tracked: [ObjectIdentifier: UtteranceInfo] = [:]

    override init() {
        super.init()
        synthesizer.delegate = self
        // Speak through our .playback / .spokenAudio session so audio continues in the background.
        synthesizer.usesApplicationAudioSession = true
        synthesizer.mixToTelephonyUplink = false
    }

    var isPaused: Bool { synthesizer.isPaused }
    var isSpeaking: Bool { synthesizer.isSpeaking && !synthesizer.isPaused }

    /// Starts speaking `fullText` from `offset` (snapped back to a word start).
    /// Any current speech is cancelled.
    func speak(_ fullText: String, from offset: Int, configuration: SpeechConfiguration) {
        cancelCurrent()

        text = fullText as NSString
        let start = SpeechSegmenter.wordStart(at: offset, in: text)
        let ranges = SpeechSegmenter.segments(in: text)
            .filter { NSMaxRange($0) > start }
            .map { range -> NSRange in
                range.location >= start ? range : NSRange(location: start, length: NSMaxRange(range) - start)
            }

        guard !ranges.isEmpty else {
            onEvent?(.finished)
            return
        }

        for (index, range) in ranges.enumerated() {
            let utterance = AVSpeechUtterance(string: text.substring(with: range))
            utterance.rate = configuration.rate
            utterance.voice = configuration.voice
            utterance.postUtteranceDelay = configuration.paragraphPause
            utterance.prefersAssistiveTechnologySettings = false
            tracked[ObjectIdentifier(utterance)] = UtteranceInfo(
                baseOffset: range.location, length: range.length, isLast: index == ranges.count - 1)
            synthesizer.speak(utterance)
        }
        onEvent?(.progress(start))
    }

    @discardableResult
    func pause() -> Bool {
        synthesizer.pauseSpeaking(at: .word)
    }

    /// Returns false when there is nothing paused to continue (e.g. the system
    /// tore down speech during an interruption); callers should re-`speak`.
    @discardableResult
    func resume() -> Bool {
        guard synthesizer.isPaused else { return false }
        return synthesizer.continueSpeaking()
    }

    func stop() {
        cancelCurrent()
    }

    private func cancelCurrent() {
        tracked.removeAll()
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    // MARK: - Delegate handling (main actor)

    fileprivate func handleWillSpeak(_ id: ObjectIdentifier, location: Int) {
        guard let info = tracked[id] else { return }
        onEvent?(.progress(info.baseOffset + location))
    }

    fileprivate func handleFinish(_ id: ObjectIdentifier) {
        guard let info = tracked.removeValue(forKey: id) else { return }
        onEvent?(.progress(info.baseOffset + info.length))
        if info.isLast {
            onEvent?(.finished)
        }
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    // AVSpeechSynthesizer calls its delegate on an internal queue. Hop to the
    // main queue in FIFO order so progress events are never reordered.

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        let location = characterRange.location
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.handleWillSpeak(id, location: location) }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.handleFinish(id) }
        }
    }
}
