import SwiftUI
import UIKit

/// Notchman's visual language: near-black surfaces, amber accents, pixel-art
/// mascot and pixel type for playful moments. The app is designed dark-first.
enum Theme {
    static let background = Color(red: 0.043, green: 0.043, blue: 0.051)     // #0B0B0D
    static let card = Color(red: 0.094, green: 0.094, blue: 0.106)           // #18181B
    static let cardRaised = Color(red: 0.137, green: 0.137, blue: 0.149)     // #232326
    static let stroke = Color.white.opacity(0.06)
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.11)              // #FFB81C
    static let amberDeep = Color(red: 0.96, green: 0.58, blue: 0.04)         // #F5940A
    static let tldr = Color(red: 1.0, green: 0.36, blue: 0.37)               // #FF5C5F
    static let secondaryText = Color.white.opacity(0.55)
    static let tertiaryText = Color.white.opacity(0.35)

    static let amberGradient = LinearGradient(colors: [amber, amberDeep], startPoint: .top, endPoint: .bottom)

    static let cornerRadius: CGFloat = 22
    static let horizontalPadding: CGFloat = 20
}

extension Font {
    /// Large rounded display type ("Read less. Listen instead.").
    static func display(_ size: CGFloat = 36) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }

    /// Silkscreen pixel type for playful labels: "TL;DR", "GOT IT", the wordmark.
    static func pixel(_ size: CGFloat, bold: Bool = true) -> Font {
        .custom(bold ? "Silkscreen-Bold" : "Silkscreen-Regular", size: size, relativeTo: .body)
    }
}

extension SourceType {
    var tint: Color {
        switch self {
        case .chatGPT: Color(red: 0.86, green: 0.88, blue: 0.87)
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .gemini: Color(red: 0.45, green: 0.62, blue: 1.0)
        case .reddit: Color(red: 1.0, green: 0.34, blue: 0.12)
        case .linkedin: Color(red: 0.04, green: 0.40, blue: 0.76)
        case .email: Color(red: 0.30, green: 0.60, blue: 1.0)
        case .webpage: Color(red: 0.55, green: 0.75, blue: 1.0)
        case .text: Color(red: 0.35, green: 0.85, blue: 0.40)
        }
    }
}

enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - Buttons

/// Large amber capsule ("Go Premium").
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 58)
            .foregroundStyle(Color.black.opacity(0.85))
            .background(Theme.amberGradient, in: Capsule())
            .shadow(color: Theme.amber.opacity(0.25), radius: 16, y: 6)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

/// Dark rounded button with a hairline border ("View full text").
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 58)
            .foregroundStyle(.white)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 29, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 29, style: .continuous).stroke(Theme.stroke))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var notchmanPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var notchmanSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// Circular dark icon button used in top bars (back, more, settings).
struct CircleIconButtonStyle: ButtonStyle {
    var size: CGFloat = 46

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.cardRaised, in: Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Dates

enum RelativeDay {
    static func string(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// History section headers: "Today", "Yesterday", "Earlier".
    static func section(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: date, to: .now).day, days < 7 { return "This Week" }
        return "Earlier"
    }
}
