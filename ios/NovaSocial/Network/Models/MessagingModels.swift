import Foundation

// MARK: - Messaging Models (align with backend contract)

struct ConversationResponse: Codable, Sendable {
    let id: UUID
    let memberCount: Int
    let lastMessageId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case memberCount = "member_count"
        case lastMessageId = "last_message_id"
    }
}

struct MessageDto: Codable, Sendable {
    let id: UUID
    let senderId: UUID
    let sequenceNumber: Int64
    let createdAt: String?
    let contentEncrypted: String?
    let contentNonce: String?

    enum CodingKeys: String, CodingKey {
        case id
        case senderId = "sender_id"
        case sequenceNumber = "sequence_number"
        case createdAt = "created_at"
        case contentEncrypted = "content_encrypted"
        case contentNonce = "content_nonce"
    }
}
