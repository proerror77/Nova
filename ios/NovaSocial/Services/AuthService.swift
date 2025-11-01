import Foundation
import Security
import Observation

/// AuthService - Modern authentication service using @Observable
/// Responsibilities: Token storage, token refresh, authentication state management
/// Uses dependency injection instead of singleton pattern
@Observable
final class AuthService: @unchecked Sendable {
    // MARK: - Properties

    private let keychainService = "com.nova.social"
    private let accessTokenKey = "access_token"
    private let refreshTokenKey = "refresh_token"
    private let tokenExpiryKey = "token_expiry"
    private let currentUserKey = "current_user"

    nonisolated private let lock = NSLock()
    private var _currentUser: User?
    private var _isAuthenticated: Bool = false

    var currentUser: User? {
        lock.withLock { _currentUser }
    }

    var isAuthenticated: Bool {
        lock.withLock { _isAuthenticated }
    }

    // MARK: - Computed Properties

    var accessToken: String? {
        loadFromKeychain(key: accessTokenKey)
    }

    var refreshToken: String? {
        loadFromKeychain(key: refreshTokenKey)
    }

    var isTokenExpired: Bool {
        guard let expiryString = UserDefaults.standard.string(forKey: tokenExpiryKey),
              let expiryDate = ISO8601DateFormatter().date(from: expiryString) else {
            return true
        }
        // Refresh 1 minute early to avoid edge cases
        return Date().addingTimeInterval(60) >= expiryDate
    }

    // MARK: - Initialization

    init() {
        loadCurrentUser()
        checkAuthenticationStatus()
    }

    // MARK: - Public API

    /// Save authentication information
    func saveAuth(user: User, tokens: AuthTokens) {
        // Save user info to Keychain
        if let userData = try? JSONEncoder().encode(user) {
            let encoded = userData.base64EncodedString()
            saveToKeychain(value: encoded, key: currentUserKey)
        }

        // Save Tokens to Keychain
        saveToKeychain(value: tokens.accessToken, key: accessTokenKey)
        saveToKeychain(value: tokens.refreshToken, key: refreshTokenKey)

        // Calculate and save expiry time
        let expiryDate = Date().addingTimeInterval(TimeInterval(tokens.expiresIn))
        let expiryString = ISO8601DateFormatter().string(from: expiryDate)
        UserDefaults.standard.set(expiryString, forKey: tokenExpiryKey)

        // Update state
        lock.withLock {
            _currentUser = user
            _isAuthenticated = true
        }

        Logger.log("✅ Auth saved for user: \(user.username)", level: .info)
    }

    /// Update Access Token (called during token refresh)
    func updateAccessToken(_ accessToken: String, expiresIn: Int) {
        saveToKeychain(value: accessToken, key: accessTokenKey)

        let expiryDate = Date().addingTimeInterval(TimeInterval(expiresIn))
        let expiryString = ISO8601DateFormatter().string(from: expiryDate)
        UserDefaults.standard.set(expiryString, forKey: tokenExpiryKey)

        Logger.log("✅ Access token refreshed", level: .info)
    }

    /// Clear authentication information (logout)
    func clearAuth() {
        // Clear Keychain
        deleteFromKeychain(key: accessTokenKey)
        deleteFromKeychain(key: refreshTokenKey)
        deleteFromKeychain(key: currentUserKey)

        // Clear UserDefaults
        UserDefaults.standard.removeObject(forKey: tokenExpiryKey)

        // Update state
        lock.withLock {
            _currentUser = nil
            _isAuthenticated = false
        }

        Logger.log("✅ Auth cleared", level: .info)
    }

    /// Attempt to restore login state from local storage
    func restoreSession() -> Bool {
        loadCurrentUser()
        checkAuthenticationStatus()
        return isAuthenticated
    }

    // MARK: - Private Helpers

    private func loadCurrentUser() {
        let decodedUser: User?
        if let encoded = loadFromKeychain(key: currentUserKey),
           let data = Data(base64Encoded: encoded),
           let user = try? JSONDecoder().decode(User.self, from: data) {
            decodedUser = user
        } else {
            decodedUser = nil
        }

        lock.withLock {
            _currentUser = decodedUser
        }
    }

    private func checkAuthenticationStatus() {
        let cachedUser = lock.withLock { _currentUser }
        let isValid = (cachedUser != nil && accessToken != nil && !isTokenExpired)
        lock.withLock {
            _isAuthenticated = isValid
        }
    }

    // MARK: - Keychain Operations

    private func saveToKeychain(value: String, key: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete old value first
        deleteFromKeychain(key: key)

        // Save new value
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            Logger.log("❌ Keychain save failed: \(status)", level: .error)
        }
    }

    private func loadFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            Logger.log("Keychain delete failed for key \(key): \(status)", level: .error)
        }
    }
}
