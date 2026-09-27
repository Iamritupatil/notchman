import Foundation

/// Product switches.
///
/// **Test builds (Debug, run from Xcode)** have everything on, so you can try
/// Pro / Pro+ with free test purchases (StoreKit testing) and the real Groq +
/// ElevenLabs backend. See docs/TESTING.md.
///
/// **App Store builds (Release)** stay on the free, on-device version until
/// the backend and the App Store Connect subscriptions are ready. Then set
/// both to `true` here.
enum FeatureFlags {
    #if DEBUG
    static let paidPlans = true
    static let cloudTLDR = true
    #else
    /// Show Pro / Pro+ plans, Go Premium buttons and monthly TL;DR counts.
    static let paidPlans = false
    /// Send Pro / Pro+ TL;DRs to the Notchman Cloud Functions (needs Firebase set up).
    static let cloudTLDR = false
    #endif
}
