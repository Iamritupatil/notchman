import Foundation

/// Produces the spoken TL;DR.
///
/// - **Pro / Pro+:** the Notchman server writes the summary (Groq) and records
///   it in a natural voice (ElevenLabs). The server holds the keys and counts
///   each plan's monthly allowance.
/// - **Free:** 10 a month, made on the iPhone (Apple Intelligence when
///   available, otherwise the Basic summarizer) and read by Apple's voice.
///   These never reach the server, so they cost nothing.
///
/// If the cloud TL;DR fails (offline, timed out, server error) that's an error
/// the user sees with Retry (`SummaryError`), never a silent switch to the much
/// weaker on-device summary. Running out of an allowance is `CloudError.quotaExceeded`.
struct QuickListenService {
    var settings = AppSettings()
    var cloud = NotchmanCloud()
    var freeAllowance = FreeAllowance()
    /// True when the user has an active Pro or Pro+ subscription.
    var isPaid = false

    struct Result {
        let text: String
        /// The natural-voice recording, or nil to read `text` with Apple's voice.
        let audio: Data?
        /// Updated allowance for display, when known.
        let usage: CloudUsage?
        /// Why the cloud (Groq summary or ElevenLabs voice) wasn't used, if it was meant to be.
        var cloudProblem: String? = nil
    }

    func spokenSummary(of spokenText: String) async throws -> Result {
        // No fixed duration: the TL;DR keeps every key point and its length
        // follows the information.
        let duration = QuickListenDuration.detailed

        if isPaid || FeatureFlags.cloudForEveryone, FeatureFlags.cloudTLDR {
            do {
                let response = try await cloud.tldr(text: spokenText, length: duration)
                CloudDiagnostics.lastProblem = nil
                return Result(text: clean(response.summary), audio: response.audio, usage: response.usage)
            } catch CloudError.quotaExceeded(let usage) {
                throw CloudError.quotaExceeded(usage)
            } catch {
                let problem = CloudDiagnostics.describe(error)
                CloudDiagnostics.lastProblem = problem
                throw SummaryError.failed(Self.userMessage(for: error))
            }
        }

        let usage = try freeAllowance.consume()
        do {
            return Result(text: clean(try await onDeviceSummary(of: spokenText, duration: duration)), audio: nil, usage: usage)
        } catch {
            freeAllowance.refund()
            throw error
        }
    }

    /// Apple Intelligence when available; the Basic summarizer otherwise, or when
    /// Apple Intelligence can't handle the message (e.g. an unsupported language).
    private func onDeviceSummary(of text: String, duration: QuickListenDuration) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), AppleIntelligenceSummarizationProvider.isAvailable,
           let summary = try? await AppleIntelligenceSummarizationProvider()
               .summarizeForListening(text, targetDuration: duration) {
            return summary
        }
        #endif
        return try await MockSummarizationProvider().summarizeForListening(text, targetDuration: duration)
    }

    enum SummaryError: LocalizedError, Equatable {
        case failed(String)
        var errorDescription: String? {
            switch self { case .failed(let message): message }
        }
    }

    /// What went wrong, in words for the Retry screen.
    static func userMessage(for error: Error) -> String {
        switch error {
        case CloudError.slowDown: "Too many at once. Wait a minute, then retry."
        case CloudError.busy: "Notchman is very busy right now. Retry in a little while."
        case let urlError as URLError where urlError.code == .timedOut: "It took too long. Check your connection and retry."
        case is URLError: "No connection. Check your internet and retry."
        default: "Something went wrong making the TL;DR. Retry."
        }
    }

    /// Models occasionally slip into markdown; clean it like any other text.
    private func clean(_ text: String) -> String {
        TextCleaner(options: settings.textCleanerOptions).clean(text)
    }
}
