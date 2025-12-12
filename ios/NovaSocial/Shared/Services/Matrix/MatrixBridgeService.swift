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
    private let chatService = ChatService()
    private let keychain = KeychainService.shared
    private let apiClient = APIClient.shared

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
    func initialize() async throws {
        guard !isInitialized else {
            #if DEBUG
            print("[MatrixBridge] Already initialized")
            #endif
            return
        }

        #if DEBUG
        print("[MatrixBridge] Initializing bridge...")
        #endif

        do {
            // Check if Matrix bridge is enabled for this user
            isBridgeEnabled = await checkBridgeEnabled()

            guard isBridgeEnabled else {
                #if DEBUG
                print("[MatrixBridge] Bridge disabled for this user")
                #endif
                return
            }

            // Initialize Matrix client
            try await matrixService.initialize(
                homeserverURL: MatrixConfiguration.homeserverURL,
                sessionPath: MatrixConfiguration.sessionPath
            )

            // Try to restore existing session first
            let sessionRestored = try await matrixService.restoreSession()

            if !sessionRestored {
                // Login to Matrix with Nova credentials
                guard let currentUser = AuthenticationManager.shared.currentUser else {
                    throw MatrixBridgeError.notAuthenticated
                }

                // Get Matrix access token from Nova backend
                let matrixToken = try await getMatrixAccessToken(novaUserId: currentUser.id)

                try await matrixService.login(
                    novaUserId: currentUser.id,
                    accessToken: matrixToken
                )
            }

            // Start sync to receive messages
            try await matrixService.startSync()

            // Load existing conversation mappings
            try await loadConversationMappings()

            isInitialized = true
            initializationError = nil

            #if DEBUG
            print("[MatrixBridge] Bridge initialized successfully")
            #endif
        } catch {
            initializationError = error
            #if DEBUG
            print("[MatrixBridge] Initialization failed: \(error)")
            #endif
            throw error
        }
    }

    /// Shutdown the Matrix bridge
    func shutdown() async {
        #if DEBUG
        print("[MatrixBridge] Shutting down...")
        #endif

        matrixService.stopSync()

        do {
            try await matrixService.logout()
        } catch {
            #if DEBUG
            print("[MatrixBridge] Logout error: \(error)")
            #endif
        }

        conversationToRoomMap.removeAll()
        roomToConversationMap.removeAll()
        isInitialized = false

        #if DEBUG
        print("[MatrixBridge] Shutdown complete")
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

        let roomId = try await getRoomId(for: conversationId)

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

    /// Get messages for a conversation via Matrix
    func getMessages(
        conversationId: String,
        limit: Int = 50,
        from: String? = nil
    ) async throws -> [MatrixMessage] {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let roomId = try await getRoomId(for: conversationId)
        return try await matrixService.getRoomMessages(roomId: roomId, limit: limit, from: from)
    }

    /// Set typing indicator for a conversation
    func setTyping(conversationId: String, isTyping: Bool) async throws {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let roomId = try await getRoomId(for: conversationId)
        try await matrixService.setTyping(roomId: roomId, isTyping: isTyping)
    }

    /// Mark conversation as read
    func markAsRead(conversationId: String) async throws {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let roomId = try await getRoomId(for: conversationId)
        try await matrixService.markRoomAsRead(roomId: roomId)
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
            isEncrypted: true  // Always use E2EE
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
    func startConversationWithFriend(friendUserId: String) async throws -> Conversation {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        guard let currentUserId = AuthenticationManager.shared.currentUser?.id else {
            throw MatrixBridgeError.notAuthenticated
        }

        #if DEBUG
        print("[MatrixBridge] Starting conversation with friend: \(friendUserId)")
        #endif

        // Create Nova conversation first
        let conversation = try await chatService.createConversation(
            type: .direct,
            participantIds: [currentUserId, friendUserId],
            name: nil
        )

        // Create Matrix room for E2EE
        let roomId = try await matrixService.createRoom(
            name: nil,
            isDirect: true,
            inviteUserIds: [friendUserId],
            isEncrypted: true
        )

        // Save mapping
        cacheMapping(conversationId: conversation.id, roomId: roomId)
        try await saveRoomMapping(conversationId: conversation.id, roomId: roomId)

        #if DEBUG
        print("[MatrixBridge] Created conversation \(conversation.id) with Matrix room \(roomId)")
        #endif

        return conversation
    }

    /// Invite user to conversation's Matrix room
    func inviteUser(conversationId: String, userId: String) async throws {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let roomId = try await getRoomId(for: conversationId)
        try await matrixService.inviteUser(roomId: roomId, userId: userId)
    }

    /// Remove user from conversation's Matrix room
    func removeUser(conversationId: String, userId: String, reason: String? = nil) async throws {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let roomId = try await getRoomId(for: conversationId)
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
        // Convert Matrix room ID to Nova conversation ID
        guard let conversationId = try? await getConversationId(for: message.roomId) else {
            #if DEBUG
            print("[MatrixBridge] Unknown room: \(message.roomId)")
            #endif
            return
        }

        onMatrixMessage?(conversationId, message)
    }

    private func handleTypingIndicator(roomId: String, userIds: [String]) async {
        guard let conversationId = try? await getConversationId(for: roomId) else {
            return
        }

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
        // For now, return true to enable Matrix integration
        do {
            struct ConfigResponse: Codable {
                let enabled: Bool
                let homeserverUrl: String?
            }

            let response: ConfigResponse = try await apiClient.get(
                endpoint: APIConfig.Matrix.getConfig
            )
            return response.enabled
        } catch {
            #if DEBUG
            print("[MatrixBridge] Failed to check bridge status: \(error)")
            #endif
            // Default to enabled in debug mode
            #if DEBUG
            return true
            #else
            return false
            #endif
        }
    }

    private func getMatrixAccessToken(novaUserId: String) async throws -> String {
        struct MatrixTokenRequest: Codable {
            let userId: String

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
            }
        }

        struct MatrixTokenResponse: Codable {
            let accessToken: String
            let matrixUserId: String
            let deviceId: String
            let homeserverUrl: String?

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case matrixUserId = "matrix_user_id"
                case deviceId = "device_id"
                case homeserverUrl = "homeserver_url"
            }
        }

        let response: MatrixTokenResponse = try await apiClient.request(
            endpoint: APIConfig.Matrix.getToken,
            method: "POST",
            body: MatrixTokenRequest(userId: novaUserId)
        )

        return response.accessToken
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
