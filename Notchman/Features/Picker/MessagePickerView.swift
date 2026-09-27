import SwiftUI
import UIKit

/// "Which message?" — shows the captured screen with glass borders around
/// each detected message. The user taps one within 3 seconds, or Notchman
/// plays the TL;DR of the one that glows: the main message as judged by Apple
/// Intelligence (`MessageChooser`), or the longest one without it.
struct MessagePickerView: View {
    let imageURL: URL
    /// TL;DR or Read in full; the user can switch before the countdown ends.
    @State var action: PendingListen.Action = .quickListen

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    enum Phase: Equatable {
        case reading
        case choosing(deadline: Date)
        case chosen
        case failed(String)
    }

    static let choiceWindow: TimeInterval = 3

    @State private var image: UIImage?
    @State private var lines: [TextLine] = []
    @State private var blocks: [MessageBlock] = []
    @State private var defaultID: Int?
    @State private var selectedID: Int?
    @State private var phase: Phase = .reading
    @State private var countdown: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                GeometryReader { proxy in
                    let frame = fittedRect(for: image.size, in: proxy.size)
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                            .opacity(phase == .reading ? 0.6 : 0.85)

                        ForEach(blocks) { block in
                            GlassBorder(isDefault: block.id == defaultID && selectedID == nil,
                                        isSelected: block.id == selectedID)
                                .frame(width: block.box.width * frame.width + 16,
                                       height: block.box.height * frame.height + 16)
                                .offset(x: frame.minX + block.box.minX * frame.width - 8,
                                        y: frame.minY + block.box.minY * frame.height - 8)
                                .onTapGesture { choose(block) }
                                .accessibilityElement()
                                .accessibilityLabel("Message: \(block.text.prefix(80))")
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                }
                .ignoresSafeArea()
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedID)
            }

            VStack {
                HStack {
                    Button { cancel() } label: { Image(systemName: "xmark") }
                        .buttonStyle(CircleIconButtonStyle())
                        .accessibilityLabel("Cancel")
                    Spacer()
                }
                .padding(.horizontal, 20)
                Spacer()
                statusPill
                    .padding(.bottom, 30)
            }
        }
        .task { await load() }
        .onDisappear { countdown?.cancel() }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusPill: some View {
        HStack(spacing: 12) {
            switch phase {
            case .reading:
                ProgressView().tint(Theme.amber)
                Text("Finding the long message…")
            case .choosing(let deadline):
                TimelineView(.animation) { context in
                    let remaining = max(0, deadline.timeIntervalSince(context.date))
                    CountdownRing(fraction: remaining / Self.choiceWindow, seconds: Int(remaining.rounded(.up)))
                }
                ModeSwitch(action: $action)
            case .chosen:
                ShibaSprite(isActive: true).frame(width: 26)
                Text(action == .read ? "Reading it…" : "Summing it up…")
            case .failed(let message):
                Image(systemName: "text.badge.xmark").foregroundStyle(Theme.amber)
                Text(message)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.18)))
        .padding(.horizontal, 20)
    }

    // MARK: - Flow

    private func load() async {
        guard let data = try? Data(contentsOf: imageURL), let uiImage = UIImage(data: data), let cgImage = uiImage.cgImage else {
            phase = .failed("That screenshot couldn't be opened.")
            return
        }
        image = uiImage
        do {
            lines = try await ScreenTextReader.lines(in: cgImage)
            blocks = MessageBlockDetector.blocks(from: lines)
            defaultID = MessageBlockDetector.defaultBlock(in: blocks)?.id
            guard !blocks.isEmpty else {
                phase = .failed("No long message found on that screen.")
                return
            }
            Haptics.tap()
            startCountdown()
            await refineDefault()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func startCountdown() {
        let deadline = Date().addingTimeInterval(blocks.count > 1 ? Self.choiceWindow : 1)
        phase = .choosing(deadline: deadline)
        countdown = Task {
            try? await Task.sleep(for: .seconds(deadline.timeIntervalSinceNow))
            guard !Task.isCancelled, let pick = blocks.first(where: { $0.id == defaultID }) else { return }
            choose(pick)
        }
    }

    /// Lets Apple Intelligence move the glow to the main message while the
    /// countdown runs. The user's own tap always wins.
    private func refineDefault() async {
        guard blocks.count > 1, let pick = await MessageChooser.choose(from: blocks) else { return }
        guard selectedID == nil, case .choosing = phase, pick.id != defaultID else { return }
        withAnimation(.snappy) { defaultID = pick.id }
    }

    private func choose(_ block: MessageBlock) {
        guard phase != .chosen else { return }
        countdown?.cancel()
        selectedID = block.id
        phase = .chosen
        Haptics.success()

        let source = MessageBlockDetector.guessSource(from: lines)
        let content = ExtractedContent(text: block.text, title: nil, sourceType: source,
                                       sourceName: source == .text ? "Screenshot" : source.displayName, url: nil)
        try? FileManager.default.removeItem(at: imageURL)
        // Short pause so the selection registers visually before the player takes over.
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            env.ingest(content, action: action)
        }
    }

    private func cancel() {
        countdown?.cancel()
        try? FileManager.default.removeItem(at: imageURL)
        dismiss()
    }

    private func fittedRect(for imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2,
                      width: size.width, height: size.height)
    }
}

/// Apple-style glass outline around a detected message.
private struct GlassBorder: View {
    var isDefault: Bool
    var isSelected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        shape
            .fill(Color.white.opacity(isSelected ? 0.10 : 0.04))
            .overlay(
                shape.stroke(
                    isSelected || isDefault
                        ? AnyShapeStyle(Theme.amberGradient)
                        : AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.25)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing)),
                    lineWidth: isSelected ? 3.5 : 2)
            )
            .shadow(color: (isSelected || isDefault ? Theme.amber : .white).opacity(isSelected ? 0.7 : 0.35),
                    radius: isSelected ? 16 : 10)
            .scaleEffect(isSelected ? 1.02 : 1)
            .contentShape(shape)
    }
}

/// TL;DR | Read, as a small glass segmented switch.
private struct ModeSwitch: View {
    @Binding var action: PendingListen.Action

    var body: some View {
        HStack(spacing: 4) {
            segment("TL;DR", .quickListen)
            segment("Read", .read)
        }
        .padding(3)
        .background(Color.white.opacity(0.08), in: Capsule())
        .animation(.snappy(duration: 0.2), value: action)
    }

    private func segment(_ title: String, _ value: PendingListen.Action) -> some View {
        Button {
            Haptics.tap()
            action = value
        } label: {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(action == value ? Color.black : Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background {
                    if action == value { Capsule().fill(Theme.amber) }
                }
        }
        .buttonStyle(.plain)
    }
}

private struct CountdownRing: View {
    let fraction: Double
    let seconds: Int

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.2), lineWidth: 3)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Theme.amber, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(seconds)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.amber)
        }
        .frame(width: 28, height: 28)
    }
}
