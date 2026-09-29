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
                           ? "TL;DRs and full reads are voiced by ElevenLabs: the text is sent to Notchman's server, which passes it to ElevenLabs to make the audio. The audio is kept on this iPhone so it replays instantly."
                           : "Reading aloud uses Apple's built-in voices, processed by iOS.")
                privacyRow("sparkles", "TL;DR",
                           FeatureFlags.cloudTLDR
                           ? "The message is sent to Notchman's server and summarized by Groq. Notchman doesn't store it; the server only keeps counts of how much you've used. Screenshots are read on your iPhone and never uploaded."
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
