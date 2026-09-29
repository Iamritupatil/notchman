import Foundation

enum SettingsKey {
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let voiceIdentifier = "voiceIdentifier"
    static let defaultSpeed = "defaultSpeed"
    static let language = "language"
    static let skipCodeBlocks = "skipCodeBlocks"
    static let cleanMarkdown = "cleanMarkdown"
    static let autoStartFromShare = "shareStartsTLDR"
    static let quickListenDuration = "tldrLength"
    static let calibratedCharactersPerSecond = "calibratedCharactersPerSecond"
    static let restInDynamicIsland = "restInDynamicIsland"
    /// The ElevenLabs voice (`CloudVoice.id`).
    static let cloudVoiceID = "cloudVoiceID"
}

/// Typed read access to settings stored in the shared App Group defaults, so
/// the Share Extension sees the same values as the app. SwiftUI views bind to
/// the same keys with `@AppStorage(key, store: AppGroup.defaults)`.
struct AppSettings {
    enum Default {
        static let speed = 1.0
        static let skipCodeBlocks = true
        static let cleanMarkdown = true
        static let autoStartFromShare = true
        static let quickListenDuration = "detailed"
    }

    var defaults: UserDefaults = AppGroup.defaults

    var voiceIdentifier: String? {
        let value = defaults.string(forKey: SettingsKey.voiceIdentifier)
        return value?.isEmpty == false ? value : nil
    }

    /// BCP-47 language, e.g. "en-US". Empty means "follow the device".
    var language: String {
        let value = defaults.string(forKey: SettingsKey.language) ?? ""
        return value.isEmpty ? Locale.current.identifier(.bcp47) : value
    }

    var defaultSpeed: Double {
        let value = defaults.double(forKey: SettingsKey.defaultSpeed)
        return value > 0 ? value : Default.speed
    }

    var skipCodeBlocks: Bool { bool(SettingsKey.skipCodeBlocks, Default.skipCodeBlocks) }
    var cleanMarkdown: Bool { bool(SettingsKey.cleanMarkdown, Default.cleanMarkdown) }
    var autoStartFromShare: Bool { bool(SettingsKey.autoStartFromShare, Default.autoStartFromShare) }

    var quickListenDuration: String {
        defaults.string(forKey: SettingsKey.quickListenDuration) ?? Default.quickListenDuration
    }

    var textCleanerOptions: TextCleaner.Options {
        TextCleaner.Options(skipCodeBlocks: skipCodeBlocks, cleanMarkdown: cleanMarkdown)
    }

    private func bool(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }
}
