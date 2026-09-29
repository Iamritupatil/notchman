import SwiftUI

/// Whether the user agreed to send message text to Notchman's AI partners.
enum VoiceConsent {
    private static let key = "voiceConsent.granted"

    static var isGranted: Bool {
        get { AppGroup.defaults.bool(forKey: key) }
        set { AppGroup.defaults.set(newValue, forKey: key) }
    }
}

/// Asked once, before the first TL;DR or Read. Apple requires clear disclosure
/// and permission before personal data goes to third-party AI services.
struct VoiceConsentView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 22) {
            MascotStage(isActive: true, width: 110)
                .frame(height: 120)
                .padding(.top, 28)

            VStack(spacing: 8) {
                Text("Hear it in Notchman's voice")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("To make the TL;DR and read it naturally, Notchman sends the message's text to two AI services.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 0) {
                row("text.alignleft", "Groq", "Writes the TL;DR.")
                Divider().overlay(Theme.stroke).padding(.leading, 56)
                row("waveform", "ElevenLabs", "Speaks it in a natural voice.")
                Divider().overlay(Theme.stroke).padding(.leading, 56)
                row("lock.fill", "Only for your audio", "Notchman doesn't store your text on its servers. Screenshots never leave your iPhone.")
            }
            .card()

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Button("Continue") { env.voiceConsentAnswered(true) }
                    .buttonStyle(.notchmanPrimary)
                Button("Not Now") { env.voiceConsentAnswered(false) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
        .background(Theme.background.ignoresSafeArea())
        .interactiveDismissDisabled()
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.amber)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }
}
