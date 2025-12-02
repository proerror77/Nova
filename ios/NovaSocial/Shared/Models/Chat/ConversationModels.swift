import Foundation

// MARK: - Conversation Models

/// Represents a chat conversation with another user
/// Maps to backend API: GET /conversations
struct Conversation: Identifiable, Codable, Sendable {
    let id: String
    let type: ConversationType
    let name: String?
    let participants: [String]  // User IDs
    let lastMessage: LastMessage?
    let createdAt: Date
    let updatedAt: Date

    // Optional fields for future expansion
    var avatarUrl: String?
    var unreadCount: Int = 0

    enum CodingKeys: String, CodingKey {
        case id, type, name, participants
        case lastMessage = "last_message"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case avatarUrl = "avatar_url"
        case unreadCount = "unread_count"
    }
}

/// Conversation type
enum ConversationType: String, Codable, Sendable {
    case direct = "direct"      // 1-on-1 chat
    case group = "group"        // Group chat
}

/// Last message preview in conversation list
struct LastMessage: Codable, Sendable {
    let content: String
    let senderId: String
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case content
        case senderId = "sender_id"
        case timestamp
    }
}

// MARK: - Message Models

/// Represents a single message in a conversation
/// Maps to backend API: POST /conversations/{id}/messages
struct Message: Identifiable, Codable, Sendable {
    let id: String
    let conversationId: String
    let senderId: String
    let content: String
    let type: ChatMessageType
    let createdAt: Date
    var isEdited: Bool
    var isDeleted: Bool

    // Optional fields
    var mediaUrl: String?
    var replyToId: String?

    // Local-only fields (not from backend)
    var status: MessageStatus = .sent

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case content, type
        case createdAt = "created_at"
        case isEdited = "is_edited"
        case isDeleted = "is_deleted"
        case mediaUrl = "media_url"
        case replyToId = "reply_to_id"
    }
}

/// Chat message type (renamed from MessageType to avoid conflict with Alice's MessageType)
enum ChatMessageType: String, Codable, Sendable {
    case text = "text"
    case image = "image"
    case video = "video"
    case audio = "audio"
    case file = "file"
    case location = "location"
}

/// Message delivery status (local only)
enum MessageStatus: String, Codable, Sendable {
    case sending    // Message is being sent
    case sent       // Successfully sent to server
    case delivered  // Delivered to recipient
    case read       // Read by recipient
    case failed     // Failed to send
}

// MARK: - API Request/Response Models

/// Request to create a new conversation
struct CreateConversationRequest: Codable, Sendable {
    let type: ConversationType
    let participants: [String]  // User IDs
    let name: String?  // Required for groups
}

/// Request to send a message
struct SendMessageRequest: Codable, Sendable {
    let content: String
    let type: ChatMessageType
    let mediaUrl: String?
    let replyToId: String?

    enum CodingKeys: String, CodingKey {
        case content, type
        case mediaUrl = "media_url"
        case replyToId = "reply_to_id"
    }
}

/// Response when fetching messages
struct GetMessagesResponse: Codable, Sendable {
    let messages: [Message]
    let cursor: String?
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case messages, cursor
        case hasMore = "has_more"
    }
}
