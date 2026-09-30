import Foundation
import UIKit

/// A stable fingerprint of a message's text (FNV-1a over normalized text), used
/// to recognise the same message again. Swift's `Hasher` changes every launch.
enum ContentHash {
    static func of(_ text: String) -> String {
        let normalized = text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let value = normalized.utf8.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return String(value, radix: 16)
    }
}

/// How a piece of content reached Notchman.
enum AcquisitionMethod: String, Sendable {
    case clipboard, screenshot, share, safari, link
}

/// Something Notchman is about to read, with where it came from and why we
/// believe that.
struct AcquiredContent: Equatable, Sendable {
    let id: String              // ContentHash of the text
    let text: String
    let source: SourceType
    let sourceName: String
    /// Why `source` is what it is ("Link to linkedin.com"); nil means no evidence,
    /// and the source is then the neutral "Copied text".
    let evidence: String?
    let method: AcquisitionMethod
    let acquiredAt: Date
    let url: URL?

    var extracted: ExtractedContent {
        ExtractedContent(text: text, title: nil, sourceType: source, sourceName: sourceName, url: url,
                         method: method.rawValue, evidence: evidence, acquiredAt: acquiredAt)
    }
}

// MARK: - Source resolution

/// Attributes a source only from evidence in the content itself: a link's
/// domain, a chat share link inside the text, email headers, or the app that
/// shared it. It never guesses from which app the user happens to be in.
enum SourceResolver {
    struct Resolution: Equatable {
        let source: SourceType
        let name: String
        let evidence: String?
    }

    static func resolve(text: String, url: URL?) -> Resolution {
        if let url, let type = SourceDetector.detect(url: url), type != .webpage {
            return Resolution(source: type, name: type.displayName, evidence: "Link to \(url.host ?? type.displayName)")
        }
        if let url, let host = url.host {
            let name = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            return Resolution(source: .webpage, name: name, evidence: "Link to \(host)")
        }
        if WhatsAppChat.isChat(text) {
            return Resolution(source: .text, name: "WhatsApp", evidence: "WhatsApp chat format ([date, time] Name:)")
        }
        let fromText = SourceDetector.detect(text: text)
        switch fromText {
        case .chatGPT, .claude:
            return Resolution(source: fromText, name: fromText.displayName, evidence: "Contains a \(fromText.displayName) share link")
        case .email:
            return Resolution(source: .email, name: "Email", evidence: "Has email headers")
        default:
            return Resolution(source: .text, name: SourceType.text.displayName, evidence: nil)
        }
    }
}

/// Several WhatsApp messages copied together come as lines like
/// "[29/09/26, 10:15:02 PM] Ritu: See you at 6". That shape is evidence the
/// text is from WhatsApp; for listening, the dates are dropped ("Ritu: See you at 6").
enum WhatsAppChat {
    private static let line = #"(?m)^\x{200E}?\[\d{1,4}[/.\-]\d{1,2}[/.\-]\d{1,4},? \d{1,2}[:.]\d{2}(?:[:.]\d{2})?(?:\s?[APap]\.?[Mm]\.?)?\] ([^:\n]{1,60}): "#

    static func isChat(_ text: String) -> Bool {
        RegexKit.matches(line, in: text)
    }

    static func spoken(_ text: String) -> String {
        RegexKit.replace(line, in: text, with: "$1: ")
    }
}

// MARK: - Clipboard

/// The clipboard's copy counter over time, so Notchman can tell a fresh copy
/// from old content without reading the clipboard (which can make iOS ask for
/// paste permission). Kept in the app group.
struct ClipboardLedger {
    var defaults: UserDefaults = AppGroup.defaults

    private enum Key {
        static let consumedChange = "clip.consumedChange"
        static let consumedHash = "clip.consumedHash"
        static let seenChange = "clip.seenChange"
        static let seenAt = "clip.seenAt"
    }

    /// A copy Notchman saw this long ago (and nothing was copied since) is old.
    static let staleAfter: TimeInterval = 10 * 60

    enum Freshness: Equatable {
        /// Copied since Notchman last looked.
        case fresh
        /// Already listened to; never replayed as new.
        case alreadyUsed
        /// On the clipboard since at least `since`; too old to present as current.
        case stale(since: Date)
    }

    func freshness(changeCount: Int, now: Date = Date()) -> Freshness {
        if defaults.object(forKey: Key.consumedChange) != nil, defaults.integer(forKey: Key.consumedChange) == changeCount {
            return .alreadyUsed
        }
        if defaults.object(forKey: Key.seenChange) != nil, defaults.integer(forKey: Key.seenChange) == changeCount {
            let seenAt = Date(timeIntervalSince1970: defaults.double(forKey: Key.seenAt))
            if now.timeIntervalSince(seenAt) > Self.staleAfter { return .stale(since: seenAt) }
        }
        return .fresh
    }

    /// Records the counter when Notchman runs (opened, backgrounded, island tap),
    /// keeping the first time each copy was seen.
    func observe(changeCount: Int, now: Date = Date()) {
        guard defaults.object(forKey: Key.seenChange) == nil || defaults.integer(forKey: Key.seenChange) != changeCount else { return }
        defaults.set(changeCount, forKey: Key.seenChange)
        defaults.set(now.timeIntervalSince1970, forKey: Key.seenAt)
    }

    func markUsed(changeCount: Int, hash: String) {
        defaults.set(changeCount, forKey: Key.consumedChange)
        defaults.set(hash, forKey: Key.consumedHash)
    }

