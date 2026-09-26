import Foundation
import Observation
import os
import SwiftData

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
        let pending = SharedInbox.drain()
        guard let primary = pending.first(where: { $0.id == id }) ?? pending.last else { return }
        let options = AppSettings().textCleanerOptions
        for item in pending where item.id != primary.id {
            history.addItem(from: item.content, options: options)
        }
        ingest(primary.content, action: primary.action)
    }

    func handle(url: URL) {
        guard let link = DeepLink(url: url) else { return }
        switch link {
        case .listen(let id):
            processInbox(preferring: id)
        case .player:
            if playback.isActive { router.sheet = .player }
        case .home:
            processInbox()
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

    func quickListen(to item: ListeningItem) {
        let service = QuickListenService(isPremium: premium.isPremium)
        guard service.isEnabled else {
            router.alert = .quickListenDisabled
            return
        }
        guard !router.isPreparingQuickListen else { return }
        router.isPreparingQuickListen = true
        let source = TextCleaner(options: AppSettings().textCleanerOptions).clean(item.originalText)
        Task {
            defer { router.isPreparingQuickListen = false }
            do {
                let summary = try await service.spokenSummary(of: source)
                let quick = history.addQuickListen(for: item, summary: summary)
                listen(to: quick, fromStart: true)
            } catch {
                router.alert = AppAlert(title: "TL;DR", message: error.localizedDescription,
                                        showsSettingsButton: error is SummarizationError)
            }
        }
    }

    func delete(_ item: ListeningItem) {
        playback.stopIfPlaying(itemID: item.id)
        history.delete(item)
    }
}
