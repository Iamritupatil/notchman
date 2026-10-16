import SwiftUI

struct AccountView: View {
    @Environment(AccountStore.self) private var account
    @Environment(PremiumStore.self) private var premium
    @Environment(AppRouter.self) private var router
    @AppStorage(SettingsKey.hasCompletedOnboarding, store: AppGroup.defaults) private var hasCompletedOnboarding = true
    @State private var showsPrivacy = false
    @State private var confirmsDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("Account")
                    .font(.pageTitle)
                    .padding(.top, Spacing.sm)

                profileCard
                if FeatureFlags.paidPlans {
                    premiumCard
                }

                VStack(spacing: 0) {
                    NavigationLink(value: Route.settings) { row("gearshape.fill", "Settings") }
                    divider
                    Button { showsPrivacy = true } label: { row("hand.raised.fill", "Privacy") }
                    divider
                    #if DEBUG
                    Button { router.sheet = .tryNotchman } label: { row("text.badge.plus", "Try Notchman") }
                    divider
                    #endif
                    Button { hasCompletedOnboarding = false } label: { row("sparkles", "Show onboarding again") }
                }
                .buttonStyle(.plain)
                .card()

                if account.isSignedIn {
                    Button("Sign Out", role: .destructive) { account.signOut() }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                    // Apple requires deleting an account in the app (guideline 5.1.1(v)).
                    Button("Delete Account", role: .destructive) { confirmsDelete = true }
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Spacing.page)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.sky.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Delete your account?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) { Task { await account.deleteAccount() } }
        } message: {
            Text("Your name, email and Apple account ID are deleted from Notchman's server and this iPhone. Your listens and subscription stay. To also stop using your Apple ID with Notchman: Settings → your name → Sign-In & Security → Sign in with Apple.")
        }
        .sheet(isPresented: $showsPrivacy) {
            NavigationStack { PrivacyDetailsView() }.preferredColorScheme(.light)
        }
    }

    private var profileCard: some View {
        HStack(spacing: 16) {
            ShibaSprite(image: "MascotCollar")
                .frame(width: 64)
                .frame(width: 80, height: 80)
                .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                if let signedIn = account.account {
                    Text(signedIn.displayName)
                        .font(.title3.weight(.semibold))
                    Text(signedIn.email ?? (signedIn.provider == "email" ? "Email account" : "Signed in with Apple"))
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    Text("Not signed in")
                        .font(.title3.weight(.semibold))
                    Text("Notchman works without an account.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 0)
            if !account.isSignedIn {
                Button("Sign In") { router.sheet = .signIn }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.amber, in: Capsule())
                    .fixedSize()
            }
        }
        .padding(16)
        .card()
    }

    @ViewBuilder
    private var premiumCard: some View {
        if premium.isPremium {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").foregroundStyle(Theme.amber)
                Text("Notchman Premium is active").font(.headline)
                Spacer()
            }
            .padding(18)
            .card()
        } else {
            Button { router.sheet = .paywall } label: { Text("Go Premium ✨").font(.title3.weight(.semibold)) }
                .buttonStyle(.notchmanPrimary)
        }
    }

    private var divider: some View {
        Divider().overlay(Theme.stroke).padding(.leading, 60)
    }

    private func row(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.amber)
                .frame(width: 30)
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.primaryText)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.tertiaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}
