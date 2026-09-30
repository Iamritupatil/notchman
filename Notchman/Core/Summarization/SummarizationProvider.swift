import Foundation

enum QuickListenDuration: String, CaseIterable, Identifiable, Sendable {
    case thirtySeconds, oneMinute, twoMinutes, detailed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .thirtySeconds: "30 sec"
        case .oneMinute: "1 min"
        case .twoMinutes: "2 min"
        case .detailed: "Complete"
        }
    }

    /// Spoken-word budget (~150 wpm). "Complete" (the default) scales with the
    /// message so every key point fits; the timed lengths are caps. Mirrors
    /// `targetWords` in server/src/plans.ts.
    func targetWords(forSourceWords sourceWords: Int) -> Int {
        let cap = { (words: Int) in max(30, min(words, sourceWords * 60 / 100)) }
        switch self {
        case .thirtySeconds: return cap(75)
        case .oneMinute: return cap(150)
        case .twoMinutes: return cap(300)
        case .detailed: return max(60, min(900, sourceWords * 45 / 100))
        }
    }
}

enum SummarizationError: LocalizedError {
    case disabled
    case unavailable(String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .disabled: "TL;DR is off. You can turn it on in Settings."
        case .unavailable(let reason): reason
        case .badResponse(let reason): "The summary couldn't be created. \(reason)"
        }
    }
}

/// Produces an audio-first version of a long text: something written to be
/// heard once, not skimmed.
protocol SummarizationProvider: Sendable {
    var displayName: String { get }
    /// Whether content leaves the device.
    var isExternal: Bool { get }
    func summarizeForListening(_ text: String, targetDuration: QuickListenDuration) async throws -> String
}

/// Shared prompt for LLM-backed providers.
enum SummarizationPrompt {
    static let instructions = """
    You turn long written messages into spoken summaries that will be read aloud by a text-to-speech voice.

    Always answer in the same language as the message.

    Write for the ear, not the eye:
    - Plain conversational sentences. No bullet points, headings, markdown, tables, emoji or URLs.
    - When there are several points, say how many, then walk through them: "There are three main ideas. First, …"
    - Create the shortest spoken explanation that preserves all materially useful information: every fact, number, name, decision, reason, warning, recommendation, caveat, step, action item, deadline and conclusion, plus the context needed to follow it. Losing information is worse than running long.
    - Remove repetition, filler, redundant examples, formatting and conversational padding.
    - If there are steps or a list, keep every item, in order.
    - Keep just enough context for the listener to follow.
    - Drop repetition, filler, pleasantries, citations and anything that only makes sense visually.
    - If the text contains code, describe what it does in one sentence instead of reading it.
    - Never invent facts that aren't in the text.
    """

    /// "Complete" TL;DRs: no duration target; length follows the information,
    /// and it's a summary, never a retelling.
    /// Mirrors the server's prompt for `detailed`.
    static func completeRequest(for text: String) -> String {
        """
        Summarize the following message for listening. Make it as short as possible without losing any materially important information: facts, numbers, dates, names, reasoning, conclusions, recommendations, warnings, caveats, action items and the context needed to follow them. Cut filler, repetition, redundant examples, formatting noise and conversational padding. Do not retell the message sentence by sentence, and do not target a fixed duration: a dense message may need a long summary, a padded one a very short one. Write in the same language as the message. The summary must be clearly shorter than the message unless nearly every sentence carries essential information.

        MESSAGE:
        \(text)
        """
    }

    static func request(for text: String, targetWords: Int) -> String {
        """
        Rewrite the following message as a spoken summary of about \(targetWords) words, in the same language as the message. Include every key point even if that takes more words.

        MESSAGE:
        \(text)
        """
    }
}
