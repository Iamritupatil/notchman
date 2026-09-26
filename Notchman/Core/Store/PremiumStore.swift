import Foundation
import Observation
import os
import StoreKit

/// Notchman Premium subscription state, backed by StoreKit 2.
///
/// Product identifiers must match App Store Connect (and `StoreKit/Notchman.storekit`
/// for local testing). Entitlements are read from `Transaction.currentEntitlements`
/// and kept current by listening to `Transaction.updates`.
@MainActor
@Observable
final class PremiumStore {
    static let subscriptionGroupID = "21600001"
    static let productIDs = ["com.notchman.premium.monthly", "com.notchman.premium.yearly"]

    /// What the paywall promises. Keep this in sync with what Premium actually unlocks.
    static let benefits: [(symbol: String, text: String)] = [
        ("sparkles", "Smarter TL;DRs with Apple Intelligence, on your iPhone"),
        ("key.fill", "Or bring your own OpenAI key"),
        ("heart.fill", "Support an independent app"),
    ]

    private(set) var isPremium = false

    private let log = Logger(subsystem: "com.notchman", category: "Premium")
    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refresh()
            }
        }
        Task { await refresh() }
    }

    func refresh() async {
        var active = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               Self.productIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                active = true
            }
        }
        isPremium = active
    }
}
