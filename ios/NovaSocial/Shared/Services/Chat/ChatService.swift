import Foundation

// MARK: - Chat Service

/// Chat Service - 聊天消息服务
/// 职责：
/// - 发送/接收消息（REST API）
/// - 实时消息推送（WebSocket）
/// - 消息历史管理
/// - 会话管理
/// - Matrix E2EE integration (when enabled)
@Observable
final class ChatService {
    // MARK: - Properties

    private let client = APIClient.shared

    // WebSocket属性（nonisolated以避免并发问题）
    nonisolated private var webSocketTask: URLSessionWebSocketTask?
    nonisolated private var isConnected = false

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

    // MARK: - REST API - Messages

    /// 发送消息到指定会话
    /// - Parameters:
    ///   - conversationId: 会话ID
    ///   - content: 消息内容
    ///   - type: 消息类型（默认为文本）
    ///   - mediaUrl: 媒体URL（可选）
    ///   - replyToId: 回复的消息ID（可选）
    /// - Returns: 发送后的消息对象
    @MainActor
    func sendMessage(
        conversationId: String,
        content: String,
        type: ChatMessageType = .text,
        mediaUrl: String? = nil,
        replyToId: String? = nil
    ) async throws -> Message {
        struct SendMessageAPIResponse: Codable {
            let id: String?
            let messageId: String?
            let conversationId: String?
            let timestamp: TimeInterval?
            let status: String?
        }

        let request = SendMessageRequest(
            conversationId: conversationId,
            content: content,
            type: type,
            mediaUrl: mediaUrl,
            replyToId: replyToId
        )

        let response: SendMessageAPIResponse = try await client.request(
            endpoint: APIConfig.Chat.sendMessage,
            method: "POST",
            body: request
        )

        let messageId = response.id ?? response.messageId ?? UUID().uuidString
        let createdAt = response.timestamp.map { Date(timeIntervalSince1970: $0) } ?? Date()
        let senderId = AuthenticationManager.shared.currentUser?.id ?? ""

        let message = Message(
            id: messageId,
            conversationId: conversationId,
            senderId: senderId,
            content: content,
            type: type,
            createdAt: createdAt,
            status: .sent
        )

        #if DEBUG
        print("[ChatService] Message sent: \(message.id)")
        #endif

        return message
    }

    /// Send message with automatic E2EE via Matrix (if available)
    /// Falls back to regular API if Matrix bridge is not initialized
    /// - Parameters:
    ///   - conversationId: 会话ID
    ///   - content: 消息内容
    ///   - type: 消息类型（默认为文本）
    ///   - mediaUrl: 媒体URL（可选）
    ///   - replyToId: 回复的消息ID（可选）
    ///   - preferE2EE: Prefer E2EE if available (default true)
    /// - Returns: 发送后的消息对象
    @MainActor
    func sendSecureMessage(
        conversationId: String,
        content: String,
        type: ChatMessageType = .text,
        mediaUrl: String? = nil,
        replyToId: String? = nil,
        preferE2EE: Bool = true
    ) async throws -> Message {
        // Use Matrix E2EE if enabled and bridge is initialized
        if preferE2EE && useMatrixE2EE && MatrixBridgeService.shared.isInitialized {
            #if DEBUG
            print("[ChatService] Sending message via Matrix E2EE")
            #endif

            do {
                // Send via Matrix bridge
                let eventId = try await MatrixBridgeService.shared.sendMessage(
                    conversationId: conversationId,
                    content: content
                )

                // Create local message object
                let senderId = AuthenticationManager.shared.currentUser?.id ?? ""
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
            } catch {
                #if DEBUG
                print("[ChatService] Matrix E2EE failed, falling back to REST: \(error)")
                #endif
                // Fall through to regular send
            }
        }

        // Fallback to regular REST API
        return try await sendMessage(
            conversationId: conversationId,
            content: content,
            type: type,
            mediaUrl: mediaUrl,
            replyToId: replyToId
        )
    }

    /// 获取会话消息历史
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
        var queryParams: [String: String] = [
            "conversation_id": conversationId,
            "limit": "\(limit)"
        ]
        if let cursor = cursor {
            // Backend uses before_message_id for pagination
            queryParams["before_message_id"] = cursor
        }

