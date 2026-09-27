import Foundation

/// URLs of the form `notchman://…` used to hand work from extensions to the app.
enum DeepLink: Equatable {
    /// Pick up a pending item written to the shared inbox.
    case listen(id: UUID)
    /// Pick a message from a screenshot saved in the App Group's Captures folder.
    case pick(file: String)
    /// Show the player for whatever is currently playing.
    case player
    /// TL;DR whatever is on the clipboard (the Dynamic Island, Action button or Control Center).
    case tldrClipboard
    /// Read whatever is on the clipboard in full.
    case readClipboard
    /// The Dynamic Island tap: find the messages on the screen the user was
    /// reading (Screen Reading on), or fall back to what they copied.
    case screen(read: Bool)
    /// Just open the app.
    case home

    static let scheme = "notchman"

    /// Where the Share Extension leaves screenshots for the app to pick from.
    static var capturesDirectory: URL {
        let url = AppGroup.containerURL.appendingPathComponent("Captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .listen(let id):
            components.host = "listen"
            components.queryItems = [URLQueryItem(name: "id", value: id.uuidString)]
        case .pick(let file):
            components.host = "pick"
            components.queryItems = [URLQueryItem(name: "file", value: file)]
        case .player:
            components.host = "player"
        case .tldrClipboard:
            components.host = "tldr"
        case .readClipboard:
            components.host = "read"
        case .screen(let read):
            components.host = "screen"
            components.queryItems = [URLQueryItem(name: "mode", value: read ? "read" : "tldr")]
        case .home:
            components.host = "home"
        }
        return components.url!
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        switch url.host?.lowercased() {
        case "listen":
            let idString = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "id" })?.value
            guard let idString, let id = UUID(uuidString: idString) else { return nil }
            self = .listen(id: id)
        case "pick":
            let file = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "file" })?.value
            // Only a bare file name inside the Captures folder is accepted.
            guard let file, !file.contains("/"), file.hasSuffix(".png") else { return nil }
            self = .pick(file: file)
        case "player":
            self = .player
        case "tldr":
            self = .tldrClipboard
        case "read":
            self = .readClipboard
        case "screen":
            let mode = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "mode" })?.value
            self = .screen(read: mode == "read")
        default:
            self = .home
        }
    }
}
