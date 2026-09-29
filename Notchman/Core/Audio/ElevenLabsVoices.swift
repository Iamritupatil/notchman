import Foundation

/// The ElevenLabs voices Notchman offers. These are ElevenLabs' default
/// ("premade") voices, available to every account. All speak every supported
/// language; the name describes the accent they're tuned for.
struct CloudVoice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let detail: String

    static let all: [CloudVoice] = [
        CloudVoice(id: "21m00Tcm4TlvDq8ikWAM", name: "Rachel", detail: "Calm, clear · American"),
        CloudVoice(id: "EXAVITQu4vr4xnSDxMaL", name: "Sarah", detail: "Soft, confident · American"),
        CloudVoice(id: "9BWtsMINqrJLrRacOk9x", name: "Aria", detail: "Expressive · American"),
        CloudVoice(id: "XB0fDUnXU5powFXDhCwa", name: "Charlotte", detail: "Warm · Swedish-English"),
        CloudVoice(id: "pFZP5JQG7iQjIQuC4Bku", name: "Lily", detail: "Gentle · British"),
        CloudVoice(id: "JBFqnCBsd6RMkjVDRZzb", name: "George", detail: "Warm narrator · British"),
        CloudVoice(id: "onwK4e9ZLuTAKqWW03F9", name: "Daniel", detail: "Steady, news-style · British"),
        CloudVoice(id: "nPczCjzI2devNBz1zQrb", name: "Brian", detail: "Deep, relaxed · American"),
        CloudVoice(id: "pNInz6obpgDQGcFmaJgB", name: "Adam", detail: "Deep, clear · American"),
    ]

    static let `default` = all[0]

    static func voice(id: String?) -> CloudVoice {
        all.first { $0.id == id } ?? .default
    }

    /// The saved choice (shared with the extensions through the app group).
    static var selected: CloudVoice {
        get { voice(id: AppGroup.defaults.string(forKey: SettingsKey.cloudVoiceID)) }
        set { AppGroup.defaults.set(newValue.id, forKey: SettingsKey.cloudVoiceID) }
    }
}
