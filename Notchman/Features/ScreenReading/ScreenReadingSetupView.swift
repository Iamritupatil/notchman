import ReplayKit
import SwiftUI

/// Turns Screen Reading (the ReplayKit broadcast) on or off. While it's on,
/// tapping Notchman in the Dynamic Island shows the screen you were reading with
/// a glass border around each message.
struct ScreenReadingSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isOn = ScreenFrames.isBroadcasting

    var body: some View {
        VStack(spacing: 22) {
            Capsule().fill(Color.white.opacity(0.2)).frame(width: 36, height: 5).padding(.top, 10)

            ShibaSprite(isActive: isOn).frame(width: 84)

            VStack(spacing: 8) {
                Text(isOn ? "Screen Reading is on" : "Let Notchman see your screen")
                    .font(.title2.weight(.bold))
                Text(isOn
                     ? "Tap the Shiba in the Dynamic Island on any long message: ChatGPT, WhatsApp, LinkedIn, anything."
                     : "Turn it on once. Then tap the Shiba in the Dynamic Island on any long message and pick it within 3 seconds.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 10) {
                fact("lock.fill", "Stays on your iPhone. Nothing is recorded or uploaded; only the last few seconds are kept, then deleted.")
                fact("record.circle", "iOS shows a small red indicator while it's on.")
                fact("hand.tap.fill", "Turn it off any time from here or Control Center.")
            }
            .padding(16)
            .glassCard()
            .padding(.horizontal, 20)

            BroadcastButton(isOn: isOn)
                .frame(height: 56)
                .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .task {
            // Reflect the broadcast starting or stopping while this sheet is open.
            while !Task.isCancelled {
                let on = ScreenFrames.isBroadcasting
                if on != isOn { withAnimation(.smooth) { isOn = on } }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func fact(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Theme.amber).frame(width: 20)
            Text(text).font(.footnote).foregroundStyle(Theme.secondaryText)
        }
    }
}

/// Notchman-styled button that opens the system broadcast picker, preselected
/// to the Notchman Screen Reading extension. iOS only lets the system picker
/// start a broadcast, so our button forwards its tap to the picker's own button.
struct BroadcastButton: View {
    var isOn: Bool
    @State private var picker = RPSystemBroadcastPickerView(frame: .zero)

    var body: some View {
        Button {
            Haptics.tap()
            picker.subviews.compactMap { $0 as? UIButton }.first?.sendActions(for: .touchUpInside)
        } label: {
            Label(isOn ? "Turn Off Screen Reading" : "Turn On Screen Reading",
                  systemImage: isOn ? "stop.circle.fill" : "eye.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.notchmanPrimary)
        .background(PickerHost(picker: picker).frame(width: 1, height: 1).opacity(0.01))
    }

    private struct PickerHost: UIViewRepresentable {
        let picker: RPSystemBroadcastPickerView

        func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
            picker.preferredExtension = (Bundle.main.bundleIdentifier ?? "app.notchman") + ".screen"
            picker.showsMicrophoneButton = false
            return picker
        }

        func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
    }
}

private extension View {
    /// Apple-style frosted glass card.
    func glassCard() -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
    }
}
