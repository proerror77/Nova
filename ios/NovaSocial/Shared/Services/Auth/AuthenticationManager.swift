import Foundation
import SwiftUI

// MARK: - Authentication Manager

/// Manages user authentication state and token persistence
/// Coordinates with identity-service for login/register operations
@MainActor
class AuthenticationManager: ObservableObject, @unchecked Sendable {
    static let shared = AuthenticationManager()

    @Published var isAuthenticated = false
    @Published var currentUser: UserProfile?
    @Published var authToken: String?

    /// Validated invite code stored after successful validation in InviteCodeView
    /// Used by CreateAccountEmailView for registration
    @Published var validatedInviteCode: String?

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

    // Proactive token refresh configuration
    // Refresh token when it will expire within this time window (6 hours)
    private let proactiveRefreshThreshold: TimeInterval = 6 * 60 * 60

    // Track consecutive refresh failures for graceful degradation
    private var consecutiveRefreshFailures = 0
    private let maxConsecutiveFailuresBeforeLogout = 5

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
            print("[Auth]   ✅ Found saved auth (userId: \(userId.prefix(8))..., hasRefreshToken: \(hasRefreshToken))")
            #endif

            // Load user profile and proactively refresh token if needed
            Task {
                try? await loadCurrentUser(userId: userId)
                // Proactively refresh token if it's about to expire
                await proactivelyRefreshTokenIfNeeded()
            }
        } else {
            #if DEBUG
            print("[Auth]   ℹ️ No saved auth found in Keychain")
            #endif
        }
    }

    // MARK: - Proactive Token Refresh

    /// Proactively refresh token if it will expire soon
    /// This prevents token expiration while the user is actively using the app
    func proactivelyRefreshTokenIfNeeded() async {
        guard isAuthenticated else { return }
        guard let token = authToken else { return }

        // Check if token will expire within the threshold
        if let expirationDate = getTokenExpirationDate(token: token) {
            let timeUntilExpiry = expirationDate.timeIntervalSinceNow

            #if DEBUG
            print("[Auth] 🕐 Token expires in \(String(format: "%.1f", timeUntilExpiry / 3600)) hours")
            #endif

            // If token expires within threshold, refresh proactively
            if timeUntilExpiry < proactiveRefreshThreshold && timeUntilExpiry > 0 {
                #if DEBUG
                print("[Auth] 🔄 Proactively refreshing token (expires in < 6 hours)")
                #endif
                let success = await attemptTokenRefresh()
                if success {
                    consecutiveRefreshFailures = 0
                    #if DEBUG
                    print("[Auth] ✅ Proactive token refresh successful")
                    #endif
                }
            }
        }
    }

    /// Extract expiration date from JWT token payload
    /// - Note: This is for token refresh scheduling only. Server performs authoritative validation.
    ///         Client-side parsing is purely for UX (proactive refresh before expiry).
    /// - Parameter token: The JWT token string
    /// - Returns: The expiration date if successfully parsed, nil otherwise
    private func getTokenExpirationDate(token: String) -> Date? {
        // JWT structure: header.payload.signature (3 parts separated by dots)
        let parts = token.split(separator: ".")
        guard parts.count == 3 else {
            #if DEBUG
            print("[Auth] Invalid JWT structure: expected 3 parts, got \(parts.count)")
            #endif
            return nil
        }

        // Decode the payload (second part) using URL-safe base64
        var payload = String(parts[1])

        // Convert URL-safe base64 to standard base64
        // JWT uses base64url encoding: '-' instead of '+', '_' instead of '/'
        payload = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Add padding if needed for base64 decoding
        let paddingLength = (4 - payload.count % 4) % 4
        payload += String(repeating: "=", count: paddingLength)

        guard let data = Data(base64Encoded: payload) else {
            #if DEBUG
            print("[Auth] Failed to decode JWT payload from base64")
            #endif
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            #if DEBUG
            print("[Auth] Failed to parse JWT payload as JSON")
            #endif
            return nil
        }

        // Extract expiration claim - handle both Int and Double representations
        let exp: TimeInterval
        if let expDouble = json["exp"] as? TimeInterval {
            exp = expDouble
        } else if let expInt = json["exp"] as? Int {
            exp = TimeInterval(expInt)
        } else if let expInt64 = json["exp"] as? Int64 {
            exp = TimeInterval(expInt64)
        } else {
            #if DEBUG
            print("[Auth] JWT payload missing or invalid 'exp' claim")
            #endif
            return nil
        }

        // Sanity check: expiration should be a reasonable Unix timestamp (after year 2020)
        let minValidTimestamp: TimeInterval = 1577836800 // 2020-01-01
        guard exp > minValidTimestamp else {
            #if DEBUG
            print("[Auth] JWT 'exp' claim has invalid timestamp: \(exp)")
            #endif
            return nil
        }

        return Date(timeIntervalSince1970: exp)
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
    func register(username: String, email: String, password: String, displayName: String, inviteCode: String) async throws -> UserProfile {
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

    /// Pending SSO provider type for invite code retry
    enum PendingSSOProvider {
        case google
        case apple
    }

    /// Stores which SSO provider is pending invite code
    private(set) var pendingSSOProvider: PendingSSOProvider?

    /// Clear pending SSO state
    func clearPendingSSOState() {
        pendingSSOProvider = nil
        OAuthService.shared.clearPendingCredentials()
    }

    /// Login with Google OAuth
    /// - Parameter inviteCode: Optional invite code for new user registration
    /// - Returns: User profile on success
    /// - Throws: `OAuthError.inviteCodeRequired` if new user without invite code
    @MainActor
    func loginWithGoogle(inviteCode: String? = nil) async throws -> UserProfile {
        let oauthService = OAuthService.shared

        do {
            // Perform Google Sign-In flow
            let response = try await oauthService.signInWithGoogle(inviteCode: inviteCode)

            // Clear pending state on success
            pendingSSOProvider = nil

            // Create user profile from response
            let user = createUserProfile(from: response)

            // Save authentication
            await saveAuth(token: response.token, refreshToken: response.refreshToken, user: user)

            #if DEBUG
            print("[Auth] Google Sign-In successful, isNewUser: \(response.isNewUser)")
            #endif

            return user
        } catch let error as OAuthError {
            // Store pending provider for invite code retry
            if error.requiresInviteCode {
                pendingSSOProvider = .google
            }
            throw error
        }
    }

    /// Login with Apple Sign-In
    /// - Parameter inviteCode: Optional invite code for new user registration
    /// - Returns: User profile on success
    /// - Throws: `OAuthError.inviteCodeRequired` if new user without invite code
    @MainActor
    func loginWithApple(inviteCode: String? = nil) async throws -> UserProfile {
        let oauthService = OAuthService.shared

        do {
            // Perform Apple Sign-In flow (native)
            let response = try await oauthService.signInWithApple(inviteCode: inviteCode)

            // Clear pending state on success
            pendingSSOProvider = nil

            // Create user profile from response
            let user = createUserProfile(from: response)

            // Save authentication
            await saveAuth(token: response.token, refreshToken: response.refreshToken, user: user)

            #if DEBUG
            print("[Auth] Apple Sign-In successful, isNewUser: \(response.isNewUser)")
            #endif

            return user
        } catch let error as OAuthError {
            // Store pending provider for invite code retry
            if error.requiresInviteCode {
                pendingSSOProvider = .apple
            }
            throw error
        }
    }

    /// Retry SSO login with invite code
    /// - Parameter inviteCode: Invite code for new user registration
    /// - Returns: User profile on success
    @MainActor
    func retrySSOWithInviteCode(_ inviteCode: String) async throws -> UserProfile {
        guard let provider = pendingSSOProvider else {
            throw OAuthError.invalidCallback
        }

        switch provider {
        case .google:
            return try await loginWithGoogle(inviteCode: inviteCode)
        case .apple:
            return try await loginWithApple(inviteCode: inviteCode)
        }
    }

    /// Check if there's a pending SSO that requires invite code
    var hasPendingSSO: Bool {
        pendingSSOProvider != nil
    }

    /// Helper to create UserProfile from OAuth response
    private func createUserProfile(from response: OAuthService.OAuthCallbackResponse) -> UserProfile {
        if let responseUser = response.user {
            return responseUser
        } else {
            // Minimal profile if not provided
            return UserProfile(
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
    }

    /// Login with Passkey authentication
    @available(iOS 16.0, *)
    func handlePasskeyAuthentication(_ response: PasskeyService.CompleteAuthenticationResponse) async throws {
        // Create user profile from response
        let user: UserProfile
        if let responseUser = response.user {
            user = UserProfile(
                id: responseUser.id,
                username: responseUser.username,
                email: responseUser.email,
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
        print("[Auth] Passkey Sign-In successful for user: \(response.userId)")
        #endif
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
    /// Now includes graceful degradation: only logs out after multiple consecutive failures
    func forceLogoutDueToSessionExpiry() async {
        consecutiveRefreshFailures += 1

        #if DEBUG
        print("[Auth] ⚠️ Session expiry detected (failure #\(consecutiveRefreshFailures)/\(maxConsecutiveFailuresBeforeLogout))")
        #endif

        // Graceful degradation: only force logout after multiple consecutive failures
        // This prevents accidental logouts due to temporary network issues
        guard consecutiveRefreshFailures >= maxConsecutiveFailuresBeforeLogout else {
            #if DEBUG
            print("[Auth] 🔄 Not logging out yet - giving user more chances to recover")
            print("[Auth]    Will logout after \(maxConsecutiveFailuresBeforeLogout - consecutiveRefreshFailures) more failures")
            #endif
            return
        }

        #if DEBUG
        print("[Auth] 🚪 Maximum refresh failures reached - forcing logout")
        #endif

        // Reset failure counter
        consecutiveRefreshFailures = 0

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
            userInfo: ["reason": "token_refresh_failed_after_retries"]
        )
    }

    /// Reset the consecutive failure counter (call this after successful API calls)
    func resetRefreshFailureCounter() {
        if consecutiveRefreshFailures > 0 {
            #if DEBUG
            print("[Auth] ✅ Resetting refresh failure counter (was \(consecutiveRefreshFailures))")
            #endif
            consecutiveRefreshFailures = 0
        }
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

    /// Validate the current session with smart token management
    /// - Checks if we have valid credentials
    /// - Proactively refreshes token if needed
    /// - Returns true as long as we have a valid session (even if token is expired but refreshable)
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

        // Check token expiration
        if let expirationDate = getTokenExpirationDate(token: token) {
            let timeUntilExpiry = expirationDate.timeIntervalSinceNow

            #if DEBUG
            print("[Auth] 🔍 Validating session:")
            print("[Auth]   - Token expires in: \(String(format: "%.1f", timeUntilExpiry / 3600)) hours")
            #endif

            // Token already expired
            if timeUntilExpiry <= 0 {
                #if DEBUG
                print("[Auth]   ⚠️ Token expired, attempting refresh...")
                #endif

                // Try to refresh
                if keychain.exists(.refreshToken) {
                    let success = await attemptTokenRefresh()
                    if success {
                        consecutiveRefreshFailures = 0
                        #if DEBUG
                        print("[Auth]   ✅ Token refreshed successfully")
                        #endif
                        return true
                    } else {
                        #if DEBUG
                        print("[Auth]   ❌ Token refresh failed, but keeping session")
                        print("[Auth]      User can try again on next API call")
                        #endif
                        // Don't immediately return false - give user more chances
                        // The next API call will trigger another refresh attempt
                        return isAuthenticated
                    }
                } else {
                    #if DEBUG
                    print("[Auth]   ❌ No refresh token available")
                    #endif
                    // No refresh token, but don't logout immediately
                    // Let the API layer handle it
                    return isAuthenticated
                }
            }

            // Token still valid but will expire soon - proactively refresh
            if timeUntilExpiry < proactiveRefreshThreshold {
                #if DEBUG
                print("[Auth]   🔄 Token expires soon, proactively refreshing...")
                #endif
                await proactivelyRefreshTokenIfNeeded()
            }
        }

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
        print("[Auth] 💾 Saving auth to Keychain (token: \(tokenSaved), userId: \(userIdSaved))")
        #endif

        if let refreshToken = refreshToken {
            let refreshSaved = keychain.save(refreshToken, for: .refreshToken)
            #if DEBUG
            print("[Auth]   - Refresh token saved: \(refreshSaved)")
            #endif
        } else {
            #if DEBUG
            print("[Auth]   ⚠️ No refresh token provided!")
            #endif
        }
    }
}

