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
    /// Keep in sync with server/src/plans.ts and App Store Connect.
    static let proProductIDs = ["com.notchman.pro.monthly", "com.notchman.pro.yearly"]
    static let proPlusProductIDs = ["com.notchman.proplus.monthly", "com.notchman.proplus.yearly"]
    static var productIDs: [String] { proPlusProductIDs + proProductIDs }

    /// What the paywall promises. The server enforces these same limits.
    static let benefits: [(symbol: String, text: String)] = [
        ("bolt.fill", "Pro: 40,000 characters a month (about 45 min)"),
        ("sparkles", "Pro+: 100,000 characters a month (about 1 h 50 min)"),
        ("waveform", "Natural AI voice, in your message's language"),
        ("heart.fill", "Free: TL;DRs with the iPhone voice, always"),
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
