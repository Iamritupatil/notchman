import Foundation

/// Product switches.
///
/// - **Debug builds** (run from Xcode): everything on, with free test purchases.
/// - **TestFlight builds**: cloud TL;DRs (Groq + ElevenLabs voice) on for every
///   tester, within the server's daily beta allowance. Paid plans stay hidden.
/// - **App Store builds**: free and on-device until subscriptions go live; then
///   set `paidPlans` and `cloudTLDR` to true for Release.
enum FeatureFlags {
    /// TestFlight installs have a sandbox receipt.
    static let isTestFlight = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"

    #if DEBUG
    static let paidPlans = true
    static let cloudTLDR = true
    static let cloudForEveryone = false
    #else
    /// Show Pro / Pro+ plans, Go Premium buttons and monthly TL;DR counts.
    static let paidPlans = false
    /// Talk to the Notchman API at all.
    static let cloudTLDR = isTestFlight
    /// Beta: every tester gets cloud TL;DRs, not only subscribers.
    static let cloudForEveryone = isTestFlight
    #endif
}
