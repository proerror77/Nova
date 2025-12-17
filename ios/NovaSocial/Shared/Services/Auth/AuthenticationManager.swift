import Foundation
import SwiftUI

// MARK: - Session State

/// Represents the current session state for debugging and user feedback
enum SessionState: Equatable {
    case active
    case refreshing
    case expired(reason: SessionExpiredReason)
    case loggedOut
    
    var isValid: Bool {
        if case .active = self { return true }
        return false
    }
}

/// Reason for session expiration - helps with debugging and user messaging
enum SessionExpiredReason: String, Equatable {
    case tokenExpired = "Token expired"
    case refreshTokenExpired = "Refresh token expired"
    case refreshFailed = "Token refresh failed"
    case serverRejected = "Server rejected credentials"
    case noRefreshToken = "No refresh token available"
    case userLoggedOut = "User logged out"
    case networkError = "Network error during refresh"
    
    var userMessage: String {
        switch self {
        case .tokenExpired, .refreshTokenExpired, .refreshFailed, .serverRejected:
            return "Your session has expired. Please login again."
        case .noRefreshToken:
            return "Session data missing. Please login again."
        case .userLoggedOut:
            return "You have been logged out."
        case .networkError:
            return "Network error. Please check your connection and try again."
        }
    }
}

// MARK: - Session Expiration Notification
extension Notification.Name {
    /// Posted when session expires and user needs to re-login
    /// userInfo contains: ["reason": SessionExpiredReason]
    static let sessionExpired = Notification.Name("SessionExpired")
}

// MARK: - Authentication Manager