    var lastUsedHash: String? { defaults.string(forKey: Key.consumedHash) }
}

/// Reads text from the clipboard whatever form the copying app used: plain
/// text, a URL, Markdown, HTML or RTF (ChatGPT's Copy button, for example,
/// may put Markdown or HTML alongside or instead of plain text).
enum ClipboardReader {
    struct Contents {
        let text: String
        let url: URL?
    }

    static let plainTypes = ["public.utf8-plain-text", "public.plain-text"]
    static let markdownTypes = ["net.daringfireball.markdown", "public.markdown"]

    /// Picks the best representation by type, so HTML is never read with its tags.
    static func read(_ pasteboard: UIPasteboard = .general) -> Contents? {
        if let url = pasteboard.url, url.scheme?.hasPrefix("http") == true {
            return Contents(text: url.absoluteString, url: url)
        }
        if pasteboard.contains(pasteboardTypes: plainTypes),
           let string = pasteboard.string?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty {
            return Contents(text: string, url: SharedTextExtractor.standaloneURL(in: string))
        }
        for type in markdownTypes + plainTypes {
            if let data = pasteboard.data(forPasteboardType: type), let text = String(data: data, encoding: .utf8) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return Contents(text: trimmed, url: SharedTextExtractor.standaloneURL(in: trimmed)) }
            }
        }
        for (type, documentType) in [("public.html", NSAttributedString.DocumentType.html),
                                     ("public.rtf", NSAttributedString.DocumentType.rtf)] {
            if let data = pasteboard.data(forPasteboardType: type),
               let attributed = try? NSAttributedString(data: data, options: [.documentType: documentType],
                                                        documentAttributes: nil) {
                let text = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return Contents(text: text, url: nil) }
            }
        }
        // Anything else that iOS can present as text.
        if let string = pasteboard.string?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty,
           !string.hasPrefix("<") {
            return Contents(text: string, url: SharedTextExtractor.standaloneURL(in: string))
        }
        return nil
    }
}

// MARK: - Manager

/// The one place content is acquired for listening, with freshness and
/// evidence-based source attribution. The island, the Action Button and the
/// app all go through it.
@MainActor
final class ContentAcquisitionManager {
    enum Result {
        case content(AcquiredContent, clipboardChange: Int?)
        /// The clipboard holds what was already listened to.
        case nothingNew
        /// The clipboard holds something copied a while ago.
        case staleClipboard(since: Date)
        /// Nothing usable (empty clipboard, or too short, and no fresh screenshot).
        case nothing
    }

    var ledger = ClipboardLedger()
    var pasteboard: UIPasteboard = .general
    /// Screenshots newer than this are used when nothing fresh was copied.
    var screenshotWindow: TimeInterval = 120

    /// Notes the clipboard counter whenever Notchman runs, so later taps can
    /// tell fresh copies from old ones. Doesn't read the clipboard.
    func observeClipboard() {
        ledger.observe(changeCount: pasteboard.changeCount)
    }

    /// What the island's TL;DR / Read should play: a fresh copy first, then a
    /// screenshot from the last 2 minutes. Never an old or already-used copy.
    func acquireForIsland() async throws -> Result {
        let change = pasteboard.changeCount
        let freshness = ledger.freshness(changeCount: change)
        ledger.observe(changeCount: change)

        if freshness == .fresh, let clip = ClipboardReader.read(pasteboard), clip.text.count >= 40 || clip.url != nil {
            return .content(try await acquired(from: clip), clipboardChange: change)
        }
        if let screenshot = await RecentScreenshot.latest(within: screenshotWindow) {
            let message = try await AppEnvironment.mainMessage(inScreenshot: screenshot)
            let evidence = message.sourceType == .text ? nil : "\(message.sourceType.displayName) name visible in the screenshot"
            return .content(AcquiredContent(id: ContentHash.of(message.text), text: message.text,
                                            source: message.sourceType, sourceName: message.sourceName,
                                            evidence: evidence, method: .screenshot, acquiredAt: Date(), url: nil),
                            clipboardChange: nil)
        }
        switch freshness {
        case .alreadyUsed: return .nothingNew
        case .stale(let since): return .staleClipboard(since: since)
        case .fresh: return .nothing
        }
    }

    /// Call once the content is actually playing, so it's never offered again as new.
    func markUsed(_ content: AcquiredContent, clipboardChange: Int?) {
        guard let clipboardChange else { return }
        ledger.markUsed(changeCount: clipboardChange, hash: content.id)
    }

    private func acquired(from clip: ClipboardReader.Contents) async throws -> AcquiredContent {
        let now = Date()
        if let url = clip.url {
            // A copied link: read what it points to (Reddit, LinkedIn, chat share links, pages).
            let page = try await ContentExtractionPipeline.standard.extract(.url(url))
            let resolution = SourceResolver.resolve(text: page.text, url: page.url ?? url)
            return AcquiredContent(id: ContentHash.of(page.text), text: page.text, source: page.sourceType,
                                   sourceName: page.sourceName, evidence: resolution.evidence,
                                   method: .link, acquiredAt: now, url: page.url ?? url)
        }
        let resolution = SourceResolver.resolve(text: clip.text, url: nil)
        let text = WhatsAppChat.isChat(clip.text) ? WhatsAppChat.spoken(clip.text) : clip.text
        return AcquiredContent(id: ContentHash.of(text), text: text, source: resolution.source,
                               sourceName: resolution.name, evidence: resolution.evidence,
                               method: .clipboard, acquiredAt: now, url: nil)
    }
}
