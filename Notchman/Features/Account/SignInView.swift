import AuthenticationServices
import SwiftUI

/// "Welcome back" screen from the Notchman design.
struct SignInView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var showsEmailNotice = false
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
                    .font(.pixel(46))
                    .foregroundStyle(Theme.amberGradient)
                    .padding(.top, 8)

                Spacer(minLength: 30)

                Text("Welcome back")
                    .font(.system(size: 40, weight: .bold))
                Text("Sign in to make Notchman yours")
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

                    Button {
                        showsEmailNotice = true
                    } label: {
                        Label("Continue with Email", systemImage: "envelope.fill")
                            .font(.title3.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 66)
                            .foregroundStyle(.white)
                            .background(Theme.card.opacity(0.8), in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
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
        .alert("Email sign-in is coming soon", isPresented: $showsEmailNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("For now, Sign in with Apple is the way to create a Notchman account. You can also keep using Notchman without one.")
        }
        .sheet(isPresented: $showsPrivacy) {
            NavigationStack { PrivacyDetailsView() }
                .preferredColorScheme(.dark)
        }
    }
}

/// Plain-language privacy summary, shared by Settings and Sign In.
struct PrivacyDetailsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                privacyRow("iphone", "Stored on this iPhone",
                           "Your listening history lives only on this device. No tracking, no ads.")
                privacyRow("waveform", "Speech",
                           FeatureFlags.cloudTLDR
                           ? "Reading aloud uses Apple's built-in voices, processed by iOS. Pro and Pro+ TL;DRs are recorded in a natural voice by ElevenLabs."
                           : "Reading aloud uses Apple's built-in voices, processed by iOS.")
                privacyRow("sparkles", "TL;DR",
                           FeatureFlags.cloudTLDR
                           ? "Free TL;DRs are made on your iPhone. For Pro and Pro+, the message is sent to Notchman's server, summarized by Groq and voiced by ElevenLabs. Notchman doesn't store it; the server only keeps a count of how many TL;DRs you've used this month."
                           : "TL;DRs are made on your iPhone with Apple Intelligence or Notchman's built-in summarizer. Your messages never leave the device.")
                privacyRow("app.badge", "Logos",
                           "To show app and site logos, Notchman looks up the app name on the App Store or fetches the site's icon. Only the name or domain is sent, never your messages.")
                privacyRow("person.crop.circle", "Account",
                           "Signing in is optional. Your Apple ID sign-in is stored in this iPhone's Keychain; Notchman has no servers that receive your content.")
            }
        }
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
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
