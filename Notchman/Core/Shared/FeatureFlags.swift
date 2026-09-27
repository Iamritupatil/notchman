import Foundation

/// Product switches.
///
/// Notchman launches **free**: TL;DRs are made on the iPhone (Apple Intelligence
/// or the built-in summarizer), voices are Apple's, and nothing needs a server,
/// API key or credit card. The cloud backend (`firebase/`) and paid plans are
/// kept in the code, switched off, for when they make sense.
enum FeatureFlags {
    /// Show Pro / Pro+ plans, Go Premium buttons and monthly TL;DR counts.
    static let paidPlans = false
    /// Send TL;DRs to the Notchman Cloud Functions (needs Firebase set up).
    static let cloudTLDR = false
}
