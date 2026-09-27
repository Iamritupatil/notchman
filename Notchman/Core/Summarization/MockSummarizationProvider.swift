import Foundation
import NaturalLanguage

/// On-device, extractive Quick Listen that needs no model or network.
///
/// It scores sentences for information density (numbers, decisions, warnings,
/// action words, position) and keeps the best ones in their original order
/// within the word budget. It's the default provider and the fallback when an
/// AI provider fails.
struct MockSummarizationProvider: SummarizationProvider {
    let displayName = "Basic (on device)"
    let isExternal = false

    private static let signalWords: [String] = [
        "important", "key", "must", "should", "need", "needs", "warning", "careful", "avoid", "risk",
        "recommend", "decision", "decide", "conclusion", "overall", "summary", "bottom line", "deadline",
        "action", "next step", "because", "however", "but", "result", "means", "problem", "solution",
    ]

    func summarizeForListening(_ text: String, targetDuration: QuickListenDuration) async throws -> String {
        let sentences = Self.sentences(in: text)
        let totalWords = sentences.reduce(0) { $0 + $1.words }
        let budget = targetDuration.targetWords(forSourceWords: totalWords)

        let phrases = SpokenPhrases.matching(text)
        guard totalWords > budget else {
            return phrases.map { $0.alreadyShort + "\n" + text } ?? text
        }

        let lastIndex = max(sentences.count - 1, 1)
        let scored = sentences.enumerated().map { index, sentence -> (Int, Double) in
            (index, Self.score(sentence.text, position: Double(index) / Double(lastIndex), words: sentence.words))
        }

        var chosen = Set<Int>()
        var used = 0
        for (index, _) in scored.sorted(by: { $0.1 > $1.1 }) {
            let words = sentences[index].words
            if used + words > budget { continue }
            chosen.insert(index)
            used += words
            if used >= budget - 5 { break }
        }

        let body = chosen.sorted().map { sentences[$0].text }.joined(separator: " ")
        guard let phrases else { return body }
        return "\(phrases.intro)\n\(body)\n\(phrases.outro)"
    }

    /// The spoken framing, in the message's language. Languages without a
    /// translation get just the summary, never English framing.
    struct SpokenPhrases: Equatable {
        let intro: String
        let outro: String
        let alreadyShort: String

        static let byLanguage: [String: SpokenPhrases] = [
            "en": .init(intro: "Okay, here's the quick version.", outro: "That's the gist.",
                        alreadyShort: "This one's already short, so here's all of it."),
            "es": .init(intro: "Bien, esta es la versión corta.", outro: "Eso es lo esencial.",
                        alreadyShort: "Este ya es corto, así que aquí está completo."),
            "fr": .init(intro: "Bon, voici la version courte.", outro: "Voilà l'essentiel.",
                        alreadyShort: "Celui-ci est déjà court, le voici en entier."),
            "de": .init(intro: "Okay, hier ist die Kurzfassung.", outro: "Das ist das Wichtigste.",
                        alreadyShort: "Das ist schon kurz, also hier ist alles."),
            "it": .init(intro: "Ok, ecco la versione breve.", outro: "Questo è il succo.",
                        alreadyShort: "È già breve, quindi eccolo tutto."),
            "pt": .init(intro: "Certo, aqui está a versão curta.", outro: "Esse é o essencial.",
                        alreadyShort: "Este já é curto, então aqui está completo."),
            "hi": .init(intro: "ठीक है, यह रहा छोटा रूप।", outro: "बस यही मुख्य बात है।",
                        alreadyShort: "यह पहले से छोटा है, तो यह रहा पूरा।"),
        ]

        static func matching(_ text: String) -> SpokenPhrases? {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(String(text.prefix(1_000)))
            guard let language = recognizer.dominantLanguage?.rawValue else { return byLanguage["en"] }
            let code = String(language.prefix { $0 != "-" })
            return byLanguage[code]
        }
    }

    // MARK: - Scoring

    private struct Sentence {
        let text: String
        let words: Int
    }

    private static func sentences(in text: String) -> [Sentence] {
        var result: [Sentence] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { substring, _, _, _ in
            guard let raw = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return }
            if raw.hasSuffix("code block, which I've skipped.") || raw == TextCleaner.linkNotice { return }
            result.append(Sentence(text: raw, words: ReadingEstimator.wordCount(raw)))
        }
        return result
    }

    private static func score(_ sentence: String, position: Double, words: Int) -> Double {
        let lower = sentence.lowercased()
        var score = 0.0

        // Openings set context; closings carry conclusions.
        if position < 0.15 { score += 2.0 }
        if position > 0.85 { score += 1.2 }

        if RegexKit.matches(#"\d"#, in: sentence) { score += 1.5 }
        let hits = signalWords.filter { lower.contains($0) }.count
        score += min(Double(hits), 3) * 1.2

        // Very short fragments and run-ons make poor audio.
        if words < 5 { score -= 1.5 }
        if words > 40 { score -= 1.0 }
        return score
    }
}
