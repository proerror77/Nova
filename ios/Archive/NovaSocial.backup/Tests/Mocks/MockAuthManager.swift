import Foundation
@testable import NovaSocial

/// MockAuthManager - AuthManager 的测试替身
/// TDD: 提供可控的认证状态，便于测试各种认证场景
final class MockAuthManager {

    // MARK: - Properties

    var mockUser: User?
    var mockAccessToken: String?
    var mockRefreshToken: String?
    var mockTokenExpiry: Date?

    var saveAuthCalled = false
    var clearAuthCalled = false
    var restoreSessionCalled = false

    // MARK: - Computed Properties

    var isAuthenticated: Bool {
        mockAccessToken != nil && mockUser != nil
    }

    var currentUser: User? {
        mockUser
    }

    var accessToken: String? {
        mockAccessToken
    }

    var refreshToken: String? {
        mockRefreshToken
    }

    var isTokenExpired: Bool {
        guard let expiry = mockTokenExpiry else { return false }
        return expiry <= Date()
    }

    // MARK: - Methods

    func saveAuth(user: User, tokens: AuthTokens) {
        saveAuthCalled = true
        mockUser = user
        mockAccessToken = tokens.accessToken
        mockRefreshToken = tokens.refreshToken
        mockTokenExpiry = Date().addingTimeInterval(TimeInterval(tokens.expiresIn))
    }

    func clearAuth() {
        clearAuthCalled = true
        mockUser = nil
        mockAccessToken = nil
        mockRefreshToken = nil
        mockTokenExpiry = nil
    }

    func restoreSession() -> Bool {
        restoreSessionCalled = true
        return isAuthenticated
    }

    func updateAccessToken(_ token: String, expiresIn: Int) {
        mockAccessToken = token
        mockTokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn))
    }

    // MARK: - Test Helpers

    func reset() {
        mockUser = nil
        mockAccessToken = nil
        mockRefreshToken = nil
        mockTokenExpiry = nil
        saveAuthCalled = false
        clearAuthCalled = false
        restoreSessionCalled = false
    }

    /// 设置已过期的 Token
    func setExpiredToken() {
        mockAccessToken = "expired_token"
        mockRefreshToken = "refresh_token"
        mockTokenExpiry = Date().addingTimeInterval(-1) // 1秒前过期
    }

    /// 设置有效的 Token
    func setValidToken(expiresIn: TimeInterval = 900) {
        mockAccessToken = "valid_token"
        mockRefreshToken = "refresh_token"
        mockTokenExpiry = Date().addingTimeInterval(expiresIn)
    }
}
