import SwiftUI

/// Small capsule showing where content came from.
struct SourceBadge: View {
    let type: SourceType
    let name: String

    var body: some View {
        Label(name, systemImage: type.symbolName)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(type.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(type.tint.opacity(0.12), in: Capsule())
    }
}

/// Rounded-square source icon used in lists.
struct SourceIcon: View {
    let type: SourceType
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: type.symbolName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(type.tint)
            .frame(width: size, height: size)
            .background(type.tint.opacity(0.13), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

struct QuickBadge: View {
    var body: some View {
        Label("Quick", systemImage: "bolt.fill")
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(Color.accentColor)
    }
}

/// Thin progress capsule.
struct ProgressCapsule: View {
    let value: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                Capsule().fill(Color.accentColor)
                    .frame(width: max(height, proxy.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int(value * 100)) percent"))
    }
}

/// Four bars that dance while audio plays.
struct WaveformView: View {
    var isAnimating: Bool
    var color: Color = .accentColor

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isAnimating)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                HStack(alignment: .center, spacing: proxy.size.width * 0.12) {
                    ForEach(0..<4, id: \.self) { index in
                        let phase = time * 5 + Double(index) * 1.3
                        let level = isAnimating ? 0.35 + 0.65 * abs(sin(phase)) : 0.3
                        Capsule()
                            .fill(color)
                            .frame(height: proxy.size.height * level)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The Notchman character: a Dynamic Island–shaped pill wearing tiny headphones.
struct NotchmanMark: View {
    var size: CGFloat = 120
    var isListening = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let width = size
        let height = size * 0.36

        ZStack {
            HeadbandShape()
                .stroke(Color.primary, style: StrokeStyle(lineWidth: size * 0.045, lineCap: .round))
                .frame(width: width * 0.9, height: height * 0.75)
                .offset(y: -height * 0.72)

            HStack(spacing: width * 0.77) {
                earCup
                earCup
            }

            Capsule()
                .fill(Color.black)
                .overlay(Capsule().stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0), lineWidth: 1))
                .frame(width: width * 0.86, height: height)

            HStack(spacing: width * 0.16) {
                eye
                eye
            }
            .phaseAnimator([false, true]) { content, blink in
                content.scaleEffect(y: blink && isListening ? 0.25 : 1)
            } animation: { blink in
                blink ? .easeInOut(duration: 0.12).delay(1.8) : .easeInOut(duration: 0.12)
            }
        }
        .frame(width: width * 1.05, height: height * 2.6)
        .offset(y: height * 0.35)
        .accessibilityHidden(true)
    }

    private var earCup: some View {
        RoundedRectangle(cornerRadius: size * 0.05, style: .continuous)
            .fill(Color.accentColor)
            .frame(width: size * 0.13, height: size * 0.26)
    }

    private var eye: some View {
        Circle()
            .fill(Color.white)
            .frame(width: size * 0.06, height: size * 0.06)
    }
}

private struct HeadbandShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                      control1: CGPoint(x: rect.minX, y: rect.minY - rect.height * 0.35),
                      control2: CGPoint(x: rect.maxX, y: rect.minY - rect.height * 0.35))
        return path
    }
}

#Preview {
    VStack(spacing: 40) {
        NotchmanMark(size: 160, isListening: true)
        SourceBadge(type: .chatGPT, name: "ChatGPT")
        WaveformView(isAnimating: true).frame(width: 30, height: 24)
    }
}