        let response: GetMessagesResponse = try await client.get(
            endpoint: APIConfig.Chat.getMessages,
            queryParams: queryParams
        )

        #if DEBUG
        print("[ChatService] Fetched \(response.messages.count) messages")
        #endif

        return response
    }

    /// 编辑消息
    /// - Parameters:
    ///   - messageId: 消息ID
    ///   - newContent: 新的消息内容
    /// - Returns: 更新后的消息对象
    @MainActor
    func editMessage(messageId: String, newContent: String) async throws -> Message {
        struct EditRequest: Codable {
            let content: String
        }

        let message: Message = try await client.request(
            endpoint: APIConfig.Chat.editMessage(messageId),
            method: "PUT",
            body: EditRequest(content: newContent)
        )

        #if DEBUG
        print("[ChatService] Message edited: \(messageId)")
        #endif

        return message
    }

    /// 删除消息
    /// - Parameter messageId: 消息ID
    @MainActor
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

    /// 撤回消息
    /// - Parameters:
    ///   - conversationId: 会话ID
    ///   - messageId: 消息ID
    @MainActor
    func recallMessage(conversationId: String, messageId: String) async throws {
        struct EmptyResponse: Codable {}

        let _: EmptyResponse = try await client.request(
            endpoint: APIConfig.Chat.recallMessage(conversationId: conversationId, messageId: messageId),
            method: "POST"
        )

        #if DEBUG
        print("[ChatService] Message recalled: \(messageId)")
        #endif
    }

    // MARK: - REST API - Conversations

    /// Create a new conversation (1:1 or group)
    /// Maps to API: POST /api/v1/conversations
    /// - Parameters:
    ///   - type: Conversation type (direct/group)
    ///   - participantIds: User IDs to add to the conversation
    ///   - name: Conversation name (required for groups, null for direct)
    /// - Returns: Created conversation object
    /// - Note: For direct conversations, if one already exists between the same users, 
    ///         the existing conversation is returned (idempotent)
    @MainActor
    func createConversation(
        type: ConversationType,
        participantIds: [String],
        name: String? = nil
    ) async throws -> Conversation {
        let request = CreateConversationRequest(
            type: type,
            participantIds: participantIds,
            name: name
        )

        let conversation: Conversation = try await client.request(
            endpoint: APIConfig.Chat.createConversation,
            method: "POST",
            body: request
        )

        #if DEBUG
        print("[ChatService] Conversation created: \(conversation.id)")
        #endif

        return conversation
    }
    
    /// Legacy method for backwards compatibility
    @MainActor
    func createConversation(
        type: ConversationType,
        participants: [String],
        name: String? = nil
    ) async throws -> Conversation {
        try await createConversation(type: type, participantIds: participants, name: name)
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
    
    /// Mark messages as read in a conversation
    /// Maps to API: POST /api/v1/conversations/:id/read
    /// - Parameters:
    ///   - conversationId: Conversation ID
    ///   - messageId: ID of the last read message
    @MainActor
    func markAsRead(conversationId: String, messageId: String) async throws {
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
        print("[ChatService] Marked as read: conversation=\(conversationId), message=\(messageId)")
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
    func connectWebSocket() {
        guard let token = client.getAuthToken() else {
            #if DEBUG
            print("[ChatService] WebSocket connection failed: No auth token")
            #endif
            return
        }

        // 构建WebSocket URL
        let baseURL = APIConfig.current.baseURL.replacingOccurrences(of: "https://", with: "ws://")
                                                .replacingOccurrences(of: "http://", with: "ws://")
        guard let url = URL(string: "\(baseURL)\(APIConfig.Chat.websocket)") else {
            #if DEBUG
            print("[ChatService] WebSocket URL invalid")
            #endif
            return
        }

        // 创建WebSocket请求
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        // 创建WebSocket任务
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        webSocketTask?.resume()

        isConnected = true

        Task { @MainActor in
            self.onConnectionStatusChanged?(true)
        }

        #if DEBUG
        print("[ChatService] WebSocket connected to \(url)")
        #endif

        // 开始接收消息
        receiveMessage()
    }

    /// 断开WebSocket连接
    func disconnectWebSocket() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false

        Task { @MainActor in
            self.onConnectionStatusChanged?(false)
        }

        #if DEBUG
        print("[ChatService] WebSocket disconnected")
        #endif
    }

    /// 接收WebSocket消息（递归调用）
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
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
                Task { [weak self] in
                    self?.receiveMessage()
                }

            case .failure(let error):
                #if DEBUG
                print("[ChatService] WebSocket receive error: \(error)")
                #endif

                // 连接断开
                Task { @MainActor in
                    self.isConnected = false
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
    
    /// Send typing start event
    /// - Parameter conversationId: Conversation ID
    func sendTypingStart(conversationId: String) {
        guard isConnected, let task = webSocketTask else { return }
        
        let event = TypingStartEvent(data: TypingEventData(conversationId: conversationId))
        
        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let data = try encoder.encode(event)
            if let text = String(data: data, encoding: .utf8) {
                task.send(.string(text)) { error in
                    if let error = error {
                        #if DEBUG
                        print("[ChatService] Failed to send typing.start: \(error)")
                        #endif
                    }
                }
            }
        } catch {
            #if DEBUG
            print("[ChatService] Failed to encode typing.start: \(error)")
            #endif
        }
    }
    
    /// Send typing stop event
    /// - Parameter conversationId: Conversation ID
    func sendTypingStop(conversationId: String) {
        guard isConnected, let task = webSocketTask else { return }
        
        let event = TypingStopEvent(data: TypingEventData(conversationId: conversationId))
        
        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let data = try encoder.encode(event)
            if let text = String(data: data, encoding: .utf8) {
                task.send(.string(text)) { error in
                    if let error = error {
                        #if DEBUG
                        print("[ChatService] Failed to send typing.stop: \(error)")
                        #endif
                    }
                }
            }
        } catch {
            #if DEBUG
            print("[ChatService] Failed to encode typing.stop: \(error)")
            #endif
        }
    }

    // MARK: - Message Reactions

    /// 添加表情回应到消息
    /// - Parameters:
    ///   - messageId: 消息ID
    ///   - emoji: 表情符号（如 "👍", "❤️", "😂"）
    /// - Returns: 创建的表情回应对象
    @MainActor
    func addReaction(messageId: String, emoji: String) async throws -> MessageReaction {
        let request = AddReactionRequest(emoji: emoji)

        let reaction: MessageReaction = try await client.request(
            endpoint: APIConfig.Chat.addReaction(messageId),
            method: "POST",
            body: request
        )

        #if DEBUG
        print("[ChatService] Reaction added: \(emoji) to message \(messageId)")
        #endif

        return reaction
    }

    /// 获取消息的所有表情回应
    /// - Parameter messageId: 消息ID
    /// - Returns: 表情回应列表响应
    @MainActor
    func getReactions(messageId: String) async throws -> GetReactionsResponse {
        let response: GetReactionsResponse = try await client.get(
            endpoint: APIConfig.Chat.getReactions(messageId)
        )

        #if DEBUG
        print("[ChatService] Fetched \(response.reactions.count) reactions for message \(messageId)")
        #endif

        return response
    }

    /// 删除表情回应
    /// - Parameters:
    ///   - messageId: 消息ID
    ///   - reactionId: 表情回应ID
    @MainActor
    func deleteReaction(messageId: String, reactionId: String) async throws {
        struct EmptyResponse: Codable {}

        let _: EmptyResponse = try await client.request(
            endpoint: APIConfig.Chat.deleteReaction(messageId: messageId, reactionId: reactionId),
            method: "DELETE"
        )

        #if DEBUG
        print("[ChatService] Reaction deleted: \(reactionId)")
        #endif
    }

    // MARK: - Group Management

    /// 添加成员到群组会话
    /// - Parameters:
    ///   - conversationId: 会话ID
    ///   - userIds: 要添加的用户ID列表
    @MainActor
    func addGroupMembers(conversationId: String, userIds: [String]) async throws {
        struct Response: Codable {
            let success: Bool
        }

        let request = AddGroupMembersRequest(userIds: userIds)

        let _: Response = try await client.request(
            endpoint: APIConfig.Chat.addGroupMembers(conversationId),
            method: "POST",
            body: request
        )

        #if DEBUG
        print("[ChatService] Added \(userIds.count) members to conversation \(conversationId)")
        #endif
    }

    /// 从群组会话中移除成员
    /// - Parameters:
    ///   - conversationId: 会话ID
    ///   - userId: 要移除的用户ID
    @MainActor
    func removeGroupMember(conversationId: String, userId: String) async throws {
        struct EmptyResponse: Codable {}

        let _: EmptyResponse = try await client.request(
            endpoint: APIConfig.Chat.removeGroupMember(conversationId: conversationId, userId: userId),
            method: "DELETE"
        )

        #if DEBUG
        print("[ChatService] Removed member \(userId) from conversation \(conversationId)")
        #endif
    }

    /// 更新群组成员角色
    /// - Parameters:
    ///   - conversationId: 会话ID
    ///   - userId: 用户ID
    ///   - role: 新角色（owner/admin/member）
    @MainActor
    func updateMemberRole(conversationId: String, userId: String, role: GroupMemberRole) async throws {
        struct Response: Codable {
            let success: Bool
        }

        let request = UpdateMemberRoleRequest(role: role)

        let _: Response = try await client.request(
            endpoint: APIConfig.Chat.updateMemberRole(conversationId: conversationId, userId: userId),
            method: "PUT",
            body: request
        )

        #if DEBUG
        print("[ChatService] Updated role for user \(userId) to \(role.rawValue)")
        #endif
    }

    // MARK: - Voice/Video Calls (WebRTC)

    /// 发起语音或视频通话
    /// - Parameters:
    ///   - conversationId: 会话ID
    ///   - isVideo: 是否为视频通话
    /// - Returns: 通话ID和相关信息
    @MainActor
    func initiateCall(conversationId: String, isVideo: Bool) async throws -> CallResponse {
        struct Request: Codable {
            let isVideo: Bool

            enum CodingKeys: String, CodingKey {
                case isVideo = "is_video"
            }
        }

        let request = Request(isVideo: isVideo)

        let response: CallResponse = try await client.request(
            endpoint: APIConfig.Chat.initiateCall(conversationId),
            method: "POST",
            body: request
        )

        #if DEBUG
        print("[ChatService] Call initiated: \(response.callId), video: \(isVideo)")
        #endif

        return response
    }

    /// 接听通话
    /// - Parameter callId: 通话ID
    @MainActor
    func answerCall(callId: String) async throws {
        struct EmptyRequest: Codable {}
        struct Response: Codable {
            let success: Bool
        }

        let _: Response = try await client.request(
            endpoint: APIConfig.Chat.answerCall(callId),
            method: "POST",
            body: EmptyRequest()
        )

        #if DEBUG
        print("[ChatService] Call answered: \(callId)")
        #endif
    }

    /// 拒绝通话
    /// - Parameter callId: 通话ID
    @MainActor
    func rejectCall(callId: String) async throws {
        struct EmptyRequest: Codable {}
        struct Response: Codable {
            let success: Bool
        }

        let _: Response = try await client.request(
            endpoint: APIConfig.Chat.rejectCall(callId),
            method: "POST",
            body: EmptyRequest()
        )

        #if DEBUG
        print("[ChatService] Call rejected: \(callId)")
        #endif
    }

    /// 结束通话
    /// - Parameter callId: 通话ID
    @MainActor
    func endCall(callId: String) async throws {
        struct EmptyRequest: Codable {}
        struct Response: Codable {
            let success: Bool
        }

        let _: Response = try await client.request(
            endpoint: APIConfig.Chat.endCall(callId),
            method: "POST",
            body: EmptyRequest()
        )

        #if DEBUG
        print("[ChatService] Call ended: \(callId)")
        #endif
    }

    /// 发送 ICE candidate（WebRTC连接建立）
    /// - Parameters:
    ///   - callId: 通话ID
    ///   - candidate: ICE candidate 数据
    @MainActor
    func sendIceCandidate(callId: String, candidate: String) async throws {
        struct Request: Codable {
            let callId: String
            let candidate: String

            enum CodingKeys: String, CodingKey {
                case callId = "call_id"
                case candidate
            }
        }

        struct Response: Codable {
            let success: Bool
        }

        let request = Request(callId: callId, candidate: candidate)

        let _: Response = try await client.request(
            endpoint: APIConfig.Chat.sendIceCandidate,
            method: "POST",
            body: request
        )

        #if DEBUG
        print("[ChatService] ICE candidate sent for call \(callId)")
        #endif
    }

    /// 获取 TURN/STUN 服务器配置（用于 WebRTC）
    /// - Returns: ICE 服务器配置列表
    @MainActor
    func getIceServers() async throws -> IceServersResponse {
        let response: IceServersResponse = try await client.get(
            endpoint: APIConfig.Chat.getIceServers
        )

        #if DEBUG
        print("[ChatService] Fetched \(response.iceServers.count) ICE servers")
        #endif

        return response
    }

    // MARK: - Location Sharing

    /// 分享当前位置到会话
    /// - Parameters:
    ///   - conversationId: 会话ID
    ///   - latitude: 纬度
    ///   - longitude: 经度
    ///   - accuracy: 精度（米）
    @MainActor
    func shareLocation(
        conversationId: String,
        latitude: Double,
        longitude: Double,
        accuracy: Double? = nil
    ) async throws {
        struct Request: Codable {
            let latitude: Double
            let longitude: Double
            let accuracy: Double?
        }

        struct Response: Codable {
            let success: Bool
        }

        let request = Request(latitude: latitude, longitude: longitude, accuracy: accuracy)

        let _: Response = try await client.request(
            endpoint: APIConfig.Chat.shareLocation(conversationId),
            method: "POST",
            body: request
        )

        #if DEBUG
        print("[ChatService] Location shared: \(latitude), \(longitude)")
        #endif
    }

    /// 停止分享位置
    /// - Parameter conversationId: 会话ID
    @MainActor
    func stopSharingLocation(conversationId: String) async throws {
        struct EmptyResponse: Codable {}

        let _: EmptyResponse = try await client.request(
            endpoint: APIConfig.Chat.stopSharingLocation(conversationId),
            method: "DELETE"
        )

        #if DEBUG
        print("[ChatService] Stopped sharing location for conversation \(conversationId)")
        #endif
    }

    /// 获取附近的用户
    /// - Parameters:
    ///   - latitude: 当前纬度
    ///   - longitude: 当前经度
    ///   - radius: 搜索半径（米，默认1000米）
    /// - Returns: 附近用户列表
    @MainActor
    func getNearbyUsers(
        latitude: Double,
        longitude: Double,
        radius: Int = 1000
    ) async throws -> NearbyUsersResponse {
        let response: NearbyUsersResponse = try await client.get(
            endpoint: APIConfig.Chat.getNearbyUsers,
            queryParams: [
                "latitude": String(latitude),
                "longitude": String(longitude),
                "radius": String(radius)
            ]
        )

        #if DEBUG
        print("[ChatService] Found \(response.users.count) nearby users")
        #endif

        return response
    }

    // MARK: - Cleanup

    deinit {
        // 简单取消WebSocket任务，不调用@MainActor方法
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }
}

