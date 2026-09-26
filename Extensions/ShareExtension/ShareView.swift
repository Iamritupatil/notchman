import SwiftUI

struct ShareView: View {
    let model: ShareViewModel

    var body: some View {
        VStack {
            Spacer()
            card
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .background(Color.black.opacity(0.001).onTapGesture { model.dismiss() })
    }

    private var card: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Notchman", systemImage: "headphones")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .accessibilityLabel("Close")
            }

            switch model.phase {
            case .loading:
                ProgressView("Reading…")
                    .frame(maxWidth: .infinity, minHeight: 160)
            case .ready, .handingOff:
                ready
            case .saved:
                saved
            case .failed(let message):
                failed(message)
            }
        }
        .padding(20)
        .background(Color(red: 0.094, green: 0.094, blue: 0.106), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.15), radius: 30, y: 10)
    }

    @ViewBuilder
    private var ready: some View {
        VStack(spacing: 8) {
            Image("ShibaPaws")
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 72)
            Text("Ready to listen")
                .font(.title2.weight(.bold))
            if let content = model.content {
                Label(content.sourceName, systemImage: content.sourceType.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.11))
            }
            Text(model.title)
                .font(.body)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(.secondary)
            Text(model.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }

        VStack(spacing: 10) {
            Button {
                model.read()
            } label: {
                Group {
                    if model.phase == .handingOff {
                        ProgressView().tint(.black)
                    } else {
                        Label("Read full", systemImage: "play.fill")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(Color.black.opacity(0.85))
                .background(Color(red: 1.0, green: 0.72, blue: 0.11), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            Button {
                model.quickListen()
            } label: {
                Label("TL;DR", systemImage: "bolt.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(Color.primary)
                    .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        .disabled(model.phase == .handingOff)
    }

    private var saved: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.11))
            Text("Saved to Notchman")
                .font(.title3.weight(.bold))
            Text("Open Notchman (or tap the notification) and it will start reading.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done") { model.done() }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(Color(.systemBackground))
                .background(Color.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .buttonStyle(.plain)
        }
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "text.badge.xmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
            Button("Close") { model.dismiss() }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .buttonStyle(.plain)
        }
    }
}
