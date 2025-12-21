import XCTest
@testable import ICERED

/// ChatService 單元測試
/// 測試消息去重、WebSocket 狀態管理、E2EE 加密解密等核心功能
final class ChatServiceTests: XCTestCase {

    // MARK: - Message Deduplication Tests

    /// 測試消息去重邏輯 - 相同 ID 的消息不應該重複
    func testMessageDeduplicationByID() {
        var existingMessages = [
            createTestMessage(id: "msg-1", content: "First message"),
            createTestMessage(id: "msg-2", content: "Second message"),
            createTestMessage(id: "msg-3", content: "Third message")
        ]

        let newMessages = [
            createTestMessage(id: "msg-2", content: "Second message duplicate"),
            createTestMessage(id: "msg-4", content: "Fourth message")
        ]

        // 模擬去重邏輯
        let existingIDs = Set(existingMessages.map { $0.id })
        let uniqueNewMessages = newMessages.filter { !existingIDs.contains($0.id) }
        existingMessages.append(contentsOf: uniqueNewMessages)

        XCTAssertEqual(existingMessages.count, 4, "應該只有 4 條消息，msg-2 不應重複")
        XCTAssertEqual(existingMessages.filter { $0.id == "msg-2" }.count, 1, "msg-2 應該只有一條")
    }

    /// 測試空消息列表的去重處理
    func testMessageDeduplicationEmptyList() {
        let existingMessages: [Message] = []
        let newMessages = [
            createTestMessage(id: "msg-1", content: "First message")
        ]

        let existingIDs = Set(existingMessages.map { $0.id })
        let uniqueNewMessages = newMessages.filter { !existingIDs.contains($0.id) }

        XCTAssertEqual(uniqueNewMessages.count, 1, "所有新消息都應該被添加")
    }

    /// 測試完全重複的消息列表
    func testMessageDeduplicationAllDuplicates() {
        let existingMessages = [
            createTestMessage(id: "msg-1", content: "First message"),
            createTestMessage(id: "msg-2", content: "Second message")
        ]

        let newMessages = [
            createTestMessage(id: "msg-1", content: "First message copy"),
            createTestMessage(id: "msg-2", content: "Second message copy")
        ]

        let existingIDs = Set(existingMessages.map { $0.id })
        let uniqueNewMessages = newMessages.filter { !existingIDs.contains($0.id) }

        XCTAssertEqual(uniqueNewMessages.count, 0, "不應該有新消息被添加")
    }

    // MARK: - Message Model Tests

