import Foundation
import os

/// The ElevenLabs voices Notchman offers: ElevenLabs' current default voices,
/// available to every account, chosen so each one sounds clearly different
/// (male and female; calm, energetic, conversational, narrator). All speak
/// every supported language; the detail names the accent they're tuned for.
struct CloudVoice: Identifiable, Hashable, Sendable {
    enum Gender: String, Sendable {
        case female, male, neutral
    }

    enum Style: String, CaseIterable, Sendable {
        case conversational, calm, energetic, narrator

        var title: String {
            switch self {
            case .conversational: "Conversational"
            case .calm: "Calm"
            case .energetic: "Energetic"
            case .narrator: "Narrator"
            }
        }
    }

    let id: String
    let name: String
    let gender: Gender
    let style: Style
    let detail: String

    static let all: [CloudVoice] = [
        CloudVoice(id: "cgSgspJ2msm6clMCkdW9", name: "Jessica", gender: .female, style: .conversational, detail: "Bright, friendly · American"),
        CloudVoice(id: "iP95p4xoKVk53GoZ742B", name: "Chris", gender: .male, style: .conversational, detail: "Down-to-earth · American"),
        CloudVoice(id: "bIHbv24MWmeRgasZH58o", name: "Will", gender: .male, style: .conversational, detail: "Relaxed, upbeat · American"),
        CloudVoice(id: "EXAVITQu4vr4xnSDxMaL", name: "Sarah", gender: .female, style: .calm, detail: "Soft, reassuring · American"),
        CloudVoice(id: "cjVigY5qzO86Huf0OWal", name: "Eric", gender: .male, style: .calm, detail: "Smooth, steady · American"),
        CloudVoice(id: "XrExE9yKIg1WjnnlVkGX", name: "Matilda", gender: .female, style: .calm, detail: "Warm, clear · American"),
        CloudVoice(id: "FGY2WhTYpPnrIDTdsKH5", name: "Laura", gender: .female, style: .energetic, detail: "Upbeat, lively · American"),
        CloudVoice(id: "TX3LPaxmHKxFdv7VOQHJ", name: "Liam", gender: .male, style: .energetic, detail: "Young, energetic · American"),
        CloudVoice(id: "IKne3meq5aSn9XLyUdCD", name: "Charlie", gender: .male, style: .energetic, detail: "Lively, natural · Australian"),
        CloudVoice(id: "JBFqnCBsd6RMkjVDRZzb", name: "George", gender: .male, style: .narrator, detail: "Warm storyteller · British"),
        CloudVoice(id: "onwK4e9ZLuTAKqWW03F9", name: "Daniel", gender: .male, style: .narrator, detail: "Steady, news-style · British"),
        CloudVoice(id: "nPczCjzI2devNBz1zQrb", name: "Brian", gender: .male, style: .narrator, detail: "Deep, resonant · American"),
        CloudVoice(id: "Xb7hH8MSUJpSbSDYk0k2", name: "Alice", gender: .female, style: .narrator, detail: "Clear, engaging · British"),
        CloudVoice(id: "pFZP5JQG7iQjIQuC4Bku", name: "Lily", gender: .female, style: .narrator, detail: "Velvety, gentle · British"),
    ]

    static let `default` = all.first { $0.name == "Sarah" } ?? all[0]

    static func voice(id: String?) -> CloudVoice {
        guard let id else { return .default }
        if let voice = all.first(where: { $0.id == id }) { return voice }
        // A voice from an older build that's no longer offered. Never silent: logged.
        Logger(subsystem: "com.notchman", category: "Voice")
            .error("Saved voice \(id, privacy: .public) isn't offered any more; using \(CloudVoice.default.name, privacy: .public)")
        return .default
    }

    /// The saved choice (shared with the extensions through the app group).
    static var selected: CloudVoice {
        get { voice(id: AppGroup.defaults.string(forKey: SettingsKey.cloudVoiceID)) }
        set { AppGroup.defaults.set(newValue.id, forKey: SettingsKey.cloudVoiceID) }
    }
}
