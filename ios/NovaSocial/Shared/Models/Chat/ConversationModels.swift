import Foundation
import SwiftUI
import CoreLocation

// MARK: - Conversation Models

/// Represents a chat conversation (1:1 or group)
/// Maps to backend API: GET /api/v1/conversations
/// See: docs/api/messaging-api.md
struct Conversation: Identifiable, Codable, Sendable {
    let id: String
    let type: ConversationType
    let name: String?
    let createdBy: String?
    let createdAt: Date
    let updatedAt: Date
    let members: [ConversationMember]

    // List view specific fields (from GET /conversations)
    let lastMessage: ConversationLastMessage?
    var unreadCount: Int
    var isMuted: Bool
    var isArchived: Bool

    // E2EE status - indicates if this conversation uses Matrix E2EE
    var isEncrypted: Bool

    // Legacy field - kept for backwards compatibility
    var participants: [String] {
        members.map { $0.userId }
    }

    // Optional fields
    var avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, type, name, members
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastMessage = "last_message"
        case unreadCount = "unread_count"
        case isMuted = "is_muted"
        case isArchived = "is_archived"
        case isEncrypted = "is_encrypted"
        case avatarUrl = "avatar_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(ConversationType.self, forKey: .type)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)
        members = try container.decodeIfPresent([ConversationMember].self, forKey: .members) ?? []
        lastMessage = try container.decodeIfPresent(ConversationLastMessage.self, forKey: .lastMessage)
        createdAt = try decodeFlexibleDate(container, key: .createdAt)
        updatedAt = try decodeFlexibleDate(container, key: .updatedAt)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        unreadCount = try container.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        isEncrypted = try container.decodeIfPresent(Bool.self, forKey: .isEncrypted) ?? false
    }
}

/// Conversation member with role information
/// Maps to API response members array
struct ConversationMember: Codable, Sendable, Identifiable {
    var id: String { userId }
    let userId: String
    let username: String
    let role: GroupMemberRole
    let joinedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case role
        case joinedAt = "joined_at"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        role = try container.decodeIfPresent(GroupMemberRole.self, forKey: .role) ?? .member
        joinedAt = try decodeFlexibleDate(container, key: .joinedAt)
    }
}

/// Conversation type
enum ConversationType: String, Codable, Sendable {
    case direct = "direct"      // 1-on-1 chat
    case group = "group"        // Group chat
}

/// Last message preview in conversation list
/// Maps to API response last_message object
struct ConversationLastMessage: Codable, Sendable {
    let id: String
    let senderId: String
    let encryptedContent: String
    let nonce: String
    let createdAt: Date
    
    // Computed property for backwards compatibility
    var content: String { encryptedContent }
    var timestamp: Date { createdAt }

    enum CodingKeys: String, CodingKey {
        case id
        case senderId = "sender_id"
        case encryptedContent = "encrypted_content"
        case nonce
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        senderId = try container.decodeIfPresent(String.self, forKey: .senderId) ?? ""
        encryptedContent = try container.decodeIfPresent(String.self, forKey: .encryptedContent) ?? ""
        nonce = try container.decodeIfPresent(String.self, forKey: .nonce) ?? ""
        createdAt = try decodeFlexibleDate(container, key: .createdAt)
    }
}

/// Legacy LastMessage type for backwards compatibility
typealias LastMessage = ConversationLastMessage

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
        case messageType = "message_type"
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
        // 某些歷史訊息缺少 sender_id，避免整批失敗，默認為空字串
        senderId = try container.decodeIfPresent(String.self, forKey: .senderId) ?? ""
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        // 兼容舊格式 (message_type 整數) 與新格式 (type 字串)
        if let intType = try container.decodeIfPresent(Int.self, forKey: .messageType) {
            switch intType {
            case 0: type = .text
            case 1: type = .image
            case 2: type = .video
            case 3: type = .audio
            case 4: type = .file
            case 5: type = .location
            default: type = .text
            }
        } else if let stringType = try container.decodeIfPresent(String.self, forKey: .type) {
            type = ChatMessageType(rawValue: stringType) ?? .text
        } else {
            type = .text
        }
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(conversationId, forKey: .conversationId)
        try container.encode(senderId, forKey: .senderId)
        try container.encode(content, forKey: .content)
        try container.encode(type.rawValue, forKey: .type)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(isEdited, forKey: .isEdited)
        try container.encode(isDeleted, forKey: .isDeleted)
        try container.encodeIfPresent(mediaUrl, forKey: .mediaUrl)
        try container.encodeIfPresent(replyToId, forKey: .replyToId)
        try container.encodeIfPresent(encryptionVersion, forKey: .encryptionVersion)
        try container.encodeIfPresent(encryptedContent, forKey: .encryptedContent)
        try container.encodeIfPresent(nonce, forKey: .nonce)
        try container.encodeIfPresent(sessionId, forKey: .sessionId)
        try container.encodeIfPresent(senderDeviceId, forKey: .senderDeviceId)
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
        mediaUrl: String? = nil,
        replyToId: String? = nil,
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
        self.mediaUrl = mediaUrl
        self.replyToId = replyToId
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
/// Maps to API: POST /api/v1/conversations
struct CreateConversationRequest: Codable, Sendable {
    let type: ConversationType
    let participantIds: [String]  // User IDs to add
    let name: String?  // Required for groups, null for direct
    
