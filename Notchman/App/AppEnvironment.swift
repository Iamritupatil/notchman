import Foundation
import Observation
import os
import SwiftData
import UIKit

/// Composition root: owns the long-lived services and the ingest flow that
/// every entry point (Share, Safari, Shortcuts, developer screen) funnels into.
@MainActor
@Observable
final class AppEnvironment {
    static let shared = AppEnvironment()

    let modelContainer: ModelContainer
    let history: HistoryStore
    let playback: PlaybackManager
    let router = AppRouter()
    let account = AccountStore()
    let premium = PremiumStore()

    private init() {
        // SwiftData expects Application Support to exist on first launch.
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

        let container: ModelContainer
        do {
            container = try ModelContainer(for: ListeningItem.self)
        } catch {
            // Never block launch on storage; fall back to an in-memory store.
            Logger(subsystem: "com.notchman", category: "Storage")
                .error("Persistent store failed, using memory: \(error.localizedDescription, privacy: .public)")
            container = try! ModelContainer(for: ListeningItem.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        modelContainer = container
        history = HistoryStore(context: container.mainContext)
        playback = PlaybackManager(history: history)
        playback.onError = { [weak self] message in
            self?.playbackFailed(message)
        }
        playback.onAudible = { [weak self] itemID in
            guard let self, session.itemID == itemID else { return }
            session.finish()
            playback.showIslandHint("", clearAfter: nil)
        }
        session.onStageChange = { [weak self] stage, action in
            guard let self else { return }
            switch stage {
            case .idle, .playing, .paused: break
            case .failed(let failure): playback.showIslandHint(failure.islandText, clearAfter: 10)
            default: playback.showIslandHint(stage.text(for: action), clearAfter: 40)
            }
        }
        VoiceCache.prune()
    }

    // MARK: - Ingest

    /// Saves content to history and performs the requested action.
    func ingest(_ content: ExtractedContent, action: PendingListen.Action) {
        let item = history.addItem(from: content, options: AppSettings().textCleanerOptions)
        switch action {
        case .read: listen(to: item)
        case .quickListen: quickListen(to: item)
        case .review: router.sheet = .review(item.id)
        }
    }

    /// Picks up anything the Share or Safari extension left in the shared inbox.
    /// The preferred (or newest) item is acted on; older ones are just saved.
    func processInbox(preferring id: UUID? = nil) {
        processCaptures()
        let pending = SharedInbox.drain()
        guard let primary = pending.first(where: { $0.id == id }) ?? pending.last else { return }
        let options = AppSettings().textCleanerOptions
        for item in pending where item.id != primary.id {
            history.addItem(from: item.content, options: options)
        }
        ingest(primary.content, action: primary.action)
    }

    /// Screenshots the Share Extension couldn't hand over directly: open the
    /// newest recent one in the picker, discard the rest.
    private func processCaptures() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: DeepLink.capturesDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let dated = files.compactMap { url -> (URL, Date)? in
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return date.map { (url, $0) }
        }.sorted { $0.1 > $1.1 }
        for (index, entry) in dated.enumerated() {
            defer { try? FileManager.default.removeItem(at: entry.0) }
            if index == 0, entry.1.timeIntervalSinceNow > -600, let data = try? Data(contentsOf: entry.0) {
                presentPicker(imageData: data)
            }
        }
    }

    func handle(url: URL) {
        guard let link = DeepLink(url: url) else { return }
        switch link {
        case .listen(let id):
            processInbox(preferring: id)
        case .pick(let file):
            let url = DeepLink.capturesDirectory.appendingPathComponent(file)
            if let data = try? Data(contentsOf: url) {
                try? FileManager.default.removeItem(at: url)
                presentPicker(imageData: data)
            }
        case .player:
            if playback.isActive { router.sheet = .player }
        case .tldrClipboard:
            requestFromTap(.tldr)
        case .readClipboard:
            requestFromTap(.read)
        case .home:
            processInbox()
        }
    }

    // MARK: - Actions used by views

    func listen(to item: ListeningItem, fromStart: Bool = false) {
        playback.play(item, fromStart: fromStart)
        // Started from the island (app in the background): everything stays in
        // the island; the app's screens are never touched.
        if UIApplication.shared.applicationState == .active {
            router.sheet = .player
        }
    }

    /// Plays the full text. From a Quick Listen item this switches to the original.
    func readFull(_ item: ListeningItem) {
        guard item.isQuickListen else {
            listen(to: item, fromStart: true)
            return
        }
        let content = ExtractedContent(text: item.originalText, title: nil, sourceType: item.sourceType,
                                       sourceName: item.source, url: item.url.flatMap(URL.init(string:)))
        let full = history.addItem(from: content, options: AppSettings().textCleanerOptions)
        listen(to: full, fromStart: true)
    }

    /// This month's TL;DR allowance; nil until first known.
    var usage: CloudUsage?

    /// Pro or Pro+ is active (and paid plans are switched on in this build).
    var isPaid: Bool { FeatureFlags.paidPlans && premium.isPremium }

    /// TL;DR of an item already in Notchman (history, the player, a share).
    /// The player opens at once and shows each step.
    func quickListen(to item: ListeningItem) {
        guard !router.isPreparingQuickListen else { return }
        router.isPreparingQuickListen = true
        let requestID = session.begin(.tldr)
        session.setSource(item.source)
        router.sheet = .player
        Task {
            defer { router.isPreparingQuickListen = false }
            do {
                session.set(.preparingText)
                try await playTLDR(of: item, requestID: requestID)
            } catch CloudError.quotaExceeded(let usage) {
                self.usage = usage
                session.cancel()
                router.alert = outOfTLDRsAlert(usage)
            } catch {
                guard session.requestID == requestID else { return }
                session.fail(Self.failure(for: error)) { [weak self] in self?.quickListen(to: item) }
            }
        }
    }

    // MARK: - Privacy notice

    /// Shown once, when the app is opened, to explain where message text goes
    /// (Groq for summaries, ElevenLabs for the voice). It never blocks
    /// listening, and the island never asks for it.
    func showPrivacyNoticeIfNeeded() {
        guard NotchmanCloud.isAvailable, !VoiceConsent.hasSeenNotice, router.sheet == nil else { return }
        router.sheet = .voiceConsent
    }

    func voiceConsentAnswered(_ granted: Bool) {
        VoiceConsent.hasSeenNotice = true
        router.sheet = nil
    }

    /// Makes the TL;DR (or reuses the one made before for the same text) and
    /// starts playing it. Used directly by intents that run in the background.
    func playTLDR(of item: ListeningItem, requestID: UUID? = nil) async throws {
        let textHash = ContentHash.of(item.originalText)
        let cached = generations.entry(textHash: textHash, action: .tldr)
        if let cached, let quick = cached.summaryItemID.flatMap(history.item(id:)) {
            log.info("TL;DR cache hit: no Groq call")
            play(quick, generatingFor: requestID)
            return
        }
        let summary: String
        if let text = cached?.summary {
            log.info("TL;DR summary cache hit: no Groq call")
            summary = text
        } else {
            let source = TextCleaner(options: AppSettings().textCleanerOptions).clean(item.originalText)
            let next = Task { @MainActor [weak self] in
                try await Task.sleep(for: .seconds(source.split(whereSeparator: \.isWhitespace).count > 160 ? 4 : 1.5))
                if let self, requestID == nil || self.session.requestID == requestID { self.session.set(.summarizing) }
            }
            defer { next.cancel() }
            let result = try await QuickListenService(isPaid: isPaid).spokenSummary(of: source)
            if let usage = result.usage { self.usage = usage }
            summary = result.text
        }
        if let requestID, session.requestID != requestID { return }
        let quick = history.addQuickListen(for: item, summary: summary)
        generations.save(GenerationCache.Entry(
            rawHash: textHash, textHash: textHash, action: .tldr, summaryVersion: GenerationCache.summaryVersion,
            summary: summary, itemID: item.id, summaryItemID: quick.id, source: item.source,
            resolvedURL: item.url.flatMap(URL.init(string:)), createdAt: cached?.createdAt ?? Date(), lastGeneratedAt: Date()))
        play(quick, generatingFor: requestID)
    }

    /// Hands an item to playback, telling the session whether its voice still
    /// has to be made (ElevenLabs) or is already on the iPhone.
    private func play(_ item: ListeningItem, generatingFor requestID: UUID?) {
        if let requestID, session.requestID == requestID {
            session.willPlay(item.id, generating: !voiceIsSaved(for: item))
        }
        listen(to: item, fromStart: true)
    }

    /// Whether every piece of this item's voice, in the chosen voice, is on the iPhone.
    func voiceIsSaved(for item: ListeningItem) -> Bool {
        guard NotchmanCloud.isAvailable else { return true }
        let voice = CloudVoice.selected.id
        return CloudVoiceEngine.split(item.spokenText).allSatisfy { VoiceCache.contains(voice: voice, text: $0.text) }
    }

    /// One press from any app: reads the screenshot, picks the main message
    /// (Apple Intelligence, or the longest), and plays its TL;DR, all without
    /// opening Notchman. The Dynamic Island shows the player.
    func tldrScreenInBackground(imageData: Data) async throws {
        let content = try await Self.mainMessage(inScreenshot: imageData)
        let item = history.addItem(from: content, options: AppSettings().textCleanerOptions)
        try await playTLDR(of: item)
        await playback.waitUntilAudible(timeout: 25)
    }

    /// Reads a screenshot on device and returns its main message (Apple
    /// Intelligence's pick, or the longest), labelled with the app it came from.
    static func mainMessage(inScreenshot imageData: Data) async throws -> ExtractedContent {
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
            throw ScreenTLDRError.unreadable
        }
        let lines = try await ScreenTextReader.lines(in: cgImage)
        let blocks = MessageBlockDetector.blocks(from: lines)
        guard let pick = await MessageChooser.choose(from: blocks) ?? MessageBlockDetector.defaultBlock(in: blocks) else {
            throw ScreenTLDRError.noMessage
        }
        let source = MessageBlockDetector.guessSource(from: lines)
        return ExtractedContent(text: pick.text, title: nil, sourceType: source,
                                sourceName: source == .text ? "Screenshot" : source.displayName, url: nil)
    }

