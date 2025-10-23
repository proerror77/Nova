import Foundation
import CryptoKit

/// Manages OAuth state and nonce values for CSRF and replay protection
final class OAuthStateManager: @unchecked Sendable {
    static let shared = OAuthStateManager()

    private let stateKey = "oauth_state"
    private let nonceKey = "oauth_nonce"

    private init() {}

    // MARK: - State
    func generateState() -> String {
        let state = Self.randomString(length: 32)
        UserDefaults.standard.set(state, forKey: stateKey)
        return state
    }

    func currentState() -> String? {
        UserDefaults.standard.string(forKey: stateKey)
    }

    func clearState() {
        UserDefaults.standard.removeObject(forKey: stateKey)
    }

    // MARK: - Nonce
    func generateNonce() -> String {
        let nonce = Self.randomString(length: 32)
        UserDefaults.standard.set(nonce, forKey: nonceKey)
        return nonce
    }

    func currentNonce() -> String? {
        UserDefaults.standard.string(forKey: nonceKey)
    }

    func clearNonce() {
        UserDefaults.standard.removeObject(forKey: nonceKey)
    }

    func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Helpers
    private static func randomString(length: Int) -> String {
        let charset: [Character] = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        var result = String()
        result.reserveCapacity(length)
        for _ in 0..<length {
            if let random = charset.randomElement() {
                result.append(random)
            }
        }
        return result
    }
}

