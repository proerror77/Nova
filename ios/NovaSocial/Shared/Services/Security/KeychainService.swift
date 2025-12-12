import Foundation
import Security

// MARK: - Keychain Service

/// Secure storage for sensitive data using iOS Keychain
/// Use this instead of UserDefaults for tokens and credentials
final class KeychainService {
    static let shared = KeychainService()

    private let service = "com.nova.social"

    private init() {}

    // MARK: - Keys

    enum Key: String {
        case authToken = "auth_token"
        case refreshToken = "refresh_token"
        case userId = "user_id"
        case e2eeDeviceIdentity = "e2ee_device_identity"

        // Matrix SSO credentials
        case matrixAccessToken = "matrix_access_token"
        case matrixUserId = "matrix_user_id"
        case matrixDeviceId = "matrix_device_id"
        case matrixHomeserver = "matrix_homeserver"
    }

    // MARK: - Public Methods

    /// Save string value to Keychain
    func save(_ value: String, for key: Key) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete existing item first
        delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Retrieve string value from Keychain
    func get(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    /// Delete value from Keychain
    @discardableResult
    func delete(_ key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Clear all stored values
    func clearAll() {
        for key in [Key.authToken, Key.refreshToken, Key.userId, Key.e2eeDeviceIdentity,
                    Key.matrixAccessToken, Key.matrixUserId, Key.matrixDeviceId, Key.matrixHomeserver] {
            delete(key)
        }
    }

    /// Clear only Matrix-related credentials
    func clearMatrixCredentials() {
        for key in [Key.matrixAccessToken, Key.matrixUserId, Key.matrixDeviceId, Key.matrixHomeserver] {
            delete(key)
        }
    }

    /// Check if a key exists
    func exists(_ key: Key) -> Bool {
        return get(key) != nil
    }
}