    // MARK: - Read / TL;DR from a tap (island, Control Center, Home) and shortcuts

    let acquisition = ContentAcquisitionManager()
    /// The Read or TL;DR being prepared, shown by the player.
    let session = ListenSession()
    let generations = GenerationCache()
    private let log = Logger(subsystem: "com.notchman", category: "Listen")
    /// Copied values (and actions) being prepared now, with their request: a
    /// second tap on the same one follows the first instead of starting again.
    @ObservationIgnored private var inFlight: [String: UUID] = [:]

    /// The pipeline every Read / TL;DR goes through; its steps show in the
    /// player and the island. Steps of a superseded request are ignored.
    private func listenPipeline(for requestID: UUID) -> ListenPipeline {
        let paid = isPaid
        return ListenPipeline(
            resolve: { try await URLContentResolver().resolve($0) },
            summarize: { text in try await QuickListenService(isPaid: paid).spokenSummary(of: text) },
            clean: { TextCleaner(options: AppSettings().textCleanerOptions).clean($0) },
            onStage: { [weak self] stage in
                guard let self, session.requestID == requestID else { return }
                session.set(stage)
            },
            cache: generations)
    }

    /// A tap on TL;DR or Read (the island's buttons, Control Center, Home).
    /// Opens the player at once, then reads the clipboard: iOS shows it only
    /// to the app on screen, so this is the moment it can be read. Only a tap
    /// does this; opening or returning to Notchman never processes the clipboard.
    func requestFromTap(_ action: NotchmanAction) {
        let request = PendingRequest(action: action, triggeredAt: Date(), clipboardChange: acquisition.pasteboard.changeCount)
        acquisition.pending.save(request)
        session.begin(action)
        router.sheet = .player
        Task { await processPendingRequest() }
    }

