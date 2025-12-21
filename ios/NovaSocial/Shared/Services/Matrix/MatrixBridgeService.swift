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
final class MatrixBridgeService {

    // MARK: - Singleton

    static let shared = MatrixBridgeService()

    // MARK: - Dependencies

    private let matrixService = MatrixService.shared
    private let matrixSSOManager = MatrixSSOManager.shared
    private let chatService = ChatService()
    private let keychain = KeychainService.shared
    private let apiClient = APIClient.shared

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

    // MARK: - ID Mapping Cache

    /// Conversation ID -> Room ID mapping
    private var conversationToRoomMap: [String: String] = [:]

    /// Room ID -> Conversation ID mapping (reverse lookup)
    private var roomToConversationMap: [String: String] = [:]

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
        guard let currentUser = AuthenticationManager.shared.currentUser else {
            #if DEBUG
            print("[MatrixBridge] ❌ loginWithLegacyToken failed: No current user")
            #endif
            throw MatrixBridgeError.notAuthenticated
        }

        #if DEBUG
        print("[MatrixBridge] 🔐 loginWithLegacyToken starting...")
        print("[MatrixBridge]   Nova User ID: \(currentUser.id)")
        print("[MatrixBridge]   Getting Matrix credentials from Nova backend...")
        #endif

