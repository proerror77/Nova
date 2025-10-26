import Foundation

/// Represents a message in a conversation
struct Message: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let conversationId: String
    let senderId: String
    let senderName: String
    let senderAvatar: String?
    let content: String
    let messageType: String? // "text", "audio", "image", etc.
    let sequenceNumber: Int
    let createdAt: String
    let updatedAt: String?
    let recalledAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case senderName = "sender_name"
        case senderAvatar = "sender_avatar"
        case content
        case messageType = "message_type"
        case sequenceNumber = "sequence_number"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case recalledAt = "recalled_at"
    }

    init(
        id: String,
        conversationId: String,
        senderId: String,
        senderName: String,
        senderAvatar: String? = nil,
        content: String,
        messageType: String? = "text",
        sequenceNumber: Int,
        createdAt: String,
        updatedAt: String? = nil,
        recalledAt: String? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.senderName = senderName
        self.senderAvatar = senderAvatar
        self.content = content
        self.messageType = messageType
        self.sequenceNumber = sequenceNumber
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.recalledAt = recalledAt
    }

    /// Check if message is recalled
    var isRecalled: Bool {
        recalledAt != nil
    }
}

/// Request to send a message
struct SendMessageRequest: Codable, Sendable {
    let content: String

    init(content: String) {
        self.content = content
    }
}

/// Response from sending a message
struct SendMessageResponse: Codable, Sendable, Identifiable {
    let id: String
    let sequenceNumber: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case sequenceNumber = "sequence_number"
        case createdAt = "created_at"
    }
}

/// Search result for messages
struct MessageSearchResult: Codable, Sendable, Identifiable {
    let id: String
    let content: String
    let senderId: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case content
        case senderId = "sender_id"
        case createdAt = "created_at"
    }
}