    private func processPendingRequest() async {
        // The link can arrive a moment before Notchman is fully on screen.
        for _ in 0..<30 where UIApplication.shared.applicationState != .active {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let request = acquisition.pending.take() else {
            session.cancel()
            return
        }
        log.info("Tap: \(request.action.rawValue, privacy: .public), copy #\(request.clipboardChange)")
        let isForeground = UIApplication.shared.applicationState == .active
        switch acquisition.acquireClipboard(isForeground: isForeground) {
        case .new(let clip, let change):
            await run(clip, action: request.action, clipboardChange: change)
        case .current(let record):
            // Nothing copied since it was played: never made again automatically.
            log.info("Nothing new copied; offering to play again")
            session.fail(.nothingNew) { [weak self] in
                Task { await self?.playAgain(record, action: request.action) }
            }
        case .staleClipboard(let since):
            log.info("Stale clipboard; not processed")
            session.fail(.staleCopy(since: since)) { [weak self] in
                Task { await self?.useClipboardAnyway(request.action) }
            }
        case .nothing, .hiddenByIOS:
            session.fail(.nothingCopied)
        }
    }

    /// The user chose to use what's on the clipboard although it's old.
    private func useClipboardAnyway(_ action: NotchmanAction) async {
        session.begin(action)
        guard let clip = ClipboardReader.read(acquisition.pasteboard) else {
            session.fail(.nothingCopied)
            return
        }
        await run(clip, action: action, clipboardChange: acquisition.pasteboard.changeCount)
    }

    /// Read or TL;DR of text or a link handed over directly: the "Read with
    /// Notchman" / "TL;DR with Notchman" shortcut actions, with Text set to
    /// Shortcuts' Clipboard. Runs in the background; the app never opens.
    func runProvidedAction(_ action: NotchmanAction, text: String) async {
        ShortcutSetup.hasRun = true
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let clip = ClipboardReader.Contents(text: trimmed, url: SharedTextExtractor.standaloneURL(in: trimmed))
        session.begin(action)
        guard !trimmed.isEmpty else {
            session.fail(.nothingCopied)
            return
        }
        guard trimmed.count >= 40 || clip.url != nil else {
            session.fail(.tooShort)
            return
        }
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "listen") {}
        defer { UIApplication.shared.endBackgroundTask(backgroundTask) }
        await run(clip, action: action, clipboardChange: nil)
    }

