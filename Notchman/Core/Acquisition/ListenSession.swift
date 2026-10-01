import Foundation
import Observation
import os

// MARK: - States

/// Where a Read or TL;DR is, from the tap until the voice is heard. The player
/// shows exactly this, so it never claims to play before audio is coming out.
enum PlaybackPreparationState: Equatable, Sendable {
    case idle
    case acquiringContent
    case resolvingURL
    /// TL;DR only: Groq is understanding and explaining the content.
    case summarizing
    /// Read only: the text is being made ready to speak (no network).
    case preparingText
    case generatingSpeech
    /// The voice is requested but no sound has come out yet.
    case buffering
    case playing
    case paused
    case failed(ListenFailure)

    /// The step's line in the player and the Dynamic Island.
    func text(for action: NotchmanAction) -> String {
        switch self {
        case .idle: ""
        case .acquiringContent: "Getting content…"
        case .resolvingURL: "Opening the link…"
        case .summarizing: action == .tldr ? "Creating TL;DR…" : "Preparing text…"
        case .preparingText: action == .tldr ? "Understanding message…" : "Preparing text…"
        case .generatingSpeech: "Generating voice…"
        case .buffering: "Buffering…"
        case .playing: "Playing"
        case .paused: "Paused"
        case .failed(let failure): failure.title
        }
    }

    /// A second line under the step, while waiting.
    func detail(for action: NotchmanAction) -> String? {
        switch self {
        case .summarizing where action == .tldr: "Finding the important parts"
        case .preparingText where action == .tldr: "Reading all of it first"
        case .resolvingURL: "Following the link to the real page"
        case .generatingSpeech, .buffering: "Your voice starts in a moment"
        default: nil
        }
    }

    var isWorking: Bool {
        switch self {
        case .acquiringContent, .resolvingURL, .summarizing, .preparingText, .generatingSpeech, .buffering: true
        default: false
        }
    }
}

/// Why a Read or TL;DR stopped, in words for the user, and what they can do next.
enum ListenFailure: Equatable, Sendable {
    /// The clipboard holds what was already played (nothing copied since).
    case nothingNew
    /// Nothing usable is on the clipboard.
    case nothingCopied
    /// Copied a while ago and never played: only used if the user says so.
    case staleCopy(since: Date)
    case tooShort
    case postInaccessible(site: String)
    case pageInaccessible
    case linkUnreadable(String)
    case summaryFailed(String)
    case voiceFailed(String)
    case limitReached(String)

    var title: String {
        switch self {
        case .nothingNew, .nothingCopied, .staleCopy: "Nothing new copied"
        case .tooShort: "That's too short to read"
        case .postInaccessible(let site): "Couldn't access this \(site) post"
        case .pageInaccessible: "Couldn't access this page"
        case .linkUnreadable: "Couldn't read that link"
        case .summaryFailed: "Couldn't create TL;DR"
        case .voiceFailed: "Voice generation failed"
        case .limitReached: "Limit reached"
        }
    }

    var message: String {
        switch self {
        case .nothingNew: "What's copied is what you last listened to. Copy something new, or play it again."
        case .nothingCopied: "Copy a message or a link, then tap TL;DR or Read."
        case .staleCopy(let since):
            "What's on the clipboard was copied before \(since.formatted(date: .omitted, time: .shortened)). Copy the message again, or use it anyway."
        case .tooShort: "Copy the whole message, then try again."
        case .postInaccessible: "It's private, deleted, or needs signing in. Copy the post's text instead."
        case .pageInaccessible: "The site wouldn't show it without signing in. Copy the text instead."
        case .linkUnreadable(let detail), .summaryFailed(let detail), .voiceFailed(let detail), .limitReached(let detail): detail
        }
    }

    /// What the main button does.
    enum Recovery: Equatable, Sendable {
        case retry, playAgain, useAnyway, none
    }

    var recovery: Recovery {
        switch self {
        case .nothingNew: .playAgain
        case .staleCopy: .useAnyway
        case .summaryFailed, .voiceFailed, .linkUnreadable: .retry
        case .nothingCopied, .tooShort, .postInaccessible, .pageInaccessible, .limitReached: .none
        }
    }

    /// Short enough for the Dynamic Island.
    var islandText: String {
        switch self {
        case .summaryFailed: "Couldn't create TL;DR — Retry in Notchman"
        case .voiceFailed: "Voice generation failed — Retry in Notchman"
        default: title
        }
    }
}

// MARK: - The tap

/// One tap on TL;DR or Read (island, Control Center, in-app). Only a tap makes
/// one; opening or switching to Notchman never does, so old clipboard content
/// is never processed just because the app came up.
struct PendingRequest: Codable, Equatable, Sendable {
    var action: NotchmanAction
    var triggeredAt: Date
    /// The clipboard's copy counter at the tap (readable without the content).
    var clipboardChange: Int
    /// Filled in once the clipboard is read.
    var clipboardHash: String?

    /// A request is only acted on right after its tap.
    static let lifetime: TimeInterval = 15

    func isLive(now: Date = Date()) -> Bool {
        now.timeIntervalSince(triggeredAt) <= Self.lifetime && now >= triggeredAt.addingTimeInterval(-1)
    }
}

/// Holds the latest tap until the app is on screen to read the clipboard.
struct PendingRequestStore {
    var defaults: UserDefaults = AppGroup.defaults
    private static let key = "pending.request"

    func save(_ request: PendingRequest) {
        if let data = try? JSONEncoder().encode(request) { defaults.set(data, forKey: Self.key) }
    }

