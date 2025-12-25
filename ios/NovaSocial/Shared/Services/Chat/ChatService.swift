import Foundation

// MARK: - Chat Service Errors

/// ChatService 錯誤類型
enum ChatServiceError: LocalizedError {
    case matrixNotInitialized
    case messageSendFailed(String)
    case invalidMediaUrl

    var errorDescription: String? {
        switch self {
        case .matrixNotInitialized:
            return "Matrix service is not initialized"
        case .messageSendFailed(let reason):
            return "Failed to send message: \(reason)"
        case .invalidMediaUrl:
            return "Invalid media URL"
        }
    }
}



// MARK: - Chat Service

/// Chat Service - 聊天消息服务
/// 职责：
/// - 发送/接收消息（REST API）
/// - 实时消息推送（WebSocket）
/// - 消息历史管理
/// - 会话管理
/// - Matrix E2EE integration (when enabled)
@MainActor
@Observable
final class ChatService {
    // MARK: - Singleton

    static let shared = ChatService()

    // MARK: - Properties

    private let client = APIClient.shared

    // Thread-safe WebSocket state manager
    private let wsStateManager = WebSocketStateManager()

    /// WebSocket消息接收回调
    /// 当收到新消息时，会调用这个闭包
    @MainActor var onMessageReceived: ((Message) -> Void)?

    /// WebSocket连接状态变化回调
    @MainActor var onConnectionStatusChanged: ((Bool) -> Void)?

    /// E2EE Service for client-side encryption
    /// Note: Optional because E2EE may not be initialized (requires device registration)
    private let e2eeService: E2EEService?

    /// Keychain for device ID storage
    private let keychain = KeychainService.shared

    /// Feature flag: Use Matrix for E2EE messaging
    /// When enabled, messages are routed through Matrix Rust SDK for true E2EE
    private var useMatrixE2EE: Bool = false

    // MARK: - Delegated Services
    @ObservationIgnored private lazy var reactionsService = ChatReactionsService()
    @ObservationIgnored private lazy var groupService = ChatGroupService()
    @ObservationIgnored private lazy var callService = ChatCallService()
    @ObservationIgnored private lazy var locationService = ChatLocationService()

    // MARK: - Initialization

    init() {
        // Initialize E2EE service
        self.e2eeService = E2EEService()

        // Check if Matrix E2EE is available
        // This will be true when MatrixBridgeService is initialized
        self.useMatrixE2EE = false  // Will be updated by enableMatrixE2EE()
    }

    /// Enable Matrix E2EE for this chat service instance
    /// Called after MatrixBridgeService is initialized
    @MainActor
    func enableMatrixE2EE() {
        self.useMatrixE2EE = MatrixBridgeService.shared.isInitialized
        #if DEBUG
        print("[ChatService] Matrix E2EE enabled: \(useMatrixE2EE)")
        #endif
    }

    // MARK: - Matrix SDK - Messages

    /// 透過 Matrix SDK 發送訊息（E2EE 端到端加密）
    /// - Parameters:
    ///   - conversationId: 會話ID
    ///   - content: 訊息內容
    ///   - type: 訊息類型（預設為文字）
    ///   - mediaUrl: 媒體URL（可選，用於媒體訊息）
    ///   - replyToId: 回覆的訊息ID（可選）
    ///   - preferE2EE: 未使用，保留為 API 相容性
    /// - Returns: 發送後的訊息物件
    /// - Throws: 如果 Matrix 未初始化則拋出錯誤
    @MainActor
    func sendSecureMessage(
        conversationId: String,
        content: String,
        type: ChatMessageType = .text,
        mediaUrl: String? = nil,
        replyToId: String? = nil,
        preferE2EE: Bool = true
    ) async throws -> Message {
        // 確保 Matrix 已初始化
        guard MatrixBridgeService.shared.isInitialized else {
            throw ChatServiceError.matrixNotInitialized
        }

        #if DEBUG
        print("[ChatService] 📤 Sending message via Matrix SDK (type: \(type))")
        #endif

        // 轉換 mediaUrl 字串為 URL 並判斷 MIME 類型
        var mediaURL: URL? = nil
        var mimeType: String? = nil

        if let mediaUrlString = mediaUrl, let url = URL(string: mediaUrlString) {
            mediaURL = url
            // 根據訊息類型判斷 MIME 類型
            switch type {
            case .image:
                mimeType = "image/jpeg"
            case .video:
                mimeType = "video/mp4"
            case .audio:
                mimeType = "audio/mp4"  // M4A format
            case .file:
                mimeType = "application/octet-stream"
            default:
                break
            }
        }

        // 透過 Matrix Bridge 發送訊息
        let eventId = try await MatrixBridgeService.shared.sendMessage(
            conversationId: conversationId,
            content: content,
            mediaURL: mediaURL,
            mimeType: mimeType
        )

        // 建立本地訊息物件
        let senderId = AuthenticationManager.shared.currentUser?.id ?? ""

        #if DEBUG
        print("[ChatService] ✅ Message sent via Matrix: \(eventId)")
        #endif

        return Message(
            id: eventId,
            conversationId: conversationId,
            senderId: senderId,
            content: content,
            type: type,
            createdAt: Date(),
            status: .sent,
            encryptionVersion: 3  // Matrix E2EE
        )
    }

