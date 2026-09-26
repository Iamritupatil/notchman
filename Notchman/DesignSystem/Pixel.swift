import SwiftUI

// MARK: - Mascot

/// The Notchman mascot (design/art/mascot.png). Hops gently while `isActive`.
struct ShibaSprite: View {
    var isActive = false
    var image = "Mascot"

    var body: some View {
        Image(image)
            .resizable()
            .interpolation(.medium)
            .scaledToFit()
            .phaseAnimator([0.0, -1.0]) { content, lift in
                content.offset(y: isActive ? lift * 5 : 0)
            } animation: { _ in
                .easeInOut(duration: 0.35)
            }
            .accessibilityHidden(true)
    }
}

/// The mascot with twinkling sparkles; optionally writes a word ("TL;DR") on
/// the amber bar under its paws, as in the design.
struct MascotStage: View {
    var sign: String?
    var isActive = true
    var width: CGFloat = 170

    /// Where the amber bar sits in design/art/mascot.png, as fractions of the image.
    private static let barCenterY: CGFloat = 0.915
    private static let barHeight: CGFloat = 0.15

    var body: some View {
        ZStack {
            PixelSparkles(count: 9)
                .frame(width: width * 1.9, height: width * 1.3)

            ShibaSprite(isActive: isActive)
                .frame(width: width)
                .overlay {
                    if let sign {
                        GeometryReader { proxy in
                            Text(sign)
                                .font(.pixel(proxy.size.height * Self.barHeight * 0.62))
                                .foregroundStyle(Color(red: 0.15, green: 0.09, blue: 0.03))
                                .position(x: proxy.size.width / 2, y: proxy.size.height * Self.barCenterY)
                        }
                    }
                }
        }
        .accessibilityHidden(true)
    }
}

/// Pixel "+" sparkles and dots that twinkle.
struct PixelSparkles: View {
    var count = 8
    var color: Color = Theme.amber

    // Fixed layout so the scene is stable across renders.
    private static let layout: [(x: CGFloat, y: CGFloat, big: Bool)] = [
        (0.12, 0.30, true), (0.86, 0.18, true), (0.07, 0.62, false), (0.93, 0.55, true),
        (0.20, 0.85, true), (0.80, 0.86, false), (0.33, 0.10, false), (0.67, 0.05, false),
        (0.50, 0.95, false), (0.97, 0.30, false), (0.03, 0.12, false), (0.60, 0.98, true),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { gfx, size in
                for (index, spark) in Self.layout.prefix(count).enumerated() {
                    let alpha = 0.45 + 0.55 * abs(sin(t * 1.3 + Double(index) * 1.7))
                    let unit: CGFloat = spark.big ? 4 : 3
                    let cx = spark.x * size.width
                    let cy = spark.y * size.height
                    var shading = gfx
                    shading.opacity = alpha
                    if spark.big {
                        // 3x3 plus sign.
                        for (dx, dy) in [(0, -1), (-1, 0), (0, 0), (1, 0), (0, 1)] {
                            let r = CGRect(x: cx + CGFloat(dx) * unit - unit / 2, y: cy + CGFloat(dy) * unit - unit / 2,
                                           width: unit, height: unit)
                            shading.fill(Path(r), with: .color(color))
                        }
                    } else {
                        shading.fill(Path(CGRect(x: cx, y: cy, width: unit, height: unit)), with: .color(color))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Soft dark pixel clouds for onboarding and sign-in backgrounds.
struct PixelClouds: View {
    private static let clouds: [(x: CGFloat, y: CGFloat, scale: CGFloat)] = [
        (0.05, 0.12, 1.0), (0.78, 0.10, 1.3), (0.02, 0.30, 0.8), (0.88, 0.32, 0.9),
        (0.05, 0.88, 1.2), (0.85, 0.86, 1.0),
    ]

    var body: some View {
        Canvas { gfx, size in
            let unit: CGFloat = 6
            // Rows of a cloud: (offset, width) in units.
            let rows: [(CGFloat, CGFloat)] = [(4, 5), (2, 10), (0, 16), (0, 16)]
            for cloud in Self.clouds {
                let origin = CGPoint(x: cloud.x * size.width - 40, y: cloud.y * size.height)
                for (index, row) in rows.enumerated() {
                    let rect = CGRect(x: origin.x + row.0 * unit * cloud.scale,
                                      y: origin.y + CGFloat(index) * unit * cloud.scale,
                                      width: row.1 * unit * cloud.scale, height: unit * cloud.scale)
                    gfx.fill(Path(rect), with: .color(Color.white.opacity(0.045)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Full-screen dark backdrop with clouds and sparkles.
struct PixelSkyBackground: View {
    var body: some View {
        ZStack {
            Theme.background
            PixelClouds()
            PixelSparkles(count: 12)
        }
        .ignoresSafeArea()
    }
}

#Preview {
    ZStack {
        PixelSkyBackground()
        VStack(spacing: 40) {
            MascotStage(sign: "TL;DR")
            Button("Got it →") {}.buttonStyle(.notchmanPrimary).padding(.horizontal, 40)
        }
    }
    .preferredColorScheme(.dark)
}
