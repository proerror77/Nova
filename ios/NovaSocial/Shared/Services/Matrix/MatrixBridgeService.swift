import Foundation
import Combine

// MARK: - Matrix-Nova Bridge Service
//
// Bridges Nova chat conversations with Matrix rooms
// Handles ID mapping, session management, and message routing
//
// Architecture:
// - Nova Conversation ID <-> Matrix Room ID mapping
// - Nova User ID <-> Matrix User ID mapping
// - Message format conversion between Nova and Matrix

@MainActor
@Observable
final class MatrixBridgeService: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = MatrixBridgeService()

    // MARK: - Dependencies (internal for extension access)

    let matrixService = MatrixService.shared
    let matrixSSOManager = MatrixSSOManager.shared
    let chatService = ChatService()
    let keychain = KeychainService.shared
    let apiClient = APIClient.shared

    /// Feature flag to use SSO login instead of legacy token endpoint
    /// When false, uses the Nova access token to exchange for a Matrix token via backend
    /// When true, uses ASWebAuthenticationSession for SSO (requires user interaction)
    ///
    /// Now using legacy token endpoint because backend has been updated to generate
    /// device-bound tokens via Synapse Admin API (device_id parameter added in Synapse 1.81+)
    /// This provides seamless single sign-on: login once to Nova, Matrix works automatically
    private let useSSOLogin = false

    // MARK: - State

    private(set) var isInitialized = false
    private(set) var isBridgeEnabled = false
    private(set) var initializationError: Error?

    // MARK: - ID Mapping Cache (internal for extension access)

    /// Conversation ID -> Room ID mapping
    var conversationToRoomMap: [String: String] = [:]

    /// Room ID -> Conversation ID mapping (reverse lookup)
    var roomToConversationMap: [String: String] = [:]

    // MARK: - Callbacks

    /// Called when a new message arrives via Matrix
    var onMatrixMessage: ((String, MatrixMessage) -> Void)?  // conversationId, message

    /// Called when typing indicator changes
    var onTypingIndicator: ((String, [String]) -> Void)?  // conversationId, userIds

    /// Called when room list updates
    var onRoomListUpdated: (([MatrixRoom]) -> Void)?

    // MARK: - Cancellables

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        #if DEBUG
        print("[MatrixBridge] Initialized")
        #endif

        setupMessageHandlers()
        observeConnectionState()
    }

    // MARK: - Public API

    /// Initialize the Matrix bridge for the current user
    /// Should be called after Nova login
    /// - Parameter requireLogin: If true, will trigger SSO login if session restore fails.
    ///                          If false, will silently fail without showing SSO dialog.
    ///                          Default is true for backwards compatibility with chat views.
    /// - Parameter retryOnMismatch: If true, will clear session and retry on MismatchedAccount error.
    func initialize(requireLogin: Bool = true, retryOnMismatch: Bool = true) async throws {
        guard !isInitialized else {
            #if DEBUG
            print("[MatrixBridge] ✅ Already initialized, skipping")
            #endif
            return
        }

        #if DEBUG
        print("[MatrixBridge] ═══════════════════════════════════════════")
        print("[MatrixBridge] 🚀 Initializing Matrix Bridge...")
        print("[MatrixBridge]   requireLogin: \(requireLogin)")
        print("[MatrixBridge]   retryOnMismatch: \(retryOnMismatch)")
        print("[MatrixBridge]   useSSOLogin: \(useSSOLogin)")
        print("[MatrixBridge]   homeserver: \(MatrixConfiguration.homeserverURL)")
        #endif

        do {
            // Check if Matrix bridge is enabled for this user
            isBridgeEnabled = await checkBridgeEnabled()
            // Matrix-first mode: treat backend flag as advisory only.
            // We still initialize Matrix locally so Nova chat can be disabled.
            #if DEBUG
            if !isBridgeEnabled {
                print("[MatrixBridge] ⚠️ Backend reported bridge disabled; continuing with Matrix-first initialization")
            }
            #endif

            // Initialize Matrix client
            #if DEBUG
            print("[MatrixBridge] 📱 Initializing Matrix client...")
            #endif
            try await matrixService.initialize(
                homeserverURL: MatrixConfiguration.homeserverURL,
                sessionPath: MatrixConfiguration.sessionPath
            )
            #if DEBUG
            print("[MatrixBridge] ✅ Matrix client initialized")
            #endif

            // Try to restore existing session first
            #if DEBUG
            print("[MatrixBridge] 🔄 Attempting to restore existing session...")
            #endif
            let sessionRestored = try await matrixService.restoreSession()
            #if DEBUG
            print("[MatrixBridge]   Session restored: \(sessionRestored)")
            #endif

            if !sessionRestored {
                // Only trigger login if explicitly required (e.g., user navigated to chat)
                // This prevents SSO dialog from appearing on app startup
                if requireLogin {
                    #if DEBUG
                    print("[MatrixBridge] 🔑 No session found, need to login...")
                    print("[MatrixBridge]   Using SSO: \(useSSOLogin)")
                    #endif
                    // Choose login method based on feature flag
                    if useSSOLogin {
                        // Use SSO login flow (requires user interaction)
                        try await loginWithSSO()
                    } else {
                        // Use backend token exchange (recommended)
                        // Backend now generates device-bound tokens via Synapse Admin API
                        // This provides seamless login without requiring a second SSO prompt
                        #if DEBUG
                        print("[MatrixBridge] 🔑 Using device-bound token from Nova backend...")
                        #endif
                        try await loginWithLegacyToken()
                    }
                } else {
                    #if DEBUG
                    print("[MatrixBridge] ⚠️ Session not restored, but login not required - skipping")
                    #endif
                    // Don't throw error, just don't mark as initialized
                    // User will be prompted to login when they actually use chat
                    return
                }
            }

            // Start sync to receive messages
            #if DEBUG
            print("[MatrixBridge] 🔄 Starting sync...")
            #endif
            try await matrixService.startSync()
            #if DEBUG
            print("[MatrixBridge] ✅ Sync started")
            #endif

            // Load existing conversation mappings
            try await loadConversationMappings()

            isInitialized = true
            initializationError = nil

            // Sync user profile (display name and avatar) to Matrix
            // Run in background with delay to allow token refresh to complete if needed
            Task {
                // Wait for sync to stabilize and potential token refresh
                try? await Task.sleep(nanoseconds: 8_000_000_000) // 8 seconds

                // Verify we're still connected
                guard self.isInitialized && (self.connectionState == .connected || self.connectionState == .syncing) else {
                    #if DEBUG
                    print("[MatrixBridge] ⚠️ Skipping profile sync - not connected")
                    #endif
                    return
                }

                do {
                    try await self.syncProfileToMatrix()
                } catch {
                    #if DEBUG
                    print("[MatrixBridge] ⚠️ Profile sync failed (non-blocking): \(error)")
                    #endif
                }
            }

            #if DEBUG
            print("[MatrixBridge] ═══════════════════════════════════════════")
            print("[MatrixBridge] ✅ Bridge initialized successfully!")
            print("[MatrixBridge] ═══════════════════════════════════════════")
            #endif
        } catch {
            // Check if this is a MismatchedAccount error (device ID mismatch)
            if retryOnMismatch && isMismatchedAccountError(error) {
                #if DEBUG
                print("[MatrixBridge] ⚠️ MismatchedAccount error detected, clearing session and retrying...")
                #endif

                // Clear corrupted session data
                clearSessionData()

                // Retry initialization once without retry flag to prevent infinite loop
                try await initialize(requireLogin: requireLogin, retryOnMismatch: false)
                return
            }

            // Check if this is an expired token error
            if retryOnMismatch && isUnknownTokenError(error) {
                #if DEBUG
                print("[MatrixBridge] ⚠️ Token expired error detected, clearing session and retrying...")
                #endif

                // Clear expired session data
                clearSessionData()

                // Retry initialization once without retry flag to prevent infinite loop
                try await initialize(requireLogin: requireLogin, retryOnMismatch: false)
                return
            }

            initializationError = error
            #if DEBUG
            print("[MatrixBridge] ═══════════════════════════════════════════")
            print("[MatrixBridge] ❌ INITIALIZATION FAILED!")
            print("[MatrixBridge]   Error: \(error)")
            print("[MatrixBridge]   Error type: \(type(of: error))")
            print("[MatrixBridge]   Localized: \(error.localizedDescription)")
            if let matrixError = error as? MatrixError {
                print("[MatrixBridge]   MatrixError: \(matrixError)")
            }
            if let bridgeError = error as? MatrixBridgeError {
                print("[MatrixBridge]   BridgeError: \(bridgeError)")
            }
            if let apiError = error as? APIError {
                print("[MatrixBridge]   APIError: \(apiError)")
            }
            print("[MatrixBridge] ═══════════════════════════════════════════")
            #endif
            throw error
        }
    }

    /// Login to Matrix using SSO flow
    /// This is the preferred method - user authenticates via Zitadel
    private func loginWithSSO() async throws {
        #if DEBUG
        print("[MatrixBridge] 🔐 Starting SSO login flow...")
        #endif

        // Check if we have stored SSO credentials
        if let storedCredentials = matrixSSOManager.loadStoredCredentials() {
            #if DEBUG
            print("[MatrixBridge] ✅ Found stored SSO credentials:")
            print("[MatrixBridge]   - userId: \(storedCredentials.userId)")
            print("[MatrixBridge]   - accessToken length: \(storedCredentials.accessToken.count)")
            print("[MatrixBridge]   Attempting restore...")
            #endif

            // Try to use stored credentials
            do {
                try await matrixService.login(
                    novaUserId: storedCredentials.userId,
                    accessToken: storedCredentials.accessToken
                )
                #if DEBUG
                print("[MatrixBridge] ✅ SSO credentials restore successful")
                #endif
                return
            } catch {
                #if DEBUG
                print("[MatrixBridge] ❌ Stored credentials invalid: \(error)")
                print("[MatrixBridge]   Clearing credentials and initiating new SSO login...")
                #endif
                matrixSSOManager.clearCredentials()
            }
        } else {
            #if DEBUG
            print("[MatrixBridge] ⚠️ No stored SSO credentials found")
            print("[MatrixBridge]   Will initiate new SSO login flow...")
            #endif
        }

        // Perform SSO login
        #if DEBUG
        print("[MatrixBridge] 🌐 Starting SSO web authentication...")
        #endif

        do {
            let result = try await matrixSSOManager.startSSOLogin()

            #if DEBUG
            print("[MatrixBridge] ✅ SSO authentication successful:")
            print("[MatrixBridge]   - userId: \(result.userId)")
            print("[MatrixBridge]   - accessToken length: \(result.accessToken.count)")
            #endif

            // Login to Matrix service with obtained credentials
            try await matrixService.login(
                novaUserId: result.userId,
                accessToken: result.accessToken
            )

            #if DEBUG
            print("[MatrixBridge] ✅ SSO login completed successfully")
            #endif
        } catch {
            #if DEBUG
            print("[MatrixBridge] ❌ SSO login failed: \(error)")
            print("[MatrixBridge]   Error type: \(type(of: error))")
            #endif
            throw error
        }
    }

    /// Login to Matrix using legacy token endpoint
    /// Gets fresh credentials from Nova backend for each login attempt
    private func loginWithLegacyToken() async throws {
        // Get user ID from currentUser or fall back to stored keychain value
        // (currentUser may be nil early in app lifecycle before profile is fetched)
        let userId = AuthenticationManager.shared.currentUser?.id
            ?? AuthenticationManager.shared.storedUserId

        guard let novaUserId = userId else {
            #if DEBUG
            print("[MatrixBridge] ❌ loginWithLegacyToken failed: No user ID (neither currentUser nor storedUserId)")
            #endif
            throw MatrixBridgeError.notAuthenticated
        }

        #if DEBUG
        print("[MatrixBridge] 🔐 loginWithLegacyToken starting...")
        print("[MatrixBridge]   Nova User ID: \(novaUserId)")
        print("[MatrixBridge]   Getting Matrix credentials from Nova backend...")
        #endif

        // Get Matrix credentials from Nova backend
        let credentials: MatrixCredentials
        do {
            credentials = try await getMatrixCredentials(novaUserId: novaUserId)
        } catch {
            #if DEBUG
            print("[MatrixBridge] ❌ Failed to get Matrix credentials: \(error)")
            if let apiError = error as? APIError {
                print("[MatrixBridge]   API Error: \(apiError)")
            }
            #endif
            throw error
        }

        #if DEBUG
        print("[MatrixBridge] ✅ Got Matrix credentials:")
        print("[MatrixBridge]   - Matrix User ID: \(credentials.matrixUserId)")
        print("[MatrixBridge]   - Device ID: \(credentials.deviceId)")
        print("[MatrixBridge]   - Access Token length: \(credentials.accessToken.count) chars")
        print("[MatrixBridge]   - Homeserver: \(credentials.homeserverUrl ?? "default (using \(MatrixConfiguration.homeserverURL))")")
        #endif

        do {
            try await matrixService.login(
                novaUserId: credentials.matrixUserId,
                accessToken: credentials.accessToken,
                deviceId: credentials.deviceId
            )
            #if DEBUG
            print("[MatrixBridge] ✅ matrixService.login() succeeded")
            #endif

            // Store credentials with expiry info
            if let expiresAt = credentials.expiresAt {
                matrixService.storeCredentials(
                    userId: credentials.matrixUserId,
                    accessToken: credentials.accessToken,
                    deviceId: credentials.deviceId,
                    homeserverUrl: credentials.homeserverUrl,
                    expiresAt: expiresAt
                )

                // Start proactive token refresh
                MatrixTokenRefreshManager.shared.startProactiveRefresh(tokenExpiresAt: expiresAt)
            }
        } catch {
            #if DEBUG
            print("[MatrixBridge] ❌ matrixService.login() failed: \(error)")
            #endif
            throw error
        }
    }

    /// Resume Matrix sync after app returns from background
    /// This should be called when:
    /// - App comes back to foreground
    /// - Push notification arrives (to fetch pending messages)
    /// Does not trigger SSO login - only syncs if already authenticated
    func resumeSync() async throws {
        #if DEBUG
        print("[MatrixBridge] 🔄 Resuming sync...")
        #endif

        // If not initialized, try to initialize without requiring login
        // This prevents SSO dialog from appearing when app resumes
        if !isInitialized {
            #if DEBUG
            print("[MatrixBridge] Not initialized, attempting silent initialization...")
            #endif
            do {
                try await initialize(requireLogin: false)
            } catch {
                #if DEBUG
                print("[MatrixBridge] Silent initialization failed: \(error)")
                #endif
                // Don't throw - just skip sync if we can't initialize silently
                return
            }
        }

        // If still not initialized (no stored session), skip
        guard isInitialized else {
            #if DEBUG
            print("[MatrixBridge] ⚠️ Cannot resume sync - no active session")
            #endif
            return
        }

        // Restart sync to fetch any pending messages
        do {
            try await matrixService.startSync()
            #if DEBUG
            print("[MatrixBridge] ✅ Sync resumed successfully")
            #endif
        } catch {
            #if DEBUG
            print("[MatrixBridge] ❌ Failed to resume sync: \(error)")
            #endif
            throw error
        }
    }

    /// Pause Matrix sync when app enters background
    /// This should be called when app enters background to save resources
    func pauseSync() {
        #if DEBUG
        print("[MatrixBridge] ⏸️ Pausing sync...")
        #endif
        matrixService.stopSync()
    }

    /// Shutdown the Matrix bridge
    /// - Parameter clearCredentials: If true, clears stored SSO credentials (for full logout)
    func shutdown(clearCredentials: Bool = false) async {
        #if DEBUG
        print("[MatrixBridge] Shutting down... (clearCredentials: \(clearCredentials))")
        #endif

        // Stop proactive token refresh
        MatrixTokenRefreshManager.shared.stopProactiveRefresh()

        matrixService.stopSync()

        do {
            try await matrixService.logout()
        } catch {
            #if DEBUG
            print("[MatrixBridge] Logout error: \(error)")
            #endif
        }

        // Clear SSO credentials if requested (full logout)
        if clearCredentials {
            matrixSSOManager.clearCredentials()
        }

        conversationToRoomMap.removeAll()
        roomToConversationMap.removeAll()
        isInitialized = false

        #if DEBUG
        print("[MatrixBridge] Shutdown complete")
        #endif
    }

    /// Clear Matrix session data (crypto store) to fix MismatchedAccount errors
    /// This should be called when device ID mismatch occurs
    func clearSessionData() {
        #if DEBUG
        print("[MatrixBridge] Clearing Matrix session data...")
        #endif

        let sessionPath = MatrixConfiguration.sessionPath
        let fileManager = FileManager.default

        // Clear main session path (Documents/matrix_session)
        do {
            if fileManager.fileExists(atPath: sessionPath) {
                try fileManager.removeItem(atPath: sessionPath)
                #if DEBUG
                print("[MatrixBridge] Session data cleared at: \(sessionPath)")
                #endif
            }
        } catch {
            #if DEBUG
            print("[MatrixBridge] Failed to clear session data: \(error)")
            #endif
        }

        // Also clear legacy Application Support paths (from previous incorrect implementation)
        // This ensures we don't have stale data from when reinitializeSession used wrong paths
        if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let legacySessionPath = appSupportURL.appendingPathComponent("matrix_session").path
            let legacyCachePath = appSupportURL.appendingPathComponent("matrix_cache").path

            for path in [legacySessionPath, legacyCachePath] {
                do {
                    if fileManager.fileExists(atPath: path) {
                        try fileManager.removeItem(atPath: path)
                        #if DEBUG
                        print("[MatrixBridge] Legacy data cleared at: \(path)")
                        #endif
                    }
                } catch {
                    #if DEBUG
                    print("[MatrixBridge] Failed to clear legacy data at \(path): \(error)")
                    #endif
                }
            }
        }

        // Also clear SSO credentials to force re-login (includes device ID)
        matrixSSOManager.clearCredentials()

        // Clear MatrixService stored credentials (UserDefaults) to force fresh token fetch
        matrixService.clearCredentials()

        // Reset initialization state so next call to initialize() will re-authenticate
        isInitialized = false

        #if DEBUG
        print("[MatrixBridge] Session data cleared, isInitialized reset to false")
        #endif
    }

    /// Force a full sync by clearing the local session cache and re-initializing.
    /// Use this when rooms are missing from the conversation list due to stale cache.
    /// - Returns: True if the re-initialization was successful
    @discardableResult
    func forceFullSync() async throws -> Bool {
        #if DEBUG
        print("[MatrixBridge] 🔄 Force full sync requested - clearing session cache...")
        #endif

        // Stop current sync
        matrixService.stopSync()

        // Clear the session data to remove stale room cache
        clearSessionData()

        // Re-initialize with fresh sync
        do {
            try await initialize(requireLogin: true, retryOnMismatch: false)

            // Wait for sync to receive initial room list (up to 10 seconds)
            // The room list observer will populate rooms asynchronously after sync starts
            #if DEBUG
            print("[MatrixBridge] ⏳ Waiting for sync to receive rooms...")
            #endif

            var waitTime = 0
            let maxWaitMs = 10000
            let checkIntervalMs = 500

            while waitTime < maxWaitMs {
                let rooms = try await matrixService.getJoinedRooms()
                if !rooms.isEmpty {
                    #if DEBUG
                    print("[MatrixBridge] ✅ Force full sync completed - received \(rooms.count) rooms")
                    #endif
                    return true
                }
                try await Task.sleep(nanoseconds: UInt64(checkIntervalMs) * 1_000_000)
                waitTime += checkIntervalMs
            }

            #if DEBUG
            print("[MatrixBridge] ⚠️ Force full sync timed out waiting for rooms (may still arrive)")
            #endif
            return true
        } catch {
            #if DEBUG
            print("[MatrixBridge] ❌ Force full sync failed: \(error)")
            #endif
            throw error
        }
    }

    /// Check if error is a MismatchedAccount error
    private func isMismatchedAccountError(_ error: Error) -> Bool {
        let errorString = String(describing: error)
        return errorString.contains("MismatchedAccount") ||
               errorString.contains("doesn't match the account")
    }

    /// Check if error is an unknown/expired token error
    private func isUnknownTokenError(_ error: Error) -> Bool {
        let errorString = String(describing: error)
        return errorString.contains("unknownToken") ||
               errorString.contains("M_UNKNOWN_TOKEN") ||
               errorString.contains("Access token has expired")
    }

    /// Check if error is a database corruption error (SQLite constraint violations)
    private func isDatabaseCorruptionError(_ error: Error) -> Bool {
        let errorString = String(describing: error)
        return errorString.contains("FOREIGN KEY constraint failed") ||
               errorString.contains("EventCacheError") ||
               errorString.contains("SqliteFailure") ||
               errorString.contains("ConstraintViolation") ||
               errorString.contains("database disk image is malformed")
    }

    /// Handle Matrix API errors - clears session for recoverable errors
    /// Returns true if the error was handled and the operation should be retried
    func handleMatrixError(_ error: Error) -> Bool {
        if isUnknownTokenError(error) {
            #if DEBUG
            print("[MatrixBridge] ⚠️ Token expired error detected, clearing session for re-authentication...")
            #endif
            clearSessionData()
            return true
        }

        if isDatabaseCorruptionError(error) {
            #if DEBUG
            print("[MatrixBridge] ⚠️ Database corruption detected, clearing session data to recover...")
            #endif
            clearSessionData()
            return true
        }

        return false
    }

    // MARK: - Token Refresh Wrapper

    /// Execute an operation with automatic token refresh on failure
    /// If the operation fails with a token error, attempts to refresh the token and retry once
    /// - Parameter operation: The async operation to execute
    /// - Returns: The result of the operation
    func withTokenRefresh<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            // Check if this is a token error
            if isUnknownTokenError(error) {
                #if DEBUG
                print("[MatrixBridge] 🔄 Token error detected, attempting refresh and retry...")
                #endif

                // Attempt to refresh the token
                let refreshManager = MatrixTokenRefreshManager.shared
                let refreshed = await refreshManager.handleTokenError(error)

                if refreshed {
                    #if DEBUG
                    print("[MatrixBridge] ✅ Token refreshed, retrying operation...")
                    #endif
                    // Retry the operation once
                    return try await operation()
                } else {
                    #if DEBUG
                    print("[MatrixBridge] ❌ Token refresh failed, re-throwing original error")
                    #endif
                }
            }

            throw error
        }
    }

    // MARK: - Profile Sync

    /// Sync the current Nova user's profile (display name and avatar) to Matrix
    /// This should be called after login and whenever the user updates their profile
    /// Includes retry logic for token refresh scenarios
    func syncProfileToMatrix() async throws {
        try await syncProfileToMatrixWithRetry(attempt: 1)
    }

    /// Internal implementation with retry support
    private func syncProfileToMatrixWithRetry(attempt: Int, maxAttempts: Int = 3) async throws {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        guard let currentUser = AuthenticationManager.shared.currentUser else {
            throw MatrixBridgeError.notAuthenticated
        }

        #if DEBUG
        print("[MatrixBridge] 🔄 Syncing profile to Matrix... (attempt \(attempt)/\(maxAttempts))")
        print("[MatrixBridge]   Display name: \(currentUser.displayName ?? currentUser.username)")
        print("[MatrixBridge]   Avatar URL: \(currentUser.avatarUrl ?? "none")")
        #endif

        var displayNameSynced = false
        var avatarSynced = false
        var needsRetry = false

        // Sync display name
        let displayName = currentUser.displayName ?? currentUser.username
        do {
            try await matrixService.setDisplayName(displayName)
            displayNameSynced = true
            #if DEBUG
            print("[MatrixBridge] ✅ Display name synced: \(displayName)")
            #endif
        } catch {
            let errorString = String(describing: error)
            if errorString.contains("M_UNKNOWN_TOKEN") || errorString.contains("expired") || errorString.contains("notInitialized") {
                needsRetry = true
                #if DEBUG
                print("[MatrixBridge] ⚠️ Display name sync failed (token issue), will retry: \(error)")
                #endif
            } else {
                #if DEBUG
                print("[MatrixBridge] ⚠️ Failed to sync display name: \(error)")
                #endif
            }
        }

        // Sync avatar if available
        if let avatarUrlString = currentUser.avatarUrl,
           !avatarUrlString.isEmpty,
           let avatarUrl = URL(string: avatarUrlString) {
            do {
                // Download the avatar image from Nova's storage
                let (data, response) = try await URLSession.shared.data(from: avatarUrl)

                // Determine MIME type from response or URL
                let mimeType: String
                if let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") {
                    mimeType = contentType
                } else if avatarUrlString.lowercased().hasSuffix(".png") {
                    mimeType = "image/png"
                } else if avatarUrlString.lowercased().hasSuffix(".gif") {
                    mimeType = "image/gif"
                } else if avatarUrlString.lowercased().hasSuffix(".webp") {
                    mimeType = "image/webp"
                } else {
                    mimeType = "image/jpeg"
                }

                // Upload to Matrix
                try await matrixService.uploadAvatar(imageData: data, mimeType: mimeType)
                avatarSynced = true

                #if DEBUG
                print("[MatrixBridge] ✅ Avatar synced successfully")
                #endif
            } catch {
                let errorString = String(describing: error)
                if errorString.contains("M_UNKNOWN_TOKEN") || errorString.contains("expired") || errorString.contains("notInitialized") {
                    needsRetry = true
                    #if DEBUG
                    print("[MatrixBridge] ⚠️ Avatar sync failed (token issue), will retry: \(error)")
                    #endif
                } else {
                    #if DEBUG
                    print("[MatrixBridge] ⚠️ Failed to sync avatar: \(error)")
                    #endif
                }
            }
        } else {
            avatarSynced = true // No avatar to sync
            #if DEBUG
            print("[MatrixBridge] ℹ️ No avatar URL to sync")
            #endif
        }

        // Retry if needed and we haven't exceeded max attempts
        if needsRetry && attempt < maxAttempts && (!displayNameSynced || !avatarSynced) {
            #if DEBUG
            print("[MatrixBridge] 🔄 Waiting for token refresh before retry...")
            #endif
            // Wait longer for token refresh and client reinitialization to complete
            try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds

            // Check if we're connected before retrying
            let state = connectionState
            guard state == .connected || state == .syncing else {
                #if DEBUG
                print("[MatrixBridge] ⚠️ Not connected (state: \(state)), skipping retry")
                #endif
                return
            }

            try await syncProfileToMatrixWithRetry(attempt: attempt + 1, maxAttempts: maxAttempts)
            return
        }

        #if DEBUG
        print("[MatrixBridge] ✅ Profile sync complete (displayName: \(displayNameSynced), avatar: \(avatarSynced))")
        #endif
    }

    /// Update just the display name on Matrix
    func updateDisplayName(_ displayName: String) async throws {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        try await matrixService.setDisplayName(displayName)

        #if DEBUG
        print("[MatrixBridge] ✅ Display name updated to: \(displayName)")
        #endif
    }

    /// Update the avatar on Matrix from image data
    func updateAvatar(imageData: Data, mimeType: String) async throws {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        try await matrixService.uploadAvatar(imageData: imageData, mimeType: mimeType)

        #if DEBUG
        print("[MatrixBridge] ✅ Avatar updated")
        #endif
    }

    /// Remove the avatar from Matrix
    func removeMatrixAvatar() async throws {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        try await matrixService.removeAvatar()

        #if DEBUG
        print("[MatrixBridge] ✅ Avatar removed")
        #endif
    }

    // MARK: - Conversation Mapping

    /// Get or create Matrix room for a Nova conversation
    func getRoomId(for conversationId: String) async throws -> String {
        // Check cache first
        if let roomId = conversationToRoomMap[conversationId] {
            return roomId
        }

        // Query backend for existing mapping
        if let roomId = try await queryRoomMapping(conversationId: conversationId) {
            cacheMapping(conversationId: conversationId, roomId: roomId)
            return roomId
        }

        // No existing room - create one
        let conversation = try await chatService.getConversation(conversationId: conversationId)
        let roomId = try await createRoomForConversation(conversation)

        // Store mapping on backend
        try await saveRoomMapping(conversationId: conversationId, roomId: roomId)

        cacheMapping(conversationId: conversationId, roomId: roomId)
        return roomId
    }

    /// Resolve a Matrix room ID from either:
    /// - a Matrix room ID (`!room:server`) in Matrix-first mode, or
    /// - a Nova conversation ID (requires mapping via backend/cache) in Nova-first mode.
    func resolveRoomId(for conversationOrRoomId: String) async throws -> String {
        if conversationOrRoomId.hasPrefix("!") {
            return conversationOrRoomId
        }
        return try await getRoomId(for: conversationOrRoomId)
    }

    /// Get Nova conversation ID for a Matrix room
    func getConversationId(for roomId: String) async throws -> String? {
        // Check cache first
        if let conversationId = roomToConversationMap[roomId] {
            return conversationId
        }

        // Query backend
        if let conversationId = try await queryConversationMapping(roomId: roomId) {
            cacheMapping(conversationId: conversationId, roomId: roomId)
            return conversationId
        }

        return nil
    }

    // MARK: - Message Operations (moved to MatrixBridgeService+Messages.swift)

    // MARK: - Room Operations (moved to MatrixBridgeService+Rooms.swift)

    // MARK: - Private Methods

    private func setupMessageHandlers() {
        // Handle incoming Matrix messages
        matrixService.onMessageReceived = { [weak self] message in
            Task { @MainActor in
                await self?.handleMatrixMessage(message)
            }
        }

        // Handle typing indicators
        matrixService.onTypingIndicator = { [weak self] roomId, userIds in
            Task { @MainActor in
                await self?.handleTypingIndicator(roomId: roomId, userIds: userIds)
            }
        }

        // Handle room updates
        matrixService.onRoomUpdated = { [weak self] room in
            Task { @MainActor in
                self?.handleRoomUpdated(room)
            }
        }
    }

    private func observeConnectionState() {
        matrixService.connectionStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleConnectionStateChange(state)
            }
            .store(in: &cancellables)
    }

    private func handleConnectionStateChange(_ state: MatrixConnectionState) {
        #if DEBUG
        print("[MatrixBridge] Connection state changed: \(state)")
        #endif

        // Could notify UI about connection state changes
    }

    private func handleMatrixMessage(_ message: MatrixMessage) async {
        // Matrix-first: treat roomId as the conversationId if no Nova mapping exists.
        let conversationId = (try? await getConversationId(for: message.roomId)) ?? message.roomId
        onMatrixMessage?(conversationId, message)
    }

    private func handleTypingIndicator(roomId: String, userIds: [String]) async {
        let conversationId = (try? await getConversationId(for: roomId)) ?? roomId

        // Convert Matrix user IDs to Nova user IDs
        let novaUserIds = userIds.compactMap { matrixService.convertToNovaUserId(matrixUserId: $0) }
        onTypingIndicator?(conversationId, novaUserIds)
    }

    private func handleRoomUpdated(_ room: MatrixRoom) {
        // Notify about room list updates
        Task {
            if let rooms = try? await matrixService.getJoinedRooms() {
                onRoomListUpdated?(rooms)
            }
        }
    }

    func cacheMapping(conversationId: String, roomId: String) {
        conversationToRoomMap[conversationId] = roomId
        roomToConversationMap[roomId] = conversationId
    }

    func clearMapping(conversationId: String, roomId: String) {
        conversationToRoomMap.removeValue(forKey: conversationId)
        roomToConversationMap.removeValue(forKey: roomId)
    }

    // MARK: - Backend API Calls (moved to MatrixBridgeService+API.swift)
}

