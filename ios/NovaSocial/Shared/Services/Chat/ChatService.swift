import Foundation

// MARK: - Chat Service

/// Chat Service - 聊天消息服务
/// 职责：
/// - 发送/接收消息（REST API）
/// - 实时消息推送（WebSocket）
/// - 消息历史管理
/// - 会话管理
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

    // MARK: - Initialization

    init() {
        // Try to initialize E2EE service
        do {
            self.e2eeService = try E2EEService()
        } catch {
            #if DEBUG
            print("[ChatService] E2EE not available: \(error)")
            #endif
            self.e2eeService = nil
        }
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
        let request = SendMessageRequest(
            conversationId: conversationId,
            content: content,
            type: type,
            mediaUrl: mediaUrl,
            replyToId: replyToId
        )

        let message: Message = try await client.request(
            endpoint: APIConfig.Chat.sendMessage,
            method: "POST",
            body: request
        )

        #if DEBUG
        print("[ChatService] Message sent: \(message.id)")
        #endif

        return message
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

    /// 创建新会话
    /// - Parameters:
    ///   - type: 会话类型（单聊/群聊）
    ///   - participants: 参与者用户ID列表
    ///   - name: 会话名称（群聊时必填）
    /// - Returns: 创建的会话对象
    @MainActor
    func createConversation(
        type: ConversationType,
        participants: [String],
        name: String? = nil
    ) async throws -> Conversation {
        let request = CreateConversationRequest(
            type: type,
            participants: participants,
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

    /// 获取所有会话列表
    /// - Returns: 会话列表
    @MainActor
    func getConversations() async throws -> [Conversation] {
        let conversations: [Conversation] = try await client.get(
            endpoint: APIConfig.Chat.getConversations
        )

        #if DEBUG
        print("[ChatService] Fetched \(conversations.count) conversations")
        #endif

        return conversations
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
              let sessionId = message.sessionId else {
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
        let baseURL = APIConfig.current.baseURL.replacingOccurrences(of: "http://", with: "ws://")
                                                .replacingOccurrences(of: "https://", with: "wss://")
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

    /// 处理接收到的WebSocket消息
    private func handleWebSocketMessage(_ text: String) async {
        #if DEBUG
        print("[ChatService] WebSocket message received: \(text.prefix(100))")
        #endif

        // 解析JSON消息
        guard let data = text.data(using: .utf8) else { return }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601

            let message = try decoder.decode(Message.self, from: data)

            // 回调通知新消息
            await MainActor.run {
                self.onMessageReceived?(message)
            }
        } catch {
            #if DEBUG
            print("[ChatService] Failed to decode WebSocket message: \(error)")
            #endif
        }
    }

    // MARK: - Cleanup

    deinit {
        // 简单取消WebSocket任务，不调用@MainActor方法
        webSocketTask?.cancel(with: .goingAway, reason: nil)
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
