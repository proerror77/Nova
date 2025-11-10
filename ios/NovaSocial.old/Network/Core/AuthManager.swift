import Foundation
import Security

/// AuthManager - 认证管理器
/// 职责：Token 存储、Token 刷新、登录状态管理
/// 单例模式，全局唯一
final class AuthManager {
    static let shared = AuthManager()

    // MARK: - Properties

    private let keychainService = "com.nova.social"
    private let accessTokenKey = "access_token"
    private let refreshTokenKey = "refresh_token"
    private let tokenExpiryKey = "token_expiry"
    private let currentUserKey = "current_user"

    private let stateQueue = DispatchQueue(label: "com.nova.social.authmanager.state", attributes: .concurrent)
    private var _currentUser: User?
    private var _isAuthenticated: Bool = false

    var currentUser: User? {
        stateQueue.sync { _currentUser }
    }

    var isAuthenticated: Bool {
        stateQueue.sync { _isAuthenticated }
    }

    // MARK: - Computed Properties

    var accessToken: String? {
        return loadFromKeychain(key: accessTokenKey)
    }

    var refreshToken: String? {
        return loadFromKeychain(key: refreshTokenKey)
    }

    var isTokenExpired: Bool {
        guard let expiryString = UserDefaults.standard.string(forKey: tokenExpiryKey),
              let expiryDate = ISO8601DateFormatter().date(from: expiryString) else {
            return true
        }
        // 提前 1 分钟刷新，避免边界情况
        return Date().addingTimeInterval(60) >= expiryDate
    }

    // MARK: - Initialization

    private init() {
        loadCurrentUser()
        checkAuthenticationStatus()
    }

    // MARK: - Public API

    /// 保存认证信息
    func saveAuth(user: User, tokens: AuthTokens) {
        // 保存用户信息到 Keychain
        if let userData = try? JSONEncoder().encode(user) {
            let encoded = userData.base64EncodedString()
            saveToKeychain(value: encoded, key: currentUserKey)
        }

        // 保存 Tokens 到 Keychain
        saveToKeychain(value: tokens.accessToken, key: accessTokenKey)
        saveToKeychain(value: tokens.refreshToken, key: refreshTokenKey)

        // 计算并保存过期时间
        let expiryDate = Date().addingTimeInterval(TimeInterval(tokens.expiresIn))
        let expiryString = ISO8601DateFormatter().string(from: expiryDate)
        UserDefaults.standard.set(expiryString, forKey: tokenExpiryKey)

        // 更新状态
        stateQueue.sync(flags: .barrier) {
            self._currentUser = user
            self._isAuthenticated = true
        }

        Logger.log("✅ Auth saved for user: \(user.username)", level: .info)
    }

    /// 更新 Access Token（Token 刷新时调用）
    func updateAccessToken(_ accessToken: String, expiresIn: Int) {
        saveToKeychain(value: accessToken, key: accessTokenKey)

        let expiryDate = Date().addingTimeInterval(TimeInterval(expiresIn))
        let expiryString = ISO8601DateFormatter().string(from: expiryDate)
        UserDefaults.standard.set(expiryString, forKey: tokenExpiryKey)

        Logger.log("✅ Access token refreshed", level: .info)
    }

    /// 清空认证信息（登出）
    func clearAuth() {
        // 清空 Keychain
        deleteFromKeychain(key: accessTokenKey)
        deleteFromKeychain(key: refreshTokenKey)
        deleteFromKeychain(key: currentUserKey)

        // 清空 UserDefaults
        UserDefaults.standard.removeObject(forKey: tokenExpiryKey)

        // 更新状态
        stateQueue.sync(flags: .barrier) {
            self._currentUser = nil
            self._isAuthenticated = false
        }

        Logger.log("✅ Auth cleared", level: .info)
    }

    /// 尝试从本地恢复登录状态
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

        stateQueue.sync(flags: .barrier) {
            self._currentUser = decodedUser
        }
    }

    private func checkAuthenticationStatus() {
        let cachedUser = stateQueue.sync { self._currentUser }
        let isValid = (cachedUser != nil && accessToken != nil && !isTokenExpired)
        stateQueue.sync(flags: .barrier) {
            self._isAuthenticated = isValid
        }
    }

    // MARK: - Keychain Operations

    private func saveToKeychain(value: String, key: String) {
        guard let data = value.data(using: .utf8) else { return }

        // 先删除旧值
        deleteFromKeychain(key: key)

        // 保存新值
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
