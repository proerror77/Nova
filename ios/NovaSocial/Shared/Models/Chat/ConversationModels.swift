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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(ConversationType.self, forKey: .type)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        participants = try container.decodeIfPresent([String].self, forKey: .participants) ?? []
        lastMessage = try container.decodeIfPresent(LastMessage.self, forKey: .lastMessage)
        createdAt = try decodeFlexibleDate(container, key: .createdAt)
        updatedAt = try decodeFlexibleDate(container, key: .updatedAt)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        unreadCount = try container.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        senderId = try container.decodeIfPresent(String.self, forKey: .senderId) ?? ""
        timestamp = try decodeFlexibleDate(container, key: .timestamp)
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        // Backend有時缺少 conversation_id，容錯為空字串以免整個列表解碼失敗
        conversationId = try container.decodeIfPresent(String.self, forKey: .conversationId) ?? ""
        senderId = try container.decode(String.self, forKey: .senderId)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        type = try container.decode(ChatMessageType.self, forKey: .type)
        createdAt = try decodeFlexibleDate(container, key: .createdAt)
        isEdited = try container.decodeIfPresent(Bool.self, forKey: .isEdited) ?? false
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        mediaUrl = try container.decodeIfPresent(String.self, forKey: .mediaUrl)
        replyToId = try container.decodeIfPresent(String.self, forKey: .replyToId)
        encryptionVersion = try container.decodeIfPresent(Int.self, forKey: .encryptionVersion)
        encryptedContent = try container.decodeIfPresent(String.self, forKey: .encryptedContent)
        nonce = try container.decodeIfPresent(String.self, forKey: .nonce)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        senderDeviceId = try container.decodeIfPresent(String.self, forKey: .senderDeviceId)
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        conversationId = try container.decode(String.self, forKey: .conversationId)
        senderId = try container.decode(String.self, forKey: .senderId)
        createdAt = try decodeFlexibleDate(container, key: .createdAt)
        sequenceNumber = try container.decode(Int64.self, forKey: .sequenceNumber)
    }
}

// MARK: - Message Reactions

/// Represents a reaction to a message (emoji reaction)
struct MessageReaction: Identifiable, Codable, Sendable {
    let id: String
    let messageId: String
    let userId: String
    let emoji: String  // e.g., "👍", "❤️", "😂"
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case messageId = "message_id"
        case userId = "user_id"
        case emoji
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        messageId = try container.decode(String.self, forKey: .messageId)
        userId = try container.decode(String.self, forKey: .userId)
        emoji = try container.decode(String.self, forKey: .emoji)
        createdAt = try decodeFlexibleDate(container, key: .createdAt)
    }
}

// MARK: - Flexible Date Decoding Helper

/// Allows decoding dates from either ISO8601 strings or Unix epoch (seconds)
private func decodeFlexibleDate<K: CodingKey>(_ container: KeyedDecodingContainer<K>, key: K) throws -> Date {
    // If field is missing entirely, fall back to now to avoid blocking UI
    if !container.contains(key) {
#if DEBUG
        print("[decodeFlexibleDate] key missing for \(key.stringValue); defaulting to now()")
#endif
        return Date()
    }

    if let seconds = try? container.decode(Double.self, forKey: key) {
        return Date(timeIntervalSince1970: seconds)
    }
    var stringDecodeError: Error?
    var dateString: String?
    do {
        dateString = try container.decode(String.self, forKey: key)
    } catch {
        stringDecodeError = error
    }
    if var dateString = dateString {
#if DEBUG
        print("[decodeFlexibleDate] raw value for \(key.stringValue): \(dateString)")
#endif
        // Clean up whitespace or duplicated timezone suffixes that occasionally appear from backend
        dateString = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        if dateString.hasSuffix("Z"), dateString.contains("+") {
            dateString.removeLast() // Handle "+00:00Z" style strings
        }

        // Try ISO8601 with and without fractional seconds (explicitly keep timezone colon)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withColonSeparatorInTimeZone]
        if let d = iso.date(from: dateString) {
            return d
        }
        iso.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        if let d = iso.date(from: dateString) {
            return d
        }
        // Fallback: common RFC3339 patterns with offset like "+00:00"
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd HH:mm:ss Z"
        ]
        for fmt in formats {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = fmt
            if let d = df.date(from: dateString) {
                return d
            }
        }
    }
#if DEBUG
    if let stringDecodeError {
        print("[decodeFlexibleDate] decode(String) error for \(key.stringValue): \(stringDecodeError)")
    }
    print("[decodeFlexibleDate] failed to parse value for \(key.stringValue)")
#endif
    // Fail-soft to avoid breaking UI when backend date format is unexpected
    return Date()
}

/// Request to add a reaction to a message
struct AddReactionRequest: Codable, Sendable {
    let emoji: String
}

/// Response when getting reactions for a message
struct GetReactionsResponse: Codable, Sendable {
    let reactions: [MessageReaction]
    let totalCount: Int

    enum CodingKeys: String, CodingKey {
        case reactions
        case totalCount = "total_count"
    }
}

// MARK: - Group Management

/// Request to add members to a group conversation
struct AddGroupMembersRequest: Codable, Sendable {
    let userIds: [String]

    enum CodingKeys: String, CodingKey {
        case userIds = "user_ids"
    }
}

/// Request to update a member's role in a group
struct UpdateMemberRoleRequest: Codable, Sendable {
    let role: GroupMemberRole
}

/// Group member role
enum GroupMemberRole: String, Codable, Sendable {
    case owner = "owner"
    case admin = "admin"
    case member = "member"
}

/// Request to update conversation details
struct UpdateConversationRequest: Codable, Sendable {
    let name: String?
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case name
        case avatarUrl = "avatar_url"
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
