import SafariServices
import SwiftUI

/// The Terms of Service and Privacy Policy everyone agrees to before using
/// Notchman. Bump `version` (the documents' date) when either changes
/// materially: everyone is asked again.
enum LegalAgreement {
    static let version = "2026-10-11"
    static let versionKey = "legal.acceptedVersion"
    private static let dateKey = "legal.acceptedAt"

    static var isAccepted: Bool { AppGroup.defaults.string(forKey: versionKey) == version }

    /// Records the tick on this device: which version, and when.
    static func accept() {
        AppGroup.defaults.set(version, forKey: versionKey)
        AppGroup.defaults.set(Date(), forKey: dateKey)
        // The agreement screen also says where message text goes.
        VoiceConsent.hasSeenNotice = true
    }
}

/// Where message text goes, the round "I agree" tick and Continue. Used in
/// onboarding and when the Terms change.
struct AgreementPanel: View {
    var onAgree: () -> Void
    @State private var agreed = false

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 0) {
                row("text.alignleft", "Groq writes the TL;DR")
                Divider().overlay(Theme.stroke).padding(.leading, 54)
                row("waveform", "ElevenLabs speaks it")
                Divider().overlay(Theme.stroke).padding(.leading, 54)
                row("lock.fill", "Your text isn't stored")
            }
            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))

            AgreeCheckbox(agreed: $agreed)

            Button {
                Haptics.success()
                LegalAgreement.accept()
                onAgree()
            } label: {
                Text("Continue")
            }
            .buttonStyle(.notchmanPrimary)
            .disabled(!agreed)
            .padding(.top, 6)
        }
        .opensLegalPagesInApp()
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.amber)
                .frame(width: 26)
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.primaryText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }
}

/// "I agree to the Terms of Service and Privacy Policy" with a round tick box.
/// The links open the full documents inside the app.
struct AgreeCheckbox: View {
    @Binding var agreed: Bool

    var body: some View {
        HStack(spacing: 14) {
            Button {
                Haptics.tap()
                withAnimation(.snappy) { agreed.toggle() }
            } label: {
                Image(systemName: agreed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 28))
                    .foregroundStyle(agreed ? Theme.amber : Theme.tertiaryText)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("I agree to the Terms of Service and Privacy Policy")
            .accessibilityAddTraits(agreed ? .isSelected : [])

            Text("I agree to the [Terms of Service](https://notchman.app/terms?app=1) and [Privacy Policy](https://notchman.app/privacy?app=1)")
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .tint(Theme.amber)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
                .strokeBorder(agreed ? Theme.amber : Theme.stroke, lineWidth: agreed ? 2 : 1)
        )
    }
}

/// Shown instead of the app when the Terms changed since you last agreed.
struct AgreementScreen: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ShibaBuddy(mood: .hello)
                    .frame(width: 116)
                    .padding(.top, 24)
                Text("Our terms have changed")
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                AgreementPanel {}
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Theme.sky.ignoresSafeArea())
    }
}

/// A page of notchman.app shown inside the app.
private struct LegalPage: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Safari inside the app, for the Terms and the Privacy Policy.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(Theme.amber)
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

extension View {
    /// Opens notchman.app links (the Terms, the Privacy Policy) in a sheet
    /// inside the app instead of switching to Safari.
    func opensLegalPagesInApp() -> some View { modifier(LegalPagesInApp()) }
}

private struct LegalPagesInApp: ViewModifier {
    @State private var page: LegalPage?

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                guard url.host() == Legal.terms.host() else { return .systemAction }
                page = LegalPage(url: url)
                return .handled
            })
            .sheet(item: $page) { page in
                SafariView(url: page.url).ignoresSafeArea()
            }
    }
}
