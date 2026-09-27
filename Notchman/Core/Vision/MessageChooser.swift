import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Picks which message on a captured screen the user most likely wants a TL;DR of.
///
/// With Apple Intelligence (iOS 26+, on device), the model reads the detected
/// blocks and picks the main message: an assistant's answer rather than the
/// user's own question, an email body rather than the header. Without it, or
/// if it doesn't answer in time, the longest block wins.
enum MessageChooser {
    /// Must finish inside the picker's 3-second window.
    static let timeLimit: Duration = .milliseconds(2_200)
    /// Keeps the prompt well inside the on-device model's context window.
    static let charactersPerBlock = 400
    static let maximumBlocks = 8

    static func choose(from blocks: [MessageBlock]) async -> MessageBlock? {
        let fallback = MessageBlockDetector.defaultBlock(in: blocks)
        guard blocks.count > 1 else { return fallback }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), AppleIntelligence.isAvailable {
            let candidates = Array(blocks.sorted { $0.characterCount > $1.characterCount }.prefix(maximumBlocks))
            let prompt = self.prompt(for: candidates)
            if let number = await answer(within: timeLimit, { try await askModel(prompt) }),
               candidates.indices.contains(number - 1) {
                return candidates[number - 1]
            }
        }
        #endif
        return fallback
    }

    static let instructions = """
    You are shown the text blocks found on a phone screenshot, in any language. \
    Pick the one the person most likely wants summarized and read aloud: the main long message, \
    such as an AI assistant's answer, an email body, a post, a comment or an article. \
    Not their own short question, menus, buttons, names or timestamps. \
    Reply with only the block's number.
    """

    static func prompt(for candidates: [MessageBlock]) -> String {
        let listed = candidates.enumerated().map { index, block in
            let text = block.text.replacingOccurrences(of: "\n", with: " ")
            return "[\(index + 1)] \(text.prefix(charactersPerBlock))"
        }
        return "Blocks:\n" + listed.joined(separator: "\n") + "\n\nWhich number?"
    }

    /// The first whole number in the model's reply.
    static func number(in reply: String) -> Int? {
        let digits = reply.drop { !$0.isNumber }.prefix { $0.isNumber }
        return Int(digits)
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func askModel(_ prompt: String) async throws -> Int? {
        let session = LanguageModelSession(instructions: instructions)
        return number(in: try await session.respond(to: prompt).content)
    }
    #endif

    /// Runs `operation`, but gives up after `limit` without waiting for it.
    private static func answer(within limit: Duration,
                               _ operation: @escaping @Sendable () async throws -> Int?) async -> Int? {
        await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            let work = Task { once.resume((try? await operation()) ?? nil) }
            Task {
                try? await Task.sleep(for: limit)
                work.cancel()
                once.resume(nil)
            }
        }
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Int?, Never>?

    init(_ continuation: CheckedContinuation<Int?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Int?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
