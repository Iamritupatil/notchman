import AVFoundation
import Foundation

/// Reads any text in the ElevenLabs voice, starting within a second or two.
///
/// The text is split at sentence boundaries into pieces: a short first piece so
/// audio starts almost at once, then longer ones. Pieces are voiced by the
/// Notchman server (`/speak`) a few ahead of playback and played back to back,
/// each with its neighbours as context so the voice flows across them.
///
/// Each piece's audio is kept on the iPhone (`VoiceCache`, per item and voice),
/// so replays, seeks and skips read it from disk. Pieces are never joined into
/// one MP3: every ElevenLabs MP3 carries its own length header, and a joined
/// file reports only the first piece's length, which broke duration and seeking.
@MainActor
final class CloudVoiceEngine: NSObject, SpeechEngine, AVAudioPlayerDelegate {
    var onEvent: ((SpeechService.Event) -> Void)?

    struct Piece {
        let range: NSRange
        let text: String
    }

    let pieces: [Piece]
    let voiceID: String
    private let textLength: Int
    private let source: VoiceSource
    private let cacheKey: UUID?

    private var audio: [Int: Data] = [:]
    private var inFlight: Set<Int> = []
    private var failures: [Int: Int] = [:]
    /// Internal (not private) so tests can check seeking and speed on the real player.
    private(set) var player: AVAudioPlayer?
    private(set) var current = 0
    /// Where to start once the needed piece arrives.
    private var waiting: (index: Int, fraction: Double)?
    private var speed = 1.0
    private var isPaused = false
    private var isStopped = true
    private var timer: Timer?
    private var reportedRate = false

    /// How many pieces to voice ahead of the one playing.
    private static let lookahead = 2

    /// - Parameter cacheKey: the item's ID, so its voiced pieces are kept for replays.
    init(text: String, voiceID: String, cacheKey: UUID?, source: VoiceSource = NotchmanCloud()) {
        self.pieces = Self.split(text)
        self.textLength = (text as NSString).length
        self.voiceID = voiceID
        self.cacheKey = cacheKey
        self.source = source
    }

    // MARK: - SpeechEngine

    func speak(_ text: String, from offset: Int, configuration: SpeechConfiguration) {
        guard !pieces.isEmpty else {
            onEvent?(.finished)
            return
        }
        speed = min(max(configuration.speed, 0.5), 2.0)
        isStopped = false
        isPaused = false
        let index = pieceIndex(at: offset)
        let piece = pieces[index]
        let fraction = Double(max(0, offset - piece.range.location)) / Double(max(piece.range.length, 1))
        start(index, fraction: fraction)
    }

    func pause() -> Bool {
        isPaused = true
        player?.pause()
        stopTimer()
        return true
    }

    func resume() -> Bool {
        guard !isStopped else { return false }
        isPaused = false
        if let player {
            let started = player.play()
            if started { startTimer() }
            return started
        }
        // Still waiting for a piece; it starts playing when it arrives.
        return waiting != nil
    }

    func setSpeed(_ newSpeed: Double) -> Bool {
        speed = min(max(newSpeed, 0.5), 2.0)
        player?.rate = Float(speed)
        return true
    }

    func stop() {
        isStopped = true
        isPaused = false
        waiting = nil
        player?.stop()
        player = nil
        stopTimer()
    }

    // MARK: - Playback

