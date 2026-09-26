import Foundation
import StoreKit

/// This month's TL;DR allowance, as reported by the Notchman server.
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
}

enum CloudError: LocalizedError {
    case notConfigured
    case quotaExceeded(CloudUsage)
    case busy
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "The Notchman server isn't configured in this build."
        case .quotaExceeded(let usage): "You've used all \(usage.limit) TL;DRs in your \(usage.planName) plan this month."
        case .busy: "Notchman is very busy right now. Try again in a little while."
        case .server(let message): message
        }
    }
}

/// Anonymous, per-install identifier used only to count Free-plan TL;DRs.
/// Stored in the Keychain so it survives app updates.
enum InstallID {
    private static let account = "install-id"

    static var value: String {
        if let existing = KeychainStore.string(for: account), UUID(uuidString: existing) != nil {
            return existing
        }
        let fresh = UUID().uuidString.lowercased()
        KeychainStore.set(fresh, for: account)
        return fresh
    }
}

/// Client for the Notchman server (see /server). The server holds the AI
/// provider keys; the app never does.
struct NotchmanCloud {
    var session: URLSession = .shared

    /// From Info.plist (`NotchmanAPIBaseURL`, set by NOTCHMAN_API_BASE_URL in project.yml).
    static var baseURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "NotchmanAPIBaseURL") as? String,
              !value.isEmpty, let url = URL(string: value), url.scheme == "https" else { return nil }
        return url
    }

    func tldr(text: String, length: QuickListenDuration) async throws -> (summary: String, usage: CloudUsage) {
        let (data, status) = try await post("api/tldr", body: [
            "installId": InstallID.value,
            "text": text,
            "length": length.rawValue,
            "transactions": await Self.currentTransactions(),
        ])
        struct Response: Decodable {
            let summary: String?
            let plan: String?, used: Int?, limit: Int?, remaining: Int?
            let error: String?, message: String?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        let usage = CloudUsage(plan: response.plan ?? "free", used: response.used ?? 0,
                               limit: response.limit ?? 0, remaining: response.remaining ?? 0)
        switch status {
        case 200:
            guard let summary = response.summary else { throw CloudError.server("Empty summary.") }
            return (summary, usage)
        case 402: throw CloudError.quotaExceeded(usage)
        case 503: throw CloudError.busy
        default: throw CloudError.server(response.message ?? "The summary couldn't be created (\(status)).")
        }
    }

    func usage() async throws -> CloudUsage {
        let (data, status) = try await post("api/usage", body: [
            "installId": InstallID.value,
            "transactions": await Self.currentTransactions(),
        ])
        guard status == 200 else { throw CloudError.server("Usage unavailable (\(status)).") }
        return try JSONDecoder().decode(CloudUsage.self, from: data)
    }

    private func post(_ path: String, body: [String: Any]) async throws -> (Data, Int) {
        guard let base = Self.baseURL else { throw CloudError.notConfigured }
        var request = URLRequest(url: base.appendingPathComponent(path), timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Signed StoreKit transactions proving the user's subscription; the server
    /// verifies Apple's signature, so these can't be forged.
    static func currentTransactions() async -> [String] {
        var signed: [String] = []
        for await entitlement in Transaction.currentEntitlements {
            signed.append(entitlement.jwsRepresentation)
        }
        return signed
    }
}
