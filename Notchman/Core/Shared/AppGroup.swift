import Foundation
import os

/// The App Group shared by the app and its extensions.
///
/// The identifier is injected into each target's Info.plist (`NotchmanAppGroup`)
/// from `APP_GROUP_ID` in project.yml, so it is defined in exactly one place.
enum AppGroup {
    static let identifier: String =
        (Bundle.main.object(forInfoDictionaryKey: "NotchmanAppGroup") as? String) ?? "group.app.notchman"

    static let log = Logger(subsystem: "com.notchman", category: "AppGroup")

    /// Shared container. Falls back to the process's own Application Support
    /// directory when the group isn't provisioned (e.g. unsigned simulator builds),
    /// in which case the app and extensions cannot see each other's files.
    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        log.error("App Group \(identifier, privacy: .public) unavailable; using local storage.")
        let local = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        return local
    }

    static let defaults: UserDefaults = UserDefaults(suiteName: identifier) ?? .standard
}
