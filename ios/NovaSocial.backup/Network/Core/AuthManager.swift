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

    private(set) var currentUser: User?
    private(set) var isAuthenticated: Bool = false

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
        // 保存用户信息到 UserDefaults
        if let userData = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(userData, forKey: "current_user")
        }

        // 保存 Tokens 到 Keychain
        saveToKeychain(value: tokens.accessToken, key: accessTokenKey)
        saveToKeychain(value: tokens.refreshToken, key: refreshTokenKey)

        // 计算并保存过期时间
        let expiryDate = Date().addingTimeInterval(TimeInterval(tokens.expiresIn))
        let expiryString = ISO8601DateFormatter().string(from: expiryDate)
        UserDefaults.standard.set(expiryString, forKey: tokenExpiryKey)

        // 更新状态
        currentUser = user
        isAuthenticated = true

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

        // 清空 UserDefaults
        UserDefaults.standard.removeObject(forKey: "current_user")
        UserDefaults.standard.removeObject(forKey: tokenExpiryKey)

        // 更新状态
        currentUser = nil
        isAuthenticated = false

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
        guard let userData = UserDefaults.standard.data(forKey: "current_user"),
              let user = try? JSONDecoder().decode(User.self, from: userData) else {
            currentUser = nil
            return
        }
        currentUser = user
    }

    private func checkAuthenticationStatus() {
        isAuthenticated = (currentUser != nil && accessToken != nil && !isTokenExpired)
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

        SecItemDelete(query as CFDictionary)
    }
}
