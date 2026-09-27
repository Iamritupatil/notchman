import FirebaseAppCheck
import FirebaseAuth
import FirebaseCore
import FirebaseFunctions
import Foundation
import os
import StoreKit

/// This month's TL;DR allowance, as reported by the Notchman backend.
struct CloudUsage: Codable, Equatable, Sendable {
    let plan: String
    let used: Int
    let limit: Int
    let remaining: Int

    var planName: String {
        switch plan {
        case "pro": "Pro"
        case "proplus": "Pro+"
        default: "Free"
        }
    }

    init(plan: String, used: Int, limit: Int, remaining: Int) {
        self.plan = plan
        self.used = used
        self.limit = limit
        self.remaining = remaining
    }

    init?(_ dictionary: [String: Any]?) {
        guard let dictionary, let limit = (dictionary["limit"] as? NSNumber)?.intValue else { return nil }
        self.init(plan: dictionary["plan"] as? String ?? "free",
                  used: (dictionary["used"] as? NSNumber)?.intValue ?? 0,
                  limit: limit,
                  remaining: (dictionary["remaining"] as? NSNumber)?.intValue ?? 0)
    }
}

enum CloudError: LocalizedError {
    case notConfigured
    case quotaExceeded(CloudUsage)
    case slowDown
    case busy
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Notchman's cloud isn't set up in this build."
        case .quotaExceeded(let usage): "You've used all \(usage.limit) TL;DRs in your \(usage.planName) plan this month."
        case .slowDown: "That's a lot of TL;DRs at once. Try again in a minute."
        case .busy: "Notchman is very busy right now. Try again in a little while."
        case .server(let message): message
        }
    }
}

/// Firebase setup. Everything that talks to the backend is protected three ways:
/// App Check (App Attest: only the genuine app on a real device), Firebase Auth
/// (an anonymous account per user), and server-side secrets (the AI keys never
/// ship in the app).
enum FirebaseSetup {
    private static let log = Logger(subsystem: "com.notchman", category: "Firebase")

    /// True once Firebase is configured. Builds without GoogleService-Info.plist
    /// (e.g. CI) skip the cloud and summarize on device.
    private(set) static var isConfigured = false

    static func configureIfAvailable() {
        guard FeatureFlags.cloudTLDR, !isConfigured else { return }
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            log.info("GoogleService-Info.plist missing; cloud TL;DRs disabled.")
            return
        }
        AppCheck.setAppCheckProviderFactory(NotchmanAppCheckProviderFactory())
        FirebaseApp.configure()
        isConfigured = true
    }
}

/// App Attest on real devices. The simulator can't attest, so it uses Firebase's
/// debug provider, whose token must be registered in the Firebase console.
final class NotchmanAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        #if targetEnvironment(simulator)
        return AppCheckDebugProvider(app: app)
        #else
        return AppAttestProvider(app: app)
        #endif
    }
}

/// Client for the Notchman Cloud Functions (see /firebase).
struct NotchmanCloud {
    private static let region = "us-central1"

    struct TLDR {
        let summary: String
        /// MP3 of the summary in the natural (ElevenLabs) voice; nil if the voice
        /// couldn't be made, in which case Apple's voice reads it.
        let audio: Data?
        let usage: CloudUsage
    }

    func tldr(text: String, length: QuickListenDuration) async throws -> TLDR {
        let data = try await call("tldr", [
            "text": text,
            "length": length.rawValue,
            "transactions": await Self.currentTransactions(),
        ])
        guard let summary = data["summary"] as? String, let usage = CloudUsage(data) else {
            throw CloudError.server("The summary came back empty.")
        }
        let audio = (data["audio"] as? String).flatMap { Data(base64Encoded: $0) }
        return TLDR(summary: summary, audio: audio, usage: usage)
    }

    func usage() async throws -> CloudUsage {
        let data = try await call("usage", ["transactions": await Self.currentTransactions()])
        guard let usage = CloudUsage(data) else { throw CloudError.server("Usage unavailable.") }
        return usage
    }

    private func call(_ name: String, _ payload: [String: Any]) async throws -> [String: Any] {
        guard FirebaseSetup.isConfigured else { throw CloudError.notConfigured }
        try await Self.signInIfNeeded()
        do {
            let result = try await Functions.functions(region: Self.region).httpsCallable(name).call(payload)
            return result.data as? [String: Any] ?? [:]
        } catch let error as NSError where error.domain == FunctionsErrorDomain {
            throw Self.map(error)
        }
    }

    /// Every user gets an anonymous Firebase account: no sign-up, but a stable,
    /// server-verified identity for counting TL;DRs.
    private static func signInIfNeeded() async throws {
        if Auth.auth().currentUser == nil {
            _ = try await Auth.auth().signInAnonymously()
        }
    }

    private static func map(_ error: NSError) -> CloudError {
        let details = error.userInfo[FunctionsErrorDetailsKey] as? [String: Any]
        switch FunctionsErrorCode(rawValue: error.code) {
        case .resourceExhausted:
            if let usage = CloudUsage(details), details?["reason"] as? String == "monthly_limit" {
                return .quotaExceeded(usage)
            }
            return .slowDown
        case .unavailable:
            return .busy
        default:
            return .server(error.localizedDescription)
        }
    }

    /// Signed StoreKit transactions proving the user's plan. The backend verifies
    /// Apple's signature, so they can't be forged.
    static func currentTransactions() async -> [String] {
        var signed: [String] = []
        for await entitlement in Transaction.currentEntitlements {
            signed.append(entitlement.jwsRepresentation)
        }
        return signed
    }
}
