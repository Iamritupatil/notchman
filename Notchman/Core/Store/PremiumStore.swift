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
        let badge: String?
        /// Shown until the App Store price loads (and in screenshots).
        let fallbackPrice: String
    }

    static let plans: [Plan] = [
        Plan(id: "com.notchman.pro.monthly", name: "Pro",
             headline: "About 28 min of voice a month", badge: nil, fallbackPrice: "$4.99"),
        Plan(id: "com.notchman.proplus.monthly", name: "Pro+",
             headline: "About 67 min of voice a month", badge: "Best value", fallbackPrice: "$9.99"),
    ]

    /// What every plan has, shown above the plans.
    static let benefits: [(symbol: String, text: String)] = [
        ("waveform", "Natural Notchman voice"),
        ("globe", "In your message's language"),
        ("xmark.circle", "Cancel anytime"),
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
    /// Why the plans didn't load, for the message when buying fails.
    private(set) var loadProblem: String?

    private let log = Logger(subsystem: "com.notchman", category: "Premium")
    private var updatesTask: Task<Void, Never>?
    private var loading: Task<Void, Never>?

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

    /// Loads prices from the App Store (in the customer's currency). Callers
    /// that arrive while a load is running wait for that same load.
    func loadProducts() async {
        if let loading { return await loading.value }
        let task = Task { await fetchProducts() }
        loading = task
        await task.value
        loading = nil
    }

    private func fetchProducts() async {
        loadState = .loading
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            loadState = loaded.isEmpty ? .failed : .loaded
            loadProblem = loaded.isEmpty ? "The App Store returned none of \(Self.productIDs.joined(separator: ", "))." : nil
            if loaded.isEmpty { log.error("No products returned for \(Self.productIDs, privacy: .public)") }
        } catch {
            log.error("Loading products failed: \(error.localizedDescription, privacy: .public)")
            loadProblem = error.localizedDescription
            loadState = .failed
        }
    }

    /// Why a plan can't be bought right now, in words for the customer.
    var unavailableReason: String {
        var text = "The App Store didn't load this plan. Try again in a few minutes."
        if FeatureFlags.isTestFlight {
            text += "\n\nTestFlight: needs the Paid Apps Agreement in App Store Connect."
        }
        if let loadProblem { text += "\n\nDetails: \(loadProblem)" }
        return text
    }

    /// "$4.99" in the customer's currency, or the fallback until prices load.
    func price(for plan: Plan) -> String {
        products[plan.id]?.displayPrice ?? plan.fallbackPrice
    }

    /// Buys a plan. `buy` is SwiftUI's purchase action (from the paywall),
    /// which shows Apple's payment sheet over the app's own window.
    func purchase(_ plan: Plan, using buy: (Product) async throws -> Product.PurchaseResult) async -> PurchaseOutcome {
        guard let product = products[plan.id] else {
            return .failed(unavailableReason)
        }
        do {
            switch try await buy(product) {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    return .failed("The App Store couldn't verify this purchase. Try again.")
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