    /// New content: fetch (links), summarize (TL;DR only), voice, play. Each
    /// step reuses what was made before for the same content, so nothing is
    /// sent to Groq or ElevenLabs twice.
    private func run(_ clip: ClipboardReader.Contents, action: NotchmanAction, clipboardChange: Int?) async {
        let requestID = session.requestID
        let rawHash = ContentHash.of(clip.text)
        let flight = "\(action.rawValue)|\(rawHash)"
        if let running = inFlight[flight] {
            log.info("Same request already in progress; following it")
            session.adopt(running)
            return
        }
        inFlight[flight] = requestID
        defer { inFlight[flight] = nil }

        // The same copied value made before (also skips fetching a link again).
        if let entry = generations.entry(rawHash: rawHash, action: action),
           let item = (action == .tldr ? entry.summaryItemID : entry.itemID).flatMap(history.item(id:)) {
            log.info("Cache hit for \(action.rawValue, privacy: .public): no fetch, no Groq call")
            session.setSource(entry.source)
            let record = ContentRecord(rawHash: rawHash, kind: clip.url == nil ? .text : .url, detectedAt: Date(),
                                       consumedAt: nil, source: entry.source, resolvedURL: entry.resolvedURL,
                                       resolvedTextHash: entry.textHash, requestedAction: action,
                                       itemID: entry.itemID, summaryItemID: entry.summaryItemID)
            await start(item, record: record, requestID: requestID, clipboardChange: clipboardChange)
            return
        }

        do {
            let prepared = try await listenPipeline(for: requestID).prepare(clip, action: action)
            guard session.requestID == requestID else { return }
            var record = prepared.record
            session.setSource(prepared.content.sourceName)
            let item = history.addItem(from: prepared.content, options: AppSettings().textCleanerOptions)
            record.itemID = item.id
            var toPlay = item
            if action == .tldr, let summary = prepared.summary {
                if let usage = summary.usage { self.usage = usage }
                let earlier = prepared.summaryFromCache
                    ? generations.entry(textHash: record.resolvedTextHash ?? "", action: .tldr)?.summaryItemID.flatMap(history.item(id:))
                    : nil
                let quick = earlier ?? history.addQuickListen(for: item, summary: summary.text)
                record.summaryItemID = quick.id
                toPlay = quick
            }
            generations.save(GenerationCache.Entry(
                rawHash: rawHash, textHash: record.resolvedTextHash ?? ContentHash.of(prepared.content.text),
                action: action, summaryVersion: GenerationCache.summaryVersion, summary: prepared.summary?.text,
                itemID: item.id, summaryItemID: record.summaryItemID, source: record.source,
                resolvedURL: record.resolvedURL, createdAt: Date(), lastGeneratedAt: Date()))
            await start(toPlay, record: record, requestID: requestID, clipboardChange: clipboardChange)
        } catch CloudError.quotaExceeded(let usage) {
            self.usage = usage
            guard session.requestID == requestID else { return }
            session.fail(.limitReached("You've used today's TL;DRs. They reset tomorrow."))
        } catch {
            guard session.requestID == requestID else { return }
            log.error("\(action.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            session.fail(Self.failure(for: error)) { [weak self] in
                guard let self else { return }
                session.begin(action)
                Task { await self.run(clip, action: action, clipboardChange: clipboardChange) }
            }
        }
    }

    /// Plays a prepared item and, once it's really heard, makes it the current content.
    private func start(_ item: ListeningItem, record: ContentRecord, requestID: UUID, clipboardChange: Int?) async {
        guard session.requestID == requestID else { return }
        let voice = CloudVoice.selected
        log.info("Generation \(GenerationCache.generationKey(text: item.spokenText, action: record.requestedAction, voiceID: voice.id), privacy: .public) · voice \(voice.name, privacy: .public) (\(voice.id, privacy: .public))")
        play(item, generatingFor: requestID)
        await playback.waitUntilAudible(timeout: PlaybackManager.bufferingTimeout + 1)
        guard playback.isPlaying, playback.nowPlaying?.itemID == item.id else { return }
        var used = record
        used.consumedAt = Date()
        acquisition.markUsed(used, clipboardChange: clipboardChange)
    }

