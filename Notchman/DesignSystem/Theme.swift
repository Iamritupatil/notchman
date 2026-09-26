import SwiftUI
import UIKit

enum Theme {
    static let cornerRadius: CGFloat = 20
    static let horizontalPadding: CGFloat = 20
}

extension Font {
    /// Large rounded display type used for headlines ("Read less. Listen instead.").
    static func display(_ size: CGFloat = 36) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}

extension SourceType {
    var tint: Color {
        switch self {
        case .chatGPT: Color(red: 0.06, green: 0.64, blue: 0.50)
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .gemini: Color(red: 0.26, green: 0.52, blue: 0.96)
        case .reddit: Color(red: 1.00, green: 0.27, blue: 0.00)
        case .email: Color(red: 0.20, green: 0.48, blue: 0.96)
        case .webpage: Color(red: 0.36, green: 0.40, blue: 0.47)
        case .text: Color(red: 0.45, green: 0.45, blue: 0.50)
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

/// Monochrome filled button: black in light mode, white in dark mode.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(Color(.systemBackground))
            .background(Color.primary.opacity(isEnabled ? 1 : 0.3),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(Color.primary)
            .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

// MARK: - Dates

enum RelativeDay {
    static func string(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
