import Foundation

// MARK: - Conversation Models

/// Represents a chat conversation with another user
struct Conversation: Identifiable {
    let id: String
    let userId: String
    let username: String
    let lastMessage: String
    let timestamp: Date
    let unreadCount: Int

    // Optional fields for future expansion
    var avatarUrl: String?
    var isOnline: Bool = false
    var lastMessageSenderId: String?
}

/// Represents a single message in a conversation
struct Message: Identifiable {
    let id: String
    let conversationId: String
    let senderId: String
    let receiverId: String
    let content: String
    let timestamp: Date
    var status: MessageStatus

    // Optional fields
    var mediaUrl: String?
    var mediaType: MediaType?
    var isDeleted: Bool = false
}

/// Message delivery status
enum MessageStatus: String, Codable {
    case sending
    case sent
    case delivered
    case read
    case failed
}

/// Media type in messages
enum MediaType: String, Codable {
    case image
    case video
    case audio
    case document
}
