import Foundation

/// Represents a conversation (direct message or group)
struct Conversation: Codable, Sendable, Identifiable, Equatable, Hashable {
    let id: String
    let name: String?
    let participantCount: Int
    let lastMessage: String?
    let lastMessageAt: String?
    let lastMessageSenderName: String?
    let unreadCount: Int
    let isGroup: Bool
    let createdAt: String
    let participants: [User]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case participantCount = "participant_count"
        case lastMessage = "last_message"
        case lastMessageAt = "last_message_at"
        case lastMessageSenderName = "last_message_sender_name"
        case unreadCount = "unread_count"
        case isGroup = "is_group"
        case createdAt = "created_at"
        case participants
    }

    init(
        id: String,
        name: String? = nil,
        participantCount: Int,
        lastMessage: String? = nil,
        lastMessageAt: String? = nil,
        lastMessageSenderName: String? = nil,
        unreadCount: Int = 0,
        isGroup: Bool = false,
        createdAt: String,
        participants: [User]? = nil
    ) {
        self.id = id
        self.name = name
        self.participantCount = participantCount
        self.lastMessage = lastMessage
        self.lastMessageAt = lastMessageAt
        self.lastMessageSenderName = lastMessageSenderName
        self.unreadCount = unreadCount
        self.isGroup = isGroup
        self.createdAt = createdAt
        self.participants = participants
    }

    /// Display name for the conversation
    var displayName: String {
        if let name = name, !name.isEmpty {
            return name
        }
        // For DM, use participant names
        if let participants = participants, participants.count > 0 {
            return participants.map { $0.displayName }.joined(separator: ", ")
        }
        return "Conversation"
    }
}

/// Request to create a conversation
struct CreateConversationRequest: Codable, Sendable {
    let participantIds: [String]
    let name: String?

    enum CodingKeys: String, CodingKey {
        case participantIds = "participant_ids"
        case name
    }

    init(participantIds: [String], name: String? = nil) {
        self.participantIds = participantIds
        self.name = name
    }
}

/// Request to mark conversation as read
struct MarkAsReadRequest: Codable, Sendable {
    let lastReadSequence: Int

    enum CodingKeys: String, CodingKey {
        case lastReadSequence = "last_read_sequence"
    }

    init(lastReadSequence: Int) {
        self.lastReadSequence = lastReadSequence
    }
}