// MARK: - Matrix Bridge Errors

enum MatrixBridgeError: Error, LocalizedError {
    case notInitialized
    case notAuthenticated
    case roomMappingFailed(String)
    case messageSendFailed(String)
    case bridgeDisabled
    case sessionExpired
    case roomNotFound

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Matrix bridge not initialized"
        case .notAuthenticated:
            return "User not authenticated"
        case .roomMappingFailed(let reason):
            return "Room mapping failed: \(reason)"
        case .messageSendFailed(let reason):
            return "Message send failed: \(reason)"
        case .bridgeDisabled:
            return "Matrix bridge is disabled"
        case .sessionExpired:
            return "Session expired. Please try again."
        case .roomNotFound:
            return "Room not found"
        }
    }
}

// MARK: - Message Conversion Helpers

extension MatrixBridgeService {

    /// Convert MatrixMessage to Nova Message format
    func convertToNovaMessage(_ matrixMessage: MatrixMessage, conversationId: String) -> Message {
        // Determine message type
        let chatType: ChatMessageType
        switch matrixMessage.type {
        case .text, .notice, .emote:
            chatType = .text
        case .image:
            chatType = .image
        case .video:
            chatType = .video
        case .audio:
            chatType = .audio
        case .file:
            chatType = .file
        case .location:
            chatType = .location
        }

        // Convert sender ID from Matrix format (@nova-uuid:server) to Nova format (uuid)
        let convertedId = matrixService.convertToNovaUserId(matrixUserId: matrixMessage.senderId)
        let senderId = convertedId ?? matrixMessage.senderId

        #if DEBUG
        let currentUserId = keychain.get(.userId) ?? "unknown"
        print("[MatrixBridge] 📧 Message sender conversion:")
        print("  - Matrix sender: \(matrixMessage.senderId)")
        print("  - Converted ID: \(convertedId ?? "nil")")
        print("  - Final senderId: \(senderId)")
        print("  - Current user: \(currentUserId)")
        print("  - isFromMe: \(senderId == currentUserId)")
        #endif

        return Message(
            id: matrixMessage.id,
            conversationId: conversationId,
            senderId: senderId,
            content: matrixMessage.content,
            type: chatType,
            createdAt: matrixMessage.timestamp,
            status: .delivered,
            mediaUrl: matrixMessage.mediaURL
        )
    }

