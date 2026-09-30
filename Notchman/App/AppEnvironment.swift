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
            guard let self else { return }
            if UIApplication.shared.applicationState == .active {
                self.router.alert = AppAlert(title: "Couldn't play", message: message)
            } else {
                self.playback.showIslandHint(message)
            }
        }
        IslandActionCenter.handler = { [weak self] action in
            await self?.runIslandAction(action)
        }
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
            acquisition.pending.clear()
            Task { await runIslandAction(.tldr) }
        case .readClipboard:
            acquisition.pending.clear()
            Task { await runIslandAction(.read) }
        case .home:
            processInbox()
        }
    }

    /// TL;DR of the text or link on the clipboard: copy a long message in any
    /// app, then press the Action button or the Control Center control.
    func tldrCopiedText(action: PendingListen.Action = .quickListen) {
        let pasteboard = UIPasteboard.general
        let copied = (pasteboard.string ?? pasteboard.url?.absoluteString ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard copied.count >= 40 else {
            router.alert = AppAlert(
                title: "Nothing copied",
                message: "No copying needed: press the Action Button (or double-tap the back of your iPhone) on a long message, or use Share → Notchman. Set it up on Home → One press, any app.")
            return
        }
        Task {
            do {
                let content = try await ContentExtractionPipeline.standard.extract(.sharedText(copied))
                ingest(content, action: action)
            } catch {
                router.alert = AppAlert(title: "TL;DR", message: error.localizedDescription)
            }
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

    func quickListen(to item: ListeningItem) {
        guard !router.isPreparingQuickListen else { return }
        router.isPreparingQuickListen = true
        Task {
            defer { router.isPreparingQuickListen = false }
            do {
                try await playTLDR(of: item)
            } catch CloudError.quotaExceeded(let usage) {
                self.usage = usage
                router.alert = outOfTLDRsAlert(usage)
            } catch {
                router.alert = AppAlert(title: "TL;DR", message: error.localizedDescription)
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

    /// Makes the TL;DR and starts playing it; returns once audio has started.
    /// Used directly by intents that run in the background.
    func playTLDR(of item: ListeningItem) async throws {
        let source = TextCleaner(options: AppSettings().textCleanerOptions).clean(item.originalText)
        let result = try await QuickListenService(isPaid: isPaid).spokenSummary(of: source)
        if let usage = result.usage { self.usage = usage }
        let quick = history.addQuickListen(for: item, summary: result.text, audio: result.audio)
        listen(to: quick, fromStart: true)
        // Any cloud problem is kept for Settings → Check Cloud (developer
        // option); users just hear the TL;DR.
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

    // MARK: - Read / TL;DR from the island and shortcuts

    let acquisition = ContentAcquisitionManager()
    @ObservationIgnored private var isRunningAction = false

    /// The pipeline every Read / TL;DR goes through. Island messages follow
    /// its steps: Getting content… → Fetching post… → Summarizing… → Generating voice….
    private var listenPipeline: ListenPipeline {
        let paid = isPaid
        return ListenPipeline(
            resolve: { try await URLContentResolver().resolve($0) },
            summarize: { text in try await QuickListenService(isPaid: paid).spokenSummary(of: text) },
            clean: { TextCleaner(options: AppSettings().textCleanerOptions).clean($0) },
            onStage: { [weak self] stage in self?.playback.showIslandHint(stage.islandText, clearAfter: 30) })
    }

    /// Read or TL;DR from the Dynamic Island. Runs inside the island's intent
    /// (not on app launch or foregrounding) and never opens the app.
    ///
    /// iOS shows the clipboard only to the app on screen. When Notchman is in
    /// the background, the clipboard comes back empty: the island says so
    /// truthfully and remembers the action, and the Back Tap / Action Button
    /// shortcut (Shortcuts reads the clipboard and hands it over) is the way to
    /// stay in the other app.
    func runIslandAction(_ action: NotchmanAction) async {
        guard !isRunningAction else { return }
        isRunningAction = true
        defer { isRunningAction = false }
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "listen") {}
        defer { UIApplication.shared.endBackgroundTask(backgroundTask) }

        let isForeground = UIApplication.shared.applicationState == .active
        if isForeground { acquisition.pending.clear() }
        playback.showIslandHint(ListenStage.gettingContent.islandText, clearAfter: 30)

        switch acquisition.acquireClipboard(isForeground: isForeground) {
        case .new(let clip, let change):
            await run(clip, action: action, clipboardChange: change)
        case .current(let record):
            await replay(record, action: action)
        case .staleClipboard:
            playback.showIslandHint("What's copied is from earlier. Copy the message again.")
        case .nothing:
            playback.showIslandHint("Copy a message or link first, then tap \(action == .tldr ? "TL;DR" : "Read").")
        case .hiddenByIOS:
            acquisition.pending.save(action)
            playback.showIslandHint(ShortcutSetup.hasRun
                ? "iOS hides the clipboard from the island. Use your Notchman Back Tap or Action Button."
                : "iOS hides the clipboard from the island. Set up Back Tap once (Notchman → Home).",
                clearAfter: 12)
        }
    }

    /// Read or TL;DR of text or a link handed over directly: the "Read with
    /// Notchman" / "TL;DR with Notchman" shortcut actions, with Text set to
    /// Shortcuts' Clipboard (Back Tap, Action Button, Control Center). Runs in
    /// the background; the app never opens.
    func runProvidedAction(_ action: NotchmanAction, text: String) async {
        ShortcutSetup.hasRun = true
        guard !isRunningAction else { return }
        isRunningAction = true
        defer { isRunningAction = false }
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "listen") {}
        defer { UIApplication.shared.endBackgroundTask(backgroundTask) }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            playback.showIslandHint("Copy a message or link first.")
            return
        }
        let clip = ClipboardReader.Contents(text: trimmed, url: SharedTextExtractor.standaloneURL(in: trimmed))
        if let current = acquisition.records.current, current.rawHash == ContentHash.of(trimmed) {
            await replay(current, action: action)
            return
        }
        guard trimmed.count >= 40 || clip.url != nil else {
            playback.showIslandHint("That's too short to read. Copy the whole message.")
            return
        }
        await run(clip, action: action, clipboardChange: nil)
    }

    /// Finishes an island action iOS blocked, once Notchman is on screen.
    func runPendingActionIfAny() {
        guard let action = acquisition.pending.take() else { return }
        Task { await runIslandAction(action) }
    }

    /// New content: fetch (links), summarize (TL;DR only), then play what was asked for.
    private func run(_ clip: ClipboardReader.Contents, action: NotchmanAction, clipboardChange: Int?) async {
        do {
            let prepared = try await listenPipeline.prepare(clip, action: action)
            var record = prepared.record
            let item = history.addItem(from: prepared.content, options: AppSettings().textCleanerOptions)
            record.itemID = item.id
            playback.showIslandHint(ListenStage.generatingVoice.islandText, clearAfter: 30)
            switch prepared.action {
            case .tldr:
                guard let summary = prepared.summary else { return }
                if let usage = summary.usage { self.usage = usage }
                let quick = history.addQuickListen(for: item, summary: summary.text, audio: summary.audio)
                record.summaryItemID = quick.id
                listen(to: quick, fromStart: true)
            case .read:
                listen(to: item, fromStart: true)
            }
            record.consumedAt = Date()
            acquisition.markUsed(record, clipboardChange: clipboardChange)
            // iOS may suspend background work once this returns, so wait until
            // the voice is actually playing (audio then keeps Notchman running).
            await playback.waitUntilAudible(timeout: 25)
        } catch {
            showListenFailure(error)
        }
    }

    /// Pressed again with nothing new copied: play the current content again,
    /// as the action now asked for. Labelled as a replay, never as new.
    private func replay(_ record: ContentRecord, action: NotchmanAction) async {
        guard let itemID = record.itemID, let original = history.item(id: itemID) else {
            playback.showIslandHint("Copy the message again, then tap \(action == .tldr ? "TL;DR" : "Read").")
            return
        }
        playback.showIslandHint("Again: \(record.source)", clearAfter: 30)
        do {
            switch action {
            case .read:
                listen(to: original, fromStart: true)
            case .tldr:
                if let summaryID = record.summaryItemID, let summary = history.item(id: summaryID) {
                    listen(to: summary, fromStart: true)
                } else {
                    playback.showIslandHint(ListenStage.summarizing.islandText, clearAfter: 30)
                    try await playTLDR(of: original)
                    var updated = record
                    updated.summaryItemID = playback.nowPlaying?.itemID
                    acquisition.records.current = updated
                }
            }
            await playback.waitUntilAudible(timeout: 25)
        } catch {
            showListenFailure(error)
        }
    }

    private func showListenFailure(_ error: Error) {
        switch error {
        case CloudError.quotaExceeded:
            playback.showIslandHint("You've used today's TL;DRs.")
        case CloudError.voiceLimit(let message):
            playback.showIslandHint(message)
        case let error as URLContentResolver.ResolveError:
            playback.showIslandHint(error.localizedDescription)
        case ExtractionError.emptyContent:
            playback.showIslandHint("That link has no readable text.")
        case ExtractionError.network:
            playback.showIslandHint("Couldn't load that link. Check your connection.")
        default:
            playback.showIslandHint("Couldn't do that. Check your connection.")
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
