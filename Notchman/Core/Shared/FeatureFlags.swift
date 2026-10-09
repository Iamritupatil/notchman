import Foundation

/// Product switches.
///
/// - **Debug builds** (run from Xcode): everything on, with free test purchases.
/// - **TestFlight and App Store builds**: everyone uses the Notchman cloud;
///   the server enforces the plans (Free: a few TL;DRs a day and a short
///   preview of the natural voice; Pro and Pro+: monthly voice allowances),
///   and the paywall sells Pro and Pro+ through the App Store.
enum FeatureFlags {
    /// TestFlight installs have a sandbox receipt.
    static let isTestFlight = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"

    #if DEBUG
    static let paidPlans = true
    static let cloudTLDR = true
    static let cloudForEveryone = false
    #else
    /// Show Pro / Pro+ plans, Go Premium buttons and allowances.
    static let paidPlans = true
    /// Talk to the Notchman API at all.
    static let cloudTLDR = true
    /// Free users get cloud TL;DRs too, within the server's free limits.
    static let cloudForEveryone = true
    #endif
}
