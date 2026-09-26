import AuthenticationServices
import Foundation
import Observation
import os

/// Optional account. Notchman works fully without signing in; signing in with
/// Apple records who you are on this device. There is no Notchman server yet,
/// so nothing is uploaded and history isn't synced.
@MainActor
@Observable
final class AccountStore {
    struct Account: Codable, Equatable {
        var userID: String
        var name: String?
        var email: String?
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
            let account = Account(userID: credential.user,
                                  name: (name?.isEmpty == false ? name : nil) ?? self.account?.name,
                                  email: credential.email ?? self.account?.email)
            save(account)
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

    /// Signs out locally if the Apple ID credential was revoked.
    func refreshCredentialState() async {
        guard let userID = account?.userID else { return }
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