    /// 获取会话消息历史 - 優先使用 Matrix SDK
    /// - Parameters:
    ///   - conversationId: 会话ID
    ///   - limit: 获取消息数量（默认50条）
    ///   - cursor: 分页游标（可选）
    /// - Returns: 消息列表响应
    @MainActor
    func getMessages(
        conversationId: String,
        limit: Int = 50,
        cursor: String? = nil
    ) async throws -> GetMessagesResponse {
        // 優先使用 Matrix SDK
        if MatrixBridgeService.shared.isInitialized {
            do {
                let matrixMessages = try await MatrixBridgeService.shared.getMessages(
                    conversationId: conversationId,
                    limit: limit
                )

                // 轉換 MatrixMessage 到 Message
                let messages = matrixMessages.map { matrixMsg -> Message in
                    let msgType: ChatMessageType
                    switch matrixMsg.type {
                    case .text: msgType = .text
                    case .image: msgType = .image
                    case .video: msgType = .video
                    case .audio: msgType = .audio
                    case .file: msgType = .file
                    case .location: msgType = .location
                    default: msgType = .text
                    }

                    return Message(
                        id: matrixMsg.id,
                        conversationId: conversationId,
                        senderId: matrixMsg.senderId,
                        content: matrixMsg.content,
                        type: msgType,
                        createdAt: matrixMsg.timestamp,
                        status: .delivered,
                        encryptionVersion: 3  // Matrix E2EE
                    )
                }

                #if DEBUG
                print("[ChatService] ✅ Fetched \(messages.count) messages via Matrix SDK")
                #endif

                return GetMessagesResponse(
                    messages: messages,
                    hasMore: messages.count >= limit,
                    nextCursor: messages.last?.id
                )
            } catch {
                #if DEBUG
                print("[ChatService] Matrix getMessages failed, falling back to REST API: \(error)")
                #endif
            }
        }

        // Fallback: REST API
        var queryParams: [String: String] = [
            "conversation_id": conversationId,
            "limit": "\(limit)"
        ]
        if let cursor = cursor {
            queryParams["before_message_id"] = cursor
        }

        let response: GetMessagesResponse = try await client.get(
            endpoint: APIConfig.Chat.getMessages,
            queryParams: queryParams
        )

        #if DEBUG
        print("[ChatService] Fetched \(response.messages.count) messages via REST API")
        #endif

        return response
    }

    /// 编辑消息 - 優先使用 Matrix SDK
    /// - Parameters:
    ///   - conversationId: 會話ID
    ///   - messageId: 消息ID
    ///   - newContent: 新的消息内容
    /// - Returns: 更新后的消息对象
    @MainActor
    func editMessage(conversationId: String, messageId: String, newContent: String) async throws -> Message {
        // 優先使用 Matrix SDK
        if MatrixBridgeService.shared.isInitialized {
            try await MatrixBridgeService.shared.editMessage(
                conversationId: conversationId,
                messageId: messageId,
                newContent: newContent
            )

            #if DEBUG
            print("[ChatService] ✅ Message edited via Matrix SDK: \(messageId)")
            #endif

            // 返回更新後的訊息物件
            return Message(
                id: messageId,
                conversationId: conversationId,
                senderId: AuthenticationManager.shared.currentUser?.id ?? "",
                content: newContent,
                type: .text,
                createdAt: Date(),
                status: .sent,
                encryptionVersion: 3
            )
        }

        // Fallback: REST API (舊版本兼容)
        struct EditRequest: Codable {
            let content: String
        }

        let message: Message = try await client.request(
            endpoint: APIConfig.Chat.editMessage(messageId),
            method: "PUT",
            body: EditRequest(content: newContent)
        )

        #if DEBUG
        print("[ChatService] Message edited via REST API: \(messageId)")
        #endif

        return message
    }

    /// 编辑消息 - 舊版本兼容 (無 conversationId)
    @MainActor
    @available(*, deprecated, message: "Use editMessage(conversationId:messageId:newContent:) instead")
    func editMessage(messageId: String, newContent: String) async throws -> Message {
        struct EditRequest: Codable {
            let content: String
        }

        let message: Message = try await client.request(
            endpoint: APIConfig.Chat.editMessage(messageId),
            method: "PUT",
            body: EditRequest(content: newContent)
        )

        return message
    }

    /// 删除消息 - 優先使用 Matrix SDK
    /// - Parameters:
    ///   - conversationId: 會話ID
    ///   - messageId: 消息ID
    @MainActor
    func deleteMessage(conversationId: String, messageId: String) async throws {
        // 優先使用 Matrix SDK
        if MatrixBridgeService.shared.isInitialized {
            try await MatrixBridgeService.shared.deleteMessage(
                conversationId: conversationId,
                messageId: messageId
            )

            #if DEBUG
            print("[ChatService] ✅ Message deleted via Matrix SDK: \(messageId)")
            #endif
            return
        }

        // Fallback: REST API
        struct EmptyResponse: Codable {}

        let _: EmptyResponse = try await client.request(
            endpoint: APIConfig.Chat.deleteMessage(messageId),
            method: "DELETE"
        )

        #if DEBUG
        print("[ChatService] Message deleted via REST API: \(messageId)")
        #endif
    }

