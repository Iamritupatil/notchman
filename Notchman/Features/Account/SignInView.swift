import AuthenticationServices
import SwiftUI

/// "Welcome back" screen from the Notchman design.
struct SignInView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var showsEmail = false
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
                        showsEmail = true
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
        .sheet(isPresented: $showsEmail) {
            EmailSignInView {
                showsEmail = false
                dismiss()
            }
            .preferredColorScheme(.dark)
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

/// Email and password sign-in / sign-up (Firebase Auth).
struct EmailSignInView: View {
    var onSignedIn: () -> Void

    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var creating = false
    @State private var working = false
    @State private var message: String?
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    private var canSubmit: Bool {
        email.contains("@") && email.contains(".") && password.count >= 6 && !working
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Picker("", selection: $creating) {
                    Text("Sign In").tag(false)
                    Text("Create Account").tag(true)
                }
                .pickerStyle(.segmented)

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                    SecureField(creating ? "Password (6+ characters)" : "Password", text: $password)
                        .textContentType(creating ? .newPassword : .password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { if canSubmit { submit() } }
                }
                .padding(16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                }

                Button(action: submit) {
                    Group {
                        if working { ProgressView().tint(.black) } else { Text(creating ? "Create Account" : "Sign In") }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.notchmanPrimary)
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.5)

                if !creating {
                    Button("Forgot password?") { resetPassword() }
                        .font(.subheadline)
                        .foregroundStyle(Theme.amber)
                        .disabled(!email.contains("@"))
                }
                Spacer()
            }
            .padding(20)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(creating ? "Create Account" : "Sign In with Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
            .onAppear { focus = .email }
        }
        .presentationDetents([.medium, .large])
    }

    private func submit() {
        working = true
        message = nil
        Task {
            defer { working = false }
            do {
                try await account.emailSignIn(email: email, password: password, createAccount: creating)
                Haptics.success()
                onSignedIn()
            } catch {
                message = Self.friendly(error, creating: creating)
            }
        }
    }

    private func resetPassword() {
        Task {
            do {
                try await account.sendPasswordReset(to: email)
                message = "Check your inbox for a link to reset your password."
            } catch {
                message = Self.friendly(error, creating: false)
            }
        }
    }

    private static func friendly(_ error: Error, creating: Bool) -> String {
        let code = (error as NSError).code
        switch code {
        case 17007: return "That email already has an account. Switch to Sign In."
        case 17008: return "That email address doesn't look right."
        case 17026: return "Use a password with at least 6 characters."
        case 17004, 17009, 17011: return "Wrong email or password."
        case 17020: return "You're offline. Try again when you're connected."
        default: return error.localizedDescription
        }
    }
}
