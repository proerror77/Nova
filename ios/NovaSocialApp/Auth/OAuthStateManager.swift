import Foundation
import CryptoKit

/// Manages OAuth state, nonce, and PKCE values for security
final class OAuthStateManager: @unchecked Sendable {
    static let shared = OAuthStateManager()

    private let stateKey = "oauth_state"
    private let nonceKey = "oauth_nonce"
    private let codeVerifierKey = "pkce_code_verifier"
    private let codeChallengeKey = "pkce_code_challenge"
    private let codeChallengeMethodKey = "pkce_code_challenge_method"

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

    // MARK: - PKCE (Proof Key for Code Exchange)
    /// Generates PKCE code verifier and challenge for enhanced OAuth security
    /// - Returns: Tuple of (codeVerifier, codeChallenge, codeChallengeMethod)
    func generatePKCE() -> (verifier: String, challenge: String, method: String) {
        // Generate code verifier: 128 characters of [A-Z0-9._~-]
        let codeVerifier = Self.generateCodeVerifier()

        // Calculate code challenge: BASE64URL(SHA256(codeVerifier))
        let codeChallenge = sha256Base64URL(codeVerifier)
        let method = "S256"

        // Store for verification during token exchange
        UserDefaults.standard.set(codeVerifier, forKey: codeVerifierKey)
        UserDefaults.standard.set(codeChallenge, forKey: codeChallengeKey)
        UserDefaults.standard.set(method, forKey: codeChallengeMethodKey)

        return (codeVerifier, codeChallenge, method)
    }

    func currentCodeVerifier() -> String? {
        UserDefaults.standard.string(forKey: codeVerifierKey)
    }

    func currentCodeChallenge() -> String? {
        UserDefaults.standard.string(forKey: codeChallengeKey)
    }

    func currentCodeChallengeMethod() -> String? {
        UserDefaults.standard.string(forKey: codeChallengeMethodKey)
    }

    func clearPKCE() {
        UserDefaults.standard.removeObject(forKey: codeVerifierKey)
        UserDefaults.standard.removeObject(forKey: codeChallengeKey)
        UserDefaults.standard.removeObject(forKey: codeChallengeMethodKey)
    }

    // MARK: - Hashing
    func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// SHA256 hash encoded in BASE64URL format for PKCE
    private func sha256Base64URL(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        let hashData = Data(hashed)

        // BASE64URL encoding (no padding, - instead of +, _ instead of /)
        let base64 = hashData.base64EncodedString()
        return base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    // MARK: - Helpers
    /// Generates PKCE-compliant code verifier: 128 characters of [A-Z0-9._~-]
    private static func generateCodeVerifier() -> String {
        // PKCE requires: 43-128 characters of unreserved characters
        // [A-Z] [a-z] [0-9] - . _ ~
        let charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        var result = String()
        result.reserveCapacity(128)
        for _ in 0..<128 {
            if let random = charset.randomElement() {
                result.append(random)
            }
        }
        return result
    }

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

