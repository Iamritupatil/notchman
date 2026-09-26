import Foundation

/// Where a piece of content came from. Drives labels, icons and extraction hints.
enum SourceType: String, Codable, CaseIterable, Sendable {
    case chatGPT
    case claude
    case gemini
    case reddit
    case email
    case webpage
    case text

    var displayName: String {
        switch self {
        case .chatGPT: "ChatGPT"
        case .claude: "Claude"
        case .gemini: "Gemini"
        case .reddit: "Reddit"
        case .email: "Email"
        case .webpage: "Web"
        case .text: "Text"
        }
    }

    /// SF Symbol used for badges and the Live Activity.
    var symbolName: String {
        switch self {
        case .chatGPT: "sparkles"
        case .claude: "asterisk"
        case .gemini: "sparkle"
        case .reddit: "bubble.left.and.bubble.right.fill"
        case .email: "envelope.fill"
        case .webpage: "safari.fill"
        case .text: "text.alignleft"
        }
    }
}

/// Best-effort source detection from URLs and text shape.
enum SourceDetector {
    static func detect(url: URL?) -> SourceType? {
        guard let host = url?.host?.lowercased() else { return nil }
        func matches(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        if matches("chatgpt.com") || matches("chat.openai.com") { return .chatGPT }
        if matches("claude.ai") { return .claude }
        if matches("gemini.google.com") { return .gemini }
        if matches("reddit.com") || matches("redd.it") { return .reddit }
        if matches("mail.google.com") || matches("outlook.live.com") || matches("outlook.office.com") { return .email }
        return .webpage
    }

    static func detect(text: String) -> SourceType {
        let lower = text.lowercased()
        if lower.contains("chatgpt.com/share") || lower.contains("chat.openai.com/share") { return .chatGPT }
        if lower.contains("claude.ai/share") { return .claude }

        // Emails pasted or shared with headers intact.
        let head = text.split(separator: "\n", omittingEmptySubsequences: true).prefix(12)
        let headerCount = head.filter { line in
            ["from:", "to:", "subject:", "sent:", "date:", "cc:"].contains { line.lowercased().hasPrefix($0) }
        }.count
        if headerCount >= 2 { return .email }
        return .text
    }

    /// Human label for a URL: known service name, otherwise the bare host.
    static func sourceName(for url: URL?, type: SourceType) -> String {
        guard type == .webpage, let host = url?.host else { return type.displayName }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
