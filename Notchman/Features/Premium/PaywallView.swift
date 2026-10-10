import StoreKit
import SwiftUI

/// Notchman Pro / Pro+ paywall. Our own layout on StoreKit 2: the plans are
/// always visible with what they include, prices come from the App Store in
/// the customer's currency, and every App Store requirement is here (price
/// and period, auto-renewal terms, restore, manage, Terms and Privacy).
struct PaywallView: View {
    @Environment(PremiumStore.self) private var premium
    @Environment(\.dismiss) private var dismiss
    @Environment(\.purchase) private var purchaseAction
    @State private var selectedID = PremiumStore.plans[0].id
    @State private var working = false
    @State private var notice: Notice?
    @State private var showManage = false

    /// What happened after Subscribe or Restore, shown as an alert.
    private struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private var selected: PremiumStore.Plan {
        PremiumStore.plans.first { $0.id == selectedID } ?? PremiumStore.plans[0]
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.sky.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    MascotStage(width: 112)
                        .frame(height: 118)
                        .padding(.top, 8)
                    VStack(spacing: 6) {
                        Text("Notchman Pro")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(Theme.primaryText)
                        Text("Hear your TL;DRs in the natural Notchman voice.")
                            .font(.callout)
                            .foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    benefits
                    VStack(spacing: 12) {
                        ForEach(PremiumStore.plans) { plan in planCard(plan) }
                    }
                    purchaseArea
                    footer
                }
                .padding(.horizontal, Theme.horizontalPadding)
                .padding(.top, 24)
                .padding(.bottom, 28)
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.8), in: Circle())
            }
            .accessibilityLabel("Close")
            .padding(16)
        }
        .task {
            if premium.loadState != .loaded { await premium.loadProducts() }
            if let active = premium.activeProductID { selectedID = active }
        }
        .manageSubscriptionsSheet(isPresented: $showManage)
        .alert(notice?.title ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } }),
               presenting: notice) { _ in
            Button("OK", role: .cancel) {}
        } message: { notice in
            Text(notice.message)
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(PremiumStore.benefits, id: \.text) { benefit in
                Label {
                    Text(benefit.text).foregroundStyle(Theme.primaryText)
                } icon: {
                    Image(systemName: benefit.symbol).foregroundStyle(Theme.amber)
                }
                .font(.subheadline.weight(.medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    private func planCard(_ plan: PremiumStore.Plan) -> some View {
        let isSelected = plan.id == selectedID
        let isCurrent = plan.id == premium.activeProductID
        return Button {
            selectedID = plan.id
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.amber : Theme.tertiaryText)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(plan.name).font(.headline).foregroundStyle(Theme.primaryText)
                        if isCurrent {
                            tag("Your plan", color: .green)
                        } else if let badge = plan.badge {
                            tag(badge, color: Theme.amber)
                        }
                        Spacer(minLength: 4)
                        Text("\(premium.price(for: plan)) / month")
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                    }
                    Text(plan.headline).font(.subheadline).foregroundStyle(Theme.primaryText)
                    Text(plan.detail).font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .strokeBorder(isSelected ? Theme.amber : Theme.stroke, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color, in: Capsule())
    }

    @ViewBuilder
    private var purchaseArea: some View {
        VStack(spacing: 10) {
            if premium.activeProductID == selectedID {
                Button("Manage subscription") { showManage = true }
                    .buttonStyle(.notchmanPrimary)
            } else {
                Button {
                    Task { await buy() }
                } label: {
                    if working || premium.loadState == .loading {
                        ProgressView().tint(.white)
                    } else {
                        Text(premium.isPremium ? "Switch to \(selected.name)" : "Subscribe to \(selected.name) for \(premium.price(for: selected))/month")
                    }
                }
                .buttonStyle(.notchmanPrimary)
                .disabled(working)
            }
            if premium.loadState == .failed {
                HStack(spacing: 6) {
                    Text("Prices couldn't load from the App Store.")
                    Button("Try again") { Task { await premium.loadProducts() } }
                        .fontWeight(.semibold)
                }
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 18) {
                Button("Restore Purchases") { Task { await restore() } }
                if premium.isPremium {
                    Button("Manage") { showManage = true }
                }
            }
            .font(.footnote.weight(.semibold))
            .tint(Theme.amber)
            Text("Payment is charged to your Apple ID when you confirm. Subscriptions renew automatically each month unless cancelled at least 24 hours before the end of the current period; renewal is charged within the 24 hours before it ends. Manage or cancel anytime in Settings → your name → Subscriptions.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Link("Terms of Service", destination: Legal.terms)
                Link("Privacy Policy", destination: Legal.privacy)
            }
            .font(.caption.weight(.semibold))
            .tint(Theme.amber)
        }
        .padding(.top, 4)
    }

    private func buy() async {
        working = true
        defer { working = false }
        if premium.loadState != .loaded { await premium.loadProducts() }
        switch await premium.purchase(selected, with: purchaseAction) {
        case .purchased:
            dismiss()
        case .pending:
            notice = Notice(title: "Waiting for approval",
                            message: "Your purchase is waiting for approval. Notchman Pro switches on as soon as it's approved.")
        case .cancelled:
            break
        case .failed(let reason):
            notice = Notice(title: "Couldn't subscribe", message: reason)
        }
    }

    private func restore() async {
        working = true
        defer { working = false }
        notice = await premium.restore()
            ? Notice(title: "Restored", message: "Thanks for supporting Notchman!")
            : Notice(title: "Nothing to restore", message: "No active Notchman subscription was found for this Apple ID.")
    }
}

/// The legal pages on notchman.app (linked from the paywall and Settings).
enum Legal {
    static let terms = URL(string: "https://notchman.app/terms")!
    static let privacy = URL(string: "https://notchman.app/privacy")!
}