    /// Convert Nova Message to content for Matrix sending
    func convertToMatrixContent(_ message: Message) -> String {
        // For now, just return the text content
        // Media messages are handled separately via sendMedia
        return message.content
    }
}

// MARK: - Convenience Extensions

extension MatrixBridgeService {

    /// Check if Matrix E2EE is available for messaging
    var isE2EEAvailable: Bool {
        isInitialized && isBridgeEnabled
    }

    /// Get current Matrix connection state
    var connectionState: MatrixConnectionState {
        matrixService.connectionState
    }

    /// Get current Matrix user ID
    var matrixUserId: String? {
        matrixService.userId
    }
}

// MARK: - Matrix Rooms as Conversations

extension MatrixBridgeService {

    /// Data structure representing a conversation from Matrix
    /// This is used by MessageView to display the conversation list
    struct MatrixConversationInfo: Identifiable {
        let id: String              // Matrix room ID
        let displayName: String     // Room name or other user's name for DM
        let lastMessage: String?    // Last message content
        let lastMessageTime: Date?  // Last message timestamp
        let unreadCount: Int        // Unread message count
        let isEncrypted: Bool       // E2EE status
        let isDirect: Bool          // 1:1 vs group
        let avatarURL: String?      // Avatar URL
        let memberCount: Int        // Number of members
        let memberAvatars: [String?]  // Member avatar URLs (for stacked avatars in groups)
        let memberNames: [String]     // Member names (for initials fallback)
    }

