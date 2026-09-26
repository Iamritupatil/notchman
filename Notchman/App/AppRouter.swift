import Foundation
import Observation

enum Route: Hashable {
    case history
    case settings
}

struct AppAlert: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var message: String
    var showsSettingsButton = false

    static let quickListenDisabled = AppAlert(
        title: "Quick Listen is off",
        message: "Choose a Quick Listen provider in Settings. The basic one runs entirely on your iPhone.",
        showsSettingsButton: true)
}

/// Navigation state shared by the whole app.
@MainActor
@Observable
final class AppRouter {
    enum Sheet: Identifiable, Equatable {
        case player
        case review(UUID)
        case tryNotchman

        var id: String {
            switch self {
            case .player: "player"
            case .review(let id): "review-\(id.uuidString)"
            case .tryNotchman: "try"
            }
        }
    }

    var sheet: Sheet?
    var path: [Route] = []
    var alert: AppAlert?
    var isPreparingQuickListen = false

    func openSettings() {
        sheet = nil
        alert = nil
        if path.last != .settings { path.append(.settings) }
    }
}