    /// The pending request if it's still live; removed either way.
    func take(now: Date = Date()) -> PendingRequest? {
        defer { clear() }
        guard let data = defaults.data(forKey: Self.key),
              let request = try? JSONDecoder().decode(PendingRequest.self, from: data) else { return nil }
        return request.isLive(now: now) ? request : nil
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}

// MARK: - Generation cache

/// What's been made before, so the same content is never sent to Groq or
/// ElevenLabs twice. A TL;DR is reused unless the content, the action or the
/// summary version changes, or the user asks to regenerate. Voice audio is
/// kept per voice and text (`VoiceCache`), so a replay in the same voice is
/// free and a different voice makes new audio.
struct GenerationCache {
    /// Bump when the TL;DR prompt changes in a way that should replace old summaries.
    static let summaryVersion = "tldr-5"

    var defaults: UserDefaults = AppGroup.defaults
    private static let key = "generation.cache"
    private static let maxEntries = 150

    struct Entry: Codable, Equatable {
        /// `ContentHash` of the copied value (text, or the link as copied).
        var rawHash: String
        /// `ContentHash` of the text that was read or summarized.
        var textHash: String
        var action: NotchmanAction
        var summaryVersion: String
        /// The TL;DR (nil for Read).
        var summary: String?
        /// The original item, and the TL;DR item when there is one.
        var itemID: UUID?
        var summaryItemID: UUID?
        var source: String
        var resolvedURL: URL?
        var createdAt: Date
        var lastGeneratedAt: Date
    }

    /// The key for a generation, as `hash(normalizedText + action + voiceID + summaryVersion)`.
    /// Used to log and de-duplicate requests in flight.
    static func generationKey(text: String, action: NotchmanAction, voiceID: String,
                              summaryVersion: String = GenerationCache.summaryVersion) -> String {
        ContentHash.of("\(normalized(text))|\(action.rawValue)|\(voiceID)|\(summaryVersion)")
    }

    static func normalized(_ text: String) -> String {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private var entries: [Entry] {
        get { defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? [] }
        nonmutating set {
            let kept = Array(newValue.suffix(Self.maxEntries))
            if let data = try? JSONEncoder().encode(kept) { defaults.set(data, forKey: Self.key) }
        }
    }

    /// A previous result for the same copied value (skips fetching a link again).
    func entry(rawHash: String, action: NotchmanAction) -> Entry? {
        entries.last { $0.rawHash == rawHash && $0.action == action && $0.summaryVersion == Self.summaryVersion }
    }

    /// A previous result for the same text (the same message copied from elsewhere, or a link's page).
    func entry(textHash: String, action: NotchmanAction) -> Entry? {
        entries.last { $0.textHash == textHash && $0.action == action && $0.summaryVersion == Self.summaryVersion }
    }

    func save(_ entry: Entry) {
        var all = entries.filter { !($0.rawHash == entry.rawHash && $0.action == entry.action) }
        all.append(entry)
        entries = all
    }

    func removeAll() {
        defaults.removeObject(forKey: Self.key)
    }
}

// MARK: - Session

/// The Read or TL;DR in progress, for the player. It covers the steps before
/// playback (content, link, summary, voice) and failures with what to do next;
/// once audio is heard, the player follows `PlaybackManager`.
@MainActor
@Observable
final class ListenSession {
    private(set) var action: NotchmanAction = .tldr
    private(set) var stage: PlaybackPreparationState = .idle
    /// A short label for what's being prepared ("WhatsApp", "x.com").
    private(set) var sourceName: String?
    /// The item that will play, once known; the session ends when it's heard.
    private(set) var itemID: UUID?
    @ObservationIgnored private(set) var recovery: (() -> Void)?
    private let log = Logger(subsystem: "com.notchman", category: "Listen")
    /// Identifies the current request, so a late step of an old one can't change the screen.
    private(set) var requestID = UUID()
    /// Mirrors each step elsewhere (the Dynamic Island's status line).
    @ObservationIgnored var onStageChange: ((PlaybackPreparationState, NotchmanAction) -> Void)?

    var isActive: Bool { stage != .idle }

    var failure: ListenFailure? {
        if case .failed(let failure) = stage { return failure }
        return nil
    }

    @discardableResult
    func begin(_ action: NotchmanAction) -> UUID {
        self.action = action
        sourceName = nil
        itemID = nil
        recovery = nil
        requestID = UUID()
        set(.acquiringContent)
        return requestID
    }

    /// A repeated tap for what's already being prepared: show that request's steps.
    func adopt(_ requestID: UUID) {
        self.requestID = requestID
    }

    func set(_ stage: PlaybackPreparationState) {
        self.stage = stage
        onStageChange?(stage, action)
        log.info("\(self.action.rawValue, privacy: .public): \(stage.text(for: self.action), privacy: .public)")
    }

    func setSource(_ name: String?) {
        sourceName = name
    }

    /// The item is handed to playback. `generating`: its voice isn't on the
    /// iPhone yet, so ElevenLabs is making it ("Generating voice…").
    func willPlay(_ itemID: UUID, generating: Bool) {
        self.itemID = itemID
        set(generating ? .generatingSpeech : .buffering)
    }

    func fail(_ failure: ListenFailure, recovery: (() -> Void)? = nil) {
        self.recovery = recovery
        set(.failed(failure))
    }

    /// Audio is coming out: the player takes over.
    func finish() {
        recovery = nil
        stage = .idle
    }

    func cancel() {
        requestID = UUID()
        recovery = nil
        stage = .idle
    }
}
