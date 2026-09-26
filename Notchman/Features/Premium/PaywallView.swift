import StoreKit
import SwiftUI

/// Notchman Premium paywall, using StoreKit's native subscription store so
/// prices, trials, purchase and restore are all handled by the system.
struct PaywallView: View {
    @Environment(PremiumStore.self) private var premium
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubscriptionStoreView(productIDs: PremiumStore.productIDs) {
            VStack(spacing: 18) {
                MascotStage(width: 110)
                    .frame(height: 170)
                Text("Notchman Premium")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.amberGradient)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(PremiumStore.benefits, id: \.text) { benefit in
                        Label {
                            Text(benefit.text).foregroundStyle(.white)
                        } icon: {
                            Image(systemName: benefit.symbol).foregroundStyle(Theme.amber)
                        }
                        .font(.body.weight(.medium))
                    }
                }
                .padding(.horizontal, 8)
            }
            .padding(.top, 24)
            .padding(.horizontal, 20)
        }
        .subscriptionStoreControlBackground(.clear)
        .storeButton(.visible, for: .restorePurchases)
        .storeButton(.visible, for: .cancellation)
        .tint(Theme.amber)
        .background(Theme.background.ignoresSafeArea())
        .onInAppPurchaseCompletion { _, result in
            if case .success(.success) = result {
                await premium.refresh()
                dismiss()
            }
        }
    }
}
