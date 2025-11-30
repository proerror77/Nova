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

    private let identityService = IdentityService()
    private let keychain = KeychainService.shared

    // Legacy UserDefaults for migration (will be removed in future)
    private let userDefaults = UserDefaults.standard
    private let legacyTokenKey = "auth_token"
    private let legacyRefreshTokenKey = "refresh_token"
    private let legacyUserIdKey = "user_id"

    // Token refresh state - use task coalescence to prevent race conditions
    // Note: Using nonisolated property access pattern for Swift 6 compatibility
    private var refreshTask: Task<Bool, Never>?

    private init() {
        migrateFromUserDefaults()
        loadSavedAuth()
    }

    // MARK: - Migration

    /// Migrate tokens from UserDefaults to Keychain (one-time)
    private func migrateFromUserDefaults() {
        // Check if migration needed
        if keychain.exists(.authToken) { return }

        // Migrate auth token
        if let token = userDefaults.string(forKey: legacyTokenKey) {
            _ = keychain.save(token, for: .authToken)
            userDefaults.removeObject(forKey: legacyTokenKey)
        }

        // Migrate refresh token
        if let refreshToken = userDefaults.string(forKey: legacyRefreshTokenKey) {
            _ = keychain.save(refreshToken, for: .refreshToken)
            userDefaults.removeObject(forKey: legacyRefreshTokenKey)
        }

        // Migrate user ID
        if let userId = userDefaults.string(forKey: legacyUserIdKey) {
            _ = keychain.save(userId, for: .userId)
            userDefaults.removeObject(forKey: legacyUserIdKey)
        }

        #if DEBUG
        print("[Auth] Tokens migrated from UserDefaults to Keychain")
        #endif
    }

    // MARK: - Authentication State

    /// Load saved authentication from Keychain
    func loadSavedAuth() {
        if let token = keychain.get(.authToken),
           let userId = keychain.get(.userId) {
            self.authToken = token
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
            #if DEBUG
            print("[Auth] Failed to load user profile: \(error)")
            #endif
            // Keep auth state but user will be nil
        }
    }

    // MARK: - Guest Mode (临时登录)

    /// 设置访客模式，允许用户跳过登录浏览应用
    func setGuestMode() {
        self.isAuthenticated = true
        self.currentUser = UserProfile(
            id: "guest",
            username: "Guest",
            email: nil,
            displayName: "Guest User",
            bio: nil,
            avatarUrl: nil,
            coverUrl: nil,
            website: nil,
            location: nil,
            isVerified: false,
            isPrivate: false,
            followerCount: 0,
            followingCount: 0,
            postCount: 0,
            createdAt: nil,
            updatedAt: nil,
            deletedAt: nil
        )
        self.authToken = "guest_token"

        #if DEBUG
        print("[Auth] Guest mode enabled")
        #endif
    }

    /// 检查是否为访客模式
    var isGuestMode: Bool {
        currentUser?.id == "guest"
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

        // Save authentication with refresh token
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

        // Save authentication with refresh token
        await saveAuth(token: response.token, refreshToken: response.refreshToken, user: response.user)

        return response.user
    }

    // MARK: - OAuth Login

    /// Login with Google OAuth
    func loginWithGoogle() async throws -> UserProfile {
        let oauthService = OAuthService.shared

        // Perform Google Sign-In flow
        let response = try await oauthService.signInWithGoogle()

        // Create user profile from response
        let user: UserProfile
        if let responseUser = response.user {
            user = responseUser
        } else {
            // Minimal profile if not provided
            user = UserProfile(
                id: response.userId,
                username: "user_\(response.userId.prefix(8))",
                email: nil,
                displayName: nil,
                bio: nil,
                avatarUrl: nil,
                coverUrl: nil,
                website: nil,
                location: nil,
                isVerified: false,
                isPrivate: false,
                followerCount: 0,
                followingCount: 0,
                postCount: 0,
                createdAt: nil,
                updatedAt: nil,
                deletedAt: nil
            )
        }

        // Save authentication
        await saveAuth(token: response.token, refreshToken: response.refreshToken, user: user)

        #if DEBUG
        print("[Auth] Google Sign-In successful, isNewUser: \(response.isNewUser)")
        #endif

        return user
    }

    // MARK: - Logout

    /// Logout current user
    func logout() async {
        // Clear identity service auth
        try? await identityService.logout()

        // Clear local state
        self.authToken = nil
        self.currentUser = nil
        self.isAuthenticated = false

        // Clear APIClient token
        APIClient.shared.setAuthToken("")

        // Clear Keychain
        keychain.clearAll()
    }

    // MARK: - Token Refresh

    /// Refresh authentication token
    func refreshToken(refreshToken: String) async throws {
        let response = try await identityService.refreshToken(refreshToken: refreshToken)

        // Update token in Keychain
        self.authToken = response.token
        APIClient.shared.setAuthToken(response.token)
        _ = keychain.save(response.token, for: .authToken)

        // Update refresh token if provided
        if let newRefreshToken = response.refreshToken {
            _ = keychain.save(newRefreshToken, for: .refreshToken)
        }

        // Update user
        self.currentUser = response.user
        _ = keychain.save(response.user.id, for: .userId)
    }

    /// Attempt to refresh token if expired (401 error)
    /// Returns true if refresh was successful
    /// Uses task coalescence to prevent multiple concurrent refresh attempts (race condition fix)
    func attemptTokenRefresh() async -> Bool {
        // If already refreshing, wait for the existing task (MainActor ensures thread safety)
        if let existingTask = refreshTask {
            return await existingTask.value
        }

        guard let storedRefreshToken = keychain.get(.refreshToken) else {
            #if DEBUG
            print("[Auth] No refresh token available")
            #endif
            return false
        }

        // Create and store the refresh task
        let task = Task<Bool, Never> { [weak self] in
            guard let self = self else { return false }

            do {
                try await self.refreshToken(refreshToken: storedRefreshToken)
                #if DEBUG
                print("[Auth] Token refreshed successfully")
                #endif
                return true
            } catch {
                #if DEBUG
                print("[Auth] Token refresh failed: \(error)")
                #endif
                // Clear auth state on refresh failure
                await self.logout()
                return false
            }
        }

        refreshTask = task

        // Wait for result and clean up
        let result = await task.value
        refreshTask = nil

        return result
    }

    /// Get stored refresh token
    var storedRefreshToken: String? {
        keychain.get(.refreshToken)
    }

    /// Get stored user ID
    var storedUserId: String? {
        keychain.get(.userId)
    }

    // MARK: - Private Helpers

    private func saveAuth(token: String, refreshToken: String?, user: UserProfile) async {
        self.authToken = token
        self.currentUser = user
        self.isAuthenticated = true

        // Set token in APIClient
        APIClient.shared.setAuthToken(token)

        // Save to Keychain (secure storage)
        _ = keychain.save(token, for: .authToken)
        _ = keychain.save(user.id, for: .userId)
        if let refreshToken = refreshToken {
            _ = keychain.save(refreshToken, for: .refreshToken)
        }
    }
}
