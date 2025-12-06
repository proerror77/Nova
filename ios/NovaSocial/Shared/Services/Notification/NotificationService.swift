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

    // MARK: - Single Notification

    /// Get a specific notification by ID
    func getNotification(id: String) async throws -> NotificationItemRaw {
        return try await client.get(endpoint: APIConfig.Notifications.getNotification(id))
    }

    /// Delete a notification
    func deleteNotification(id: String) async throws {
        struct EmptyResponse: Codable {}

        let _: EmptyResponse = try await client.request(
            endpoint: APIConfig.Notifications.deleteNotification(id),
            method: "DELETE"
        )
    }

    // MARK: - Notification Stats

    /// Get unread notification count
    func getUnreadCount() async throws -> Int {
        struct Response: Codable {
            let unreadCount: Int

            enum CodingKeys: String, CodingKey {
                case unreadCount = "unread_count"
            }
        }

        let response: Response = try await client.get(endpoint: APIConfig.Notifications.unreadCount)
        return response.unreadCount
    }

    /// Get notification statistics
    func getNotificationStats() async throws -> NotificationStats {
        return try await client.get(endpoint: APIConfig.Notifications.stats)
    }

    // MARK: - Notification Preferences

    /// Get user's notification preferences
    func getNotificationPreferences() async throws -> NotificationPreferences {
        return try await client.get(endpoint: APIConfig.Notifications.getPreferences)
    }

    /// Update notification preferences
    func updateNotificationPreferences(_ preferences: NotificationPreferencesUpdate) async throws -> NotificationPreferences {
        return try await client.request(
            endpoint: APIConfig.Notifications.updatePreferences,
            method: "PUT",
            body: preferences
        )
    }

    // MARK: - Push Notification Tokens

    /// Register a push notification token for this device
    func registerPushToken(token: String, platform: PushPlatform, deviceId: String, appVersion: String? = nil) async throws {
        struct Request: Codable {
            let token: String
            let platform: String
            let deviceId: String
            let appVersion: String?

            enum CodingKeys: String, CodingKey {
                case token
                case platform
                case deviceId = "device_id"
                case appVersion = "app_version"
            }
        }

        struct Response: Codable {
            let success: Bool
        }

        let request = Request(
            token: token,
            platform: platform.rawValue,
            deviceId: deviceId,
            appVersion: appVersion
        )

        let _: Response = try await client.request(
            endpoint: APIConfig.Notifications.registerPushToken,
            method: "POST",
            body: request
        )
    }

    /// Unregister a push notification token
    func unregisterPushToken(token: String) async throws {
        struct EmptyResponse: Codable {}

        let _: EmptyResponse = try await client.request(
            endpoint: APIConfig.Notifications.unregisterPushToken(token),
            method: "DELETE"
        )
    }

    // MARK: - Create Notifications (Admin/System)

    /// Create a notification (typically used by system/admin)
    func createNotification(
        userId: String,
        type: NotificationType,
        title: String,
        body: String,
        channels: [NotificationChannel]
    ) async throws -> NotificationItemRaw {
        struct Request: Codable {
            let userId: String
            let type: String
            let title: String
            let body: String
            let channels: [String]

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case type
                case title
                case body
                case channels
            }
        }

        let request = Request(
            userId: userId,
            type: type.rawValue,
            title: title,
            body: body,
            channels: channels.map { $0.rawValue }
        )

        return try await client.request(
            endpoint: APIConfig.Notifications.createNotification,
            method: "POST",
            body: request
        )
    }

    /// Batch create notifications
    func batchCreateNotifications(_ notifications: [BatchNotificationRequest]) async throws -> BatchNotificationResponse {
        struct Request: Codable {
            let notifications: [BatchNotificationRequest]
        }

        let request = Request(notifications: notifications)
        return try await client.request(
            endpoint: APIConfig.Notifications.batchCreate,
            method: "POST",
            body: request
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

// MARK: - Additional Models

/// Notification statistics
struct NotificationStats: Codable {
    let totalCount: Int
    let unreadCount: Int
    let todayCount: Int
    let weekCount: Int

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case unreadCount = "unread_count"
        case todayCount = "today_count"
        case weekCount = "week_count"
    }
}

/// Notification preferences
struct NotificationPreferences: Codable {
    let inAppEnabled: Bool
    let pushEnabled: Bool
    let emailEnabled: Bool
    let smsEnabled: Bool
    let quietHoursStart: Int?  // 0-23 hour
    let quietHoursEnd: Int?    // 0-23 hour

    enum CodingKeys: String, CodingKey {
        case inAppEnabled = "in_app_enabled"
        case pushEnabled = "push_enabled"
        case emailEnabled = "email_enabled"
        case smsEnabled = "sms_enabled"
        case quietHoursStart = "quiet_hours_start"
        case quietHoursEnd = "quiet_hours_end"
    }
}

/// Notification preferences update request
struct NotificationPreferencesUpdate: Codable {
    let inAppEnabled: Bool?
    let pushEnabled: Bool?
    let emailEnabled: Bool?
    let smsEnabled: Bool?
    let quietHoursStart: Int?
    let quietHoursEnd: Int?

    enum CodingKeys: String, CodingKey {
        case inAppEnabled = "in_app_enabled"
        case pushEnabled = "push_enabled"
        case emailEnabled = "email_enabled"
        case smsEnabled = "sms_enabled"
        case quietHoursStart = "quiet_hours_start"
        case quietHoursEnd = "quiet_hours_end"
    }
}

/// Push notification platform
enum PushPlatform: String, Codable {
    case apns = "apns"    // Apple Push Notification Service
    case fcm = "fcm"      // Firebase Cloud Messaging
    case webPush = "web_push"
}

/// Notification channel
enum NotificationChannel: String, Codable {
    case inApp = "in-app"
    case push = "push"
    case email = "email"
    case sms = "sms"
}

/// Batch notification request
struct BatchNotificationRequest: Codable {
    let userId: String
    let type: String
    let title: String
    let body: String
    let channels: [String]

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case type
        case title
        case body
        case channels
    }
}

/// Batch notification response
struct BatchNotificationResponse: Codable {
    let successCount: Int
    let failureCount: Int
    let errors: [String]?

    enum CodingKeys: String, CodingKey {
        case successCount = "success_count"
        case failureCount = "failure_count"
        case errors
    }
}
