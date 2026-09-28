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
        /// Why the natural voice is missing, when the server says.
        let voiceError: String?
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
        return TLDR(summary: summary, audio: audio, usage: usage, voiceError: data["voiceError"] as? String)
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
            let message = body["message"] as? String ?? "The TL;DR server returned an error."
            return .server("\(message) (\(status))")
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

/// Tells testers (and us) why a TL;DR didn't use the cloud, step by step.
enum CloudDiagnostics {
    struct Step: Identifiable {
        let id = UUID()
        let name: String
        let ok: Bool
        let detail: String
    }

    private static let lastProblemKey = "cloud.lastProblem"

    /// The last reason a TL;DR fell back to the iPhone, or nil after a cloud success.
    static var lastProblem: String? {
        get { AppGroup.defaults.string(forKey: lastProblemKey) }
        set { AppGroup.defaults.set(newValue, forKey: lastProblemKey) }
    }

    /// A readable error with its Firebase/URL code, so a screenshot is enough to debug.
    static func describe(_ error: Error) -> String {
        if let cloud = error as? CloudError { return cloud.localizedDescription }
        let ns = error as NSError
        let domain = ns.domain.replacingOccurrences(of: "com.firebase.", with: "")
        var text = "\(ns.localizedDescription) [\(domain) \(ns.code)]"
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            text += " ← \(underlying.localizedDescription) [\(underlying.domain) \(underlying.code)]"
        }
        return text
    }

    /// Runs each piece the cloud TL;DR needs, in order, stopping at the first failure.
    static func run() async -> [Step] {
        var steps: [Step] = []
        steps.append(Step(name: "Cloud switched on", ok: FeatureFlags.cloudTLDR,
                          detail: FeatureFlags.cloudTLDR ? (FeatureFlags.isTestFlight ? "TestFlight build" : "On")
                                                         : "Off in this build (not detected as TestFlight)"))
        guard FeatureFlags.cloudTLDR else { return steps }

        steps.append(Step(name: "Firebase file", ok: FirebaseSetup.isConfigured,
                          detail: FirebaseSetup.isConfigured ? "Found" : "GoogleService-Info.plist is missing from this build"))
        let url = NotchmanCloud.baseURL
        steps.append(Step(name: "Server address", ok: url != nil, detail: url?.host() ?? "NOTCHMAN_API_URL is missing"))
        guard FirebaseSetup.isConfigured, url != nil else { return steps }

        do {
            let user: User
            if let current = Auth.auth().currentUser {
                user = current
            } else {
                user = try await Auth.auth().signInAnonymously().user
            }
            _ = try await user.getIDToken()
            steps.append(Step(name: "Firebase sign-in", ok: true, detail: user.isAnonymous ? "Anonymous" : (user.email ?? "Signed in")))
        } catch {
            var detail = describe(error)
            if (error as NSError).code == 17006 { detail = "Turn on Anonymous in Firebase → Authentication → Sign-in method. " + detail }
            steps.append(Step(name: "Firebase sign-in", ok: false, detail: detail))
            return steps
        }

        do {
            _ = try await AppCheck.appCheck().token(forcingRefresh: true)
            steps.append(Step(name: "App Check (App Attest)", ok: true, detail: "Token received"))
        } catch {
            steps.append(Step(name: "App Check (App Attest)", ok: false, detail: describe(error)))
            return steps
        }

        do {
            let usage = try await NotchmanCloud().usage()
            steps.append(Step(name: "Notchman server", ok: true, detail: "\(usage.remaining) of \(usage.limit) left"))
        } catch {
            steps.append(Step(name: "Notchman server", ok: false, detail: describe(error)))
            return steps
        }

        do {
            let sample = "Hi team, quick update on the launch. The app build passed review this morning, so we can release on Friday at 10am. Before then, Priya needs to finish the App Store screenshots by Wednesday, and Sam should double-check the pricing in India. Marketing will send the email on Friday afternoon. If anything slips, tell me by Thursday so we can move the date."
            let result = try await NotchmanCloud().tldr(text: sample, length: .thirtySeconds)
            steps.append(Step(name: "Groq summary", ok: true, detail: String(result.summary.prefix(120))))
            steps.append(Step(name: "ElevenLabs voice", ok: result.audio != nil,
                              detail: result.audio.map { "\($0.count / 1024) KB of audio" } ?? (result.voiceError ?? "No audio returned")))
        } catch {
            steps.append(Step(name: "TL;DR", ok: false, detail: describe(error)))
        }
        return steps
    }
}
