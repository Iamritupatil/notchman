import Foundation
import Observation
import os
import StoreKit

/// Notchman Pro / Pro+ subscriptions, backed by StoreKit 2.
///
/// Product identifiers must match App Store Connect (scripts/asc.py creates
/// them) and `StoreKit/Notchman.storekit` for local testing. Entitlements are
/// read from `Transaction.currentEntitlements` and kept current by listening to
/// `Transaction.updates`. The server reads the same signed transactions to
/// apply the plan, so nothing else needs to be told about a purchase.
@MainActor
@Observable
final class PremiumStore {
    /// Keep in sync with server/src/plans.ts and App Store Connect.
    static let proProductIDs = ["com.notchman.pro.monthly"]
    static let proPlusProductIDs = ["com.notchman.proplus.monthly"]
    static var productIDs: [String] { proProductIDs + proPlusProductIDs }

    /// What each plan includes. The server enforces these same allowances.
    struct Plan: Identifiable {
        let id: String
        let name: String
        let headline: String
        let detail: String
        let badge: String?
        /// Shown until the App Store price loads (and in screenshots).
        let fallbackPrice: String
    }

    static let plans: [Plan] = [
        Plan(id: "com.notchman.pro.monthly", name: "Pro",
             headline: "25,000 characters a month in the natural voice",
             detail: "About 28 minutes of listening, then the free voice", badge: nil, fallbackPrice: "$4.99"),
        Plan(id: "com.notchman.proplus.monthly", name: "Pro+",
             headline: "60,000 characters a month in the natural voice",
             detail: "About 1 hour 7 minutes, enough for full reads", badge: "Best value", fallbackPrice: "$9.99"),
    ]

    /// What every plan has, shown above the plans.
    static let benefits: [(symbol: String, text: String)] = [
        ("waveform", "The natural Notchman voice, in your message's language"),
        ("sparkles", "Complete TL;DRs with every key point and number"),
        ("bolt.fill", "Faster: audio starts in seconds"),
        ("heart.fill", "Free stays free: daily TL;DRs with the iPhone voice"),
    ]

    enum LoadState: Equatable { case idle, loading, loaded, failed }

    enum PurchaseOutcome: Equatable {
        case purchased, pending, cancelled
        case failed(String)
    }

    private(set) var isPremium = false
    /// The product of the active subscription, if any.
    private(set) var activeProductID: String?
    private(set) var products: [String: Product] = [:]
    private(set) var loadState: LoadState = .idle

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
        var active: String?
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               Self.productIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                // Pro+ wins if, briefly, both are active (an upgrade in progress).
                if active == nil || Self.proPlusProductIDs.contains(transaction.productID) {
                    active = transaction.productID
                }
            }
        }
        activeProductID = active
        isPremium = active != nil
    }

    /// Loads prices from the App Store (in the customer's currency).
    func loadProducts() async {
        guard loadState != .loading else { return }
        loadState = .loading
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            loadState = loaded.isEmpty ? .failed : .loaded
            if loaded.isEmpty { log.error("No products returned for \(Self.productIDs, privacy: .public)") }
        } catch {
            log.error("Loading products failed: \(error.localizedDescription, privacy: .public)")
            loadState = .failed
        }
    }

    /// "$4.99" in the customer's currency, or the fallback until prices load.
    func price(for plan: Plan) -> String {
        products[plan.id]?.displayPrice ?? plan.fallbackPrice
    }

    func purchase(_ plan: Plan) async -> PurchaseOutcome {
        guard let product = products[plan.id] else {
            return .failed("The App Store didn't load this plan. Check your connection and try again.")
        }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    return .failed("The App Store couldn't verify this purchase. Please try again.")
                }
                await transaction.finish()
                await refresh()
                return .purchased
            case .pending:
                // Ask to Buy or a payment that needs approval: Transaction.updates delivers it later.
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .cancelled
            }
        } catch {
            log.error("Purchase failed: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }

    #if DEBUG
    /// Screenshots (-demoScreen paywall): show the plans with their usual prices, no App Store.
    func useDemoPrices() {
        loadState = .loaded
    }
    #endif

    /// Restores purchases made with this Apple ID (asks the App Store to sync).
    func restore() async -> Bool {
        do {
            try await AppStore.sync()
        } catch {
            log.error("Restore failed: \(error.localizedDescription, privacy: .public)")
        }
        await refresh()
        return isPremium
    }
}