    /// "Play again" for what was last played: from the iPhone's saved copy
    /// when there is one (no Groq or ElevenLabs call for the same voice).
    private func playAgain(_ record: ContentRecord, action: NotchmanAction) async {
        let requestID = session.begin(action)
        session.setSource(record.source)
        let original = record.itemID.flatMap(history.item(id:))
        switch action {
        case .read:
            guard let original else { return session.fail(.nothingCopied) }
            play(original, generatingFor: requestID)
        case .tldr:
            if let summary = record.summaryItemID.flatMap(history.item(id:)) {
                play(summary, generatingFor: requestID)
            } else if let original {
                do {
                    session.set(.preparingText)
                    try await playTLDR(of: original, requestID: requestID)
                } catch {
                    guard session.requestID == requestID else { return }
                    session.fail(Self.failure(for: error)) { [weak self] in
                        Task { await self?.playAgain(record, action: action) }
                    }
                }
            } else {
                session.fail(.nothingCopied)
            }
        }
    }

    /// Playback stopped with an error (usually the voice).
    private func playbackFailed(_ message: String) {
        guard let nowPlaying = playback.nowPlaying else { return }
        let failure: ListenFailure = message.contains("used up") || message.contains("needs Pro")
            ? .limitReached(message) : .voiceFailed(message)
        if UIApplication.shared.applicationState == .active {
            if !session.isActive || session.itemID != nowPlaying.itemID {
                session.begin(nowPlaying.isQuickListen ? .tldr : .read)
            }
            let itemID = nowPlaying.itemID
            session.fail(failure) { [weak self] in
                guard let self else { return }
                session.willPlay(itemID, generating: true)
                playback.resume()
            }
            router.sheet = .player
        } else {
            playback.showIslandHint(failure.islandText)
        }
    }

    /// What the user sees for an error from fetching, summarizing or voicing.
    static func failure(for error: Error) -> ListenFailure {
        switch error {
        case CloudError.voiceLimit(let message):
            return .limitReached(message)
        case QuickListenService.SummaryError.failed(let message):
            return .summaryFailed(message)
        case URLContentResolver.ResolveError.inaccessible(let site, let isPost):
            return isPost ? .postInaccessible(site: site) : .pageInaccessible
        case let error as URLContentResolver.ResolveError:
            return .linkUnreadable(error.localizedDescription)
        case ExtractionError.emptyContent:
            return .linkUnreadable("That link has no readable text.")
        case ExtractionError.network:
            return .linkUnreadable("Couldn't load that link. Check your connection and retry.")
        case ExtractionError.loginRequired(let site):
            return .postInaccessible(site: site)
        default:
            return .summaryFailed(error.localizedDescription)
        }
    }

    enum ScreenTLDRError: LocalizedError {
        case unreadable, noMessage
        var errorDescription: String? {
            switch self {
            case .unreadable: "That screenshot couldn't be read."
            case .noMessage: "No long message on this screen."
            }
        }
    }

    private func outOfTLDRsAlert(_ usage: CloudUsage) -> AppAlert {
        let canUpgrade = FeatureFlags.paidPlans && usage.plan != "proplus"
        let resets = FreeAllowance().resetDate().formatted(.dateTime.month(.wide).day())
        let next = canUpgrade
            ? "Upgrade for more, or listen to the full message."
            : "More arrive on \(resets). You can still listen to the full message."
        return AppAlert(title: "Out of TL;DRs",
                        message: "You've used all \(usage.limit) TL;DRs in your \(usage.planName) plan this month. \(next)",
                        showsUpgradeButton: canUpgrade)
    }

    /// Refreshes the allowance shown in Settings and History.
    func refreshUsage() async {
        guard isPaid, FeatureFlags.cloudTLDR else {
            usage = isPaid ? nil : FreeAllowance().usage()
            return
        }
        if let usage = try? await NotchmanCloud().usage() {
            self.usage = usage
        }
    }

    /// Starts the "which message?" flow for a captured screen (Back Tap, Action
    /// button or a shared screenshot).
    func presentPicker(imageData: Data) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-\(UUID().uuidString).png")
        do {
            try imageData.write(to: url)
            router.sheet = .screenPicker(url)
        } catch {
            router.alert = AppAlert(title: "Couldn't open screenshot", message: error.localizedDescription)
        }
    }

    func delete(_ item: ListeningItem) {
        playback.stopIfPlaying(itemID: item.id)
        history.delete(item)
    }
}
