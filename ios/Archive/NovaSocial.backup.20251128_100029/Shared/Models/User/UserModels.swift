import Foundation

// MARK: - User Profile Models
// Matches: backend/proto/services/user_service.proto

struct UserProfile: Codable, Identifiable {
    let id: String
    let username: String
    let email: String?
    let displayName: String?
    let bio: String?
    let avatarUrl: String?
    let coverUrl: String?
    let website: String?
    let location: String?
    let isVerified: Bool?
    let isPrivate: Bool?
    let followerCount: Int?
    let followingCount: Int?
    let postCount: Int?
    let createdAt: Int64?
    let updatedAt: Int64?
    let deletedAt: Int64?

    // Make fields that may be missing from API optional with defaults
    var safeIsVerified: Bool { isVerified ?? false }
    var safeIsPrivate: Bool { isPrivate ?? false }
    var safeFollowerCount: Int { followerCount ?? 0 }
    var safeFollowingCount: Int { followingCount ?? 0 }
    var safePostCount: Int { postCount ?? 0 }

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case email
        case displayName = "display_name"
        case bio
        case avatarUrl = "avatar_url"
        case coverUrl = "cover_url"
        case website
        case location
        case isVerified = "is_verified"
        case isPrivate = "is_private"
        case followerCount = "follower_count"
        case followingCount = "following_count"
        case postCount = "post_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct UserSettings: Codable {
    let userId: String
    let emailNotifications: Bool
    let pushNotifications: Bool
    let marketingEmails: Bool
    let timezone: String
    let language: String
    let darkMode: Bool
    let privacyLevel: String
    let allowMessages: Bool
    let createdAt: Int64
    let updatedAt: Int64

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case emailNotifications = "email_notifications"
        case pushNotifications = "push_notifications"
        case marketingEmails = "marketing_emails"
        case timezone
        case language
        case darkMode = "dark_mode"
        case privacyLevel = "privacy_level"
        case allowMessages = "allow_messages"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct UserRelationship: Codable, Identifiable {
    let id: String
    let followerId: String
    let followeeId: String
    let relationshipType: String  // "follow" or "block"
    let status: String  // "active", "pending", "rejected"
    let createdAt: Int64
    let updatedAt: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case followerId = "follower_id"
        case followeeId = "followee_id"
        case relationshipType = "relationship_type"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Request/Response Models

struct UpdateUserProfileRequest: Codable {
    let userId: String
    let displayName: String?
    let bio: String?
    let avatarUrl: String?
    let coverUrl: String?
    let website: String?
    let location: String?
    let isPrivate: Bool?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case bio
        case avatarUrl = "avatar_url"
        case coverUrl = "cover_url"
        case website
        case location
        case isPrivate = "is_private"
    }
}
