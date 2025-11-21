import Foundation
import SwiftUI

// MARK: - Authentication Manager

/// Manages user authentication state and token persistence
/// Coordinates with identity-service for login/register operations
@MainActor
class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()

    @Published var isAuthenticated = false
    @Published var currentUser: UserProfile?
    @Published var authToken: String?
    @Published var refreshToken: String?

    private let identityService = IdentityService()
    private let userDefaults = UserDefaults.standard

    // UserDefaults keys
    private let tokenKey = "auth_token"
    private let refreshTokenKey = "refresh_token"
    private let userIdKey = "user_id"

    private init() {
        loadSavedAuth()
    }

    // MARK: - Authentication State

    /// Load saved authentication from UserDefaults
    func loadSavedAuth() {
        if let token = userDefaults.string(forKey: tokenKey),
           let refresh = userDefaults.string(forKey: refreshTokenKey),
           let userId = userDefaults.string(forKey: userIdKey) {
            self.authToken = token
            self.refreshToken = refresh
            APIClient.shared.setAuthToken(token)
            self.isAuthenticated = true

            // Load user profile in background
            Task {
                try? await loadCurrentUser(userId: userId)
            }
        }
    }

    /// Load current user profile
    private func loadCurrentUser(userId: String) async throws {
        do {
            self.currentUser = try await identityService.getUser(userId: userId)
        } catch {
            print("Failed to load user profile: \(error)")
            // Keep auth state but user will be nil
        }
    }

    // MARK: - Registration

    /// Register new user
    func register(username: String, email: String, password: String, displayName: String) async throws -> UserProfile {
        let response = try await identityService.register(
            username: username,
            email: email,
            password: password,
            displayName: displayName
        )

        // Save authentication
        await saveAuth(token: response.token, refreshToken: response.refreshToken, user: response.user)

        return response.user
    }

    // MARK: - Login

    /// Login with username/email and password
    func login(username: String, password: String) async throws -> UserProfile {
        let response = try await identityService.login(
            username: username,
            password: password
        )

        // Save authentication
        await saveAuth(token: response.token, refreshToken: response.refreshToken, user: response.user)

        return response.user
    }

    // MARK: - Logout

    /// Logout current user
    func logout() async {
        // Clear identity service auth
        try? await identityService.logout()

        // Clear local state
        self.authToken = nil
        self.refreshToken = nil
        self.currentUser = nil
        self.isAuthenticated = false

        // Clear APIClient token
        APIClient.shared.setAuthToken("")

        // Clear UserDefaults
        userDefaults.removeObject(forKey: tokenKey)
        userDefaults.removeObject(forKey: refreshTokenKey)
        userDefaults.removeObject(forKey: userIdKey)
    }

    // MARK: - Token Refresh

    /// Refresh authentication token
    func refreshToken(refreshToken: String) async throws {
        let response = try await identityService.refreshToken(refreshToken: refreshToken)

        // Update token
        self.authToken = response.token
        APIClient.shared.setAuthToken(response.token)
        userDefaults.set(response.token, forKey: tokenKey)

        // Update user
        self.currentUser = response.user
        userDefaults.set(response.user.id, forKey: userIdKey)
    }

    // MARK: - Private Helpers

    private func saveAuth(token: String, refreshToken: String?, user: UserProfile) async {
        self.authToken = token
        self.refreshToken = refreshToken
        self.currentUser = user
        self.isAuthenticated = true

        // Set token in APIClient
        APIClient.shared.setAuthToken(token)

        // Save to UserDefaults
        userDefaults.set(token, forKey: tokenKey)
        if let refreshToken {
            userDefaults.set(refreshToken, forKey: refreshTokenKey)
        }
        userDefaults.set(user.id, forKey: userIdKey)
    }

    /// Attempt to refresh session if refresh token exists.
    /// Returns true if refresh succeeded.
    func refreshSessionIfPossible() async -> Bool {
        guard let refresh = refreshToken else {
            return false
        }
        do {
            let response = try await identityService.refreshToken(refreshToken: refresh)
            await saveAuth(token: response.token, refreshToken: response.refreshToken, user: response.user)
            return true
        } catch {
            // 清理失效 token，要求重新登录
            await logout()
            return false
        }
    }
}
