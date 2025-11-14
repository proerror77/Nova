import Foundation

// MARK: - Notification Models

/// Represents a user notification
struct NotificationItem: Identifiable {
    let id: String
    let type: NotificationType
    let message: String
    let timestamp: Date
    let isRead: Bool

    // Related entities
    let relatedUserId: String?
    let relatedPostId: String?
    let relatedCommentId: String?

    // Optional fields
    var userAvatarUrl: String?
    var userName: String?
    var postThumbnailUrl: String?
}

/// Type of notification
enum NotificationType: String, Codable {
    case like
    case comment
    case follow
    case mention
    case share
    case reply
    case system

    /// Display icon name for the notification type
    var iconName: String {
        switch self {
        case .like: return "heart.fill"
        case .comment: return "bubble.left.fill"
        case .follow: return "person.badge.plus.fill"
        case .mention: return "at"
        case .share: return "square.and.arrow.up.fill"
        case .reply: return "arrowshape.turn.up.left.fill"
        case .system: return "bell.fill"
        }
    }

    /// Display color for the notification type
    var displayColor: String {
        switch self {
        case .like: return "red"
        case .comment: return "blue"
        case .follow: return "green"
        case .mention: return "purple"
        case .share: return "orange"
        case .reply: return "blue"
        case .system: return "gray"
        }
    }
}

/// Notification filter options
enum NotificationFilter: String, CaseIterable {
    case all = "All"
    case unread = "Unread"
    case mentions = "Mentions"
    case likes = "Likes"
    case comments = "Comments"
}
