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
            tldrCopiedText()
        case .readClipboard:
            tldrCopiedText(action: .read)
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
        router.sheet = .player
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
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
            throw ScreenTLDRError.unreadable
        }
        let lines = try await ScreenTextReader.lines(in: cgImage)
        let blocks = MessageBlockDetector.blocks(from: lines)
        guard let pick = await MessageChooser.choose(from: blocks) ?? MessageBlockDetector.defaultBlock(in: blocks) else {
            throw ScreenTLDRError.noMessage
        }
        let source = MessageBlockDetector.guessSource(from: lines)
        let content = ExtractedContent(text: pick.text, title: nil, sourceType: source,
                                       sourceName: source == .text ? "Screenshot" : source.displayName, url: nil)
        let item = history.addItem(from: content, options: AppSettings().textCleanerOptions)
        try await playTLDR(of: item)
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