/// Manages user authentication state and token persistence
/// Coordinates with identity-service for login/register operations
@MainActor
class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()

    @Published var isAuthenticated = false
    @Published var currentUser: UserProfile?
    @Published var authToken: String?
    @Published var sessionState: SessionState = .loggedOut
    
    /// Last session expiration reason (for debugging and user feedback)
    @Published var lastExpirationReason: SessionExpiredReason?

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
        print("[Auth] 🔍 Loading saved authentication...")
        
        if let token = keychain.get(.authToken),
           let userId = keychain.get(.userId) {
            print("[Auth] ✅ Found saved token (length: \(token.count)) and userId: \(userId)")
            
            self.authToken = token
            APIClient.shared.setAuthToken(token)
            self.isAuthenticated = true
            self.sessionState = .active

            // Load user profile in background
            Task {
                try? await loadCurrentUser(userId: userId)
            }
        } else {
            print("[Auth] ℹ️ No saved auth found - user needs to login")
            self.sessionState = .loggedOut
        }
        
        // Log refresh token availability
        if keychain.get(.refreshToken) != nil {
            print("[Auth] ✅ Refresh token available")
        } else {
            print("[Auth] ⚠️ No refresh token saved")
        }
    }
    
    /// Validate current session by making a lightweight API call
    /// Call this on app launch/resume to proactively detect expired sessions
    /// Returns true if session is valid, false if expired (will trigger logout)
    func validateSession() async -> Bool {
        print("╔════════════════════════════════════════════════════════════")
        print("║ [Auth] 🔐 VALIDATING SESSION")
        print("║ isAuthenticated: \(isAuthenticated)")
        print("║ hasToken: \(authToken != nil)")
        print("║ hasRefreshToken: \(keychain.get(.refreshToken) != nil)")
        print("╚════════════════════════════════════════════════════════════")
        
        guard isAuthenticated, let userId = keychain.get(.userId) else {
            print("[Auth] ℹ️ Not authenticated, skipping validation")
            return false
        }
        
        sessionState = .refreshing
        
        do {
            // Try to load user profile - this will trigger 401 if token expired
            let user = try await identityService.getUser(userId: userId)
            self.currentUser = user
            self.sessionState = .active
            print("[Auth] ✅ Session validated successfully")
            return true
        } catch {
            print("[Auth] ⚠️ Session validation failed: \(error)")
            
            if let apiError = error as? APIError {
                switch apiError {
                case .unauthorized:
                    // Token expired - try to refresh
                    print("[Auth] 🔄 Token expired, attempting refresh...")
                    let refreshed = await attemptTokenRefresh()
                    if refreshed {
                        print("[Auth] ✅ Token refreshed, session is now valid")
                        return true
                    } else {
                        print("[Auth] ❌ Token refresh failed, session invalid")
                        return false
                    }
                default:
                    // Other errors (network, etc) - keep session, don't logout
                    print("[Auth] 🌐 Non-auth error during validation, keeping session")
                    self.sessionState = .active
                    return true
                }
            }
            
            // Unknown error - keep session
            self.sessionState = .active
            return true
        }
    }

    /// Load current user profile
    private func loadCurrentUser(userId: String) async throws {
        do {
            self.currentUser = try await identityService.getUser(userId: userId)
            print("[Auth] ✅ Loaded user profile: \(currentUser?.displayName ?? "unknown")")
        } catch {
            print("[Auth] ⚠️ Failed to load user profile: \(error)")
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
        print("[Auth] Current user updated: \(user.username)")
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

    /// Logout current user (manual logout by user)
    func logout() async {
        print("[Auth] 🚪 User initiated logout")
        await performLogout(reason: .userLoggedOut, postNotification: false)
    }
    
    /// Handle session expiration (automatic logout due to token issues)
    /// Posts notification to trigger navigation back to login
    func handleSessionExpired(reason: SessionExpiredReason) async {
        print("╔════════════════════════════════════════════════════════════")
        print("║ [Auth] ⚠️ SESSION EXPIRED")
        print("║ Reason: \(reason.rawValue)")
        print("║ User message: \(reason.userMessage)")
        print("╚════════════════════════════════════════════════════════════")
        
        await performLogout(reason: reason, postNotification: true)
    }
    
    /// Internal logout implementation
    private func performLogout(reason: SessionExpiredReason, postNotification: Bool) async {
        // Clear identity service auth
        try? await identityService.logout()

        // Update session state
        self.sessionState = reason == .userLoggedOut ? .loggedOut : .expired(reason: reason)
        self.lastExpirationReason = reason
        
        // Clear local state
        self.authToken = nil
        self.currentUser = nil
        self.isAuthenticated = false

        // Clear APIClient token
        APIClient.shared.setAuthToken("")

        // Clear Keychain
        keychain.clearAll()
        
        print("[Auth] 🧹 Cleared all auth state and tokens")
        
        // Post notification for session expiration (not for manual logout)
        if postNotification {
            print("[Auth] 📢 Posting sessionExpired notification")
            NotificationCenter.default.post(
                name: .sessionExpired,
                object: nil,
                userInfo: ["reason": reason]
            )
        }
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
        let startTime = Date()
        
        print("╔════════════════════════════════════════════════════════════")
        print("║ [Auth] 🔄 TOKEN REFRESH STARTED")
        print("║ Time: \(ISO8601DateFormatter().string(from: startTime))")
        print("║ Current auth state: \(isAuthenticated ? "authenticated" : "not authenticated")")
        print("║ Session state: \(sessionState)")
        print("╚════════════════════════════════════════════════════════════")
        
        // If already refreshing, wait for the existing task (MainActor ensures thread safety)
        if let existingTask = refreshTask {
            print("[Auth] ⏳ Already refreshing, waiting for existing task...")
            sessionState = .refreshing
            return await existingTask.value
        }

        guard let storedRefreshToken = keychain.get(.refreshToken) else {
            print("[Auth] ❌ NO REFRESH TOKEN AVAILABLE - Cannot refresh session")
            print("[Auth] 📍 This usually means:")
            print("[Auth]    1. User never logged in properly")
            print("[Auth]    2. Refresh token was cleared/corrupted")
            print("[Auth]    3. Keychain access issue")
            
            await handleSessionExpired(reason: .noRefreshToken)
            return false
        }
        
        print("[Auth] ✅ Found refresh token (length: \(storedRefreshToken.count) chars)")
        sessionState = .refreshing

        // Create and store the refresh task
        let task = Task<Bool, Never> { [weak self] in
            guard let self = self else { return false }

            // Retry loop for network failures
            for attempt in 1...self.maxRefreshRetries {
                print("[Auth] 🔄 Refresh attempt \(attempt)/\(self.maxRefreshRetries)...")
                
                do {
                    try await self.refreshToken(refreshToken: storedRefreshToken)
                    
                    let duration = Date().timeIntervalSince(startTime)
                    print("╔════════════════════════════════════════════════════════════")
                    print("║ [Auth] ✅ TOKEN REFRESH SUCCESSFUL")
                    print("║ Attempt: \(attempt)/\(self.maxRefreshRetries)")
                    print("║ Duration: \(String(format: "%.2f", duration))s")
                    print("║ New token set: \(self.authToken != nil)")
                    print("╚════════════════════════════════════════════════════════════")
                    
                    self.sessionState = .active
                    return true
                    
                } catch {
                    print("[Auth] ⚠️ Refresh attempt \(attempt) failed:")
                    print("[Auth]    Error: \(error)")
                    print("[Auth]    Error type: \(type(of: error))")
                    
                    if let apiError = error as? APIError {
                        print("[Auth]    APIError case: \(apiError)")
                        print("[Auth]    Is retryable: \(apiError.isRetryable)")
                    }

                    // Check if it's a network error (worth retrying) vs auth error (don't retry)
                    let isNetworkError = self.isRetryableError(error)
                    let isAuthError = self.isAuthenticationError(error)
                    
                    print("[Auth]    Is network error (retryable): \(isNetworkError)")
                    print("[Auth]    Is auth error (fatal): \(isAuthError)")

                    if isNetworkError && attempt < self.maxRefreshRetries {
                        print("[Auth] 🔄 Will retry in \(self.refreshRetryDelaySeconds)s...")
                        try? await Task.sleep(nanoseconds: self.refreshRetryDelaySeconds * 1_000_000_000)
                        continue
                    }

                    // Determine expiration reason
                    let reason: SessionExpiredReason
                    if isAuthError {
                        if let apiError = error as? APIError, case .unauthorized = apiError {
                            reason = .refreshTokenExpired
                        } else {
                            reason = .serverRejected
                        }
                    } else if isNetworkError {
                        reason = .networkError
                    } else {
                        reason = .refreshFailed
                    }
                    
                    print("╔════════════════════════════════════════════════════════════")
                    print("║ [Auth] ❌ TOKEN REFRESH FAILED")
                    print("║ Reason: \(reason.rawValue)")
                    print("║ Will logout: \(isAuthError)")
                    print("╚════════════════════════════════════════════════════════════")

                    // Only logout on authentication errors (401/403), not network failures
                    if isAuthError {
                        await self.handleSessionExpired(reason: reason)
                    } else {
                        // Network error - keep session but mark state
                        print("[Auth] 🌐 Network error - keeping session, user can retry later")
                        self.sessionState = .expired(reason: reason)
                        self.lastExpirationReason = reason
                    }
                    return false
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

