import SwiftUI

// MARK: - Tokens

/// Spacing scale. Use these instead of one-off numbers so screens line up.
enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    /// Left and right page margins.
    static let page: CGFloat = 20
}

/// Corner radii by role.
enum CornerRadius {
    static let card: CGFloat = 22
    static let tile: CGFloat = 14
    static let button: CGFloat = 29
    static let player: CGFloat = 28
    /// Floating surfaces: mini player.
    static let floating: CGFloat = 22
}

/// Type roles. The pixel font is only for the brand (the NOTCHMAN wordmark and
/// a few brand moments); everything else is native iOS type.
extension Font {
    /// The NOTCHMAN wordmark.
    static func brand(_ size: CGFloat = 24) -> Font { .pixel(size) }
    /// Top-level page titles (History, Account).
    static let pageTitle = Font.system(size: 34, weight: .bold)
    /// Card and section headings.
    static let sectionTitle = Font.title3.weight(.semibold)
    /// Supporting text.
    static let metadata = Font.subheadline
    /// Small labels in capsules (TL;DR, Full read).
    static let badge = Font.caption.weight(.semibold)
}

// MARK: - Surfaces

/// Floating, interactive surfaces (mini player, tab bar, player controls) use
/// glass; informational content uses plain `card()`s.
struct GlassSurface<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: shape)
            .background(Color.white.opacity(0.55), in: shape)
            .overlay(shape.stroke(Color.white.opacity(0.9), lineWidth: 0.75))
            .shadow(color: Theme.primaryText.opacity(0.14), radius: 16, y: 6)
    }
}

extension View {
    func glass<S: Shape>(_ shape: S) -> some View { modifier(GlassSurface(shape: shape)) }
}

// MARK: - Persistent bottom chrome

/// The height of what floats at the bottom of every tab (mini player, if
/// shown, and the tab bar), measured by the app shell. Pages reserve it with
/// `tabPage()`, so content never ends up hidden underneath.
private struct BottomChromeHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var bottomChromeHeight: CGFloat {
        get { self[BottomChromeHeightKey.self] }
        set { self[BottomChromeHeightKey.self] = newValue }
    }
}

/// Reserves the bottom chrome's space inside the page, so scroll views and
/// lists end above the mini player and tab bar. Applied by the shell to every
/// tab root and every pushed screen, never by screens themselves.
private struct TabPage: ViewModifier {
    @Environment(\.bottomChromeHeight) private var height

    func body(content: Content) -> some View {
        content.safeAreaPadding(.bottom, height)
    }
}

/// One title system for pushed screens (Settings, Voice…): a native inline
/// title on a soft bar, so content never shows under a second, large title.
/// It also reserves the bottom chrome's space, like `tabPage()`.
private struct PushedPage: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(Theme.skyTop.opacity(0.92), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tabPage()
    }
}

extension View {
    func tabPage() -> some View { modifier(TabPage()) }
    func pushedPage(_ title: String) -> some View { modifier(PushedPage(title: title)) }
}

/// Measures a view's height and reports it (for the bottom chrome).
struct HeightReader: ViewModifier {
    let onChange: (CGFloat) -> Void

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { onChange(proxy.size.height) }
                    .onChange(of: proxy.size.height) { _, height in onChange(height) }
            }
        }
    }
}

extension View {
    func readHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        modifier(HeightReader(onChange: onChange))
    }
}

// MARK: - Badges

/// Quiet label for the listening mode ("TL;DR", "Full read"): metadata, not a
/// warning, so it never outshouts the title.
struct ModeBadge: View {
    let isTLDR: Bool

    var body: some View {
        Text(isTLDR ? "TL;DR" : "Full read")
            .font(.badge)
            .foregroundStyle(Theme.amber)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Theme.amber.opacity(0.12), in: Capsule())
            .accessibilityLabel(isTLDR ? "Summary" : "Full read")
    }
}