    /// 删除消息 - 舊版本兼容 (無 conversationId)
    @MainActor
    @available(*, deprecated, message: "Use deleteMessage(conversationId:messageId:) instead")
    func deleteMessage(messageId: String) async throws {
        struct EmptyResponse: Codable {}

        let _: EmptyResponse = try await client.request(
            endpoint: APIConfig.Chat.deleteMessage(messageId),
            method: "DELETE"
        )

        #if DEBUG
        print("[ChatService] Message deleted: \(messageId)")
        #endif
    }

    /// 撤回消息 - 優先使用 Matrix SDK
    /// - Parameters:
    ///   - conversationId: 会话ID
    ///   - messageId: 消息ID
    @MainActor
    func recallMessage(conversationId: String, messageId: String) async throws {
        // 優先使用 Matrix SDK
        if MatrixBridgeService.shared.isInitialized {
            try await MatrixBridgeService.shared.recallMessage(
                conversationId: conversationId,
                messageId: messageId
            )

            #if DEBUG
            print("[ChatService] ✅ Message recalled via Matrix SDK: \(messageId)")
            #endif
            return
        }

        // Fallback: REST API
        struct EmptyResponse: Codable {}

        let _: EmptyResponse = try await client.request(
            endpoint: APIConfig.Chat.recallMessage(conversationId: conversationId, messageId: messageId),
            method: "POST"
        )

        #if DEBUG
        print("[ChatService] Message recalled via REST API: \(messageId)")
        #endif
    }

    // MARK: - REST API - Conversations

    /// Create a new conversation (1:1 or group)
    /// Maps to API: POST /api/v2/chat/conversations
    /// - Parameters:
    ///   - type: Conversation type (direct/group)
    ///   - participantIds: User IDs to add to the conversation
    ///   - name: Conversation name (required for groups, null for direct)
    ///   - isEncrypted: Whether to use E2EE (true = private chat, false = plain text)
    /// - Returns: Created conversation object
    /// - Note: For direct conversations, if one already exists between the same users,
    ///         the existing conversation is returned (idempotent)
    @MainActor
    func createConversation(
        type: ConversationType,
        participantIds: [String],
        name: String? = nil,
        isEncrypted: Bool = false
    ) async throws -> Conversation {
        let request = CreateConversationRequest(
            type: type,
            participantIds: participantIds,
            name: name,
            isEncrypted: isEncrypted
        )

        // Use flexible response parser that handles multiple backend formats
        let response: CreateConversationFlexibleResponse = try await client.request(
            endpoint: APIConfig.Chat.createConversation,
            method: "POST",
            body: request
        )

        let conversation = response.toConversation(type: type, name: name, participantIds: participantIds)

        #if DEBUG
        print("[ChatService] Conversation created: \(conversation.id)")
        #endif

        return conversation
    }

    /// Flexible response parser for createConversation API
    /// Handles multiple backend response formats:
    /// 1. Direct Conversation object (new format)
    /// 2. Wrapped format: { "conversation": {...} }
    /// 3. Minimal format: { "id": "...", "member_count": ..., "last_message_id": ... }
    private struct CreateConversationFlexibleResponse: Codable {
        // Direct format fields
        let id: String
        let type: String?
        let name: String?
        let members: [ConversationMember]?
        let createdAt: Date?
        let updatedAt: Date?
        let lastMessage: ConversationLastMessage?
        let unreadCount: Int?
        let isMuted: Bool?
        let isArchived: Bool?
        let isEncrypted: Bool?
        let avatarUrl: String?

        // Wrapped format field
        let conversation: Conversation?

        // Minimal format fields
        let memberCount: Int?
        let lastMessageId: String?

        enum CodingKeys: String, CodingKey {
            case id, type, name, members, conversation
            case createdAt = "created_at"
            case updatedAt = "updated_at"
            case lastMessage = "last_message"
            case unreadCount = "unread_count"
            case isMuted = "is_muted"
            case isArchived = "is_archived"
            case isEncrypted = "is_encrypted"
            case avatarUrl = "avatar_url"
            case memberCount = "member_count"
            case lastMessageId = "last_message_id"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            // Try to get ID (required in all formats)
            id = try container.decode(String.self, forKey: .id)

