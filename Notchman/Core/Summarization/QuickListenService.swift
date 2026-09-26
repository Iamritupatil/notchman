import Foundation

/// Produces the spoken TL;DR script.
///
/// TL;DRs are made by the Notchman server (which holds the AI keys and counts
/// each plan's monthly allowance). If the server can't be reached, Notchman
/// falls back to an on-device summary (Apple Intelligence when available,
/// otherwise the extractive Basic provider) so TL;DR never dead-ends.
/// Running out of the monthly allowance is not an error we paper over: it
/// surfaces so the app can offer an upgrade.
struct QuickListenService {
    var settings = AppSettings()
    var cloud = NotchmanCloud()

    struct Result {
        let text: String
        /// Updated allowance, or nil when the summary was made on device.
        let usage: CloudUsage?
    }

    func spokenSummary(of spokenText: String) async throws -> Result {
        let duration = QuickListenDuration(rawValue: settings.quickListenDuration) ?? .oneMinute
        do {
            let response = try await cloud.tldr(text: spokenText, length: duration)
            return Result(text: clean(response.summary), usage: response.usage)
        } catch let error as CloudError {
            if case .quotaExceeded = error { throw error }
        } catch {
            // Offline or timed out: fall through to on-device.
        }
        let summary = try await onDeviceProvider().summarizeForListening(spokenText, targetDuration: duration)
        return Result(text: clean(summary), usage: nil)
    }

    private func onDeviceProvider() -> any SummarizationProvider {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), AppleIntelligenceSummarizationProvider.isAvailable {
            return AppleIntelligenceSummarizationProvider()
        }
        #endif
        return MockSummarizationProvider()
    }

    /// Models occasionally slip into markdown; clean it like any other text.
    private func clean(_ text: String) -> String {
        TextCleaner(options: settings.textCleanerOptions).clean(text)
    }
}
