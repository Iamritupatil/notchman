import SwiftUI
import UIKit

/// Notchman's visual language (the new design): a bright sky, white glass
/// cards, navy type, blue accents, and the pixel blue Shiba on its black pill.
/// The website and the Windows/Mac app use the same colours.
enum Theme {
    /// Sky gradient behind every screen (top to bottom).
    static let skyTop = Color(red: 0.486, green: 0.753, blue: 0.957)         // #7CC0F4
    static let skyMid = Color(red: 0.725, green: 0.871, blue: 0.976)         // #B9DEF9
    static let skyLow = Color(red: 0.918, green: 0.965, blue: 1.0)           // #EAF6FF
    static let sky = LinearGradient(stops: [.init(color: skyTop, location: 0), .init(color: skyMid, location: 0.38),
                                            .init(color: skyLow, location: 0.72),
                                            .init(color: Color(red: 0.969, green: 0.984, blue: 1.0), location: 1)],
                                    startPoint: .top, endPoint: .bottom)
    /// Solid stand-in for the sky where a single colour is needed.
    static let background = skyLow
    /// White glass cards.
    static let card = Color.white.opacity(0.78)
    static let cardRaised = Color.white.opacity(0.94)
    static let stroke = Color(red: 0.043, green: 0.122, blue: 0.267).opacity(0.08)
    /// The accent (blue in the new design; the name is kept from the first design).
    static let amber = Color(red: 0.106, green: 0.455, blue: 0.894)          // #1B74E4
    static let amberDeep = Color(red: 0.07, green: 0.36, blue: 0.78)
    static let accentLight = Color(red: 0.29, green: 0.65, blue: 1.0)         // #4AA6FF
    static let tldr = Color(red: 1.0, green: 0.36, blue: 0.37)               // #FF5C5F
    /// The Shiba's pill.
    static let pill = Color(red: 0.039, green: 0.047, blue: 0.071)           // #0A0C12
    static let primaryText = Color(red: 0.043, green: 0.122, blue: 0.267)     // #0B1F44 navy
    static let secondaryText = Color(red: 0.31, green: 0.388, blue: 0.525)    // #4F6386
    static let tertiaryText = primaryText.opacity(0.42)
    /// Text and icons on the accent colour.
    static let onAccent = Color.white

    static let amberGradient = LinearGradient(colors: [accentLight, amber], startPoint: .top, endPoint: .bottom)

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

/// Large blue capsule ("Go Premium").
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 58)
            .foregroundStyle(Theme.onAccent)
            .background(Theme.amberGradient, in: Capsule())
            .shadow(color: Theme.amber.opacity(0.25), radius: 16, y: 6)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

/// White glass button with a hairline border ("View full text").
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 58)
            .foregroundStyle(Theme.primaryText)
            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 29, style: .continuous))
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

/// Circular white icon button used in top bars (back, more, settings).
struct CircleIconButtonStyle: ButtonStyle {
    var size: CGFloat = 46

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.primaryText)
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

/// Space the floating tab bar and mini player take at the bottom of each tab.
enum TabBarSpace {
    static let height: CGFloat = 150
}
