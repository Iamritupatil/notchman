import SwiftUI
import UIKit

/// Rounded tile showing the source's real logo, found dynamically by
/// `LogoStore` (bundled file → site icon → App Store icon), or a neutral
/// symbol while loading or when none exists.
struct SourceTile: View {
    let type: SourceType
    var name: String
    var url: String?
    var size: CGFloat = 52

    @State private var logo: LogoStore.Logo?

    private var query: LogoStore.Query {
        // A known service's own icon wins over a page host (e.g. chatgpt.com/share/…).
        let host = url.flatMap(URL.init(string:))?.host
        return LogoStore.Query(name: name, domain: SourceTile.knownDomain(for: type) ?? host)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        Group {
            if let logo {
                Image(uiImage: logo.image)
                    .resizable()
                    .scaledToFit()
                    .padding(logo.fillsTile ? 0 : size * 0.2)
            } else {
                Image(systemName: type.symbolName)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(type.tint)
            }
        }
        .frame(width: size, height: size)
        .background(Theme.cardRaised)
        .clipShape(shape)
        .overlay(shape.stroke(Theme.stroke))
        .task(id: query) {
            logo = await LogoStore.shared.logo(for: query)
        }
        .accessibilityHidden(true)
    }

    /// Known services use their own site's icon: reliable, and it doesn't
    /// depend on an App Store name lookup succeeding.
    static func knownDomain(for type: SourceType) -> String? {
        switch type {
        case .chatGPT: "chatgpt.com"
        case .claude: "claude.ai"
        case .gemini: "gemini.google.com"
        case .reddit: "reddit.com"
        case .linkedin: "linkedin.com"
        case .email, .webpage, .text: nil
        }
    }
}

/// Small tile plus source name, used on the player.
struct SourceBadge: View {
    let type: SourceType
    let name: String
    var url: String?

    var body: some View {
        HStack(spacing: 10) {
            SourceTile(type: type, name: name, url: url, size: 40)
            Text(name)
                .font(.title3)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
        }
    }
}

/// Red "TL;DR" pill marking summaries.
struct TLDRBadge: View {
    var body: some View {
        Text("TL;DR")
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(Color(red: 0.25, green: 0.03, blue: 0.04))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Theme.tldr, in: Capsule())
            .accessibilityLabel("Summary")
    }
}

/// Thin progress capsule.
struct ProgressCapsule: View {
    let value: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.primaryText.opacity(0.1))
                Capsule().fill(Theme.amber)
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
    var color: Color = Theme.amber

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

/// Dark rounded card container used for grouped rows and banners.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).stroke(Theme.stroke))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}