    /// Get all Matrix rooms as conversation info for the message list
    /// This is the main entry point for loading conversations via Matrix
    func getConversationsFromMatrix() async throws -> [MatrixConversationInfo] {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        #if DEBUG
        print("[MatrixBridge] 📋 Loading conversations from Matrix rooms...")
        #endif

        let rooms = try await matrixService.getJoinedRooms()

        #if DEBUG
        print("[MatrixBridge] Found \(rooms.count) Matrix rooms")
        #endif

        // Convert MatrixRoom to MatrixConversationInfo (with optional Nova profile enrichment)
        let currentUserId = keychain.get(.userId) ?? AuthenticationManager.shared.currentUser?.id ?? ""

        var conversations: [MatrixConversationInfo] = []
        conversations.reserveCapacity(rooms.count)

        for room in rooms {
            var displayName: String
            var avatarURL: String?

            // Helper function to check if a string looks like a Matrix room ID
            func looksLikeRoomId(_ name: String) -> Bool {
                return name.hasPrefix("!") && name.contains(":")
            }

            // Helper function to check if name looks like a member count fallback (e.g., "2 people", "3 people")
            func looksLikeMemberCountFallback(_ name: String) -> Bool {
                let pattern = #"^\d+\s+people$"#
                return name.range(of: pattern, options: .regularExpression) != nil
            }

            // Helper function to check if name looks like "Conversation {uuid}" (legacy backend format)
            func looksLikeConversationUUID(_ name: String) -> Bool {
                // Pattern: "Conversation " followed by UUID (e.g., "Conversation c76f28f8-3650-422b-adcc-74a00cd68a55")
                let pattern = #"^Conversation\s+[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}(-.*)?$"#
                return name.range(of: pattern, options: .regularExpression) != nil
            }

            // Helper function to check if name looks like "Nova User {uuid-prefix}" (legacy display name format)
            func looksLikeNovaUserUUID(_ name: String) -> Bool {
                // Pattern: "Nova User " followed by hex characters (e.g., "Nova User a291bbb4")
                // Also matches with additional text like "Nova User 5ff89416, testmatrix"
                let pattern = #"^Nova User\s+[0-9a-fA-F]{6,}"#
                return name.range(of: pattern, options: .regularExpression) != nil
            }

            // Helper function to check if name looks like Matrix localpart format "nova-{username}"
            func looksLikeMatrixLocalpart(_ name: String) -> Bool {
                // Pattern: "nova-" prefix (e.g., "nova-timmikins747")
                return name.hasPrefix("nova-")
            }

            // Treat as direct message if explicitly marked OR if it has exactly 2 members
            // (isDirect flag may not be synced correctly after logout/login, see findExistingDirectRoom)
            let isLikelyDirect = room.isDirect || room.memberCount == 2

            if isLikelyDirect {
                let initialName = room.name ?? ""
                displayName = initialName.isEmpty ? "Direct Message" : initialName
                avatarURL = room.avatarURL

                // Check if we need to enrich the display name or avatar
                // - Empty/default name
                // - Looks like a Matrix room ID
                // - Looks like a member count fallback (e.g., "2 people")
                // - Looks like legacy "Conversation {uuid}" format from backend
                // - Looks like legacy "Nova User {uuid-prefix}" format
                // - Looks like Matrix localpart format "nova-{username}"
                // - Avatar URL is missing (common for DMs where room avatar isn't set)
                let needsNameEnrichment = displayName == "Direct Message" ||
                                          looksLikeRoomId(displayName) ||
                                          looksLikeMemberCountFallback(displayName) ||
                                          looksLikeConversationUUID(displayName) ||
                                          looksLikeNovaUserUUID(displayName) ||
                                          looksLikeMatrixLocalpart(displayName)
                let needsAvatarEnrichment = avatarURL == nil || avatarURL?.isEmpty == true
                let needsEnrichment = needsNameEnrichment || needsAvatarEnrichment

                // Try to enrich from Nova conversation + identity profiles.
                // This fixes cases where Matrix room display names/avatars are not yet configured.
                if needsEnrichment {
                    #if DEBUG
                    print("[MatrixBridge] 🔄 Enriching DM: \(room.id), initial name: '\(displayName)', needsName: \(needsNameEnrichment), needsAvatar: \(needsAvatarEnrichment)")
                    #endif
                    if let novaConversationId = try? await queryConversationMapping(roomId: room.id),
                       let conversation = try? await chatService.getConversation(conversationId: novaConversationId) {
                        // Try conversation name first
                        if let name = conversation.name, !name.isEmpty, !looksLikeRoomId(name) {
                            displayName = name
                        }
                        // Fall back to other user's username
                        else if let other = conversation.members.first(where: { $0.userId != currentUserId }),
                                  !other.username.isEmpty {
                            displayName = other.username
                        }

                        // Get avatar from conversation
                        if let convAvatar = conversation.avatarUrl, !convAvatar.isEmpty {
                            avatarURL = convAvatar
                        }
                    }

                    // If still showing room ID, member count fallback, "Conversation {uuid}", or avatar still missing, try to get other user from Matrix room members
                    let stillNeedsNameEnrichment = looksLikeRoomId(displayName) || looksLikeMemberCountFallback(displayName) || looksLikeConversationUUID(displayName)
                    let stillNeedsAvatarEnrichment = avatarURL == nil || avatarURL?.isEmpty == true
                    if stillNeedsNameEnrichment || stillNeedsAvatarEnrichment {
                        #if DEBUG
                        print("[MatrixBridge]   📋 Trying Matrix room members for: \(room.id)")
                        #endif
                        // Try to get the other user directly from Matrix room members
                        do {
                            let members = try await matrixService.getRoomMembers(roomId: room.id)
                            #if DEBUG
                            print("[MatrixBridge]   📋 Got \(members.count) members")
                            #endif
                            // Find the other member (not current user)
                            if let otherMember = members.first(where: { member in
                                // Check if this is not the current user
                                if let novaId = matrixService.convertToNovaUserId(matrixUserId: member.userId) {
                                    return novaId != currentUserId
                                }
                                return !member.userId.contains(currentUserId)
                            }) {
                                #if DEBUG
                                print("[MatrixBridge]   👤 Found other member: \(otherMember.userId), displayName: \(otherMember.displayName ?? "nil"), avatar: \(otherMember.avatarUrl ?? "nil")")
                                #endif
                                // Use their display name if available
                                if let memberDisplayName = otherMember.displayName, !memberDisplayName.isEmpty {
                                    if stillNeedsNameEnrichment {
                                        displayName = memberDisplayName
                                    }
                                    if stillNeedsAvatarEnrichment {
                                        if let memberAvatarUrl = otherMember.avatarUrl, !memberAvatarUrl.isEmpty {
                                            avatarURL = memberAvatarUrl
                                        } else {
                                            // Member has displayName but no avatar - try to get avatar from UserService
                                            if let novaUserId = matrixService.convertToNovaUserId(matrixUserId: otherMember.userId) {
                                                #if DEBUG
                                                print("[MatrixBridge]   🔍 Looking up avatar for: \(novaUserId)")
                                                #endif
                                                if let userProfile = try? await UserService.shared.getUser(userId: novaUserId) {
                                                    avatarURL = userProfile.avatarUrl
                                                    #if DEBUG
                                                    print("[MatrixBridge]   ✅ Got avatar from UserService: \(avatarURL ?? "nil")")
                                                    #endif
                                                }
                                            }
                                        }
                                    }
                                } else {
                                    // Matrix member has no displayName, try to look up via Nova UserService
                                    // But only update displayName if we actually need name enrichment
                                    if let novaUserId = matrixService.convertToNovaUserId(matrixUserId: otherMember.userId) {
                                        #if DEBUG
                                        print("[MatrixBridge]   🔍 Looking up user profile for: \(novaUserId)")
                                        #endif
                                        do {
                                            let userProfile = try await UserService.shared.getUser(userId: novaUserId)
                                            if stillNeedsNameEnrichment {
                                                displayName = userProfile.displayName ?? userProfile.username
                                            }
                                            if stillNeedsAvatarEnrichment, let profileAvatar = userProfile.avatarUrl, !profileAvatar.isEmpty {
                                                avatarURL = profileAvatar
                                            }
                                            #if DEBUG
                                            print("[MatrixBridge]   ✅ Found user: \(userProfile.displayName ?? userProfile.username)")
                                            #endif
                                        } catch {
                                            #if DEBUG
                                            print("[MatrixBridge]   ⚠️ UserService lookup failed for \(novaUserId): \(error)")
                                            #endif
                                            // UserService lookup failed - only update name if we need it
                                            if stillNeedsNameEnrichment {
                                                if novaUserId.count == 36 && novaUserId.contains("-") {
                                                    // UUID - use generic fallback
                                                    displayName = "Chat"
                                                } else {
                                                    // It's a username - show it directly
                                                    displayName = novaUserId
                                                }
                                            }
                                        }
                                    } else if stillNeedsNameEnrichment {
                                        // Can't convert to Nova user ID, extract from Matrix ID
                                        // Only do this if we need name enrichment
                                        let matrixId = otherMember.userId
                                        if matrixId.hasPrefix("@") {
                                            let withoutAt = String(matrixId.dropFirst())
                                            if let colonIdx = withoutAt.firstIndex(of: ":") {
                                                let localpart = String(withoutAt.prefix(upTo: colonIdx))
                                                // Remove "nova-" prefix if present
                                                if localpart.hasPrefix("nova-") {
                                                    let identifier = String(localpart.dropFirst(5))
                                                    // Check if it's a UUID (36 chars with hyphens)
                                                    if identifier.count == 36 && identifier.contains("-") {
                                                        displayName = "Chat"  // Generic fallback
                                                    } else {
                                                        // It's a username - show it
                                                        displayName = identifier
                                                    }
                                                } else {
                                                    displayName = localpart
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        } catch {
                            #if DEBUG
                            print("[MatrixBridge]   ⚠️ Failed to get room members for DM enrichment: \(error)")
                            #endif
                        }
                    }

                    // Fallback: Try to use lastMessage sender for DM display name
                    if looksLikeRoomId(displayName) || looksLikeMemberCountFallback(displayName) || looksLikeConversationUUID(displayName) || looksLikeNovaUserUUID(displayName) || looksLikeMatrixLocalpart(displayName) {
                        #if DEBUG
                        print("[MatrixBridge]   📨 Trying lastMessage sender fallback")
                        #endif
                        if let lastMsg = room.lastMessage {
                            let senderId = lastMsg.senderId
                            // Convert to Nova ID for comparison (senderId is Matrix format, currentUserId is Nova format)
                            let senderNovaId = matrixService.convertToNovaUserId(matrixUserId: senderId)
                            let isOtherUser = (senderNovaId == nil || senderNovaId != currentUserId) && !senderId.contains(currentUserId)
                            #if DEBUG
                            print("[MatrixBridge]   📨 lastMessage sender: \(senderId), isOtherUser: \(isOtherUser)")
                            #endif

                            // Only use sender info if it's the other user (not current user)
                            if isOtherUser {
                                // Try to convert Matrix sender ID to Nova user ID and look up
                                if let novaUserId = senderNovaId {
                                    if let userProfile = try? await UserService.shared.getUser(userId: novaUserId) {
                                        displayName = userProfile.displayName ?? userProfile.username
                                        if avatarURL == nil || avatarURL?.isEmpty == true {
                                            avatarURL = userProfile.avatarUrl
                                        }
                                    } else {
                                        // UserService failed - check if UUID or username
                                        if novaUserId.count == 36 && novaUserId.contains("-") {
                                            // UUID - use generic fallback
                                            displayName = "Chat"
                                        } else {
                                            // Username - show it directly
                                            displayName = novaUserId
                                        }
                                    }
                                } else if senderId.hasPrefix("@") {
                                    // Extract username from Matrix ID
                                    let withoutAt = String(senderId.dropFirst())
                                    if let colonIdx = withoutAt.firstIndex(of: ":") {
                                        let localpart = String(withoutAt.prefix(upTo: colonIdx))
                                        if localpart.hasPrefix("nova-") {
                                            let identifier = String(localpart.dropFirst(5))
                                            // Check if it's a UUID (36 chars with hyphens)
                                            if identifier.count == 36 && identifier.contains("-") {
                                                // UUID - use generic fallback
                                                displayName = "Chat"
                                            } else {
                                                // Username - show it
                                                displayName = identifier
                                            }
                                        } else {
                                            displayName = localpart
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Final cleanup - handle ugly display names
                    if looksLikeRoomId(displayName) || looksLikeMemberCountFallback(displayName) || looksLikeConversationUUID(displayName) || looksLikeNovaUserUUID(displayName) {
                        // These are unrecoverable - show generic fallback
                        displayName = "Chat"
                    } else if looksLikeMatrixLocalpart(displayName) {
                        // Strip "nova-" prefix and show just the username
                        let identifier = String(displayName.dropFirst(5))
                        // Check if it's a UUID (36 chars with hyphens) - if so, show generic
                        if identifier.count == 36 && identifier.contains("-") {
                            displayName = "Chat"
                        } else {
                            displayName = identifier
                        }
                    }
                }
            } else {
                displayName = room.name ?? "Group Chat"
                avatarURL = room.avatarURL

                // For group chats, also check if name looks like room ID
                if looksLikeRoomId(displayName) {
                    displayName = "Group Chat"
                }
            }

            // Fetch member avatars for group chats (for stacked avatar display)
            var memberAvatars: [String?] = []
            var memberNames: [String] = []

            if !isLikelyDirect {
                // For groups, fetch first 3 members (excluding current user) for stacked avatars
                do {
                    let members = try await matrixService.getRoomMembers(roomId: room.id)
                    let otherMembers = members.filter { $0.userId != currentUserId }.prefix(3)
                    for member in otherMembers {
                        memberAvatars.append(member.avatarUrl)
                        memberNames.append(member.displayName ?? member.userId)
                    }
                } catch {
                    #if DEBUG
                    print("[MatrixBridge]   ⚠️ Failed to get members for stacked avatars in room \(room.id): \(error)")
                    #endif
                }
            }

            conversations.append(
                MatrixConversationInfo(
                    id: room.id,
                    displayName: displayName,
                    lastMessage: room.lastMessage?.content,
                    lastMessageTime: room.lastActivity,
                    unreadCount: room.unreadCount,
                    isEncrypted: room.isEncrypted,
                    isDirect: isLikelyDirect,  // Use corrected detection, not just room.isDirect
                    avatarURL: avatarURL,
                    memberCount: room.memberCount,
                    memberAvatars: memberAvatars,
                    memberNames: memberNames
                )
            )
        }

        // Sort by last activity (most recent first)
        let sorted = conversations.sorted { conv1, conv2 in
            guard let time1 = conv1.lastMessageTime else { return false }
            guard let time2 = conv2.lastMessageTime else { return true }
            return time1 > time2
        }

        #if DEBUG
        print("[MatrixBridge] ✅ Returning \(sorted.count) conversations")
        #endif

        return sorted
    }

    /// Find an existing direct room with a specific user
    /// - Parameter userId: The Matrix user ID to search for
    /// - Returns: The existing conversation info if found, nil otherwise
    /// - Note: This function checks ALL rooms with 2 members, not just those marked as isDirect,
    ///         because the m.direct account data may not be synced after logout/login.
    func findExistingDirectRoom(withUserId userId: String) async throws -> MatrixConversationInfo? {
        // Convert userId to Matrix format for comparison
        let matrixUserId = matrixService.convertToMatrixUserId(novaUserId: userId)
        let currentUserId = matrixService.userId

        #if DEBUG
        print("[MatrixBridge] 🔍 Searching for existing DM with: \(userId) (Matrix ID: \(matrixUserId))")
        print("[MatrixBridge]   Current user: \(currentUserId ?? "nil")")
        #endif

        // CRITICAL: Wait for sync to be ready before checking rooms
        // This prevents duplicate room creation when sync hasn't completed yet
        let syncReady = await matrixService.waitForSyncReady(timeout: 5)
        #if DEBUG
        print("[MatrixBridge]   Sync ready: \(syncReady)")
        #endif

        // Get all rooms from Matrix
        let rooms = try await matrixService.getJoinedRooms()

        #if DEBUG
        print("[MatrixBridge]   Total rooms to check: \(rooms.count)")
        #endif

        // Check ALL rooms that could be DMs (not just isDirect, as that flag may not be synced)
        // A DM is a room with exactly 2 members: current user and target user
        for room in rooms {
            // Skip rooms with more than 2 members (definitely not a DM)
            // But check rooms with 1-2 members as they could be DMs
            if room.memberCount > 2 {
                continue
            }

            // Get members of this room
            do {
                let members = try await matrixService.getRoomMembers(roomId: room.id)
                let memberIds = members.map { $0.userId }

                #if DEBUG
                print("[MatrixBridge]   Checking room \(room.id) (isDirect=\(room.isDirect), members=\(memberIds.count)): \(memberIds)")
                #endif

                // For a DM, we need:
                // 1. The target user to be in the room
                // 2. Either exactly 2 members (normal DM) or the room is marked as isDirect
                let hasTargetUser = memberIds.contains(matrixUserId)
                let hasTwoMembers = memberIds.count == 2
                let isLikelyDM = hasTargetUser && (hasTwoMembers || room.isDirect)

                if isLikelyDM {
                    #if DEBUG
                    print("[MatrixBridge]   ✅ Found existing DM room: \(room.id)")
                    #endif

                    // Return the existing room as conversation info
                    return MatrixConversationInfo(
                        id: room.id,
                        displayName: room.name ?? "Direct Message",
                        lastMessage: room.lastMessage?.content,
                        lastMessageTime: room.lastActivity,
                        unreadCount: room.unreadCount,
                        isEncrypted: room.isEncrypted,
                        isDirect: true,
                        avatarURL: room.avatarURL,
                        memberCount: room.memberCount,
                        memberAvatars: [],
                        memberNames: []
                    )
                }
            } catch {
                #if DEBUG
                print("[MatrixBridge]   ⚠️ Failed to get members for room \(room.id): \(error)")
                #endif

                // Fallback: If this is a direct room with 1-2 members, try to match by other criteria
                // This handles E2EE rooms where member retrieval might fail
                if room.isDirect && room.memberCount <= 2 {
                    #if DEBUG
                    print("[MatrixBridge]   🔄 Trying fallback match for isDirect room with memberCount=\(room.memberCount)")
                    #endif

                    // Check if the room name contains the target user's ID or display name
                    // Matrix room names for DMs often contain the other user's info
                    let roomName = room.name?.lowercased() ?? ""
                    let targetIdPart = userId.lowercased().prefix(8)  // First 8 chars of UUID

                    // Also extract the localpart from the Matrix user ID for matching
                    // @nova-{uuid}:server -> nova-{uuid}
                    let matrixLocalpart = matrixUserId
                        .replacingOccurrences(of: "@", with: "")
                        .components(separatedBy: ":").first?.lowercased() ?? ""

                    if roomName.contains(String(targetIdPart)) || roomName.contains(matrixLocalpart) {
                        #if DEBUG
                        print("[MatrixBridge]   ✅ Fallback match found! Room name '\(room.name ?? "")' matches target user")
                        #endif

                        return MatrixConversationInfo(
                            id: room.id,
                            displayName: room.name ?? "Direct Message",
                            lastMessage: room.lastMessage?.content,
                            lastMessageTime: room.lastActivity,
                            unreadCount: room.unreadCount,
                            isEncrypted: room.isEncrypted,
                            isDirect: true,
                            avatarURL: room.avatarURL,
                            memberCount: room.memberCount,
                            memberAvatars: [],
                            memberNames: []
                        )
                    }
                }
                continue
            }
        }

        // Final fallback: Check if any isDirect room has a Nova conversation mapping
        // that includes the target user
        #if DEBUG
        print("[MatrixBridge] 🔄 Final fallback: checking Nova conversation mappings for target user")
        #endif

        for room in rooms {
            // Only check rooms that are marked as direct and have small member count
            guard room.isDirect && room.memberCount <= 2 else { continue }

            // Check if there's a Nova conversation mapped to this room
            if let conversationId = try? await queryConversationMapping(roomId: room.id) {
                // Get the Nova conversation to check participants
                if let conversation = try? await chatService.getConversation(conversationId: conversationId) {
                    // Check if the target user is a participant in this conversation
                    // Note: participants is already [String] of user IDs
                    if conversation.participants.contains(userId) {
                        #if DEBUG
                        print("[MatrixBridge] ✅ Final fallback found! Room \(room.id) has conversation with participant \(userId)")
                        #endif

                        return MatrixConversationInfo(
                            id: room.id,
                            displayName: room.name ?? conversation.name ?? "Direct Message",
                            lastMessage: room.lastMessage?.content,
                            lastMessageTime: room.lastActivity,
                            unreadCount: room.unreadCount,
                            isEncrypted: room.isEncrypted,
                            isDirect: true,
                            avatarURL: room.avatarURL,
                            memberCount: room.memberCount,
                            memberAvatars: [],
                            memberNames: []
                        )
                    }
                }
            }
        }

        #if DEBUG
        print("[MatrixBridge] 🔍 No existing DM found with user: \(userId)")
        #endif

        return nil
    }

    /// Create a new direct conversation with a user via Matrix
    /// This creates a Matrix room and returns the conversation info
    /// - Parameters:
    ///   - userId: The user ID to chat with (Matrix user ID)
    ///   - displayName: Display name for the conversation
    ///   - isPrivate: Whether this is a private (E2EE encrypted) chat. Default is false (plain text)
    func createDirectConversation(withUserId userId: String, displayName: String?, isPrivate: Bool = false) async throws -> MatrixConversationInfo {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        #if DEBUG
        print("[MatrixBridge] Looking for existing DM room with user: \(userId)")
        #endif

        // First, check if we already have a DM room with this user
        if let existingRoom = try await findExistingDirectRoom(withUserId: userId) {
            #if DEBUG
            print("[MatrixBridge] ✅ Found existing DM room: \(existingRoom.id)")
            #endif
            return existingRoom
        }

        #if DEBUG
        print("[MatrixBridge] No existing DM found, creating \(isPrivate ? "private" : "regular") direct conversation with user: \(userId)")
        #endif

        // Create a direct room in Matrix
        let roomId: String
        do {
            roomId = try await matrixService.createRoom(
                name: nil,  // Direct rooms don't need names
                isDirect: true,
                inviteUserIds: [userId],
                isEncrypted: isPrivate  // Use E2EE only for private chats
            )
        } catch {
            // Handle token expiration by clearing session and throwing sessionExpired
            // The UI should catch this and prompt user to retry (which will reinitialize)
            if isUnknownTokenError(error) {
                #if DEBUG
                print("[MatrixBridge] ⚠️ Token expired during room creation, clearing session...")
                #endif

                // Clear session data so next initialization will get fresh credentials
                clearSessionData()

                // Throw sessionExpired to let UI handle retry
                throw MatrixBridgeError.sessionExpired
            }
            throw error
        }

        #if DEBUG
        print("[MatrixBridge] Created \(isPrivate ? "private" : "regular") Matrix room: \(roomId)")
        #endif

        return MatrixConversationInfo(
            id: roomId,
            displayName: displayName ?? "Direct Message",
            lastMessage: nil,
            lastMessageTime: Date(),
            unreadCount: 0,
            isEncrypted: isPrivate,
            isDirect: true,
            avatarURL: nil,
            memberCount: 2,
            memberAvatars: [],
            memberNames: []
        )
    }

    /// Create a new group conversation via Matrix
    /// - Parameters:
    ///   - name: The group name
    ///   - userIds: User IDs to invite to the group
    ///   - isPrivate: Whether this is a private (E2EE encrypted) group. Default is false (plain text)
    func createGroupConversation(name: String, userIds: [String], isPrivate: Bool = false) async throws -> MatrixConversationInfo {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        #if DEBUG
        print("[MatrixBridge] Creating \(isPrivate ? "private" : "regular") group conversation: \(name) with \(userIds.count) users")
        #endif

        let roomId: String
        do {
            roomId = try await matrixService.createRoom(
                name: name,
                isDirect: false,
                inviteUserIds: userIds,
                isEncrypted: isPrivate  // Use E2EE only for private groups
            )
        } catch {
            // Handle token expiration by clearing session and throwing sessionExpired
            if isUnknownTokenError(error) {
                #if DEBUG
                print("[MatrixBridge] ⚠️ Token expired during group room creation, clearing session...")
                #endif

                // Clear session data so next initialization will get fresh credentials
                clearSessionData()

                // Throw sessionExpired to let UI handle retry
                throw MatrixBridgeError.sessionExpired
            }
            throw error
        }

        return MatrixConversationInfo(
            id: roomId,
            displayName: name,
            lastMessage: nil,
            lastMessageTime: Date(),
            unreadCount: 0,
            isEncrypted: isPrivate,
            isDirect: false,
            avatarURL: nil,
            memberCount: userIds.count + 1,  // Including current user
            memberAvatars: [],  // Will be populated on next refresh
            memberNames: []
        )
    }
}
