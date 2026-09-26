import Foundation
import Observation

enum Route: Hashable {
    case history
    case settings
}

enum AppTab: String, CaseIterable, Identifiable {
    case home, history, account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .history: "History"
        case .account: "Account"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .history: "clock.fill"
        case .account: "person.fill"
        }
    }
}

struct AppAlert: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var message: String
    var showsSettingsButton = false

    static let quickListenDisabled = AppAlert(
        title: "TL;DR is off",
        message: "Choose a TL;DR provider in Settings. The basic one runs entirely on your iPhone.",
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
        case signIn
        case paywall
        case screenPicker(URL)

        var id: String {
            switch self {
            case .player: "player"
            case .review(let id): "review-\(id.uuidString)"
            case .tryNotchman: "try"
            case .signIn: "signIn"
            case .paywall: "paywall"
            case .screenPicker(let url): "picker-\(url.lastPathComponent)"
            }
        }
    }

    var tab: AppTab = .home
    var homePath: [Route] = []
    var historyPath: [Route] = []
    var accountPath: [Route] = []
    var sheet: Sheet?
    var alert: AppAlert?
    var isPreparingQuickListen = false

    func openSettings() {
        sheet = nil
        alert = nil
        switch tab {
        case .home: if homePath.last != .settings { homePath.append(.settings) }
        case .history: if historyPath.last != .settings { historyPath.append(.settings) }
        case .account: if accountPath.last != .settings { accountPath.append(.settings) }
        }
    }
}
