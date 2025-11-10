import Foundation
import Security

/// Secure storage wrapper for Keychain
class KeychainHelper {
    static let standard = KeychainHelper()

    enum KeychainError: Error {
        case saveFailed(OSStatus)
        case retrievalFailed(OSStatus)
        case deleteFailed(OSStatus)
        case invalidData
    }

    /// Save data to Keychain
    func save(key: String, value: String) throws {
        guard let valueData = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: valueData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        // Delete existing value first
        SecItemDelete(query as CFDictionary)

        // Add new value
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Read data from Keychain
    func read(key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.retrievalFailed(status)
        }

        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }

        return value
    }

    /// Delete data from Keychain
    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    /// Clear all Keychain data
    func clearAll() throws {
        let queries = [
            [kSecClass as String: kSecClassGenericPassword],
            [kSecClass as String: kSecClassInternetPassword],
        ]

        for query in queries {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.deleteFailed(status)
            }
        }
    }
}

/// Configuration with secure token storage
class Config {
    static let shared = Config()

    private let keychain = KeychainHelper.standard

    // JWT token key
    private let JWT_TOKEN_KEY = "jwt_token"
    // Refresh token key
    private let REFRESH_TOKEN_KEY = "refresh_token"
    // User ID key
    private let USER_ID_KEY = "user_id"

    var graphqlEndpoint: String {
        ProcessInfo.processInfo.environment["GRAPHQL_ENDPOINT"] ??
            "https://api.novasocial.com/graphql"
    }

    // MARK: - Token Management

    /// Save JWT token securely to Keychain
    func saveJWTToken(_ token: String) throws {
        try keychain.save(key: JWT_TOKEN_KEY, value: token)
    }

    /// Retrieve JWT token from Keychain
    func getJWTToken() throws -> String? {
        return try keychain.read(key: JWT_TOKEN_KEY)
    }

    /// Save refresh token securely to Keychain
    func saveRefreshToken(_ token: String) throws {
        try keychain.save(key: REFRESH_TOKEN_KEY, value: token)
    }

    /// Retrieve refresh token from Keychain
    func getRefreshToken() throws -> String? {
        return try keychain.read(key: REFRESH_TOKEN_KEY)
    }

    /// Save user ID
    func saveUserID(_ userID: String) throws {
        try keychain.save(key: USER_ID_KEY, value: userID)
    }

    /// Retrieve user ID
    func getUserID() throws -> String? {
        return try keychain.read(key: USER_ID_KEY)
    }

    /// Check if user is authenticated
    func isAuthenticated() -> Bool {
        do {
            let token = try getJWTToken()
            return token != nil && !token!.isEmpty
        } catch {
            return false
        }
    }

    /// Clear all authentication data on logout
    func logout() throws {
        try keychain.delete(key: JWT_TOKEN_KEY)
        try keychain.delete(key: REFRESH_TOKEN_KEY)
        try keychain.delete(key: USER_ID_KEY)
    }
}

// MARK: - Migration from UserDefaults

/// Migration helper for moving tokens from UserDefaults to Keychain
class TokenMigration {
    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        let config = Config.shared

        // Check if migration flag exists
        if defaults.bool(forKey: "token_migration_completed") {
            return // Already migrated
        }

        // Migrate JWT token
        if let jwtToken = defaults.string(forKey: "jwt_token") {
            do {
                try config.saveJWTToken(jwtToken)
                defaults.removeObject(forKey: "jwt_token")
            } catch {
                print("Failed to migrate JWT token: \(error)")
            }
        }

        // Migrate refresh token
        if let refreshToken = defaults.string(forKey: "refresh_token") {
            do {
                try config.saveRefreshToken(refreshToken)
                defaults.removeObject(forKey: "refresh_token")
            } catch {
                print("Failed to migrate refresh token: \(error)")
            }
        }

        // Migrate user ID
        if let userID = defaults.string(forKey: "user_id") {
            do {
                try config.saveUserID(userID)
                defaults.removeObject(forKey: "user_id")
            } catch {
                print("Failed to migrate user ID: \(error)")
            }
        }

        // Mark migration as completed
        defaults.set(true, forKey: "token_migration_completed")
    }
}

// MARK: - Tests

#if DEBUG
import XCTest

class KeychainHelperTests: XCTestCase {
    var sut: KeychainHelper!

    override func setUp() {
        super.setUp()
        sut = KeychainHelper()
    }

    override func tearDown() {
        try? sut.delete(key: "test_key")
        super.tearDown()
    }

    func testSaveAndRetrieveToken() throws {
        let testToken = "test_jwt_token_12345"

        // Save
        try sut.save(key: "test_key", value: testToken)

        // Retrieve
        let retrieved = try sut.read(key: "test_key")
        XCTAssertEqual(retrieved, testToken)
    }

    func testRetrieveNonexistentKey() throws {
        let result = try sut.read(key: "nonexistent_key")
        XCTAssertNil(result)
    }

    func testDeleteToken() throws {
        let testToken = "test_token"
        try sut.save(key: "test_key", value: testToken)

        // Verify it exists
        let before = try sut.read(key: "test_key")
        XCTAssertNotNil(before)

        // Delete
        try sut.delete(key: "test_key")

        // Verify it's gone
        let after = try sut.read(key: "test_key")
        XCTAssertNil(after)
    }
}
#endif
