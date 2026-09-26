import Foundation

/// URLs of the form `notchman://…` used to hand work from extensions to the app.
enum DeepLink: Equatable {
    /// Pick up a pending item written to the shared inbox.
    case listen(id: UUID)
    /// Show the player for whatever is currently playing.
    case player
    /// Just open the app.
    case home

    static let scheme = "notchman"

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .listen(let id):
            components.host = "listen"
            components.queryItems = [URLQueryItem(name: "id", value: id.uuidString)]
        case .player:
            components.host = "player"
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
        case "player":
            self = .player
        default:
            self = .home
        }
    }
}
