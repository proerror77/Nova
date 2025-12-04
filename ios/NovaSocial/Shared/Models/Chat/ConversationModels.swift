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

    // E2EE fields
    var encryptionVersion: Int?
    var encryptedContent: String?  // Base64-encoded ciphertext (includes tag)
    var nonce: String?  // Base64-encoded nonce (12 bytes for ChaCha20-Poly1305)
    var sessionId: String?
    var senderDeviceId: String?

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
        case encryptionVersion = "encryption_version"
        case encryptedContent = "encrypted_content"
        case nonce
        case sessionId = "session_id"
        case senderDeviceId = "sender_device_id"
    }

    /// Convenience initializer for creating E2EE messages locally
    init(
        id: String,
        conversationId: String,
        senderId: String,
        content: String,
        type: ChatMessageType,
        createdAt: Date,
        status: MessageStatus = .sent,
        encryptedContent: String? = nil,
        nonce: String? = nil,
        sessionId: String? = nil,
        senderDeviceId: String? = nil,
        encryptionVersion: Int? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.content = content
        self.type = type
        self.createdAt = createdAt
        self.isEdited = false
        self.isDeleted = false
        self.status = status
        self.encryptedContent = encryptedContent
        self.nonce = nonce
        self.sessionId = sessionId
        self.senderDeviceId = senderDeviceId
        self.encryptionVersion = encryptionVersion
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

/// Request to send a message (REST API body for POST /api/v2/chat/messages)
struct SendMessageRequest: Codable, Sendable {
    let conversationId: String
    let content: String
    let messageType: Int
    let mediaUrl: String?
    let replyToMessageId: String?

    enum CodingKeys: String, CodingKey {
        case content
        case messageType = "message_type"
        case mediaUrl = "media_url"
        case replyToMessageId = "reply_to_message_id"
        case conversationId = "conversation_id"
    }

    init(
        conversationId: String,
        content: String,
        type: ChatMessageType,
        mediaUrl: String?,
        replyToId: String?
    ) {
        self.conversationId = conversationId
        self.content = content
        self.mediaUrl = mediaUrl
        self.replyToMessageId = replyToId

        switch type {
        case .text: self.messageType = 0
        case .image: self.messageType = 1
        case .video: self.messageType = 2
        case .audio: self.messageType = 3
        case .file: self.messageType = 4
        case .location: self.messageType = 5
        }
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

// MARK: - E2EE Message Request/Response

/// Request to send an E2EE encrypted message
/// Maps to backend WebSocket send_e2ee_message event
struct SendE2EEMessageRequest: Codable, Sendable {
    let conversationId: String
    let ciphertext: String
    let nonce: String  // Base64-encoded nonce (12 bytes)
    let sessionId: String
    let messageIndex: UInt32
    let deviceId: String
    let messageType: Int
    let replyToMessageId: String?

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case ciphertext
        case nonce
        case sessionId = "session_id"
        case messageIndex = "message_index"
        case deviceId = "device_id"
        case messageType = "message_type"
        case replyToMessageId = "reply_to_message_id"
    }
}

/// Response from sending an E2EE encrypted message
/// Maps to backend SendE2EEMessageResponse
struct SendE2EEMessageResponse: Codable, Sendable {
    let id: String
    let conversationId: String
    let senderId: String
    let createdAt: Date
    let sequenceNumber: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case createdAt = "created_at"
        case sequenceNumber = "sequence_number"
    }
}

// MARK: - Chat Errors

enum ChatError: LocalizedError {
    case e2eeNotAvailable
    case noDeviceId
    case invalidCiphertext
    case decryptionFailed
    case invalidConversationId

    var errorDescription: String? {
        switch self {
        case .e2eeNotAvailable:
            return "E2EE service not available. Device may not be initialized."
        case .noDeviceId:
            return "Device ID not found. Please log in again."
        case .invalidCiphertext:
            return "Invalid encrypted message format."
        case .decryptionFailed:
            return "Failed to decrypt message."
        case .invalidConversationId:
            return "Invalid conversation ID format."
        }
    }
}