    enum CodingKeys: String, CodingKey {
        case type
        case participantIds = "participant_ids"
        case name
    }
}

/// Conversation settings update request
/// Maps to API: PATCH /api/v1/conversations/:id/settings
struct UpdateConversationSettingsRequest: Codable, Sendable {
    let isMuted: Bool?
    let isArchived: Bool?
    
    enum CodingKeys: String, CodingKey {
        case isMuted = "is_muted"
        case isArchived = "is_archived"
    }
}

/// Conversation settings response
struct ConversationSettingsResponse: Codable, Sendable {
    let isMuted: Bool
    let isArchived: Bool
    
    enum CodingKeys: String, CodingKey {
        case isMuted = "is_muted"
        case isArchived = "is_archived"
    }
}

/// Response for listing conversations
/// Maps to API: GET /api/v1/conversations
struct ListConversationsResponse: Codable, Sendable {
    let conversations: [Conversation]
    let total: Int
    let limit: Int
    let offset: Int
}

/// Request to add members to a group
/// Maps to API: POST /api/v1/conversations/:id/members  
struct AddMembersRequest: Codable, Sendable {
    let userIds: [String]
    
    enum CodingKeys: String, CodingKey {
        case userIds = "user_ids"
    }
}

/// Response when adding members
struct AddMembersResponse: Codable, Sendable {
    let addedMembers: [ConversationMember]
    
    enum CodingKeys: String, CodingKey {
        case addedMembers = "added_members"
    }
}

/// Mark as read request
/// Maps to API: POST /api/v1/conversations/:id/read
struct MarkAsReadRequest: Codable, Sendable {
    let messageId: String
    
    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
    }
}

/// Request to send a message (E2E encrypted)
/// Maps to API: POST /api/v1/messages
struct SendMessageRequest: Codable, Sendable {
    let conversationId: String
    let encryptedContent: String  // Base64-encoded ciphertext
    let nonce: String  // Must be exactly 32 characters (24 bytes base64-encoded)
    let messageType: String  // "text", "image", "video", "audio", "file", "location", or "system"
    let mediaUrl: String?  // Required for image/video/audio/file types

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case encryptedContent = "encrypted_content"
        case nonce
        case messageType = "message_type"
        case mediaUrl = "media_url"
    }

    init(
        conversationId: String,
        encryptedContent: String,
        nonce: String,
        messageType: ChatMessageType = .text,
        mediaUrl: String? = nil
    ) {
        self.conversationId = conversationId
        self.encryptedContent = encryptedContent
        self.nonce = nonce
        self.messageType = messageType.rawValue
        self.mediaUrl = mediaUrl
    }

    /// Legacy convenience initializer for plain text (will be encrypted by caller)
    init(
        conversationId: String,
        content: String,
        type: ChatMessageType,
        mediaUrl: String?,
        replyToId: String?
    ) {
        self.conversationId = conversationId
        // For backwards compatibility - caller should encrypt
        self.encryptedContent = Data(content.utf8).base64EncodedString()
        self.nonce = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==" // Placeholder - should be real nonce
        self.messageType = type.rawValue
        self.mediaUrl = mediaUrl
    }
}

/// Response when fetching messages
/// Maps to API: GET /api/v1/conversations/:id/messages
struct GetMessagesResponse: Codable, Sendable {
    let messages: [Message]
    let hasMore: Bool
    let nextCursor: String?  // Message ID to use as 'before' parameter for next page

    enum CodingKeys: String, CodingKey {
        case messages
        case hasMore = "has_more"
        case nextCursor = "next_cursor"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messages = try container.decodeIfPresent([Message].self, forKey: .messages) ?? []
        hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
        nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
    }
    
    // Legacy alias
    var cursor: String? { nextCursor }
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


// MARK: - WebSocket Event Models

/// Base WebSocket event structure
struct WebSocketEvent: Codable, Sendable {
    let type: String
    let data: WebSocketEventData
}

/// WebSocket event data - union type for different events
enum WebSocketEventData: Codable, Sendable {
    case newMessage(WebSocketNewMessageData)
    case typingIndicator(WebSocketTypingData)
    case readReceipt(WebSocketReadReceiptData)
    case connectionEstablished(WebSocketConnectionData)
    case unknown
    
