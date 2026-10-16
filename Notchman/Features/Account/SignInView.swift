import AuthenticationServices
import SwiftUI

/// "Welcome back" screen from the Notchman design.
struct SignInView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var showsPrivacy = false

    var body: some View {
        ZStack {
            PixelSkyBackground()

            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .buttonStyle(CircleIconButtonStyle(size: 50))
                        .accessibilityLabel("Close")
                    Spacer()
                }
                .padding(.top, 16)

                Spacer(minLength: 20)

                ShibaSprite(isActive: true, image: "MascotCollar")
                    .frame(width: 190)
                Text("Notchman")
                    .font(.brand(46))
                    .foregroundStyle(Theme.amberGradient)
                    .padding(.top, 8)

                Spacer(minLength: 30)

                Text("Sign in")
                    .font(.pageTitle)
                Text("Keep your plan on every device")
                    .font(.title3)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 6)

                VStack(spacing: 16) {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        account.handle(result)
                        if account.isSignedIn {
                            Haptics.success()
                            dismiss()
                        }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 66)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.08)))
                }
                .padding(.top, 34)

                HStack(spacing: 4) {
                    Text("By continuing you agree to the")
                        .foregroundStyle(Theme.secondaryText)
                    Button("Terms & Privacy Policy") { showsPrivacy = true }
                        .foregroundStyle(Theme.amber)
                }
                .font(.footnote)
                .padding(.top, 26)

                Spacer(minLength: 30)
            }
            .padding(.horizontal, 24)
        }
        .sheet(isPresented: $showsPrivacy) {
            NavigationStack { PrivacyDetailsView() }
                .preferredColorScheme(.light)
        }
    }
}

/// Plain-language privacy summary, shared by Settings and Sign In.
struct PrivacyDetailsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Group {
                privacyRow("iphone", "On this iPhone", "History and audio stay here. No ads, no tracking.")
                if FeatureFlags.cloudTLDR {
                    privacyRow("sparkles", "TL;DR", "Groq summarizes the text. It isn't stored.")
                    privacyRow("waveform", "Voice", "ElevenLabs speaks it. It isn't stored.")
                } else {
                    privacyRow("sparkles", "TL;DR and voice", "Made on your iPhone. Nothing is sent.")
                }
                privacyRow("photo", "Screenshots", "Read on your iPhone. Never uploaded.")
                privacyRow("chart.bar", "Usage statistics", "Which features are used, never what you read. Off in Settings.")
                privacyRow("person.crop.circle", "Sign in", "Optional. Your email and Apple account ID are kept with your plan, so we can help you. Delete Account removes them.")
                Link(destination: Legal.privacy) {
                    Label("Full Privacy Policy", systemImage: "lock.doc")
                        .font(.headline)
                }
            }
            .listRowBackground(RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous).fill(Theme.cardRaised))
            .listRowSeparator(.hidden)
        }
        .listRowSpacing(10)
        .scrollContentBackground(.hidden)
        .background(Theme.sky.ignoresSafeArea())
        .opensLegalPagesInApp()
        .navigationTitle("Privacy")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
        }
    }

    private func privacyRow(_ symbol: String, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.headline)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 6)
    }
}
