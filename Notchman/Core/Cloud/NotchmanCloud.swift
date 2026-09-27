import FirebaseAppCheck
import FirebaseAuth
import FirebaseCore
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

/// App Attest in App Store builds. Test builds (simulator, or an iPhone run from
/// Xcode) use Firebase's debug provider instead: it prints a debug token in
/// Xcode's console, which you register once in the Firebase console.
final class NotchmanAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        #if DEBUG || targetEnvironment(simulator)
        return AppCheckDebugProvider(app: app)
        #else
        return AppAttestProvider(app: app)
        #endif
    }
}

/// Client for the Notchman API on AWS Lambda (see /server).
///
/// Each request carries a Firebase App Check token (App Attest: the genuine app
/// on a real iPhone) and a Firebase Auth ID token (anonymous sign-in), which the
/// server verifies. The Groq and ElevenLabs keys live only on the server.
struct NotchmanCloud {
    /// From `NOTCHMAN_API_URL` in project.yml (the SAM deploy's `ApiUrl` output).
    static var baseURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "NotchmanAPIURL") as? String,
              value.hasPrefix("https://") else { return nil }
        return URL(string: value)
    }

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
        guard FirebaseSetup.isConfigured, let baseURL = Self.baseURL else { throw CloudError.notConfigured }
        let user = try await Self.signedInUser()
        let idToken = try await user.getIDToken()
        let appCheckToken = try await AppCheck.appCheck().token(forcingRefresh: false).token

        var request = URLRequest(url: baseURL.appendingPathComponent(name))
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue(appCheckToken, forHTTPHeaderField: "X-Firebase-AppCheck")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard status == 200 else { throw Self.map(status: status, body: body) }
        return body
    }

    /// Every user gets an anonymous Firebase account: no sign-up, but a stable,
    /// server-verified identity for counting TL;DRs.
    private static func signedInUser() async throws -> User {
        if let user = Auth.auth().currentUser { return user }
        return try await Auth.auth().signInAnonymously().user
    }

    private static func map(status: Int, body: [String: Any]) -> CloudError {
        let details = body["details"] as? [String: Any]
        switch status {
        case 429:
            if let usage = CloudUsage(details), details?["reason"] as? String == "monthly_limit" {
                return .quotaExceeded(usage)
            }
            return .slowDown
        case 503:
            return .busy
        default:
            return .server(body["message"] as? String ?? "The TL;DR server returned an error (\(status)).")
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
