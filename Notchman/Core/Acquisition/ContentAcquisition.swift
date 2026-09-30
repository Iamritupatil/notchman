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
        static let seenAt = "clip.seenAtRef"
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
            let seenAt = Date(timeIntervalSinceReferenceDate: defaults.double(forKey: Key.seenAt))
            if now.timeIntervalSince(seenAt) > Self.staleAfter { return .stale(since: seenAt) }
        }
        return .fresh
    }

    /// Records the counter when Notchman runs (opened, backgrounded, island tap),
    /// keeping the first time each copy was seen.
    func observe(changeCount: Int, now: Date = Date()) {
        guard defaults.object(forKey: Key.seenChange) == nil || defaults.integer(forKey: Key.seenChange) != changeCount else { return }
        defaults.set(changeCount, forKey: Key.seenChange)
        defaults.set(now.timeIntervalSinceReferenceDate, forKey: Key.seenAt)
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
        // HTML is converted with our own text converter. Apple's HTML import
        // runs WebKit on the main thread and can deadlock inside async code
        // (the island's background work).
        if let data = pasteboard.data(forPasteboardType: "public.html"),
           let html = String(data: data, encoding: .utf8) {
            let text = GenericWebExtractor.htmlToMarkdown(html).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return Contents(text: text, url: nil) }
        }
        if let data = pasteboard.data(forPasteboardType: "public.rtf"),
           let attributed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                    documentAttributes: nil) {
            let text = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return Contents(text: text, url: nil) }
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

/// The one place the clipboard is looked at for listening, with freshness and
/// evidence-based source attribution. The island, shortcuts and the app all go
/// through it.
///
/// It's called from inside the Read / TL;DR intents themselves, never from app
/// lifecycle events. But iOS only shows the clipboard to the app on screen:
/// while Notchman is in the background (the island), `UIPasteboard` comes back
/// empty. That case is reported as `.hiddenByIOS`, never as "nothing copied".
@MainActor
final class ContentAcquisitionManager {
    enum Result {
        /// Text or a link copied since the current content.
        case new(ClipboardReader.Contents, clipboardChange: Int)
        /// The clipboard still holds the current content (what was last played):
        /// pressing again replays it, and it's never presented as new.
        case current(ContentRecord)
        /// Copied a while ago and never played; not presented as current.
        case staleClipboard(since: Date)
        /// Notchman isn't on screen, and iOS returned nothing from the clipboard.
        case hiddenByIOS
        /// Nothing usable was copied (empty, or too short).
        case nothing
    }

    var ledger = ClipboardLedger()
    var records = ContentRecordStore()
    var pending = PendingActionStore()
    var pasteboard: UIPasteboard = .general

    /// Notes the clipboard counter whenever Notchman runs, so later taps can
    /// tell fresh copies from old ones. Doesn't read the clipboard.
    func observeClipboard() {
        ledger.observe(changeCount: pasteboard.changeCount)
    }

    /// What's on the clipboard right now, compared with the current content.
    /// - Parameter isForeground: whether Notchman is on screen (iOS only
    ///   shares the clipboard then).
    func acquireClipboard(isForeground: Bool, now: Date = Date()) -> Result {
        let change = pasteboard.changeCount
        let freshness = ledger.freshness(changeCount: change, now: now)
        ledger.observe(changeCount: change, now: now)

        guard let clip = ClipboardReader.read(pasteboard) else {
            return isForeground ? .nothing : .hiddenByIOS
        }
        if let current = records.current, current.rawHash == ContentHash.of(clip.text) {
            return .current(current)
        }
        if case .stale(let since) = freshness { return .staleClipboard(since: since) }
        guard clip.text.count >= 40 || clip.url != nil else { return .nothing }
        return .new(clip, clipboardChange: change)
    }

    /// Call once the content is actually playing: it becomes the current content.
    func markUsed(_ record: ContentRecord, clipboardChange: Int?) {
        records.current = record
        if let clipboardChange {
            ledger.markUsed(changeCount: clipboardChange, hash: record.rawHash)
        }
    }
}
