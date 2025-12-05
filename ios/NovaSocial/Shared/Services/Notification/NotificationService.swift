import Foundation

// MARK: - Notification Service

/// Manages notification retrieval and read status using notification-service backend
/// Handles fetching notifications, marking as read, and pagination
class NotificationService {
    private let client = APIClient.shared

    // MARK: - Fetch Notifications

    /// Fetch user's notifications with pagination
    /// - Parameters:
    ///   - limit: Number of notifications to fetch (1-100, default 20)
    ///   - offset: Pagination offset (default 0)
    ///   - unreadOnly: Filter to show only unread notifications
    /// - Returns: NotificationsResponse containing notification items and pagination info
    func getNotifications(limit: Int = 20, offset: Int = 0, unreadOnly: Bool = false) async throws -> NotificationsResponse {
        var queryParams: [String: String] = [
            "limit": String(min(max(limit, 1), 100)),
            "offset": String(offset)
        ]

        if unreadOnly {
            queryParams["unread_only"] = "true"
        }

        return try await client.get(endpoint: APIConfig.Notifications.getNotifications, queryParams: queryParams)
    }

    // MARK: - Mark Read

    /// Mark a single notification as read
    /// - Parameter notificationId: ID of the notification to mark as read
    func markAsRead(notificationId: String) async throws {
        struct EmptyResponse: Codable {}

        let _: EmptyResponse = try await client.request(
            endpoint: APIConfig.Notifications.markRead(notificationId),
            method: "POST"
        )
    }

    /// Mark all notifications as read
    func markAllAsRead() async throws {
        struct EmptyResponse: Codable {}

        let _: EmptyResponse = try await client.request(
            endpoint: APIConfig.Notifications.markAllRead,
            method: "POST"
        )
    }
}

// MARK: - Response Models

/// Response from notifications API
/// Note: Uses APIClient's convertFromSnakeCase for automatic key mapping
struct NotificationsResponse: Codable {
    let notifications: [NotificationItemRaw]
    let totalCount: Int
    let unreadCount: Int
    let hasMore: Bool
}

/// Raw notification item from API
/// Note: Uses APIClient's convertFromSnakeCase for automatic key mapping
struct NotificationItemRaw: Codable, Identifiable {
    let id: String
    let type: String  // "like", "comment", "follow", "mention", "share", "reply", "system"
    let message: String
    let createdAt: Int64  // Unix timestamp
    let isRead: Bool

    // Related entities (optional)
    let relatedUserId: String?
    let relatedPostId: String?
    let relatedCommentId: String?

    // User info (may be populated by backend join)
    let userName: String?
    let userAvatarUrl: String?

    // Post info (may be populated by backend join)
    let postThumbnailUrl: String?

    /// Convert to UI model
    func toNotificationItem() -> NotificationItem {
        var item = NotificationItem(
            id: id,
            type: NotificationType(rawValue: type) ?? .system,
            message: message,
            timestamp: Date(timeIntervalSince1970: Double(createdAt)),
            isRead: isRead,
            relatedUserId: relatedUserId,
            relatedPostId: relatedPostId,
            relatedCommentId: relatedCommentId
        )
        item.userName = userName
        item.userAvatarUrl = userAvatarUrl
        item.postThumbnailUrl = postThumbnailUrl
        return item
    }
}
