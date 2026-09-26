import Foundation

/// A piece of content handed from an extension (Share, Safari, App Intent) to the app.
struct PendingListen: Codable, Identifiable, Sendable {
    enum Action: String, Codable, Sendable {
        /// Show "Ready to listen" and let the user choose.
        case review
        /// Start reading the full text immediately.
        case read
        /// Produce and play a Quick Listen summary.
        case quickListen
    }

    var id: UUID = UUID()
    var createdAt: Date = Date()
    var action: Action
    var content: ExtractedContent
}

/// File-based hand-off queue in the App Group container.
///
/// Extensions only ever write here; the app drains it and owns the SwiftData
/// store. That keeps a single writer for the database.
enum SharedInbox {
    static var directory: URL {
        let url = AppGroup.containerURL.appendingPathComponent("Inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func write(_ item: PendingListen) throws {
        let data = try encoder.encode(item)
        try data.write(to: fileURL(for: item.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Reads and removes one item.
    static func take(id: UUID) -> PendingListen? {
        let url = fileURL(for: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return try? decoder.decode(PendingListen.self, from: data)
    }

    /// Reads and removes every pending item, oldest first. Items older than a
    /// day are discarded rather than surprising the user.
    static func drain() -> [PendingListen] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var items: [PendingListen] = []
        for url in files where url.pathExtension == "json" {
            defer { try? FileManager.default.removeItem(at: url) }
            guard let data = try? Data(contentsOf: url),
                  let item = try? decoder.decode(PendingListen.self, from: data),
                  item.createdAt.timeIntervalSinceNow > -86_400 else { continue }
            items.append(item)
        }
        return items.sorted { $0.createdAt < $1.createdAt }
    }
}
