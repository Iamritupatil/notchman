import StoreKit
import UIKit

/// Asks for an App Store rating at a happy moment: right after a listen plays
/// to the end, the 3rd, 10th and 30th time. iOS decides whether to show it
/// (at most three times a year), and it never interrupts a TL;DR in progress.
enum ReviewPrompt {
    private static let finishedKey = "review.finishedListens"
    static let askAfter: Set<Int> = [3, 10, 30]

    @MainActor
    static func listenFinished(defaults: UserDefaults = .standard) {
        let count = defaults.integer(forKey: finishedKey) + 1
        defaults.set(count, forKey: finishedKey)
        guard askAfter.contains(count) else { return }
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard let scene else { return }
        AppStats.record("review_prompt")
        AppStore.requestReview(in: scene)
    }
}
