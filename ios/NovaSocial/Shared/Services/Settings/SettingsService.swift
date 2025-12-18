import Foundation

// MARK: - Settings Service

/// Manages user settings using auth-service backend
/// Handles preferences, notifications, privacy, and account settings
class SettingsService {
    static let shared = SettingsService()
    private let client = APIClient.shared

    private init() {}

    // MARK: - Get Settings

    /// Get user settings
    /// - Parameter userId: User ID
    /// - Returns: User settings
    func getSettings(userId: String) async throws -> DetailedUserSettings {
        return try await client.get(endpoint: APIConfig.Settings.getSettings(userId))
    }

    // MARK: - Update Settings

    /// Update user settings
    /// - Parameters:
    ///   - userId: User ID
    ///   - settings: Settings to update
    /// - Returns: Updated user settings
    func updateSettings(userId: String, settings: UserSettingsUpdate) async throws -> DetailedUserSettings {
        return try await client.request(
            endpoint: APIConfig.Settings.updateSettings(userId),
            method: "PUT",
            body: settings
        )
    }

    // MARK: - Convenience Methods

    /// Update notification settings
    func updateNotificationSettings(
        userId: String,
        pushEnabled: Bool? = nil,
        emailEnabled: Bool? = nil,
        likesEnabled: Bool? = nil,
        commentsEnabled: Bool? = nil,
        followsEnabled: Bool? = nil,
        mentionsEnabled: Bool? = nil,
        messagesEnabled: Bool? = nil
    ) async throws -> DetailedUserSettings {
        let notificationSettings = NotificationSettingsUpdate(
            pushEnabled: pushEnabled,
            emailEnabled: emailEnabled,
            likesEnabled: likesEnabled,
            commentsEnabled: commentsEnabled,
            followsEnabled: followsEnabled,
            mentionsEnabled: mentionsEnabled,
            messagesEnabled: messagesEnabled
        )

        let update = UserSettingsUpdate(notifications: notificationSettings)
        return try await updateSettings(userId: userId, settings: update)
    }

    /// Update privacy settings
    func updatePrivacySettings(
        userId: String,
        isPrivateAccount: Bool? = nil,
        showActivityStatus: Bool? = nil,
        showReadReceipts: Bool? = nil,
        allowTagging: TaggingPermission? = nil,
        allowMentions: MentionPermission? = nil
    ) async throws -> DetailedUserSettings {
        let privacySettings = PrivacySettingsUpdate(
            isPrivateAccount: isPrivateAccount,
            showActivityStatus: showActivityStatus,
            showReadReceipts: showReadReceipts,
            allowTagging: allowTagging?.rawValue,
            allowMentions: allowMentions?.rawValue
        )

        let update = UserSettingsUpdate(privacy: privacySettings)
        return try await updateSettings(userId: userId, settings: update)
    }

    /// Update content preferences
    func updateContentPreferences(
        userId: String,
        language: String? = nil,
        sensitiveContentFilter: Bool? = nil,
        autoplayVideos: AutoplayPreference? = nil
    ) async throws -> DetailedUserSettings {
        let contentSettings = ContentSettingsUpdate(
            language: language,
            sensitiveContentFilter: sensitiveContentFilter,
            autoplayVideos: autoplayVideos?.rawValue
        )

        let update = UserSettingsUpdate(content: contentSettings)
        return try await updateSettings(userId: userId, settings: update)
    }
}

// MARK: - Models

/// Complete user settings (detailed nested structure)
struct DetailedUserSettings: Codable {
    let userId: String
    let notifications: NotificationSettings
    let privacy: PrivacySettings
    let content: ContentSettings
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case notifications
        case privacy
        case content
        case updatedAt = "updated_at"
    }
}

/// Notification settings
struct NotificationSettings: Codable {
    let pushEnabled: Bool
    let emailEnabled: Bool
    let likesEnabled: Bool
    let commentsEnabled: Bool
    let followsEnabled: Bool
    let mentionsEnabled: Bool
    let messagesEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case pushEnabled = "push_enabled"
        case emailEnabled = "email_enabled"
        case likesEnabled = "likes_enabled"
        case commentsEnabled = "comments_enabled"
        case followsEnabled = "follows_enabled"
        case mentionsEnabled = "mentions_enabled"
        case messagesEnabled = "messages_enabled"
    }
}

/// Privacy settings
struct PrivacySettings: Codable {
    let isPrivateAccount: Bool
    let showActivityStatus: Bool
    let showReadReceipts: Bool
    let allowTagging: String
    let allowMentions: String

    enum CodingKeys: String, CodingKey {
        case isPrivateAccount = "is_private_account"
        case showActivityStatus = "show_activity_status"
        case showReadReceipts = "show_read_receipts"
        case allowTagging = "allow_tagging"
        case allowMentions = "allow_mentions"
    }
}

/// Content settings
struct ContentSettings: Codable {
    let language: String
    let sensitiveContentFilter: Bool
    let autoplayVideos: String

    enum CodingKeys: String, CodingKey {
        case language
        case sensitiveContentFilter = "sensitive_content_filter"
        case autoplayVideos = "autoplay_videos"
    }
}

// MARK: - Update Models

/// Settings update request
struct UserSettingsUpdate: Codable {
    let notifications: NotificationSettingsUpdate?
    let privacy: PrivacySettingsUpdate?
    let content: ContentSettingsUpdate?

    init(
        notifications: NotificationSettingsUpdate? = nil,
        privacy: PrivacySettingsUpdate? = nil,
        content: ContentSettingsUpdate? = nil
    ) {
        self.notifications = notifications
        self.privacy = privacy
        self.content = content
    }
}

/// Notification settings update
struct NotificationSettingsUpdate: Codable {
    let pushEnabled: Bool?
    let emailEnabled: Bool?
    let likesEnabled: Bool?
    let commentsEnabled: Bool?
    let followsEnabled: Bool?
    let mentionsEnabled: Bool?
    let messagesEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case pushEnabled = "push_enabled"
        case emailEnabled = "email_enabled"
        case likesEnabled = "likes_enabled"
        case commentsEnabled = "comments_enabled"
        case followsEnabled = "follows_enabled"
        case mentionsEnabled = "mentions_enabled"
        case messagesEnabled = "messages_enabled"
    }
}

/// Privacy settings update
struct PrivacySettingsUpdate: Codable {
    let isPrivateAccount: Bool?
    let showActivityStatus: Bool?
    let showReadReceipts: Bool?
    let allowTagging: String?
    let allowMentions: String?

    enum CodingKeys: String, CodingKey {
        case isPrivateAccount = "is_private_account"
        case showActivityStatus = "show_activity_status"
        case showReadReceipts = "show_read_receipts"
        case allowTagging = "allow_tagging"
        case allowMentions = "allow_mentions"
    }
}

/// Content settings update
struct ContentSettingsUpdate: Codable {
    let language: String?
    let sensitiveContentFilter: Bool?
    let autoplayVideos: String?

    enum CodingKeys: String, CodingKey {
        case language
        case sensitiveContentFilter = "sensitive_content_filter"
        case autoplayVideos = "autoplay_videos"
    }
}

// MARK: - Enums

/// Tagging permission levels
enum TaggingPermission: String, Codable {
    case everyone = "everyone"
    case followers = "followers"
    case nobody = "nobody"
}

/// Mention permission levels
enum MentionPermission: String, Codable {
    case everyone = "everyone"
    case followers = "followers"
    case nobody = "nobody"
}

/// Autoplay preference
enum AutoplayPreference: String, Codable {
    case always = "always"
    case wifi = "wifi"
    case never = "never"
}
