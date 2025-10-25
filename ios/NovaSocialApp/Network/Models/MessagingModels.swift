import Foundation

struct MessageDTO: Codable, Identifiable, Equatable {
    let id: UUID
    let conversationId: UUID
    let senderId: UUID
    let encryptedContent: String
    let nonce: String
    let messageType: String
    let createdAt: Date
    let editedAt: Date?
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case encryptedContent = "encrypted_content"
        case nonce
        case messageType = "message_type"
        case createdAt = "created_at"
        case editedAt = "edited_at"
        case deletedAt = "deleted_at"
    }
}

struct MessageHistoryResponseDTO: Codable {
    let messages: [MessageDTO]
    let hasMore: Bool
    let nextCursor: UUID?

    enum CodingKeys: String, CodingKey {
        case messages
        case hasMore = "has_more"
        case nextCursor = "next_cursor"
    }
}

struct SendMessageRequestDTO: Codable {
    let conversationId: UUID
    let encryptedContent: String
    let nonce: String
    let messageType: String
    let searchText: String?

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case encryptedContent = "encrypted_content"
        case nonce
        case messageType = "message_type"
        case searchText = "search_text"
    }
}

struct PublicKeyResponseDTO: Codable { let publicKey: String; enum CodingKeys: String, CodingKey { case publicKey = "public_key" } }

