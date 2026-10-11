import Foundation

/// Anonymous usage statistics (Privacy Policy › App usage statistics): which
/// features get used, so Notchman can be made easier to use. Only short event
/// names ("paywall_open", "island_tldr") are sent, in small batches, never what
/// anyone reads; the server keeps daily totals. Off in Settings › Share Usage
/// Statistics. Debug builds never send; TestFlight builds are counted apart.
@MainActor
enum AppStats {
    nonisolated static let enabledKey = "stats.enabled"
    static var isEnabled: Bool { AppGroup.defaults.object(forKey: enabledKey) as? Bool ?? true }

    private static var pending: [String] = []
    private static var sending = false

    /// Records one event.
    static func record(_ name: String) {
        #if DEBUG
        _ = name
        #else
        guard isEnabled, NotchmanCloud.isAvailable else { return }
        pending.append(name)
        // Purchases go right away; everything else waits for a small batch.
        if pending.count >= 15 || name.hasPrefix("purchase_") { flush() }
        #endif
    }

    /// Sends what's waiting (also called when the app goes to the background).
    static func flush() {
        guard !pending.isEmpty, !sending else { return }
        let batch = Array(pending.prefix(40))
        pending.removeFirst(batch.count)
        sending = true
        Task {
            // Best effort: a batch that can't be sent is dropped, never retried.
            try? await NotchmanCloud().sendEvents(batch, testflight: FeatureFlags.isTestFlight)
            sending = false
        }
    }
}

extension ListenFailure {
    /// A short name for statistics ("fail_nothing_copied").
    var statsName: String {
        switch self {
        case .nothingNew: "fail_nothing_new"
        case .nothingCopied: "fail_nothing_copied"
        case .staleCopy: "fail_stale_copy"
        case .tooShort: "fail_too_short"
        case .postInaccessible: "fail_post_private"
        case .pageInaccessible: "fail_page_private"
        case .linkUnreadable: "fail_link"
        case .summaryFailed: "fail_summary"
        case .voiceFailed: "fail_voice"
        case .limitReached: "fail_limit"
        }
    }
}
