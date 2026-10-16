import AuthenticationServices
import Foundation
import Observation
import os

/// Optional account: Sign in with Apple. Notchman works fully without signing in.
/// When someone signs in, the Notchman server keeps their email, Apple account
/// ID and plan (server/src/accounts.ts), so a paying user can be helped and
/// their plan follows them.
@MainActor
@Observable
final class AccountStore {
    struct Account: Codable, Equatable {
        var userID: String
        var name: String?
        var email: String?
        var provider: String? = "apple"

        /// What to show as the account's name.
        var displayName: String {
            if let name, !name.isEmpty { return name }
            if let email, let local = email.split(separator: "@").first { return String(local) }
            return "Notchman user"
        }
    }


    private(set) var account: Account?
    var isSignedIn: Bool { account != nil }

    private let log = Logger(subsystem: "com.notchman", category: "Account")
    private static let keychainKey = "apple-account"

    init() {
        if let json = KeychainStore.string(for: Self.keychainKey),
           let stored = try? JSONDecoder().decode(Account.self, from: Data(json.utf8)) {
            account = stored
        }
    }

    /// Handles the result of `SignInWithAppleButton`.
    func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            // Apple only sends name and email the first time; keep what we had.
            let name = credential.fullName.flatMap { PersonNameComponentsFormatter().string(from: $0) }
            // The email is only in `credential.email` the first time, but it's in
            // the identity token every time, so read it from there as well.
            let account = Account(userID: credential.user,
                                  name: (name?.isEmpty == false ? name : nil) ?? self.account?.name,
                                  email: credential.email ?? Self.email(fromIdentityToken: credential.identityToken)
                                      ?? self.account?.email,
                                  provider: "apple")
            save(account)
            if let data = credential.identityToken, let token = String(data: data, encoding: .utf8) {
                let name = account.name
                Task { await Self.server("signin", identityToken: token, name: name) }
            }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                log.error("Sign in with Apple failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func signOut() {
        account = nil
        KeychainStore.set(nil, for: Self.keychainKey)
    }

    /// Deletes the account: on the Notchman server and on this iPhone.
    func deleteAccount() async {
        await Self.server("delete")
        log.info("Account deleted")
        signOut()
    }

    /// Tells the server this account's current plan (after a purchase, and when the app opens).
    func syncPlan() async {
        guard isSignedIn else { return }
        await Self.server("refresh")
    }

    private static func server(_ action: String, identityToken: String? = nil, name: String? = nil) async {
        guard NotchmanCloud.isAvailable else { return }
        do {
            try await NotchmanCloud().account(action, identityToken: identityToken, name: name)
        } catch {
            Logger(subsystem: "com.notchman", category: "Account")
                .error("Account \(action, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The `email` claim from Apple's identity token (a JWT).
    static func email(fromIdentityToken token: Data?) -> String? {
        guard let token, let jwt = String(data: token, encoding: .utf8) else { return nil }
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return claims["email"] as? String
    }

    /// Signs out locally if the Apple ID credential was revoked.
    func refreshCredentialState() async {
        guard account?.provider != "email", let userID = account?.userID else { return }
        let state = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: userID)
        if state == .revoked || state == .notFound {
            signOut()
        }
    }

    private func save(_ account: Account) {
        self.account = account
        if let data = try? JSONEncoder().encode(account) {
            KeychainStore.set(String(decoding: data, as: UTF8.self), for: Self.keychainKey)
        }
    }
}
