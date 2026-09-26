import AVFoundation
import NaturalLanguage

/// Voice discovery and the mapping from user-facing speed to utterance rate.
enum VoiceCatalog {
    /// All non-novelty voices, best quality first.
    static func voices(forLanguage language: String) -> [AVSpeechSynthesisVoice] {
        let code = languageCode(language)
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { languageCode($0.language) == code && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality { return lhs.quality.rawValue > rhs.quality.rawValue }
                if (lhs.language == language) != (rhs.language == language) { return lhs.language == language }
                return lhs.name < rhs.name
            }
    }

    /// The voice to speak with: the user's choice if still installed, otherwise
    /// the best installed voice for the language.
    static func voice(identifier: String?, language: String) -> AVSpeechSynthesisVoice? {
        if let identifier, let voice = AVSpeechSynthesisVoice(identifier: identifier) { return voice }
        return voices(forLanguage: language).first ?? AVSpeechSynthesisVoice(language: language)
    }

    /// Picks a voice that matches the content's language. If the preferred voice
    /// is English but the message is clearly Spanish, a Spanish voice is used.
    static func voice(for text: String, identifier: String?, language: String) -> AVSpeechSynthesisVoice? {
        let preferred = voice(identifier: identifier, language: language)
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(1_000)))
        guard let detected = recognizer.dominantLanguage?.rawValue,
              let confidence = recognizer.languageHypotheses(withMaximum: 1).values.first, confidence > 0.8,
              languageCode(detected) != languageCode(preferred?.language ?? language) else {
            return preferred
        }
        return voices(forLanguage: detected).first ?? preferred
    }

    /// Languages with at least one installed voice, as BCP-47 codes ("en-US").
    static func availableLanguages() -> [String] {
        Array(Set(AVSpeechSynthesisVoice.speechVoices().map(\.language))).sorted { lhs, rhs in
            displayName(for: lhs) < displayName(for: rhs)
        }
    }

    static func displayName(for language: String) -> String {
        Locale.current.localizedString(forIdentifier: language) ?? language
    }

    static func qualityLabel(_ voice: AVSpeechSynthesisVoice) -> String? {
        switch voice.quality {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        default: nil
        }
    }

    private static func languageCode(_ language: String) -> String {
        String(language.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "").lowercased()
    }
}

enum PlaybackSpeed {
    static let options: [Double] = [0.8, 1.0, 1.2, 1.5, 2.0]

    /// `AVSpeechUtterance.rate` is non-linear: 0.5 is normal and small increases
    /// speed up quickly. These anchors were tuned by ear against the default
    /// voices; the playback manager measures the real rate while speaking, so
    /// time estimates stay honest even if a voice deviates.
    private static let anchors: [(speed: Double, rate: Double)] = [
        (0.5, 0.40), (0.8, 0.45), (1.0, 0.50), (1.2, 0.54), (1.5, 0.58), (2.0, 0.64), (3.0, 0.75),
    ]

    static func utteranceRate(for speed: Double) -> Float {
        let clamped = min(max(speed, anchors.first!.speed), anchors.last!.speed)
        var rate = anchors.last!.rate
        for (lower, upper) in zip(anchors, anchors.dropFirst()) where clamped <= upper.speed {
            let t = (clamped - lower.speed) / (upper.speed - lower.speed)
            rate = lower.rate + t * (upper.rate - lower.rate)
            break
        }
        return min(max(Float(rate), AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
    }

    static func label(_ speed: Double) -> String {
        speed == speed.rounded() ? "\(Int(speed))x" : "\(speed.formatted(.number.precision(.fractionLength(0...1))))x"
    }
}
