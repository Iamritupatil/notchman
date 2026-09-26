import SwiftUI

// MARK: - Pixel shapes

/// A rectangle whose corners are cut into pixel stair-steps, like an 8-bit button.
struct PixelShape: Shape {
    /// Size of one "pixel" in points.
    var step: CGFloat = 4
    /// How many steps each corner has.
    var steps: Int = 2

    func path(in rect: CGRect) -> Path {
        let s = min(step, rect.width / CGFloat(2 * steps + 1), rect.height / CGFloat(2 * steps + 1))
        let n = CGFloat(steps)
        var points: [CGPoint] = []

        // Top-left corner, walking clockwise from the left edge.
        points.append(CGPoint(x: rect.minX, y: rect.minY + n * s))
        for i in 0..<steps {
            let k = CGFloat(i)
            points.append(CGPoint(x: rect.minX + (k + 1) * s, y: rect.minY + (n - k) * s))
            points.append(CGPoint(x: rect.minX + (k + 1) * s, y: rect.minY + (n - k - 1) * s))
        }
        // Top-right.
        for i in 0..<steps {
            let k = CGFloat(i)
            points.append(CGPoint(x: rect.maxX - (n - k) * s, y: rect.minY + k * s))
            points.append(CGPoint(x: rect.maxX - (n - k) * s, y: rect.minY + (k + 1) * s))
        }
        points.append(CGPoint(x: rect.maxX, y: rect.minY + n * s))
        // Bottom-right.
        points.append(CGPoint(x: rect.maxX, y: rect.maxY - n * s))
        for i in 0..<steps {
            let k = CGFloat(i)
            points.append(CGPoint(x: rect.maxX - (k + 1) * s, y: rect.maxY - (n - k) * s))
            points.append(CGPoint(x: rect.maxX - (k + 1) * s, y: rect.maxY - (n - k - 1) * s))
        }
        // Bottom-left.
        for i in 0..<steps {
            let k = CGFloat(i)
            points.append(CGPoint(x: rect.minX + (n - k) * s, y: rect.maxY - k * s))
            points.append(CGPoint(x: rect.minX + (n - k) * s, y: rect.maxY - (k + 1) * s))
        }
        points.append(CGPoint(x: rect.minX, y: rect.maxY - n * s))

        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}

// MARK: - Mascot

/// The pixel Shiba. Scales without smoothing; hops gently while `isActive`.
struct ShibaSprite: View {
    var isActive = false

    var body: some View {
        // The one Notchman mascot. Replace Notchman/Resources/Assets.xcassets/Mascot
        // (see design/README.md) to update it everywhere.
        Image("Mascot")
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .phaseAnimator([0.0, -1.0]) { content, lift in
                content.offset(y: isActive ? lift * 6 : 0)
            } animation: { _ in
                .easeInOut(duration: 0.35)
            }
            .accessibilityHidden(true)
    }
}

/// Mascot with sparkles and excitement marks, optionally holding the TL;DR sign.
struct MascotStage: View {
    var sign: String?
    var isActive = true
    var width: CGFloat = 170

    var body: some View {
        ZStack {
            PixelSparkles(count: 9)
                .frame(width: width * 2.3, height: width * 1.5)

            VStack(spacing: -width * 0.1) {
                ZStack {
                    ShibaSprite(isActive: isActive)
                        .frame(width: width)
                    ExcitementMarks(isActive: isActive)
                        .frame(width: width * 1.75, height: width * 0.6)
                        .offset(y: -width * 0.05)
                }
                if let sign {
                    PixelSign(text: sign)
                        .frame(width: width * 1.12)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Amber pixel plaque with dark text, held by the Shiba ("TL;DR").
struct PixelSign: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.pixel(30))
            .foregroundStyle(Color(red: 0.15, green: 0.09, blue: 0.03))
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    PixelShape(step: 5, steps: 2).fill(Color(red: 0.55, green: 0.32, blue: 0.04))
                        .offset(y: 5)
                    PixelShape(step: 5, steps: 2).fill(Theme.amberGradient)
                }
            }
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

/// Little pixel "zap" marks either side of the mascot's head.
struct ExcitementMarks: View {
    var isActive = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 8, paused: !isActive)) { context in
            let wiggle = isActive ? CGFloat(sin(context.date.timeIntervalSinceReferenceDate * 6)) * 2 : 0
            Canvas { gfx, size in
                let unit: CGFloat = max(3, size.width / 60)
                // Three marks per side, radiating outward; drawn as short pixel diagonals.
                let marks: [(y: CGFloat, dx: CGFloat, dy: CGFloat)] = [(0.15, 1, -0.6), (0.5, 1, 0), (0.85, 1, 0.6)]
                for side in [-1.0, 1.0] as [CGFloat] {
                    for mark in marks {
                        let baseX = size.width / 2 + side * (size.width / 2 - unit * 4) + side * wiggle
                        let baseY = mark.y * size.height
                        for i in 0..<3 {
                            let x = baseX + side * CGFloat(i) * unit * mark.dx - unit / 2
                            let y = baseY + CGFloat(i) * unit * mark.dy + (i == 1 ? -unit * 0.5 : 0)
                            gfx.fill(Path(CGRect(x: x, y: y, width: unit * 1.4, height: unit)),
                                     with: .color(Theme.amber))
                        }
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
