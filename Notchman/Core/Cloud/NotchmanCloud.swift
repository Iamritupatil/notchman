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
    /// Today's listening allowance is used up (message from the server).
    case voiceLimit(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Notchman's cloud isn't set up in this build."
        case .quotaExceeded(let usage): "You've used all \(usage.limit) TL;DRs in your \(usage.planName) plan this month."
        case .slowDown: "That's a lot of TL;DRs at once. Try again in a minute."
        case .busy: "Notchman is very busy right now. Try again in a little while."
        case .server(let message): message
        case .voiceLimit(let message): message
        }
    }
}

/// A random ID for this install, kept in the Keychain (it survives app updates).
/// The server counts per-install daily limits against it. It identifies no one.
enum InstallID {
    private static let key = "notchman.installID"

    static var value: String {
        if let existing = KeychainStore.string(for: key), UUID(uuidString: existing) != nil { return existing }
        let id = UUID().uuidString
        _ = KeychainStore.set(id, for: key)
        return id
    }
}

/// Client for the Notchman API on AWS Lambda (see /server).
///
/// Each request carries this install's ID; the server applies per-install and
/// total daily limits. The Groq and ElevenLabs keys live only on the server.
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
            // The app voices the summary itself, piece by piece (`speak`).
            "voice": false,
            "transactions": await Self.currentTransactions(),
        ])
        guard let summary = data["summary"] as? String, let usage = CloudUsage(data) else {
            throw CloudError.server("The summary came back empty.")
        }
        let audio = (data["audio"] as? String).flatMap { Data(base64Encoded: $0) }
        return TLDR(summary: summary, audio: audio, usage: usage, voiceError: data["voiceError"] as? String)
    }

    /// ElevenLabs audio (MP3) for one piece of text. The neighbouring text keeps
    /// the voice flowing naturally from piece to piece.
    ///
    /// The server confirms which voice it used; a server that doesn't (an old
    /// deployment that ignores the choice) is an error, never a silent fallback
    /// to its default voice.
    func speak(text: String, previousText: String?, nextText: String?, voiceID: String) async throws -> Data {
        var payload: [String: Any] = ["text": text, "voiceId": voiceID, "transactions": await Self.currentTransactions()]
        if let previousText { payload["previousText"] = previousText }
        if let nextText { payload["nextText"] = nextText }
        Self.log.info("ElevenLabs request: voice \(voiceID, privacy: .public), \(text.count) characters")
        let data = try await call("speak", payload)
        guard let base64 = data["audio"] as? String, let audio = Data(base64Encoded: base64), !audio.isEmpty else {
            throw CloudError.server("The voice came back empty.")
        }
        try Self.checkVoice(requested: voiceID, response: data)
        return audio
    }

    static let log = Logger(subsystem: "com.notchman", category: "Cloud")

    /// The voice the server says it used must be the one asked for. An older
    /// server that doesn't report it still works (it's logged and shown in
    /// Settings → Check Cloud) so the app never stops working while the server
    /// catches up; a server that reports a different voice is an error.
    static func checkVoice(requested: String, response: [String: Any]) throws {
        guard let used = response["voiceId"] as? String else {
            log.error("Server didn't confirm the voice (asked for \(requested, privacy: .public)); it needs updating")
            CloudDiagnostics.lastProblem = "The Notchman server is out of date: it doesn't confirm the chosen voice."
            return
        }
        guard used == requested else {
            log.error("Voice mismatch: asked for \(requested, privacy: .public), server used \(used, privacy: .public)")
            throw CloudError.server("The server used a different voice than the one chosen.")
        }
    }

    /// True when this build can use the Notchman voice at all.
    static var isAvailable: Bool {
        FeatureFlags.cloudTLDR && baseURL != nil
    }

    func usage() async throws -> CloudUsage {
        let data = try await call("usage", ["transactions": await Self.currentTransactions()])
        guard let usage = CloudUsage(data) else { throw CloudError.server("Usage unavailable.") }
        return usage
    }

    private func call(_ name: String, _ payload: [String: Any]) async throws -> [String: Any] {
        guard let baseURL = Self.baseURL else { throw CloudError.notConfigured }

        var request = URLRequest(url: baseURL.appendingPathComponent(name))
        request.httpMethod = "POST"
        request.timeoutInterval = 80
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(InstallID.value, forHTTPHeaderField: "X-Notchman-Install")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard status == 200 else { throw Self.map(status: status, body: body) }
        return body
    }

    private static func map(status: Int, body: [String: Any]) -> CloudError {
        let details = body["details"] as? [String: Any]
        switch status {
        case 429:
            if let usage = CloudUsage(details), details?["reason"] as? String == "monthly_limit" {
                return .quotaExceeded(usage)
            }
            if details?["reason"] as? String == "voice_limit" {
                return .voiceLimit(body["message"] as? String ?? "Today's listening time is used up.")
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

        /// Plain-English reason; the raw `detail` stays behind "Technical details".
        var summary: String { ok ? detail : CloudDiagnostics.friendly(detail) }
    }

    /// Turns a raw error into one sentence someone can act on.
    static func friendly(_ raw: String) -> String {
        let text = raw.lowercased()
        if text.contains("not found") || text.contains("(404)") {
            return "The server is an older version. Deploy it again (Actions → Deploy server)."
        }
        if text.contains("install id") { return "The server rejected this install. Deploy the latest server." }
        if text.contains("offline") || text.contains("-1009") || text.contains("timed out") { return "No internet connection, or the server took too long." }
        if text.contains("elevenlabs") { return "The ElevenLabs voice failed. Check the API key and its character limit." }
        if text.contains("groq") { return "The Groq summary failed. Check the API key and spend limit." }
        return "Something went wrong. See Technical details."
    }

    private static let lastProblemKey = "cloud.lastProblem"

    /// The last reason a TL;DR fell back to the iPhone, or nil after a cloud success.
    static var lastProblem: String? {
        get { AppGroup.defaults.string(forKey: lastProblemKey) }
        set { AppGroup.defaults.set(newValue, forKey: lastProblemKey) }
    }

    /// A readable error with its error code, so a screenshot is enough to debug.
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

        let url = NotchmanCloud.baseURL
        steps.append(Step(name: "Server address", ok: url != nil, detail: url?.host() ?? "NOTCHMAN_API_URL is missing"))
        guard url != nil else { return steps }

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
        } catch {
            steps.append(Step(name: "Groq summary", ok: false, detail: describe(error)))
        }

        do {
            let audio = try await NotchmanCloud().speak(text: "Hi, this is Notchman.", previousText: nil, nextText: nil,
                                                        voiceID: CloudVoice.selected.id)
            let voice = CloudVoice.selected
            steps.append(Step(name: "ElevenLabs voice", ok: true,
                              detail: "\(voice.name) (\(voice.id)) confirmed · \(audio.count / 1024) KB"))
        } catch {
            steps.append(Step(name: "ElevenLabs voice", ok: false, detail: describe(error)))
        }
        return steps
    }
}
