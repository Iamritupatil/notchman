import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Private, on-device summaries using Apple's Foundation Models framework
/// (iOS 26+ on Apple Intelligence devices). Nothing leaves the device.
@available(iOS 26.0, *)
struct AppleIntelligenceSummarizationProvider: SummarizationProvider {
    let displayName = "Apple Intelligence"
    let isExternal = false

    /// The on-device model has a small context window; stay well inside it.
    let maxInputCharacters = 8_000

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    func summarizeForListening(_ text: String, targetDuration: QuickListenDuration) async throws -> String {
        guard Self.isAvailable else {
            throw SummarizationError.unavailable("Apple Intelligence isn't available on this device.")
        }
        let input = String(text.prefix(maxInputCharacters))
        let targetWords = targetDuration.targetWords(forSourceWords: ReadingEstimator.wordCount(input))
        let session = LanguageModelSession(instructions: SummarizationPrompt.instructions)
        let response = try await session.respond(to: SummarizationPrompt.request(for: input, targetWords: targetWords))
        return response.content
    }
}
#endif

enum AppleIntelligence {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return AppleIntelligenceSummarizationProvider.isAvailable
        }
        #endif
        return false
    }
}
