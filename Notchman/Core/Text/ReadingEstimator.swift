import Foundation

/// Word counts and listening-time estimates.
///
/// Estimates are character based because the speech engine reports progress in
/// characters. The playback manager refines the rate from real speech as it plays
/// (see `PlaybackManager`), and stores the calibrated value in shared settings.
enum ReadingEstimator {
    /// Characters per second at 1x for a typical system voice (~170 wpm).
    static let defaultCharactersPerSecond: Double = 14.5

    static func wordCount(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }

    static func baseCharactersPerSecond(defaults: UserDefaults = AppGroup.defaults) -> Double {
        let stored = defaults.double(forKey: SettingsKey.calibratedCharactersPerSecond)
        return (8...25).contains(stored) ? stored : defaultCharactersPerSecond
    }

    /// Estimated seconds to speak `text` at `speed`.
    static func duration(of text: String, speed: Double = 1.0, charactersPerSecond: Double? = nil) -> TimeInterval {
        let cps = (charactersPerSecond ?? baseCharactersPerSecond()) * max(speed, 0.1)
        return Double((text as NSString).length) / cps
    }
}

enum TimeFormatter {
    /// "4:05", or "1:02:03" for long content.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// "~4 min", "<1 min".
    static func approximate(_ seconds: TimeInterval) -> String {
        if seconds < 45 { return "<1 min" }
        let minutes = Int((seconds / 60).rounded())
        return "~\(max(1, minutes)) min"
    }

    /// "842 words • ~4 min"
    static func summary(words: Int, seconds: TimeInterval) -> String {
        let wordLabel = words == 1 ? "word" : "words"
        return "\(words.formatted()) \(wordLabel) • \(approximate(seconds))"
    }
}
