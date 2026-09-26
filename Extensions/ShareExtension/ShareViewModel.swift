import Foundation
import Observation
import UIKit
import UniformTypeIdentifiers
import UserNotifications

@MainActor
@Observable
final class ShareViewModel {
    enum Phase: Equatable {
        case loading
        case ready
        case handingOff
        /// The app couldn't be opened directly; the item is waiting in the inbox.
        case saved
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var content: ExtractedContent?
    private(set) var title = ""
    private(set) var summary = ""

    private let complete: () -> Void
    private let cancel: () -> Void
    private let openURL: (URL, @escaping (Bool) -> Void) -> Void

    init(complete: @escaping () -> Void, cancel: @escaping () -> Void,
         openURL: @escaping (URL, @escaping (Bool) -> Void) -> Void) {
        self.complete = complete
        self.cancel = cancel
        self.openURL = openURL
    }

    // MARK: - Loading

    func load(_ items: [NSExtensionItem]) async {
        // A shared screenshot goes to the app's "which message?" picker.
        if let imageData = await Self.imageData(from: items) {
            handOffScreenshot(imageData)
            return
        }
        do {
            let input = try await Self.bestInput(from: items)
            let extracted = try await ContentExtractionPipeline.standard.extract(input)
            let settings = AppSettings()
            let spoken = TextCleaner(options: settings.textCleanerOptions).clean(extracted.text)

            content = extracted
            title = extracted.title ?? TextCleaner.title(from: spoken)
            summary = TimeFormatter.summary(words: ReadingEstimator.wordCount(spoken),
                                            seconds: ReadingEstimator.duration(of: spoken, speed: settings.defaultSpeed))
            phase = .ready

            if settings.autoStartFromShare {
                handOff(.read)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Safari page payloads (from Preprocessing.js) beat plain text, which beats URLs.
    private static func bestInput(from items: [NSExtensionItem]) async throws -> ExtractionInput {
        var text: String?
        var url: URL?

        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier),
                   let dictionary = try? await provider.loadItem(forTypeIdentifier: UTType.propertyList.identifier) as? NSDictionary,
                   let results = dictionary[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any] {
                    let payload = WebPagePayload(dictionary: results)
                    if payload.hasUsableContent { return .webPage(payload) }
                    if url == nil, let pageURL = payload.url.flatMap(URL.init(string:)) { url = pageURL }
                }
                if text == nil, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let value = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) {
                    text = (value as? String) ?? (value as? NSAttributedString)?.string
                        ?? (value as? Data).flatMap { String(data: $0, encoding: .utf8) }
                }
                if url == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let value = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) {
                    url = (value as? URL) ?? (value as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                }
            }
            if text == nil, let attributed = item.attributedContentText?.string, !attributed.isEmpty {
                text = attributed
            }
        }

        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Some apps share "Title\nhttps://link"; if it's mostly a link, read the page.
            if let url, text.count < 200, text.contains(url.absoluteString) || text.contains(url.host ?? "\u{0}") {
                return .url(url)
            }
            return .sharedText(text, suggestedSource: url.flatMap { SourceDetector.detect(url: $0) })
        }
        if let url { return .url(url) }
        throw ExtractionError.emptyContent
    }

    private static func imageData(from items: [NSExtensionItem]) async -> Data? {
        for provider in items.flatMap({ $0.attachments ?? [] })
        where provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            guard let value = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) else { continue }
            if let url = value as? URL, let data = try? Data(contentsOf: url) { return pngData(data) }
            if let data = value as? Data { return pngData(data) }
            if let image = value as? UIImage { return image.pngData() }
        }
        return nil
    }

    private static func pngData(_ data: Data) -> Data? {
        UIImage(data: data)?.pngData()
    }

    private func handOffScreenshot(_ data: Data) {
        let file = "\(UUID().uuidString).png"
        do {
            try data.write(to: DeepLink.capturesDirectory.appendingPathComponent(file), options: .atomic)
        } catch {
            phase = .failed("Couldn't hand this screenshot to Notchman.")
            return
        }
        title = "Screenshot"
        phase = .handingOff
        openURL(DeepLink.pick(file: file).url) { [weak self] opened in
            guard let self else { return }
            if opened {
                complete()
            } else {
                phase = .failed("Open Notchman to pick the message from your screenshot.")
            }
        }
    }

    // MARK: - Actions

    func read() { handOff(.read) }
    func quickListen() { handOff(.quickListen) }
    func dismiss() { cancel() }
    func done() { complete() }

    private func handOff(_ action: PendingListen.Action) {
        guard let content, phase == .ready else { return }
        let pending = PendingListen(action: action, content: content)
        do {
            try SharedInbox.write(pending)
        } catch {
            phase = .failed("Couldn't hand this to Notchman. \(error.localizedDescription)")
            return
        }

        phase = .handingOff
        openURL(DeepLink.listen(id: pending.id).url) { [weak self] opened in
            guard let self else { return }
            if opened {
                complete()
            } else {
                phase = .saved
                Task { await self.postReadyNotification(for: pending) }
            }
        }
    }

    /// Supported fallback when the app can't be opened directly: a notification
    /// that opens Notchman, which then picks the item up from the inbox.
    private func postReadyNotification(for pending: PendingListen) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let notification = UNMutableNotificationContent()
        notification.title = "Ready to listen"
        notification.body = "\(pending.content.sourceName) · \(title). Tap to start."
        notification.userInfo = ["pendingID": pending.id.uuidString]
        let request = UNNotificationRequest(identifier: pending.id.uuidString, content: notification, trigger: nil)
        try? await center.add(request)
    }
}

private extension WebPagePayload {
    var hasUsableContent: Bool {
        let fields = [selection] + (messages ?? []).map(Optional.some) + [content]
        return fields.contains { ($0?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0) > 20 }
    }
}