    enum CodingKeys: String, CodingKey {
        case type
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // Try each type in order
        if let data = try? container.decode(WebSocketNewMessageData.self) {
            self = .newMessage(data)
        } else if let data = try? container.decode(WebSocketTypingData.self) {
            self = .typingIndicator(data)
        } else if let data = try? container.decode(WebSocketReadReceiptData.self) {
            self = .readReceipt(data)
        } else if let data = try? container.decode(WebSocketConnectionData.self) {
            self = .connectionEstablished(data)
        } else {
            self = .unknown
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .newMessage(let data):
            try container.encode(data)
        case .typingIndicator(let data):
            try container.encode(data)
        case .readReceipt(let data):
            try container.encode(data)
        case .connectionEstablished(let data):
            try container.encode(data)
        case .unknown:
            try container.encodeNil()
        }
    }
}

/// New message event data (message.new)
struct WebSocketNewMessageData: Codable, Sendable {
    let id: String
    let conversationId: String
    let senderId: String
    let encryptedContent: String
    let nonce: String
    let messageType: String
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case encryptedContent = "encrypted_content"
        case nonce
        case messageType = "message_type"
        case createdAt = "created_at"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        conversationId = try container.decode(String.self, forKey: .conversationId)
        senderId = try container.decode(String.self, forKey: .senderId)
        encryptedContent = try container.decode(String.self, forKey: .encryptedContent)
        nonce = try container.decode(String.self, forKey: .nonce)
        messageType = try container.decode(String.self, forKey: .messageType)
        createdAt = try decodeFlexibleDate(container, key: .createdAt)
    }
}

/// Typing indicator event data (typing.indicator)
struct WebSocketTypingData: Codable, Sendable {
    let conversationId: String
    let userId: String
    let username: String
    let isTyping: Bool
    
    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case userId = "user_id"
        case username
        case isTyping = "is_typing"
    }
}

/// Read receipt event data (message.read)
struct WebSocketReadReceiptData: Codable, Sendable {
    let conversationId: String
    let userId: String
    let lastReadMessageId: String
    
    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case userId = "user_id"
        case lastReadMessageId = "last_read_message_id"
    }
}

/// Connection established event data
struct WebSocketConnectionData: Codable, Sendable {
    let userId: String
    let connectionId: String
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case connectionId = "connection_id"
    }
}

/// Client → Server: Typing start event
struct TypingStartEvent: Codable, Sendable {
    var type: String { "typing.start" }
    let data: TypingEventData

    enum CodingKeys: String, CodingKey {
        case type, data
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(data, forKey: .data)
    }

    init(data: TypingEventData) {
        self.data = data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.data = try container.decode(TypingEventData.self, forKey: .data)
    }
}

/// Client → Server: Typing stop event
struct TypingStopEvent: Codable, Sendable {
    var type: String { "typing.stop" }
    let data: TypingEventData

    enum CodingKeys: String, CodingKey {
        case type, data
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(data, forKey: .data)
    }

    init(data: TypingEventData) {
        self.data = data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.data = try container.decode(TypingEventData.self, forKey: .data)
    }
}

/// Typing event data for client → server
struct TypingEventData: Codable, Sendable {
    let conversationId: String
    
    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
    }
}

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


// MARK: - Chat UI Models

/// UI層的消息模型，包含後端Message + UI特定字段（圖片、位置、語音）
struct ChatMessage: Identifiable, Equatable {
    let id: String
    let backendMessage: Message?
    let text: String
    let isFromMe: Bool
    let timestamp: Date
    var image: UIImage?
    var location: CLLocationCoordinate2D?
    var audioData: Data?
    var audioDuration: TimeInterval?
    var audioUrl: URL?

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }

    /// 從後端Message創建ChatMessage
    init(from message: Message, currentUserId: String) {
        self.id = message.id
        self.backendMessage = message
        self.text = message.content
        self.isFromMe = message.senderId == currentUserId
        self.timestamp = message.createdAt
        self.image = nil
        self.location = nil
        self.audioData = nil
        self.audioDuration = nil
        self.audioUrl = nil
    }

    /// 創建本地消息（發送前）
    init(
        localText: String,
        isFromMe: Bool = true,
        image: UIImage? = nil,
        location: CLLocationCoordinate2D? = nil,
        audioData: Data? = nil,
        audioDuration: TimeInterval? = nil,
        audioUrl: URL? = nil
    ) {
        self.id = UUID().uuidString
        self.backendMessage = nil
        self.text = localText
        self.isFromMe = isFromMe
        self.timestamp = Date()
        self.image = image
        self.location = location
        self.audioData = audioData
        self.audioDuration = audioDuration
        self.audioUrl = audioUrl
    }
}

// MARK: - 位置標註
struct LocationAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}