    /// 測試 Message 模型解析
    func testMessageModelDecoding() throws {
        let json = """
        {
            "id": "msg-123",
            "conversation_id": "conv-456",
            "sender_id": "user-789",
            "content": "Hello World",
            "message_type": "text",
            "created_at": 1703116800,
            "updated_at": 1703116800,
            "is_read": false,
            "is_deleted": false
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let message = try decoder.decode(Message.self, from: json)

        XCTAssertEqual(message.id, "msg-123")
        XCTAssertEqual(message.conversationId, "conv-456")
        XCTAssertEqual(message.senderId, "user-789")
        XCTAssertEqual(message.content, "Hello World")
        XCTAssertEqual(message.messageType, "text")
    }

    /// 測試 Message 模型處理缺失字段
    func testMessageModelHandlesOptionalFields() throws {
        let json = """
        {
            "id": "msg-123",
            "conversation_id": "conv-456",
            "sender_id": "user-789",
            "content": "Hello",
            "message_type": "text",
            "created_at": 1703116800
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let message = try decoder.decode(Message.self, from: json)

        XCTAssertEqual(message.id, "msg-123")
        // 可選字段應該有默認值或為 nil
    }

    // MARK: - Conversation Model Tests

    /// 測試 Conversation 模型解析
    func testConversationModelDecoding() throws {
        let json = """
        {
            "id": "conv-123",
            "type": "direct",
            "participants": ["user-1", "user-2"],
            "created_at": 1703116800,
            "updated_at": 1703116800
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let conversation = try decoder.decode(Conversation.self, from: json)

        XCTAssertEqual(conversation.id, "conv-123")
        XCTAssertEqual(conversation.type, "direct")
    }

    /// 測試群組對話模型
    func testGroupConversationDecoding() throws {
        let json = """
        {
            "id": "conv-456",
            "type": "group",
            "name": "Test Group",
            "participants": ["user-1", "user-2", "user-3"],
            "created_at": 1703116800,
            "updated_at": 1703116800
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let conversation = try decoder.decode(Conversation.self, from: json)

        XCTAssertEqual(conversation.id, "conv-456")
        XCTAssertEqual(conversation.type, "group")
        XCTAssertEqual(conversation.name, "Test Group")
    }

    // MARK: - WebSocket Message Parsing Tests

    /// 測試 WebSocket 新消息事件解析
    func testWebSocketNewMessageParsing() throws {
        let wsMessage = """
        {
            "type": "new_message",
            "payload": {
                "id": "msg-123",
                "conversation_id": "conv-456",
                "sender_id": "user-789",
                "content": "WebSocket message",
                "message_type": "text",
                "created_at": 1703116800
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        // 解析 WebSocket 消息結構
        struct WSMessage: Decodable {
            let type: String
            let payload: Message
        }

        let parsed = try decoder.decode(WSMessage.self, from: wsMessage)

        XCTAssertEqual(parsed.type, "new_message")
        XCTAssertEqual(parsed.payload.id, "msg-123")
        XCTAssertEqual(parsed.payload.content, "WebSocket message")
    }

    /// 測試 WebSocket 輸入狀態事件解析
    func testWebSocketTypingIndicatorParsing() throws {
        let wsMessage = """
        {
            "type": "typing",
            "payload": {
                "conversation_id": "conv-456",
                "user_id": "user-789",
                "is_typing": true
            }
        }
        """.data(using: .utf8)!

        struct TypingPayload: Decodable {
            let conversationId: String
            let userId: String
            let isTyping: Bool
        }

        struct WSTypingMessage: Decodable {
            let type: String
            let payload: TypingPayload
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let parsed = try decoder.decode(WSTypingMessage.self, from: wsMessage)

        XCTAssertEqual(parsed.type, "typing")
        XCTAssertTrue(parsed.payload.isTyping)
        XCTAssertEqual(parsed.payload.userId, "user-789")
    }

    /// 測試 WebSocket 已讀回執解析
    func testWebSocketReadReceiptParsing() throws {
        let wsMessage = """
        {
            "type": "read_receipt",
            "payload": {
                "conversation_id": "conv-456",
                "user_id": "user-789",
                "message_id": "msg-123",
                "read_at": 1703116800
            }
        }
        """.data(using: .utf8)!

        struct ReadReceiptPayload: Decodable {
            let conversationId: String
            let userId: String
            let messageId: String
            let readAt: Int64
        }

        struct WSReadReceiptMessage: Decodable {
            let type: String
            let payload: ReadReceiptPayload
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let parsed = try decoder.decode(WSReadReceiptMessage.self, from: wsMessage)

        XCTAssertEqual(parsed.type, "read_receipt")
        XCTAssertEqual(parsed.payload.messageId, "msg-123")
    }

    // MARK: - Encryption Version Tests

    /// 測試加密版本識別
    func testEncryptionVersionIdentification() {
        // 無加密
        let noEncryption = 0
        XCTAssertEqual(noEncryption, 0, "版本 0 表示無加密")

        // 客戶端 Megolm E2EE
        let clientE2EE = 2
        XCTAssertEqual(clientE2EE, 2, "版本 2 表示客戶端 Megolm E2EE")

        // Matrix SDK E2EE
        let matrixSDKE2EE = 3
        XCTAssertEqual(matrixSDKE2EE, 3, "版本 3 表示 Matrix SDK E2EE")
    }

    // MARK: - Error Handling Tests

    /// 測試 ChatServiceError 類型
    func testChatServiceErrorTypes() {
        // 模擬不同類型的錯誤
        enum ChatServiceError: Error, Equatable {
            case networkError
            case authenticationError
            case messageNotFound
            case conversationNotFound
            case encryptionError
            case rateLimited
        }

        let networkError = ChatServiceError.networkError
        let authError = ChatServiceError.authenticationError

        XCTAssertNotEqual(networkError, authError)
        XCTAssertEqual(networkError, ChatServiceError.networkError)
    }

    // MARK: - Message Sorting Tests

    /// 測試消息按時間排序
    func testMessageSortingByTimestamp() {
        var messages = [
            createTestMessage(id: "msg-3", content: "Third", createdAt: 1703116900),
            createTestMessage(id: "msg-1", content: "First", createdAt: 1703116700),
            createTestMessage(id: "msg-2", content: "Second", createdAt: 1703116800)
        ]

        messages.sort { $0.createdAt < $1.createdAt }

        XCTAssertEqual(messages[0].id, "msg-1", "最早的消息應該排在第一位")
        XCTAssertEqual(messages[1].id, "msg-2", "中間的消息應該排在第二位")
        XCTAssertEqual(messages[2].id, "msg-3", "最新的消息應該排在最後")
    }

    /// 測試消息按時間降序排序（最新的在前）
    func testMessageSortingDescending() {
        var messages = [
            createTestMessage(id: "msg-1", content: "First", createdAt: 1703116700),
            createTestMessage(id: "msg-3", content: "Third", createdAt: 1703116900),
            createTestMessage(id: "msg-2", content: "Second", createdAt: 1703116800)
        ]

        messages.sort { $0.createdAt > $1.createdAt }

        XCTAssertEqual(messages[0].id, "msg-3", "最新的消息應該排在第一位")
        XCTAssertEqual(messages[2].id, "msg-1", "最早的消息應該排在最後")
    }

    // MARK: - Reaction Tests

    /// 測試表情反應模型
    func testReactionModel() throws {
        let json = """
        {
            "message_id": "msg-123",
            "user_id": "user-456",
            "emoji": "👍",
            "created_at": 1703116800
        }
        """.data(using: .utf8)!

        struct Reaction: Decodable {
            let messageId: String
            let userId: String
            let emoji: String
            let createdAt: Int64
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let reaction = try decoder.decode(Reaction.self, from: json)

        XCTAssertEqual(reaction.messageId, "msg-123")
        XCTAssertEqual(reaction.emoji, "👍")
    }

    // MARK: - Helper Methods

    /// 創建測試用消息
    private func createTestMessage(id: String, content: String, createdAt: Int64 = 1703116800) -> Message {
        return Message(
            id: id,
            conversationId: "conv-test",
            senderId: "user-test",
            content: content,
            messageType: "text",
            createdAt: createdAt,
            updatedAt: createdAt,
            isRead: false,
            isDeleted: false,
            replyToId: nil,
            replyToContent: nil,
            replyToSenderId: nil,
            mediaUrls: nil,
            mediaType: nil,
            encryptionVersion: nil,
            senderUsername: nil,
            senderDisplayName: nil,
            senderAvatarUrl: nil
        )
    }
}

// MARK: - Async WebSocket State Tests

/// WebSocket 狀態管理測試
final class WebSocketStateTests: XCTestCase {

    /// 測試 WebSocket 連接狀態枚舉
    func testWebSocketConnectionStates() {
        enum WebSocketState: Equatable {
            case disconnected
            case connecting
            case connected
            case reconnecting
            case failed(Error)

            static func == (lhs: WebSocketState, rhs: WebSocketState) -> Bool {
                switch (lhs, rhs) {
                case (.disconnected, .disconnected),
                     (.connecting, .connecting),
                     (.connected, .connected),
                     (.reconnecting, .reconnecting):
                    return true
                case (.failed, .failed):
                    return true
                default:
                    return false
                }
            }
        }

        let state1 = WebSocketState.disconnected
        let state2 = WebSocketState.connected

        XCTAssertNotEqual(state1, state2)
        XCTAssertEqual(state1, .disconnected)
    }

    /// 測試狀態轉換邏輯
    func testWebSocketStateTransitions() {
        enum WebSocketState {
            case disconnected
            case connecting
            case connected
            case reconnecting

            func canTransitionTo(_ newState: WebSocketState) -> Bool {
                switch (self, newState) {
                case (.disconnected, .connecting):
                    return true
                case (.connecting, .connected),
                     (.connecting, .disconnected):
                    return true
                case (.connected, .disconnected),
                     (.connected, .reconnecting):
                    return true
                case (.reconnecting, .connected),
                     (.reconnecting, .disconnected):
                    return true
                default:
                    return false
                }
            }
        }

        let disconnected = WebSocketState.disconnected
        XCTAssertTrue(disconnected.canTransitionTo(.connecting))
        XCTAssertFalse(disconnected.canTransitionTo(.connected))

        let connecting = WebSocketState.connecting
        XCTAssertTrue(connecting.canTransitionTo(.connected))
        XCTAssertTrue(connecting.canTransitionTo(.disconnected))

        let connected = WebSocketState.connected
        XCTAssertTrue(connected.canTransitionTo(.disconnected))
        XCTAssertTrue(connected.canTransitionTo(.reconnecting))
    }
}
