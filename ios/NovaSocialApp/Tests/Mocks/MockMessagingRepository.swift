import Foundation
@testable import NovaSocial

/// MockMessagingRepository - 用于测试的消息存储库模拟
/// 提供消息发送、历史加载等功能的模拟实现
final class MockMessagingRepository {

    // MARK: - Properties

    /// 模拟发送的消息记录
    var sentMessages: [(conversationId: UUID, to: UUID, text: String, idempotencyKey: String)] = []

    /// 模拟历史消息
    var mockHistoryResponse: GetHistoryResponse?

    /// 模拟公钥获取
    var mockPublicKeys: [UUID: String] = [:]

    /// 是否应该模拟网络错误
    var shouldFailSendMessage = false
    var sendMessageError: Error?

    var shouldFailGetHistory = false
    var getHistoryError: Error?

    var shouldFailGetPublicKey = false
    var getPublicKeyError: Error?

    // MARK: - Methods

    /// 模拟发送文本消息
    func sendText(
        conversationId: UUID,
        to: UUID,
        text: String,
        idempotencyKey: String
    ) async throws -> UUID {
        if shouldFailSendMessage {
            throw sendMessageError ?? NSError(domain: "MockError", code: -1)
        }

        sentMessages.append((conversationId, to, text, idempotencyKey))
        return UUID()
    }

    /// 模拟加载聊天历史
    func getHistory(conversationId: UUID) async throws -> GetHistoryResponse {
        if shouldFailGetHistory {
            throw getHistoryError ?? NSError(domain: "MockError", code: -1)
        }

        return mockHistoryResponse ?? GetHistoryResponse(messages: [])
    }

    /// 模拟获取公钥
    func getPublicKey(of userId: UUID) async throws -> String {
        if shouldFailGetPublicKey {
            throw getPublicKeyError ?? NSError(domain: "MockError", code: -1)
        }

        return mockPublicKeys[userId] ?? "mock-public-key-\(userId.uuidString)"
    }

    /// 模拟上传公钥
    func uploadMyPublicKeyIfNeeded() async throws {
        // 模拟操作，不做任何事
    }

    /// 模拟消息解密
    func decryptMessage(_ message: MessageDto, senderPublicKey: String) throws -> String {
        // 简单的模拟实现，直接返回原文本（在真实实现中会解密）
        return message.ciphertext
    }

    /// 清除发送记录（用于测试重置）
    func clearSentMessages() {
        sentMessages.removeAll()
    }

    /// 获取已发送的消息数量
    var sentMessageCount: Int {
        sentMessages.count
    }

    /// 检查是否已发送特定消息
    func hasSentMessage(with idempotencyKey: String) -> Bool {
        sentMessages.contains { $0.idempotencyKey == idempotencyKey }
    }
}

// MARK: - Mock Types

/// 模拟的历史消息响应
struct GetHistoryResponse {
    let messages: [MessageDto]
}

/// 模拟的消息 DTO
struct MessageDto: Codable, Equatable {
    let id: UUID
    let conversationId: UUID
    let senderId: UUID
    let ciphertext: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case ciphertext
        case createdAt = "created_at"
    }
}

// MARK: - Mock ChatSocket

/// MockChatSocket - 用于测试的 WebSocket 模拟
final class MockChatSocket {

    // MARK: - Callbacks

    var onMessageNew: ((UUID, UUID, String, Date) -> Void)?
    var onTyping: ((UUID) -> Void)?
    var onError: ((Error) -> Void)?

    // MARK: - Properties

    var isConnected = false
    var sentTypingCount = 0

    // MARK: - Methods

    func connect(conversationId: UUID, meUserId: UUID, jwtToken: String?, peerPublicKeyB64: String) {
        isConnected = true
    }

    func disconnect() {
        isConnected = false
    }

    func sendTyping() {
        sentTypingCount += 1
    }

    /// 模拟接收消息
    func simulateReceiveMessage(senderId: UUID, messageId: UUID, text: String, createdAt: Date? = nil) {
        onMessageNew?(senderId, messageId, text, createdAt ?? Date())
    }

    /// 模拟接收 typing 事件
    func simulateTyping(userId: UUID) {
        onTyping?(userId)
    }

    /// 模拟接收错误
    func simulateError(_ error: Error) {
        onError?(error)
    }
}

// MARK: - Mock AuthManager

final class MockAuthManager {

    static let shared = MockAuthManager()

    var accessToken: String?
    var currentUser: MockUser?

    struct MockUser {
        let id: UUID
        let name: String
    }
}

// MARK: - Mock CryptoKeyStore

final class MockCryptoKeyStore {

    static let shared = MockCryptoKeyStore()

    func ensureKeyPair() throws -> String {
        return "mock-key-pair"
    }
}