        // Get Matrix credentials from Nova backend
        let credentials: MatrixCredentials
        do {
            credentials = try await getMatrixCredentials(novaUserId: currentUser.id)
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
        } catch {
            #if DEBUG
            print("[MatrixBridge] ❌ matrixService.login() failed: \(error)")
            #endif
            throw error
        }
    }

    /// Shutdown the Matrix bridge
    /// - Parameter clearCredentials: If true, clears stored SSO credentials (for full logout)
    func shutdown(clearCredentials: Bool = false) async {
        #if DEBUG
        print("[MatrixBridge] Shutting down... (clearCredentials: \(clearCredentials))")
        #endif

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

        // Also clear SSO credentials to force re-login
        matrixSSOManager.clearCredentials()

        // Clear MatrixService stored credentials (UserDefaults) to force fresh token fetch
        matrixService.clearCredentials()

        // Reset initialization state so next call to initialize() will re-authenticate
        isInitialized = false

        #if DEBUG
        print("[MatrixBridge] Session data cleared, isInitialized reset to false")
        #endif
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

    /// Handle Matrix API errors - clears session for token errors
    /// Returns true if the error was handled and the operation should be retried
    func handleMatrixError(_ error: Error) -> Bool {
        if isUnknownTokenError(error) {
            #if DEBUG
            print("[MatrixBridge] ⚠️ Token expired error detected, clearing session for re-authentication...")
            #endif
            clearSessionData()
            return true
        }
        return false
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
    private func resolveRoomId(for conversationOrRoomId: String) async throws -> String {
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

    // MARK: - Message Operations

    /// Send message via Matrix (E2EE)
    func sendMessage(
        conversationId: String,
        content: String,
        mediaURL: URL? = nil,
        mimeType: String? = nil
    ) async throws -> String {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let roomId = try await resolveRoomId(for: conversationId)

        let eventId: String
        if let mediaURL = mediaURL, let mimeType = mimeType {
            eventId = try await matrixService.sendMedia(
                roomId: roomId,
                mediaURL: mediaURL,
                mimeType: mimeType,
                caption: content.isEmpty ? nil : content
            )
        } else {
            eventId = try await matrixService.sendMessage(
                roomId: roomId,
                content: content
            )
        }

        #if DEBUG
        print("[MatrixBridge] Sent message \(eventId) to room \(roomId)")
        #endif

        return eventId
    }

    /// Send location via Matrix (E2EE)
    func sendLocation(
        conversationId: String,
        latitude: Double,
        longitude: Double,
        description: String? = nil
    ) async throws -> String {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        // TODO: Implement location sharing via Matrix
        // For now, send as a text message with location coordinates
        let locationText = description ?? "Location: \(latitude), \(longitude)"
        return try await sendMessage(conversationId: conversationId, content: locationText)
    }

    /// Get messages for a conversation via Matrix
    func getMessages(
        conversationId: String,
        limit: Int = 50,
        from: String? = nil
    ) async throws -> [MatrixMessage] {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let roomId = try await resolveRoomId(for: conversationId)
        try await matrixService.subscribeToRoomTimeline(roomId: roomId)
        return try await matrixService.getRoomMessages(roomId: roomId, limit: limit, from: from)
    }

    func stopListening(conversationId: String) async {
        guard isInitialized else { return }
        guard let roomId = try? await resolveRoomId(for: conversationId) else { return }
        matrixService.unsubscribeFromRoomTimeline(roomId: roomId)
    }

    /// Set typing indicator for a conversation
    func setTyping(conversationId: String, isTyping: Bool) async throws {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let roomId = try await resolveRoomId(for: conversationId)
        try await matrixService.setTyping(roomId: roomId, isTyping: isTyping)
    }

    /// Mark conversation as read
    func markAsRead(conversationId: String) async throws {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let roomId = try await resolveRoomId(for: conversationId)
        try await matrixService.markRoomAsRead(roomId: roomId)
    }

    // MARK: - Message Edit/Delete/Reactions

    /// Edit a message in a conversation
    func editMessage(conversationId: String, messageId: String, newContent: String) async throws {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let roomId = try await resolveRoomId(for: conversationId)
        try await matrixService.editMessage(roomId: roomId, eventId: messageId, newContent: newContent)

        #if DEBUG
        print("[MatrixBridge] Edited message \(messageId) in conversation \(conversationId)")
        #endif
    }

    /// Delete/redact a message in a conversation
    func deleteMessage(conversationId: String, messageId: String, reason: String? = nil) async throws {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let roomId = try await resolveRoomId(for: conversationId)
        try await matrixService.redactMessage(roomId: roomId, eventId: messageId, reason: reason)

        #if DEBUG
        print("[MatrixBridge] Deleted message \(messageId) in conversation \(conversationId)")
        #endif
    }

    /// Recall (unsend) a message - same as delete but with different semantic
    func recallMessage(conversationId: String, messageId: String) async throws {
        try await deleteMessage(conversationId: conversationId, messageId: messageId, reason: "Message recalled by sender")
    }

    /// Toggle reaction on a message (add if not present, remove if present)
    func toggleReaction(conversationId: String, messageId: String, emoji: String) async throws {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let roomId = try await resolveRoomId(for: conversationId)
        try await matrixService.toggleReaction(roomId: roomId, eventId: messageId, emoji: emoji)

        #if DEBUG
        print("[MatrixBridge] Toggled reaction \(emoji) on message \(messageId)")
        #endif
    }

    /// Add a reaction to a message
    func addReaction(conversationId: String, messageId: String, emoji: String) async throws {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let roomId = try await resolveRoomId(for: conversationId)
        try await matrixService.sendReaction(roomId: roomId, eventId: messageId, emoji: emoji)

        #if DEBUG
        print("[MatrixBridge] Added reaction \(emoji) to message \(messageId)")
        #endif
    }

    /// Remove a reaction from a message (uses toggle since Matrix doesn't have direct remove)
    func removeReaction(conversationId: String, messageId: String, emoji: String) async throws {
        // In Matrix, toggleReaction will remove if already present
        try await toggleReaction(conversationId: conversationId, messageId: messageId, emoji: emoji)
    }

    /// Get reactions for a message
    func getReactions(conversationId: String, messageId: String) async throws -> [MatrixReaction] {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let roomId = try await resolveRoomId(for: conversationId)
        return try await matrixService.getReactions(roomId: roomId, eventId: messageId)
    }

    // MARK: - Room Operations

    /// Create Matrix room for a new Nova conversation
    @discardableResult
    func createRoomForConversation(_ conversation: Conversation) async throws -> String {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let isDirect = conversation.type == .direct
        let participantIds = conversation.participants

        let roomId = try await matrixService.createRoom(
            name: isDirect ? nil : conversation.name,
            isDirect: isDirect,
            inviteUserIds: participantIds,
            isEncrypted: conversation.isEncrypted  // Use E2EE only for private chats
        )

        #if DEBUG
        print("[MatrixBridge] Created room \(roomId) for conversation \(conversation.id)")
        #endif

        // Cache and save the mapping
        cacheMapping(conversationId: conversation.id, roomId: roomId)
        try await saveRoomMapping(conversationId: conversation.id, roomId: roomId)

        return roomId
    }

    /// Create a new conversation with a friend and setup Matrix room
    /// This is the main entry point for starting a chat with a friend
    /// - Parameters:
    ///   - friendUserId: The user ID of the friend to chat with
    ///   - isPrivate: Whether this is a private (E2EE encrypted) chat. Default is false (plain text)
    func startConversationWithFriend(friendUserId: String, isPrivate: Bool = false) async throws -> Conversation {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        guard let currentUserId = AuthenticationManager.shared.currentUser?.id else {
            throw MatrixBridgeError.notAuthenticated
        }

        #if DEBUG
        print("[MatrixBridge] Starting \(isPrivate ? "private" : "regular") conversation with friend: \(friendUserId)")
        #endif

        // Create Nova conversation first
        let conversation = try await chatService.createConversation(
            type: .direct,
            participantIds: [currentUserId, friendUserId],
            name: nil,
            isEncrypted: isPrivate
        )

        // Create Matrix room - only use E2EE for private chats
        let roomId = try await matrixService.createRoom(
            name: nil,
            isDirect: true,
            inviteUserIds: [friendUserId],
            isEncrypted: isPrivate
        )

        // Save mapping
        cacheMapping(conversationId: conversation.id, roomId: roomId)
        try await saveRoomMapping(conversationId: conversation.id, roomId: roomId)

        #if DEBUG
        print("[MatrixBridge] Created \(isPrivate ? "private" : "regular") conversation \(conversation.id) with Matrix room \(roomId)")
        #endif

        return conversation
    }

    /// Invite user to conversation's Matrix room
    func inviteUser(conversationId: String, userId: String) async throws {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let roomId = try await resolveRoomId(for: conversationId)
        try await matrixService.inviteUser(roomId: roomId, userId: userId)
    }

    /// Remove user from conversation's Matrix room
    func removeUser(conversationId: String, userId: String, reason: String? = nil) async throws {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let roomId = try await resolveRoomId(for: conversationId)
        try await matrixService.kickUser(roomId: roomId, userId: userId, reason: reason)
    }

    /// Get all Matrix rooms as conversations
    func getMatrixRooms() async throws -> [MatrixRoom] {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        return try await matrixService.getJoinedRooms()
    }

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

    private func cacheMapping(conversationId: String, roomId: String) {
        conversationToRoomMap[conversationId] = roomId
        roomToConversationMap[roomId] = conversationId
    }

    // MARK: - Backend API Calls

    private func checkBridgeEnabled() async -> Bool {
        // Check feature flag from backend
        do {
            struct ConfigResponse: Codable {
                let enabled: Bool
                let homeserverUrl: String?
            }

            let response: ConfigResponse = try await apiClient.get(
                endpoint: APIConfig.Matrix.getConfig
            )
            #if DEBUG
            print("[MatrixBridge] Backend config: enabled=\(response.enabled), homeserver=\(response.homeserverUrl ?? "nil")")
            #endif
            return response.enabled
        } catch {
            #if DEBUG
            print("[MatrixBridge] Failed to check bridge status: \(error)")
            print("[MatrixBridge] ⚠️ Backend Matrix config not available; assuming enabled for Matrix-first mode")
            #endif
            // Matrix-first: default to ENABLED when backend is not available.
            return true
        }
    }

    /// Matrix credentials returned from Nova backend
    struct MatrixCredentials {
        let accessToken: String
        let matrixUserId: String
        let deviceId: String
        let homeserverUrl: String?
    }

    /// Get Matrix credentials from Nova backend
    /// Returns access token, Matrix user ID, device ID, and homeserver URL
    ///
    /// The backend generates a device-bound access token using Synapse Admin API.
    /// This enables seamless single sign-on without requiring a second SSO prompt.
    private func getMatrixCredentials(novaUserId: String) async throws -> MatrixCredentials {
        struct MatrixTokenRequest: Codable {
            let deviceId: String

            enum CodingKeys: String, CodingKey {
                case deviceId = "device_id"
            }
        }

        struct MatrixTokenResponse: Codable {
            // Note: No CodingKeys needed - APIClient uses .convertFromSnakeCase
            let accessToken: String
            let matrixUserId: String
            let deviceId: String
            let homeserverUrl: String?
        }

        // Generate a persistent device ID for this device
        // This ensures E2EE keys are consistent across app sessions
        let deviceId = getOrCreateDeviceId()

        #if DEBUG
        print("[MatrixBridge] Requesting device-bound token with device_id: \(deviceId)")
        #endif

        let response: MatrixTokenResponse = try await apiClient.request(
            endpoint: APIConfig.Matrix.getToken,
            method: "POST",
            body: MatrixTokenRequest(deviceId: deviceId)
        )

        return MatrixCredentials(
            accessToken: response.accessToken,
            matrixUserId: response.matrixUserId,
            deviceId: response.deviceId,
            homeserverUrl: response.homeserverUrl
        )
    }

    /// Get or create a persistent device ID for Matrix sessions
    /// This ensures E2EE keys are consistent across app sessions on the same device
    private func getOrCreateDeviceId() -> String {
        // Check if we already have a device ID stored
        if let existingDeviceId = keychain.get(.matrixDeviceId), !existingDeviceId.isEmpty {
            return existingDeviceId
        }

        // Generate a new device ID
        // Format: NOVA_IOS_{UUID} to identify Nova iOS clients
        let newDeviceId = "NOVA_IOS_\(UUID().uuidString.prefix(8))"

        // Store for future use
        _ = keychain.save(newDeviceId, for: .matrixDeviceId)

        #if DEBUG
        print("[MatrixBridge] Generated new device ID: \(newDeviceId)")
        #endif

        return newDeviceId
    }

    private func queryRoomMapping(conversationId: String) async throws -> String? {
        struct RoomMappingResponse: Codable {
            let roomId: String?

            enum CodingKeys: String, CodingKey {
                case roomId = "room_id"
            }
        }

        do {
            let response: RoomMappingResponse = try await apiClient.get(
                endpoint: APIConfig.Matrix.getRoomMapping(conversationId)
            )
            return response.roomId
        } catch {
            // 404 means no mapping exists
            return nil
        }
    }

    private func queryConversationMapping(roomId: String) async throws -> String? {
        struct ConversationMappingResponse: Codable {
            let conversationId: String?

            enum CodingKeys: String, CodingKey {
                case conversationId = "conversation_id"
            }
        }

        // URL encode room ID (!xxx:server contains special chars)
        let encodedRoomId = roomId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? roomId

        do {
            let response: ConversationMappingResponse = try await apiClient.get(
                endpoint: APIConfig.Matrix.getConversationMapping,
                queryParams: ["room_id": encodedRoomId]
            )
            return response.conversationId
        } catch {
            return nil
        }
    }

    private func saveRoomMapping(conversationId: String, roomId: String) async throws {
        struct SaveMappingRequest: Codable {
            let conversationId: String
            let roomId: String

            enum CodingKeys: String, CodingKey {
                case conversationId = "conversation_id"
                case roomId = "room_id"
            }
        }

        struct EmptyResponse: Codable {}

        let _: EmptyResponse = try await apiClient.request(
            endpoint: APIConfig.Matrix.saveRoomMapping,
            method: "POST",
            body: SaveMappingRequest(conversationId: conversationId, roomId: roomId)
        )
    }

    private func loadConversationMappings() async throws {
        struct AllMappingsResponse: Codable {
            let mappings: [MappingEntry]

            struct MappingEntry: Codable {
                let conversationId: String
                let roomId: String

                enum CodingKeys: String, CodingKey {
                    case conversationId = "conversation_id"
                    case roomId = "room_id"
                }
            }
        }

        do {
            let response: AllMappingsResponse = try await apiClient.get(
                endpoint: APIConfig.Matrix.getRoomMappings
            )

            for mapping in response.mappings {
                cacheMapping(conversationId: mapping.conversationId, roomId: mapping.roomId)
            }

            #if DEBUG
            print("[MatrixBridge] Loaded \(response.mappings.count) conversation mappings")
            #endif
        } catch {
            #if DEBUG
            print("[MatrixBridge] Failed to load mappings: \(error)")
            #endif
            // Not critical - mappings will be created on demand
        }
    }
}

// MARK: - Matrix Bridge Errors

enum MatrixBridgeError: Error, LocalizedError {
    case notInitialized
    case notAuthenticated
    case roomMappingFailed(String)
    case messageSendFailed(String)
    case bridgeDisabled
    case sessionExpired

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

        // Convert sender ID
        let senderId = matrixService.convertToNovaUserId(matrixUserId: matrixMessage.senderId)
            ?? matrixMessage.senderId

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

            if room.isDirect {
                displayName = room.name ?? "Direct Message"
                avatarURL = room.avatarURL

                // Try to enrich from Nova conversation + identity profiles.
                // This fixes cases where Matrix room display names/avatars are not yet configured.
                if let novaConversationId = try? await queryConversationMapping(roomId: room.id),
                   let conversation = try? await chatService.getConversation(conversationId: novaConversationId) {
                    if let name = conversation.name, !name.isEmpty {
                        displayName = name
                    } else if let other = conversation.members.first(where: { $0.userId != currentUserId }),
                              !other.username.isEmpty {
                        displayName = other.username
                    }

                    if let convAvatar = conversation.avatarUrl, !convAvatar.isEmpty {
                        avatarURL = convAvatar
                    }
                }
            } else {
                displayName = room.name ?? "Group Chat"
                avatarURL = room.avatarURL
            }

            conversations.append(
                MatrixConversationInfo(
                    id: room.id,
                    displayName: displayName,
                    lastMessage: room.lastMessage?.content,
                    lastMessageTime: room.lastActivity,
                    unreadCount: room.unreadCount,
                    isEncrypted: room.isEncrypted,
                    isDirect: room.isDirect,
                    avatarURL: avatarURL,
                    memberCount: room.memberCount
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

    /// Create a new direct conversation with a user via Matrix
    /// This creates a Matrix room and returns the conversation info
    /// - Parameters:
    ///   - userId: The user ID to chat with
    ///   - displayName: Display name for the conversation
    ///   - isPrivate: Whether this is a private (E2EE encrypted) chat. Default is false (plain text)
    func createDirectConversation(withUserId userId: String, displayName: String?, isPrivate: Bool = false) async throws -> MatrixConversationInfo {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        #if DEBUG
        print("[MatrixBridge] Creating \(isPrivate ? "private" : "regular") direct conversation with user: \(userId)")
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
            memberCount: 2
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
            memberCount: userIds.count + 1  // Including current user
        )
    }
}