// MARK: - Call Response Models

/// Response from initiating a call
struct CallResponse: Codable, Sendable {
    let callId: String
    let conversationId: String
    let initiatorId: String
    let isVideo: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case callId = "call_id"
        case conversationId = "conversation_id"
        case initiatorId = "initiator_id"
        case isVideo = "is_video"
        case createdAt = "created_at"
    }
}

/// ICE server configuration for WebRTC
struct IceServer: Codable, Sendable {
    let urls: [String]
    let username: String?
    let credential: String?
}

/// Response containing ICE servers configuration
struct IceServersResponse: Codable, Sendable {
    let iceServers: [IceServer]

    enum CodingKeys: String, CodingKey {
        case iceServers = "ice_servers"
    }
}

// MARK: - Location Response Models

/// Nearby user information
struct NearbyUser: Codable, Sendable {
    let userId: String
    let username: String
    let displayName: String
    let avatarUrl: String?
    let distance: Double  // Distance in meters

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case distance
    }
}

/// Response containing nearby users
struct NearbyUsersResponse: Codable, Sendable {
    let users: [NearbyUser]
    let totalCount: Int

    enum CodingKeys: String, CodingKey {
        case users
        case totalCount = "total_count"
    }
}

// MARK: - Helper Types

/// Wrapper for decoding DeviceIdentity from keychain
/// Matches the DeviceIdentity struct stored by E2EEService
private struct DeviceIdentityWrapper: Codable {
    let deviceId: String
    let publicKey: Data
    let secretKey: Data
    let createdAt: Date
}
