import AuthenticationServices
import Foundation

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published private(set) var isAuthenticated = false
    @Published private(set) var userIdentifier: String? = nil
    @Published private(set) var userFullName: String? = nil
    @Published private(set) var userEmail: String? = nil
    @Published var authError: String? = nil

    private let keychainKey = "auth_user_identifier"

    private init() {
        restoreSession()
    }

    // MARK: - Session restore

    private func restoreSession() {
        guard let stored = KeychainHelper.read(key: keychainKey) else { return }
        userIdentifier = stored
        isAuthenticated = true
    }

    // MARK: - Sign In with Apple

    func handleAppleSignIn(result: Result<ASAuthorization, Error>) {
        authError = nil
        switch result {
        case .failure(let error):
            let asError = error as? ASAuthorizationError
            if asError?.code != .canceled {
                authError = error.localizedDescription
            }
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            let id = cred.user
            userIdentifier = id
            if let first = cred.fullName?.givenName, let last = cred.fullName?.familyName {
                let combined = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
                if !combined.isEmpty { userFullName = combined }
            }
            userEmail = cred.email
            KeychainHelper.write(key: keychainKey, value: id)
            isAuthenticated = true
        }
    }

    // MARK: - Sign out

    func signOut() {
        KeychainHelper.delete(key: keychainKey)
        userIdentifier = nil
        userFullName = nil
        userEmail = nil
        isAuthenticated = false
    }

    // MARK: - Stubs (not yet implemented)

    func signInWithGoogle() {}
    func signInWithLinkedIn() {}
    func signInWithGitHub() {}
}

// MARK: - Keychain helper (internal to this file)

private enum KeychainHelper {
    static func write(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var ref: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &ref) == errSecSuccess,
              let data = ref as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
