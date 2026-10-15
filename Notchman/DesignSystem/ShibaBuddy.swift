import SwiftUI

/// The Shiba's head (pixel art: scripts/shiba_sprites.py), alive but calm.
/// Now and then it blinks and twitches an ear; it's happy (eyes closed, both
/// ears up) when it says hello (at most once every 10 minutes, so it stays a
/// greeting), perks one ear while it listens, looks up and sways while a
/// TL;DR is being made, and talks while the voice plays. With Reduce Motion
/// it sits still. Same timing as the floating Shiba on Windows and Mac.
struct ShibaBuddy: View {
    enum Mood: Equatable {
        case idle, hello, listening, talking, thinking
    }

    var mood: Mood = .idle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = Date()
    @State private var greeting = false

    @MainActor private static var lastHello = Date.distantPast

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let frame = reduceMotion
                ? "ShibaHeadIdle"
                : Self.frame(for: greeting ? .hello : (mood == .hello ? .idle : mood),
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

    /// Width to height of the drawing (20 × 17 cells: the head, with room for a perked ear).
    static let aspectRatio: CGFloat = 20 / 17

    private func begin() {
        started = .now
        greeting = mood == .hello && Date().timeIntervalSince(Self.lastHello) > 600
        if greeting { Self.lastHello = .now }
    }

    /// The frame `t` seconds into a mood. Hello lasts 1.6 s, then it idles.
    static func frame(for mood: Mood, at t: TimeInterval) -> String {
        switch mood {
        case .hello where t < 1.6:
            return alternate(t, every: 0.4, "ShibaHeadHappy", "ShibaHeadIdle")
        case .talking:
            return alternate(t, every: 0.2, "ShibaHeadTalk1", "ShibaHeadTalk2")
        case .thinking:
            return blinking(at: t) ? "ShibaHeadBlink" : alternate(t, every: 0.6, "ShibaHeadThink1", "ShibaHeadThink2")
        case .listening:
            // The ear goes up at once, then twitches every couple of seconds.
            if t > 0.3 && t.truncatingRemainder(dividingBy: 2.6) < 0.24 { return "ShibaHeadListen2" }
            return blinking(at: t) ? "ShibaHeadBlink" : "ShibaHeadListen1"
        default:
            if blinking(at: t) { return "ShibaHeadBlink" }
            // An ear twitch every 9 seconds.
            let cycle = t.truncatingRemainder(dividingBy: 9)
            if cycle > 7.8 && cycle < 8.4 { return alternate(cycle, every: 0.15, "ShibaHeadListen2", "ShibaHeadListen1") }
            return "ShibaHeadIdle"
        }
    }

    private static func alternate(_ t: TimeInterval, every period: TimeInterval, _ a: String, _ b: String) -> String {
        Int(t / period) % 2 == 0 ? a : b
    }

    /// A 0.2 s blink every 4.2 s.
    private static func blinking(at t: TimeInterval) -> Bool {
        t.truncatingRemainder(dividingBy: 4.2) > 4.0
    }
}
