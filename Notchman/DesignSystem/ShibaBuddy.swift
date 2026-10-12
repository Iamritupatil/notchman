import SwiftUI

/// The full-body Shiba (pixel art: scripts/shiba_sprites.py), alive but calm.
/// Now and then it blinks and wags its tail; it waves hello when it appears
/// (at most once every 10 minutes, so it stays a greeting), talks while the
/// voice plays and looks up while a TL;DR is being made. With Reduce Motion
/// it sits still.
struct ShibaBuddy: View {
    enum Mood: Equatable {
        case idle, hello, talking, thinking
    }

    var mood: Mood = .idle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = Date()
    @State private var waving = false

    @MainActor private static var lastWave = Date.distantPast

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let frame = reduceMotion
                ? "ShibaIdle"
                : Self.frame(for: waving ? .hello : (mood == .hello ? .idle : mood),
                             at: context.date.timeIntervalSince(started))
            Image(frame)
                .resizable()
                .interpolation(.none)
                .aspectRatio(Self.aspectRatio, contentMode: .fit)
        }
        .accessibilityHidden(true)
        .onAppear(perform: begin)
        .onChange(of: mood) { begin() }
    }

    /// Width to height of the drawing (34 × 30 cells).
    static let aspectRatio: CGFloat = 34 / 30

    private func begin() {
        started = .now
        waving = mood == .hello && Date().timeIntervalSince(Self.lastWave) > 600
        if waving { Self.lastWave = .now }
    }

    /// The frame `t` seconds into a mood. A wave lasts 2.4 s, then it idles.
    static func frame(for mood: Mood, at t: TimeInterval) -> String {
        switch mood {
        case .hello where t < 2.4:
            return Int(t / 0.3) % 2 == 0 ? "ShibaWave1" : "ShibaWave2"
        case .talking:
            return Int(t / 0.2) % 2 == 0 ? "ShibaTalk1" : "ShibaTalk2"
        case .thinking:
            return blinking(at: t) ? "ShibaBlink" : "ShibaThink"
        default:
            if blinking(at: t) { return "ShibaBlink" }
            // A short wag every 7 seconds.
            let cycle = t.truncatingRemainder(dividingBy: 7)
            if cycle > 5.6 { return Int(cycle / 0.2) % 2 == 0 ? "ShibaWag" : "ShibaIdle" }
            return "ShibaIdle"
        }
    }

    /// A 0.2 s blink every 4.2 s.
    private static func blinking(at t: TimeInterval) -> Bool {
        t.truncatingRemainder(dividingBy: 4.2) > 4.0
    }
}