    private func start(_ index: Int, fraction: Double) {
        player?.stop()
        player = nil
        stopTimer()
        current = index
        // A new start replaces any earlier wait (e.g. a second seek before the
        // first one's piece arrived).
        let wasWaiting = waiting != nil
        waiting = nil
        fetchAhead(from: index)

        guard let data = audio[index] else {
            waiting = (index, fraction)
            onEvent?(.buffering(true))
            onEvent?(.progress(pieces[index].range.location + Int(fraction * Double(pieces[index].range.length))))
            return
        }
        if wasWaiting { onEvent?(.buffering(false)) }
        guard let newPlayer = try? AVAudioPlayer(data: data), newPlayer.duration > 0 else {
            onEvent?(.failed("The voice couldn't be played."))
            return
        }
        newPlayer.delegate = self
        newPlayer.enableRate = true
        newPlayer.rate = Float(speed)
        newPlayer.prepareToPlay()
        newPlayer.currentTime = min(max(fraction, 0), 0.999) * newPlayer.duration
        player = newPlayer
        guard !isStopped, !isPaused else { return }
        newPlayer.play()
        startTimer()
        report()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finished = ObjectIdentifier(player)
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.pieceFinished(finished) }
        }
    }

    private func pieceFinished(_ finished: ObjectIdentifier) {
        // Ignore a player that was replaced by a seek before this callback ran.
        guard !isStopped, let player, ObjectIdentifier(player) == finished else { return }
        let next = current + 1
        if next < pieces.count {
            start(next, fraction: 0)
        } else {
            stopTimer()
            isStopped = true
            player = nil
            onEvent?(.progress(textLength))
            onEvent?(.finished)
        }
    }

    // MARK: - Fetching

    private func fetchAhead(from index: Int) {
        let last = min(pieces.count - 1, index + Self.lookahead)
        guard index <= last else { return }
        for i in index...last where audio[i] == nil && !inFlight.contains(i) {
            fetch(i)
        }
    }

    private func fetch(_ index: Int) {
        let piece = pieces[index]
        if let cacheKey, let cached = VoiceCache.load(item: cacheKey, voice: voiceID, piece: index, text: piece.text) {
            // Saved on the iPhone: store it without re-entering playback.
            store(cached, for: index)
            return
        }
        inFlight.insert(index)
        let previous = index > 0 ? pieces[index - 1].text : nil
        let next = index + 1 < pieces.count ? pieces[index + 1].text : nil
        let voiceID = voiceID
        let source = source
        Task {
            do {
                let data = try await source.speak(text: piece.text, previousText: previous, nextText: next, voiceID: voiceID)
                received(data, for: index, fromCache: false)
            } catch {
                failed(index, error: error)
            }
        }
    }

    /// Keeps a piece's audio and, for the first one, reports the voice's real
    /// pace so times, skips and the Live Activity timer are right from the start.
    private func store(_ data: Data, for index: Int) {
        audio[index] = data
        if !reportedRate, let clip = try? AVAudioPlayer(data: data), clip.duration > 0 {
            reportedRate = true
            onEvent?(.rate(Double(pieces[index].range.length) / clip.duration))
        }
    }

    /// A piece arrived from the network.
    private func received(_ data: Data, for index: Int, fromCache: Bool) {
        inFlight.remove(index)
        store(data, for: index)
        if !fromCache, let cacheKey {
            VoiceCache.save(data, item: cacheKey, voice: voiceID, piece: index, text: pieces[index].text)
        }

        if let waiting, waiting.index == index, !isStopped {
            start(index, fraction: waiting.fraction)
        }
        if !isStopped { fetchAhead(from: current) }
    }

    private func failed(_ index: Int, error: Error) {
        inFlight.remove(index)
        let attempts = (failures[index] ?? 0) + 1
        failures[index] = attempts
        if case CloudError.quotaExceeded = error {
            onEvent?(.failed(error.localizedDescription))
            return
        }
        if case CloudError.voiceLimit(let message) = error {
            onEvent?(.failed(message))
            return
        }
        if attempts < 3, !isStopped {
            Task {
                try? await Task.sleep(for: .milliseconds(600 * attempts))
                if !isStopped, audio[index] == nil, !inFlight.contains(index) { fetch(index) }
            }
            return
        }
        if waiting?.index == index || index == current {
            onEvent?(.failed("Notchman's voice isn't reachable right now. Check your connection and try again."))
        }
    }

    // MARK: - Progress

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
        guard let player, current < pieces.count else { return }
        let piece = pieces[current]
        let fraction = player.duration > 0 ? player.currentTime / player.duration : 0
        onEvent?(.progress(piece.range.location + Int(fraction * Double(piece.range.length))))
    }

    private func pieceIndex(at offset: Int) -> Int {
        pieces.lastIndex { $0.range.location <= offset } ?? 0
    }

    // MARK: - Splitting

    /// Sentence-aligned pieces: ~160 characters first (fast start), then ~600,
    /// then ~1,400. Each stays under the server's 2,500-character limit.
    static func split(_ text: String) -> [Piece] {
        let ns = text as NSString
        var sentences: [NSRange] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .bySentences) { _, range, enclosing, _ in
            sentences.append(enclosing.length > 0 ? enclosing : range)
        }
        if sentences.isEmpty, ns.length > 0 { sentences = [NSRange(location: 0, length: ns.length)] }

        var pieces: [Piece] = []
        var start: Int?
        var end = 0
        func target() -> Int { pieces.isEmpty ? 160 : pieces.count == 1 ? 600 : 1_400 }
        func flush() {
            guard let s = start, end > s else { return }
            let range = NSRange(location: s, length: end - s)
            let piece = ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { pieces.append(Piece(range: range, text: piece)) }
            start = nil
        }
        for sentence in sentences {
            // Very long sentences are cut at word boundaries.
            var remaining = sentence
            while remaining.length > 2_000 {
                let slice = NSRange(location: remaining.location, length: 2_000)
                let space = ns.range(of: " ", options: .backwards, range: slice)
                let cut = space.location != NSNotFound && space.location > remaining.location ? space.location : NSMaxRange(slice)
                flush()
                start = remaining.location
                end = cut
                flush()
                remaining = NSRange(location: cut, length: NSMaxRange(remaining) - cut)
            }
            if start == nil { start = remaining.location }
            end = NSMaxRange(remaining)
            if end - start! >= target() { flush() }
        }
        flush()
        return pieces
    }
}

/// Where voice audio comes from: the Notchman server in the app, a fake in tests.
protocol VoiceSource: Sendable {
    func speak(text: String, previousText: String?, nextText: String?, voiceID: String) async throws -> Data
}

extension NotchmanCloud: VoiceSource {}

/// Voiced pieces kept on the iPhone, per item and voice, so replays and seeks
/// need no network. A piece is only reused if its text is unchanged.
enum VoiceCache {
    static func directory(item: UUID) -> URL {
        ListeningItem.audioDirectory.appendingPathComponent("voice-\(item.uuidString)", isDirectory: true)
    }

    private static func url(item: UUID, voice: String, piece: Int, text: String) -> URL {
        // A stable digest (FNV-1a) of the text; Swift's Hasher changes every launch.
        let digest = text.utf8.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return directory(item: item).appendingPathComponent("\(voice)-\(piece)-\(String(digest, radix: 16)).mp3")
    }

    static func load(item: UUID, voice: String, piece: Int, text: String) -> Data? {
        try? Data(contentsOf: url(item: item, voice: voice, piece: piece, text: text))
    }

    static func save(_ data: Data, item: UUID, voice: String, piece: Int, text: String) {
        let url = url(item: item, voice: voice, piece: piece, text: text)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func remove(item: UUID) {
        try? FileManager.default.removeItem(at: directory(item: item))
    }
}