            // Optional fields for direct format
            type = try container.decodeIfPresent(String.self, forKey: .type)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            members = try container.decodeIfPresent([ConversationMember].self, forKey: .members)
            lastMessage = try container.decodeIfPresent(ConversationLastMessage.self, forKey: .lastMessage)
            unreadCount = try container.decodeIfPresent(Int.self, forKey: .unreadCount)
            isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted)
            isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived)
            isEncrypted = try container.decodeIfPresent(Bool.self, forKey: .isEncrypted)
            avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)

            // Wrapped format
            conversation = try container.decodeIfPresent(Conversation.self, forKey: .conversation)

            // Minimal format
            memberCount = try container.decodeIfPresent(Int.self, forKey: .memberCount)
            lastMessageId = try container.decodeIfPresent(String.self, forKey: .lastMessageId)

            // Flexible date decoding
            if let dateString = try? container.decode(String.self, forKey: .createdAt) {
                createdAt = ISO8601DateFormatter().date(from: dateString) ?? Date()
            } else if let timestamp = try? container.decode(Double.self, forKey: .createdAt) {
                createdAt = Date(timeIntervalSince1970: timestamp)
            } else {
                createdAt = nil
            }

            if let dateString = try? container.decode(String.self, forKey: .updatedAt) {
                updatedAt = ISO8601DateFormatter().date(from: dateString) ?? Date()
            } else if let timestamp = try? container.decode(Double.self, forKey: .updatedAt) {
                updatedAt = Date(timeIntervalSince1970: timestamp)
            } else {
                updatedAt = nil
            }
        }

        /// Convert flexible response to Conversation
        func toConversation(type requestType: ConversationType, name requestName: String?, participantIds: [String]) -> Conversation {
            // If wrapped format has full conversation, use it
            if let conv = conversation {
                return conv
            }

            // Otherwise build from available fields
            let convType: ConversationType
            if let typeStr = type {
                convType = ConversationType(rawValue: typeStr) ?? requestType
            } else {
                convType = requestType
            }

            let convMembers: [ConversationMember]
            if let m = members, !m.isEmpty {
                convMembers = m
            } else {
                // Create placeholder members from participantIds
                convMembers = participantIds.map { userId in
                    ConversationMember(userId: userId, username: "", role: .member, joinedAt: Date())
                }
            }

            return Conversation(
                id: id,
                type: convType,
                name: name ?? requestName,
                createdBy: participantIds.first,
                createdAt: createdAt ?? Date(),
                updatedAt: updatedAt ?? Date(),
                members: convMembers,
                lastMessage: lastMessage,
                unreadCount: unreadCount ?? 0,
                isMuted: isMuted ?? false,
                isArchived: isArchived ?? false,
                isEncrypted: isEncrypted ?? false,
                avatarUrl: avatarUrl
            )
        }
    }
    
    /// Legacy method for backwards compatibility
    @MainActor
    func createConversation(
        type: ConversationType,
        participants: [String],
        name: String? = nil,
        isEncrypted: Bool = false
    ) async throws -> Conversation {
        try await createConversation(type: type, participantIds: participants, name: name, isEncrypted: isEncrypted)
    }

    /// Get all conversations for current user
    /// Maps to API: GET /api/v1/conversations
    /// - Parameters:
    ///   - limit: Items per page (max 100, default 20)
    ///   - offset: Pagination offset
    ///   - archived: Include archived conversations
    /// - Returns: List of conversations
    @MainActor
    func getConversations(
        limit: Int = 20,
        offset: Int = 0,
        archived: Bool = false
    ) async throws -> [Conversation] {
        print("🔍 [ChatService] getConversations() called")

        do {
            let response: ListConversationsResponse = try await client.get(
                endpoint: APIConfig.Chat.getConversations,
                queryParams: [
                    "limit": String(limit),
                    "offset": String(offset),
                    "archived": String(archived)
                ]
            )

            print("✅ [ChatService] Fetched \(response.conversations.count) of \(response.total) conversations")
            return response.conversations
        } catch {
            // Fallback: try decoding as array directly (for backwards compatibility)
            do {
                let conversations: [Conversation] = try await client.get(
                    endpoint: APIConfig.Chat.getConversations,
                    queryParams: [
                        "limit": String(limit),
                        "offset": String(offset),
                        "archived": String(archived)
                    ]
                )
                print("✅ [ChatService] Fetched \(conversations.count) conversations (legacy format)")
                return conversations
            } catch {
                print("❌ [ChatService] Failed to fetch conversations: \(error)")
                throw error
            }
        }
    }
    
    /// Convenience overload without parameters
    @MainActor
    func getConversations() async throws -> [Conversation] {
        try await getConversations(limit: 20, offset: 0, archived: false)
    }
    
    /// Update conversation settings (mute/archive)
    /// Maps to API: PATCH /api/v1/conversations/:id/settings
    /// - Parameters:
    ///   - conversationId: Conversation ID
    ///   - isMuted: Mute notifications (optional)
    ///   - isArchived: Archive conversation (optional)
    /// - Returns: Updated settings
    @MainActor
    func updateConversationSettings(
        conversationId: String,
        isMuted: Bool? = nil,
        isArchived: Bool? = nil
    ) async throws -> ConversationSettingsResponse {
        let request = UpdateConversationSettingsRequest(
            isMuted: isMuted,
            isArchived: isArchived
        )
        
        let response: ConversationSettingsResponse = try await client.request(
            endpoint: "\(APIConfig.Chat.getConversation(conversationId))/settings",
            method: "PATCH",
            body: request
        )
        
        #if DEBUG
        print("[ChatService] Conversation settings updated: \(conversationId)")
        #endif
        
        return response
    }
    
    // MARK: - Matrix SDK - Read Receipts

    /// 標記訊息為已讀 - 優先使用 Matrix SDK
    /// - Parameters:
    ///   - conversationId: 會話 ID
    ///   - messageId: 最後已讀訊息 ID（用於 REST API fallback）
    @MainActor
    func markAsRead(conversationId: String, messageId: String) async throws {
        // 優先使用 Matrix SDK
        if MatrixBridgeService.shared.isInitialized {
            do {
                try await MatrixBridgeService.shared.markAsRead(conversationId: conversationId)
                #if DEBUG
                print("[ChatService] ✅ Marked as read via Matrix SDK: conversation=\(conversationId)")
                #endif
                return
            } catch {
                #if DEBUG
                print("[ChatService] Matrix markAsRead failed, falling back to REST API: \(error)")
                #endif
            }
        }

        // Fallback: REST API
        struct MessageResponse: Codable {
            let message: String
        }

        let request = MarkAsReadRequest(messageId: messageId)

        let _: MessageResponse = try await client.request(
            endpoint: "\(APIConfig.Chat.getConversation(conversationId))/read",
            method: "POST",
            body: request
        )

        #if DEBUG
        print("[ChatService] Marked as read via REST API: conversation=\(conversationId), message=\(messageId)")
        #endif
    }

    /// 僅使用 Matrix SDK 標記會話為已讀（不需要 messageId）
    /// - Parameter conversationId: 會話 ID
    @MainActor
    func markAsReadMatrix(conversationId: String) async throws {
        guard MatrixBridgeService.shared.isInitialized else {
            throw ChatServiceError.matrixNotInitialized
        }

        try await MatrixBridgeService.shared.markAsRead(conversationId: conversationId)

        #if DEBUG
        print("[ChatService] ✅ Marked as read via Matrix SDK: conversation=\(conversationId)")
        #endif
    }

    /// 获取指定会话详情
    /// - Parameter conversationId: 会话ID
    /// - Returns: 会话对象
    @MainActor
    func getConversation(conversationId: String) async throws -> Conversation {
        let conversation: Conversation = try await client.get(
            endpoint: APIConfig.Chat.getConversation(conversationId)
        )

        return conversation
    }

    /// 更新会话信息（名称、头像等）
    /// - Parameters:
    ///   - conversationId: 会话ID
    ///   - name: 新的会话名称（可选）
    ///   - avatarUrl: 新的头像URL（可选）
    /// - Returns: 更新后的会话对象
    @MainActor
    func updateConversation(
        conversationId: String,
        name: String? = nil,
        avatarUrl: String? = nil
    ) async throws -> Conversation {
        let request = UpdateConversationRequest(
            name: name,
            avatarUrl: avatarUrl
        )

        let conversation: Conversation = try await client.request(
            endpoint: APIConfig.Chat.updateConversation(conversationId),
            method: "PUT",
            body: request
        )

        #if DEBUG
        print("[ChatService] Conversation updated: \(conversationId)")
        #endif

        return conversation
    }

    // MARK: - E2EE Messaging

    /// Send an E2EE encrypted message via REST API
    /// - Parameters:
    ///   - conversationId: 会话ID
    ///   - content: 消息内容（明文）
    ///   - type: 消息类型
    ///   - replyToId: 回复的消息ID
    /// - Returns: 发送后的消息对象
    /// - Note: 使用 Megolm 群组加密（当前为简化版本，等待 vodozemac FFI 集成）
    @MainActor
    func sendEncryptedMessage(
        conversationId: String,
        content: String,
        type: ChatMessageType = .text,
        replyToId: String? = nil
    ) async throws -> Message {
        guard let e2ee = e2eeService else {
            throw ChatError.e2eeNotAvailable
        }

        // Get device ID from E2EE service
        // Device ID is stored in DeviceIdentity in keychain as JSON
        guard let deviceIdentityJSON = keychain.get(.e2eeDeviceIdentity),
              let identityData = deviceIdentityJSON.data(using: .utf8) else {
            throw ChatError.noDeviceId
        }

        // Decode device identity to get device ID
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let deviceIdentity = try? decoder.decode(DeviceIdentityWrapper.self, from: identityData) else {
            throw ChatError.noDeviceId
        }

        let deviceId = deviceIdentity.deviceId

        // Convert conversationId to UUID
        guard let conversationUUID = UUID(uuidString: conversationId) else {
            throw ChatError.invalidConversationId
        }

        // Encrypt content using simple conversation-based encryption
        // TODO: Replace with Megolm group encryption when vodozemac FFI is available
        let encrypted = try await e2ee.encryptMessage(
            for: conversationUUID,
            plaintext: content
        )

        // Build E2EE message request
        let messageTypeInt: Int
        switch type {
        case .text: messageTypeInt = 0
        case .image: messageTypeInt = 1
        case .video: messageTypeInt = 2
        case .audio: messageTypeInt = 3
        case .file: messageTypeInt = 4
        case .location: messageTypeInt = 5
        }

        let request = SendE2EEMessageRequest(
            conversationId: conversationId,
            ciphertext: encrypted.ciphertext,
            nonce: encrypted.nonce,
            sessionId: "simple-session-\(conversationId)", // Temporary session ID
            messageIndex: 0, // TODO: Implement proper message index tracking
            deviceId: deviceId,
            messageType: messageTypeInt,
            replyToMessageId: replyToId
        )

        #if DEBUG
        print("[ChatService] Sending E2EE message via REST API")
        #endif

        // Send to E2EE endpoint via REST API
        let response: SendE2EEMessageResponse = try await client.request(
            endpoint: APIConfig.E2EE.sendMessage,
            method: "POST",
            body: request
        )

        #if DEBUG
        print("[ChatService] E2EE message sent: \(response.id), sequence: \(response.sequenceNumber)")
        #endif

        // Convert response to Message object
        // Note: The response only contains metadata; content is encrypted on server
        return Message(
            id: response.id,
            conversationId: response.conversationId,
            senderId: response.senderId,
            content: "", // Content is encrypted, not returned by server
            type: type,
            createdAt: response.createdAt,
            status: .sent,
            // E2EE metadata
            encryptedContent: encrypted.ciphertext,
            nonce: encrypted.nonce,
            sessionId: request.sessionId,
            senderDeviceId: deviceId,
            encryptionVersion: 2 // Client-side Megolm E2EE
        )
    }

    /// Decrypt a received E2EE message
    /// - Parameter message: 接收到的消息（可能加密）
    /// - Returns: 解密后的明文内容（如果消息未加密，返回原始内容）
    func decryptMessage(_ message: Message) async throws -> String {
        // Check if message is encrypted
        guard let encryptionVersion = message.encryptionVersion,
              encryptionVersion == 2,
              let encryptedContent = message.encryptedContent,
              let nonce = message.nonce,
              let _ = message.sessionId else {
            // Not an E2EE message, return plaintext
            return message.content
        }

        guard let e2ee = e2eeService else {
            throw ChatError.e2eeNotAvailable
        }

        // Convert conversationId to UUID
        guard let conversationUUID = UUID(uuidString: message.conversationId) else {
            throw ChatError.invalidConversationId
        }

        // TODO: When Megolm is available, use proper session-based decryption
        // For now, use simple conversation-based decryption
        let encryptedMessage = EncryptedMessage(
            ciphertext: encryptedContent,
            nonce: nonce,
            deviceId: message.senderDeviceId ?? ""
        )

        let plaintext = try await e2ee.decryptMessage(
            encryptedMessage,
            conversationId: conversationUUID
        )

        #if DEBUG
        print("[ChatService] Decrypted message: \(message.id)")
        #endif

        return plaintext
    }

    /// Get device ID from keychain
    /// - Returns: Device ID if available
    private func getDeviceId() -> String? {
        // Parse device identity JSON to extract device ID
        guard let identityJSON = keychain.get(.e2eeDeviceIdentity),
              let identityData = identityJSON.data(using: .utf8),
              let identity = try? JSONDecoder().decode(DeviceIdentity.self, from: identityData) else {
            return nil
        }
        return identity.deviceId
    }

    // MARK: - WebSocket - Real-time Messaging

    /// 连接WebSocket以接收实时消息
    /// ⚠️ 注意：需要先登录获取JWT token
    func connectWebSocket(conversationId: String, userId: String) {
        guard let token = client.getAuthToken() else {
            #if DEBUG
            print("[ChatService] WebSocket connection failed: No auth token")
            #endif
            return
        }

        guard UUID(uuidString: conversationId) != nil else {
            #if DEBUG
            print("[ChatService] WebSocket connection failed: Invalid conversationId: \(conversationId)")
            #endif
            return
        }

        guard UUID(uuidString: userId) != nil else {
            #if DEBUG
            print("[ChatService] WebSocket connection failed: Invalid userId: \(userId)")
            #endif
            return
        }

        // 构建WebSocket URL
        let baseURL = APIConfig.current.baseURL.replacingOccurrences(of: "https://", with: "wss://")
                                                .replacingOccurrences(of: "http://", with: "ws://")
        guard var components = URLComponents(string: "\(baseURL)\(APIConfig.Chat.websocket)") else {
            #if DEBUG
            print("[ChatService] WebSocket URL invalid")
            #endif
            return
        }

        components.queryItems = [
            URLQueryItem(name: "conversation_id", value: conversationId),
            URLQueryItem(name: "user_id", value: userId),
        ]

        guard let url = components.url else {
            #if DEBUG
            print("[ChatService] WebSocket URL invalid after adding query params")
            #endif
            return
        }

        // 创建WebSocket请求
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        // 创建WebSocket任务
        let task = URLSession.shared.webSocketTask(with: request)
        task.resume()

        Task {
            await wsStateManager.setTask(task)
            await wsStateManager.setIsConnected(true)
        }

        Task { @MainActor in
            self.onConnectionStatusChanged?(true)
        }

        #if DEBUG
        print("[ChatService] WebSocket connected to \(url)")
        #endif

        // 开始接收消息
        receiveMessage(task: task)
    }

    /// 断开WebSocket连接
    func disconnectWebSocket() {
        Task {
            await wsStateManager.cancelTask()
        }

        Task { @MainActor in
            self.onConnectionStatusChanged?(false)
        }

        #if DEBUG
        print("[ChatService] WebSocket disconnected")
        #endif
    }

    /// 接收WebSocket消息（递归调用）
    private func receiveMessage(task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    Task { await self.handleWebSocketMessage(text) }
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        Task { await self.handleWebSocketMessage(text) }
                    }
                @unknown default:
                    break
                }

                // 继续接收下一条消息
                self.receiveMessage(task: task)

            case .failure(let error):
                #if DEBUG
                print("[ChatService] WebSocket receive error: \(error)")
                #endif

                // 连接断开
                Task {
                    await self.wsStateManager.setIsConnected(false)
                }
                Task { @MainActor in
                    self.onConnectionStatusChanged?(false)
                }
            }
        }
    }

    /// WebSocket typing indicator callback
    @MainActor var onTypingIndicator: ((WebSocketTypingData) -> Void)?
    
    /// WebSocket read receipt callback
    @MainActor var onReadReceipt: ((WebSocketReadReceiptData) -> Void)?
    
    /// Handle incoming WebSocket message
    /// Supports events: message.new, typing.indicator, message.read, connection.established
    private func handleWebSocketMessage(_ text: String) async {
        #if DEBUG
        print("[ChatService] WebSocket message received: \(text.prefix(200))")
        #endif

        guard let data = text.data(using: .utf8) else { return }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601

            // First, try to decode as a typed event with "type" field
            struct EventWrapper: Codable {
                let type: String
            }
            
            if let wrapper = try? decoder.decode(EventWrapper.self, from: data) {
                switch wrapper.type {
                case "message.new":
                    // New message event
                    struct NewMessageEvent: Codable {
                        let type: String
                        let data: WebSocketNewMessageData
                    }
                    let event = try decoder.decode(NewMessageEvent.self, from: data)
                    let message = Message(
                        id: event.data.id,
                        conversationId: event.data.conversationId,
                        senderId: event.data.senderId,
                        content: "", // Encrypted content needs decryption
                        type: ChatMessageType(rawValue: event.data.messageType) ?? .text,
                        createdAt: event.data.createdAt,
                        status: .delivered,
                        encryptedContent: event.data.encryptedContent,
                        nonce: event.data.nonce
                    )
                    await MainActor.run {
                        self.onMessageReceived?(message)
                    }
                    
                case "typing.indicator":
                    // Typing indicator event
                    struct TypingEvent: Codable {
                        let type: String
                        let data: WebSocketTypingData
                    }
                    let event = try decoder.decode(TypingEvent.self, from: data)
                    await MainActor.run {
                        self.onTypingIndicator?(event.data)
                    }
                    
                case "message.read":
                    // Read receipt event
                    struct ReadEvent: Codable {
                        let type: String
                        let data: WebSocketReadReceiptData
                    }
                    let event = try decoder.decode(ReadEvent.self, from: data)
                    await MainActor.run {
                        self.onReadReceipt?(event.data)
                    }
                    
                case "connection.established":
                    // Connection established - no action needed
                    #if DEBUG
                    print("[ChatService] WebSocket connection established")
                    #endif
                    
                default:
                    #if DEBUG
                    print("[ChatService] Unknown WebSocket event type: \(wrapper.type)")
                    #endif
                }
            } else {
                // Fallback: try to decode as a Message directly (legacy format)
                let message = try decoder.decode(Message.self, from: data)
                await MainActor.run {
                    self.onMessageReceived?(message)
                }
            }
        } catch {
            #if DEBUG
            print("[ChatService] Failed to decode WebSocket message: \(error)")
            #endif
        }
    }
    
    // MARK: - Matrix SDK - Typing Indicators

    /// 發送打字開始指示器 - 優先使用 Matrix SDK
    /// - Parameter conversationId: 會話 ID
    func sendTypingStart(conversationId: String) {
        Task {
            // 優先使用 Matrix SDK
            if await MainActor.run(body: { MatrixBridgeService.shared.isInitialized }) {
                do {
                    try await MatrixBridgeService.shared.setTyping(conversationId: conversationId, isTyping: true)
                    #if DEBUG
                    print("[ChatService] ✅ Typing start sent via Matrix SDK")
                    #endif
                    return
                } catch {
                    #if DEBUG
                    print("[ChatService] Matrix typing start failed, falling back to WebSocket: \(error)")
                    #endif
                }
            }

            // Fallback: WebSocket
            guard await wsStateManager.getIsConnected(),
                  let task = await wsStateManager.getTask() else { return }

            let event = TypingStartEvent(data: TypingEventData(conversationId: conversationId))

            do {
                let encoder = JSONEncoder()
                encoder.keyEncodingStrategy = .convertToSnakeCase
                let data = try encoder.encode(event)
                if let text = String(data: data, encoding: .utf8) {
                    try await task.send(.string(text))
                }
            } catch {
                #if DEBUG
                print("[ChatService] Failed to send typing.start via WebSocket: \(error)")
                #endif
            }
        }
    }

    /// 發送打字停止指示器 - 優先使用 Matrix SDK
    /// - Parameter conversationId: 會話 ID
    func sendTypingStop(conversationId: String) {
        Task {
            // 優先使用 Matrix SDK
            if await MainActor.run(body: { MatrixBridgeService.shared.isInitialized }) {
                do {
                    try await MatrixBridgeService.shared.setTyping(conversationId: conversationId, isTyping: false)
                    #if DEBUG
                    print("[ChatService] ✅ Typing stop sent via Matrix SDK")
                    #endif
                    return
                } catch {
                    #if DEBUG
                    print("[ChatService] Matrix typing stop failed, falling back to WebSocket: \(error)")
                    #endif
                }
            }

            // Fallback: WebSocket
            guard await wsStateManager.getIsConnected(),
                  let task = await wsStateManager.getTask() else { return }

            let event = TypingStopEvent(data: TypingEventData(conversationId: conversationId))

            do {
                let encoder = JSONEncoder()
                encoder.keyEncodingStrategy = .convertToSnakeCase
                let data = try encoder.encode(event)
                if let text = String(data: data, encoding: .utf8) {
                    try await task.send(.string(text))
                }
            } catch {
                #if DEBUG
                print("[ChatService] Failed to send typing.stop via WebSocket: \(error)")
                #endif
            }
        }
    }

    // MARK: - Message Reactions (delegated to ChatReactionsService)

    @MainActor
    func addReaction(conversationId: String, messageId: String, emoji: String) async throws {
        try await reactionsService.addReaction(conversationId: conversationId, messageId: messageId, emoji: emoji)
    }

    @MainActor
    func toggleReaction(conversationId: String, messageId: String, emoji: String) async throws {
        try await reactionsService.toggleReaction(conversationId: conversationId, messageId: messageId, emoji: emoji)
    }

    @MainActor
    func getReactions(conversationId: String, messageId: String) async throws -> GetReactionsResponse {
        try await reactionsService.getReactions(conversationId: conversationId, messageId: messageId)
    }

    @MainActor
    func deleteReaction(conversationId: String, messageId: String, reactionId: String) async throws {
        try await reactionsService.deleteReaction(conversationId: conversationId, messageId: messageId, reactionId: reactionId)
    }

    // MARK: - Deprecated Reaction Methods (delegated)

    @available(*, deprecated, message: "Use addReaction(conversationId:messageId:emoji:) instead")
    @MainActor
    func addReaction(messageId: String, emoji: String) async throws -> MessageReaction {
        try await reactionsService.addReaction(messageId: messageId, emoji: emoji)
    }

    @available(*, deprecated, message: "Use getReactions(conversationId:messageId:) instead")
    @MainActor
    func getReactions(messageId: String) async throws -> GetReactionsResponse {
        try await reactionsService.getReactions(messageId: messageId)
    }

    @available(*, deprecated, message: "Use deleteReaction(conversationId:messageId:reactionId:) instead")
    @MainActor
    func deleteReaction(messageId: String, reactionId: String) async throws {
        try await reactionsService.deleteReaction(messageId: messageId, reactionId: reactionId)
    }

    // MARK: - Group Management (delegated to ChatGroupService)

    @MainActor
    func addGroupMembers(conversationId: String, userIds: [String]) async throws {
        try await groupService.addGroupMembers(conversationId: conversationId, userIds: userIds)
    }

    @MainActor
    func removeGroupMember(conversationId: String, userId: String, reason: String? = nil) async throws {
        try await groupService.removeGroupMember(conversationId: conversationId, userId: userId, reason: reason)
    }

    @MainActor
    func updateMemberRole(conversationId: String, userId: String, role: GroupMemberRole) async throws {
        try await groupService.updateMemberRole(conversationId: conversationId, userId: userId, role: role)
    }

    // MARK: - Voice/Video Calls (delegated to ChatCallService)

    @MainActor
    func initiateCall(conversationId: String, isVideo: Bool) async throws -> CallResponse {
        try await callService.initiateCall(conversationId: conversationId, isVideo: isVideo)
    }

    @MainActor
    func answerCall(callId: String) async throws {
        try await callService.answerCall(callId: callId)
    }

    @MainActor
    func rejectCall(callId: String) async throws {
        try await callService.rejectCall(callId: callId)
    }

    @MainActor
    func endCall(callId: String) async throws {
        try await callService.endCall(callId: callId)
    }

    @MainActor
    func sendIceCandidate(callId: String, candidate: String) async throws {
        try await callService.sendIceCandidate(callId: callId, candidate: candidate)
    }

    @MainActor
    func getIceServers() async throws -> IceServersResponse {
        try await callService.getIceServers()
    }

    // MARK: - Location Sharing (delegated to ChatLocationService)

    @MainActor
    func shareLocation(
        conversationId: String,
        latitude: Double,
        longitude: Double,
        accuracy: Double? = nil
    ) async throws {
        try await locationService.shareLocation(conversationId: conversationId, latitude: latitude, longitude: longitude, accuracy: accuracy)
    }

    @MainActor
    func stopSharingLocation(conversationId: String) async throws {
        try await locationService.stopSharingLocation(conversationId: conversationId)
    }

    @MainActor
    func getNearbyUsers(
        latitude: Double,
        longitude: Double,
        radius: Int = 1000
    ) async throws -> NearbyUsersResponse {
        try await locationService.getNearbyUsers(latitude: latitude, longitude: longitude, radius: radius)
    }

    // MARK: - Cleanup

    deinit {
        // Actor-based cleanup handled asynchronously
        // Note: Cannot await in deinit, but disconnectWebSocket() will handle cleanup
        // If needed, call disconnectWebSocket() explicitly before releasing ChatService
    }
}

