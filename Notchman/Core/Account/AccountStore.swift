import AuthenticationServices
import FirebaseAuth
import Foundation
import Observation
import os

/// Optional account: Sign in with Apple, or email and password (Firebase Auth).
/// Notchman works fully without signing in.
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

    enum EmailError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Email sign-in isn't available in this build." }
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
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                log.error("Sign in with Apple failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Signs in with email and password, or creates the account. A new account
    /// keeps the anonymous Firebase user (and its TL;DR count) by linking to it.
    func emailSignIn(email: String, password: String, createAccount: Bool) async throws {
        guard FirebaseSetup.isConfigured else { throw EmailError.unavailable }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let user: User
        if createAccount {
            let credential = EmailAuthProvider.credential(withEmail: email, password: password)
            if let current = Auth.auth().currentUser, current.isAnonymous {
                user = try await current.link(with: credential).user
            } else {
                user = try await Auth.auth().createUser(withEmail: email, password: password).user
            }
        } else {
            user = try await Auth.auth().signIn(withEmail: email, password: password).user
        }
        save(Account(userID: user.uid, name: user.displayName, email: user.email ?? email, provider: "email"))
    }

    func sendPasswordReset(to email: String) async throws {
        guard FirebaseSetup.isConfigured else { throw EmailError.unavailable }
        try await Auth.auth().sendPasswordReset(withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func signOut() {
        if account?.provider == "email", FirebaseSetup.isConfigured {
            try? Auth.auth().signOut()
        }
        account = nil
        KeychainStore.set(nil, for: Self.keychainKey)
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
