import AVFoundation

/// Something that can "read" text aloud and report progress as a character
/// offset: the on-device synthesizer, or a pre-rendered voice clip (ElevenLabs).
/// `PlaybackManager` drives either one the same way, so the player, Live
/// Activity, lock screen, speed and ±15 behave identically.
@MainActor
protocol SpeechEngine: AnyObject {
    var onEvent: ((SpeechService.Event) -> Void)? { get set }
    func speak(_ text: String, from offset: Int, configuration: SpeechConfiguration)
    @discardableResult func pause() -> Bool
    @discardableResult func resume() -> Bool
    func stop()
    /// Changes speed on the audio that's playing. Returns false when the engine
    /// can't (live speech bakes the rate into each utterance), so the caller
    /// re-speaks from the current position instead.
    func setSpeed(_ speed: Double) -> Bool
    /// True when the engine sends `.started` once sound is really heard (the
    /// cloud voice, whose audio arrives over the network). Others start at once.
    var reportsStart: Bool { get }
}

extension SpeechEngine {
    var reportsStart: Bool { false }
}

extension SpeechService: SpeechEngine {
    func setSpeed(_ speed: Double) -> Bool { false }
}

/// Plays a recorded voice clip (e.g. an ElevenLabs TL;DR) and maps its playback
/// position onto the clip's text, so progress, seeking and the "now reading"
/// quote work like live speech.
@MainActor
final class AudioClipEngine: NSObject, SpeechEngine, AVAudioPlayerDelegate {
    var onEvent: ((SpeechService.Event) -> Void)?

    private let player: AVAudioPlayer
    private let textLength: Int
    private var timer: Timer?
    /// After `stop()` the next `resume()` reports false so the caller re-speaks
    /// from its own offset (after a seek or speed change while paused).
    private var isStopped = true

    /// Clip length at 1x.
    var clipDuration: TimeInterval { player.duration }

    init?(url: URL, textLength: Int) {
        guard textLength > 0, let player = try? AVAudioPlayer(contentsOf: url), player.duration > 0 else { return nil }
        self.player = player
        self.textLength = textLength
        super.init()
        player.delegate = self
        player.enableRate = true
        player.prepareToPlay()
    }

    func speak(_ text: String, from offset: Int, configuration: SpeechConfiguration) {
        let fraction = min(max(Double(offset) / Double(textLength), 0), 1)
        player.currentTime = fraction * player.duration
        player.rate = Float(min(max(configuration.speed, 0.5), 2.0))
        isStopped = !player.play()
        startTimer()
        report()
    }

    func pause() -> Bool {
        player.pause()
        stopTimer()
        return true
    }

    func resume() -> Bool {
        guard !isStopped, player.currentTime < player.duration else { return false }
        let started = player.play()
        if started { startTimer() }
        return started
    }

    func stop() {
        isStopped = true
        player.stop()
        stopTimer()
    }

    func setSpeed(_ speed: Double) -> Bool {
        player.rate = Float(min(max(speed, 0.5), 2.0))
        return true
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.report() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func report() {
        let fraction = player.duration > 0 ? player.currentTime / player.duration : 0
        onEvent?(.progress(Int(fraction * Double(textLength))))
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.stopTimer()
                self.isStopped = true
                self.onEvent?(.progress(self.textLength))
                self.onEvent?(.finished)
            }
        }
    }
}
