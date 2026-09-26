import Foundation

enum QuickListenProviderKind: String, CaseIterable, Identifiable {
    case off, basic, appleIntelligence, openAI

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: "Off"
        case .basic: "Basic (on device)"
        case .appleIntelligence: "Apple Intelligence"
        case .openAI: "OpenAI"
        }
    }

    /// AI-backed providers are part of Notchman Premium; Basic is free.
    var requiresPremium: Bool { self == .appleIntelligence || self == .openAI }
}

/// Chooses a summarization provider from settings and produces the spoken
/// Quick Listen script. Falls back to the on-device extractive provider if an
/// AI provider fails, so Quick Listen never dead-ends.
struct QuickListenService {
    var settings = AppSettings()
    /// Without Premium, AI providers fall back to the free on-device Basic provider.
    var isPremium = false

    var providerKind: QuickListenProviderKind {
        let kind = QuickListenProviderKind(rawValue: settings.quickListenProvider) ?? .off
        return kind.requiresPremium && !isPremium ? .basic : kind
    }

    var isEnabled: Bool { providerKind != .off }

    func makeProvider() throws -> any SummarizationProvider {
        switch providerKind {
        case .off:
            throw SummarizationError.disabled
        case .basic:
            return MockSummarizationProvider()
        case .appleIntelligence:
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *), AppleIntelligenceSummarizationProvider.isAvailable {
                return AppleIntelligenceSummarizationProvider()
            }
            #endif
            return MockSummarizationProvider()
        case .openAI:
            guard let key = KeychainStore.string(for: KeychainStore.openAIKey), !key.isEmpty else {
                throw SummarizationError.missingAPIKey
            }
            return OpenAISummarizationProvider(apiKey: key, model: settings.openAIModel)
        }
    }

    /// Summarizes already-cleaned text and cleans the result for speech.
    func spokenSummary(of spokenText: String) async throws -> String {
        let provider = try makeProvider()
        let duration = QuickListenDuration(rawValue: settings.quickListenDuration) ?? .oneMinute
        let summary: String
        do {
            summary = try await provider.summarizeForListening(spokenText, targetDuration: duration)
        } catch let error as SummarizationError {
            throw error
        } catch {
            summary = try await MockSummarizationProvider().summarizeForListening(spokenText, targetDuration: duration)
        }
        // Models occasionally slip into markdown; clean it like any other text.
        return TextCleaner(options: settings.textCleanerOptions).clean(summary)
    }
}
