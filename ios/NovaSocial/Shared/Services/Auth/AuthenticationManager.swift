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

    // Retry configuration for token refresh
    private let maxRefreshRetries = 3
    private let refreshRetryDelaySeconds: UInt64 = 2

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
        #if DEBUG
        print("[Auth] 📂 Loading saved auth from Keychain...")
        #endif

        if let token = keychain.get(.authToken),
           let userId = keychain.get(.userId) {
            self.authToken = token
            APIClient.shared.setAuthToken(token)
            self.isAuthenticated = true

            let hasRefreshToken = keychain.exists(.refreshToken)
            #if DEBUG
            print("[Auth]   ✅ Found saved auth:")
            print("[Auth]   - Access token: \(token.prefix(20))...")
            print("[Auth]   - User ID: \(userId)")
            print("[Auth]   - Has refresh token: \(hasRefreshToken)")
            #endif

            // Load user profile in background
            Task {
                try? await loadCurrentUser(userId: userId)
            }
        } else {
            #if DEBUG
            print("[Auth]   ℹ️ No saved auth found in Keychain")
            #endif
        }
    }

    /// Load current user profile
    private func loadCurrentUser(userId: String) async throws {
        do {
            self.currentUser = try await identityService.getUser(userId: userId)
            #if DEBUG
            print("[Auth] Loaded current user: id=\(currentUser?.id ?? "nil"), avatarUrl=\(currentUser?.avatarUrl ?? "nil")")
            #endif
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
            isBanned: false,
            followerCount: 0,
            followingCount: 0,
            postCount: 0,
            createdAt: nil,
            updatedAt: nil,
            deletedAt: nil,
            firstName: nil,
            lastName: nil,
            dateOfBirth: nil,
            gender: nil
        )
        self.authToken = "guest_token"

        #if DEBUG
        print("[Auth] Guest mode enabled")
        #endif
    }

    // MARK: - Profile Update

    /// Update cached current user profile
    func updateCurrentUser(_ user: UserProfile) {
        self.currentUser = user
        // Optionally persist user ID if changed
        _ = keychain.save(user.id, for: .userId)

        #if DEBUG
        print("[Auth] Current user updated: id=\(user.id), username=\(user.username), avatarUrl=\(user.avatarUrl ?? "nil")")
        #endif
    }

    /// 检查是否为访客模式
    var isGuestMode: Bool {
        currentUser?.id == "guest"
    }

    // MARK: - Registration

    /// Register new user
    func register(username: String, email: String, password: String, displayName: String, inviteCode: String = "NOVA2025TEST") async throws -> UserProfile {
        let response = try await identityService.register(
            username: username,
            email: email,
            password: password,
            displayName: displayName,
            inviteCode: inviteCode
        )

        // Save authentication with refresh token
        await saveAuth(token: response.accessToken, refreshToken: response.refreshToken, user: response.user)

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
        await saveAuth(token: response.accessToken, refreshToken: response.refreshToken, user: response.user)

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
                isBanned: false,
                followerCount: 0,
                followingCount: 0,
                postCount: 0,
                createdAt: nil,
                updatedAt: nil,
                deletedAt: nil,
                firstName: nil,
                lastName: nil,
                dateOfBirth: nil,
                gender: nil
            )
        }

        // Save authentication
        await saveAuth(token: response.token, refreshToken: response.refreshToken, user: user)

        #if DEBUG
        print("[Auth] Google Sign-In successful, isNewUser: \(response.isNewUser)")
        #endif

        return user
    }

    /// Login with Apple Sign-In
    func loginWithApple() async throws -> UserProfile {
        let oauthService = OAuthService.shared

        // Perform Apple Sign-In flow (native)
        let response = try await oauthService.signInWithApple()

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
                isBanned: false,
                followerCount: 0,
                followingCount: 0,
                postCount: 0,
                createdAt: nil,
                updatedAt: nil,
                deletedAt: nil,
                firstName: nil,
                lastName: nil,
                dateOfBirth: nil,
                gender: nil
            )
        }

        // Save authentication
        await saveAuth(token: response.token, refreshToken: response.refreshToken, user: user)

        #if DEBUG
        print("[Auth] Apple Sign-In successful, isNewUser: \(response.isNewUser)")
        #endif

        return user
    }

    // MARK: - Logout

    /// Logout current user
    func logout() async {
        // Clear identity service auth
        try? await identityService.logout()

        // Clear Matrix session (with credentials) to ensure fresh login next time
        await MatrixBridgeService.shared.shutdown(clearCredentials: true)

        // Clear local state
        self.authToken = nil
        self.currentUser = nil
        self.isAuthenticated = false

        // Clear APIClient token
        APIClient.shared.setAuthToken("")

        // Clear Keychain
        keychain.clearAll()
    }

    /// Force logout due to session expiration - posts notification to navigate to login
    /// Use this when token refresh fails and user needs to re-authenticate
    func forceLogoutDueToSessionExpiry() async {
        #if DEBUG
        print("[Auth] ⚠️ Force logout due to session expiry")
        #endif

        // Clear Matrix session (with credentials) to ensure fresh login next time
        await MatrixBridgeService.shared.shutdown(clearCredentials: true)

        // Clear local state first
        self.authToken = nil
        self.currentUser = nil
        self.isAuthenticated = false

        // Clear APIClient token
        APIClient.shared.setAuthToken("")

        // Clear Keychain
        keychain.clearAll()

        // Post notification to trigger navigation to login page
        // App.swift listens for this notification
        NotificationCenter.default.post(
            name: NSNotification.Name("SessionExpired"),
            object: nil,
            userInfo: ["reason": "token_refresh_failed"]
        )
    }

    // MARK: - Update Tokens (for account switching)

    /// Update authentication tokens (used when switching accounts)
    /// - Parameters:
    ///   - accessToken: New access token
    ///   - refreshToken: Optional new refresh token
    func updateTokens(accessToken: String, refreshToken: String?) async {
        self.authToken = accessToken
        APIClient.shared.setAuthToken(accessToken)
        _ = keychain.save(accessToken, for: .authToken)

        if let refreshToken = refreshToken {
            _ = keychain.save(refreshToken, for: .refreshToken)
        }

        #if DEBUG
        print("[Auth] Tokens updated for account switch")
        #endif
    }

    // MARK: - Token Refresh

    /// Refresh authentication token
    func refreshToken(refreshToken: String) async throws {
        let response = try await identityService.refreshToken(refreshToken: refreshToken)

        // Update token in Keychain
        self.authToken = response.accessToken
        APIClient.shared.setAuthToken(response.accessToken)
        _ = keychain.save(response.accessToken, for: .authToken)

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
    /// Includes retry logic for network failures to avoid unnecessary logouts
    func attemptTokenRefresh() async -> Bool {
        // If already refreshing, wait for the existing task (MainActor ensures thread safety)
        if let existingTask = refreshTask {
            return await existingTask.value
        }

        guard let storedRefreshToken = keychain.get(.refreshToken) else {
            #if DEBUG
            print("[Auth] ❌ No refresh token available in Keychain!")
            print("[Auth]   This means the session cannot be renewed.")
            print("[Auth]   User needs to login again.")
            #endif
            // No refresh token means we can't renew - force logout
            await forceLogoutDueToSessionExpiry()
            return false
        }

        #if DEBUG
        print("[Auth] 🔄 Attempting token refresh...")
        print("[Auth]   - Refresh token length: \(storedRefreshToken.count) chars")
        #endif

        // Create and store the refresh task
        let task = Task<Bool, Never> { [weak self] in
            guard let self = self else { return false }

            // Retry loop for network failures
            for attempt in 1...self.maxRefreshRetries {
                do {
                    try await self.refreshToken(refreshToken: storedRefreshToken)
                    #if DEBUG
                    print("[Auth] Token refreshed successfully on attempt \(attempt)")
                    #endif
                    return true
                } catch {
                    #if DEBUG
                    print("[Auth] Token refresh attempt \(attempt)/\(self.maxRefreshRetries) failed: \(error)")
                    #endif

                    // Check if it's a network error (worth retrying) vs auth error (don't retry)
                    let isNetworkError = self.isRetryableError(error)

                    if isNetworkError && attempt < self.maxRefreshRetries {
                        // Wait before retrying for network errors
                        try? await Task.sleep(nanoseconds: self.refreshRetryDelaySeconds * 1_000_000_000)
                        continue
                    }

                    // Handle based on error type
                    if self.isAuthenticationError(error) {
                        // Authentication error (401/403) - refresh token is invalid/expired
                        // Force logout and navigate to login page
                        #if DEBUG
                        print("[Auth] Authentication error - forcing logout and navigating to login")
                        #endif
                        await self.forceLogoutDueToSessionExpiry()
                        return false
                    } else {
                        // Network error - keep session, user can retry later
                        #if DEBUG
                        print("[Auth] Network error - keeping session, user can retry later")
                        #endif
                        return false
                    }
                }
            }
            return false
        }

        refreshTask = task

        // Wait for result and clean up
        let result = await task.value
        refreshTask = nil

        return result
    }

    /// Check if the error is retryable (network issues)
    private func isRetryableError(_ error: Error) -> Bool {
        // Use APIError's built-in isRetryable property
        if let apiError = error as? APIError {
            return apiError.isRetryable
        }

        // Network-related URLErrors
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .timedOut,
                 .cannotConnectToHost,
                 .dnsLookupFailed:
                return true
            default:
                return false
            }
        }

        return false
    }

    /// Check if the error is an authentication error (should trigger logout)
    private func isAuthenticationError(_ error: Error) -> Bool {
        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized:
                return true
            case .serverError(let statusCode, _):
                // 401 = Unauthorized, 403 = Forbidden
                return statusCode == 401 || statusCode == 403
            default:
                return false
            }
        }

        return false
    }

    /// Get stored refresh token
    var storedRefreshToken: String? {
        keychain.get(.refreshToken)
    }

    /// Get stored user ID
    var storedUserId: String? {
        keychain.get(.userId)
    }

    // MARK: - Password Reset

    /// Request password reset email
    /// Always succeeds (from user perspective) to prevent email enumeration
    func requestPasswordReset(email: String) async throws {
        try await identityService.requestPasswordReset(email: email)
    }

    /// Reset password using token from email
    func resetPassword(token: String, newPassword: String) async throws {
        try await identityService.resetPassword(resetToken: token, newPassword: newPassword)
    }

    // MARK: - Session Validation

    /// Validate the current session by checking if we have valid credentials
    func validateSession() async -> Bool {
        // Check if we have a stored token
        guard let token = keychain.get(.authToken), !token.isEmpty else {
            print("[Auth] No stored token found")
            return false
        }

        // Set the token in API client if not already set
        if authToken == nil {
            authToken = token
            APIClient.shared.setAuthToken(token)
        }

        // For now, just return true if we have a token
        // In a full implementation, this would call the server to validate
        return isAuthenticated
    }

    // MARK: - Private Helpers

    private func saveAuth(token: String, refreshToken: String?, user: UserProfile) async {
        self.authToken = token
        self.currentUser = user
        self.isAuthenticated = true

        // Set token in APIClient
        APIClient.shared.setAuthToken(token)

        // Save to Keychain (secure storage)
        let tokenSaved = keychain.save(token, for: .authToken)
        let userIdSaved = keychain.save(user.id, for: .userId)

        #if DEBUG
        print("[Auth] 💾 Saving auth to Keychain:")
        print("[Auth]   - Access token saved: \(tokenSaved)")
        print("[Auth]   - User ID saved: \(userIdSaved)")
        #endif

        if let refreshToken = refreshToken {
            let refreshSaved = keychain.save(refreshToken, for: .refreshToken)
            #if DEBUG
            print("[Auth]   - Refresh token saved: \(refreshSaved)")
            print("[Auth]   - Refresh token length: \(refreshToken.count) chars")
            #endif
        } else {
            #if DEBUG
            print("[Auth]   ⚠️ No refresh token provided!")
            #endif
        }
    }
}

