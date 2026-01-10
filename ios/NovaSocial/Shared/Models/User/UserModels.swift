import Foundation

// MARK: - User Profile Models
// Matches: backend/proto/services_v2/user_service.proto

struct UserProfile: Codable, Identifiable {
    let id: String
    let username: String
    var email: String? = nil
    var displayName: String? = nil
    var bio: String? = nil
    var avatarUrl: String? = nil
    var coverUrl: String? = nil
    var website: String? = nil
    var location: String? = nil
    var isVerified: Bool? = nil
    var isPrivate: Bool? = nil
    var isBanned: Bool? = nil
    var followerCount: Int? = nil
    var followingCount: Int? = nil
    var postCount: Int? = nil
    var createdAt: Int64? = nil
    var updatedAt: Int64? = nil
    var deletedAt: Int64? = nil

    // Extended profile fields (for profile settings)
    var firstName: String? = nil
    var lastName: String? = nil
    var dateOfBirth: String? = nil  // ISO 8601 date format (YYYY-MM-DD)
    var gender: Gender? = nil

    // Safe accessors with defaults
    var safeIsVerified: Bool { isVerified ?? false }
    var safeIsPrivate: Bool { isPrivate ?? false }
    var safeIsBanned: Bool { isBanned ?? false }
    var safeFollowerCount: Int { followerCount ?? 0 }
    var safeFollowingCount: Int { followingCount ?? 0 }
    var safePostCount: Int { postCount ?? 0 }

    /// Full name for display, with fallback priority: firstName+lastName > displayName > username
    var fullName: String {
        let first = (firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        if !combined.isEmpty { return combined }
        if let display = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !display.isEmpty {
            return display
        }
        return username
    }

    // Note: No CodingKeys needed - APIClient uses .convertFromSnakeCase automatically
    // All property names are already in camelCase which matches the automatic conversion
}

// MARK: - Gender Enum
enum Gender: String, Codable, CaseIterable {
    case notSet = "not_set"
    case male = "male"
    case female = "female"
    case other = "other"

    var displayName: String {
        switch self {
        case .notSet: return "Enter your gender"
        case .male: return "Male"
        case .female: return "Female"
        case .other: return "Other"
        }
    }

    // 用于选择器显示的选项（不包含 notSet）
    static var selectableCases: [Gender] {
        return [.male, .female, .other]
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Gender(rawValue: rawValue.lowercased()) ?? .notSet
    }
}

// MARK: - User Settings Model
// Matches: backend/proto/services_v2/identity_service.proto UserSettings
// NOTE: identity-service is now the SINGLE SOURCE OF TRUTH for user settings
// including dm_permission (P0 migration completed)

struct UserSettings: Codable {
    let userId: String
    let emailNotifications: Bool?
    let pushNotifications: Bool?
    let marketingEmails: Bool?
    let timezone: String?
    let language: String?
    let darkMode: Bool?
    let privacyLevel: PrivacyLevel?
    let allowMessages: Bool?
    let showOnlineStatus: Bool?
    /// DM permission setting - controls who can send direct messages
    /// Values: "anyone", "followers", "mutuals", "nobody"
    /// Default: "mutuals" (only mutual followers can DM)
    let dmPermission: DmPermission?
    let createdAt: Int64?
    let updatedAt: Int64?

    // Safe accessors with defaults
    var safeEmailNotifications: Bool { emailNotifications ?? true }
    var safePushNotifications: Bool { pushNotifications ?? true }
    var safeMarketingEmails: Bool { marketingEmails ?? false }
    var safeTimezone: String { timezone ?? "UTC" }
    var safeLanguage: String { language ?? "en" }
    var safeDarkMode: Bool { darkMode ?? false }
    var safePrivacyLevel: PrivacyLevel { privacyLevel ?? .public }
    var safeAllowMessages: Bool { allowMessages ?? true }
    var safeShowOnlineStatus: Bool { showOnlineStatus ?? true }
    var safeDmPermission: DmPermission { dmPermission ?? .mutuals }

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
        case showOnlineStatus = "show_online_status"
        case dmPermission = "dm_permission"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - DM Permission Enum
// Controls who can send direct messages to the user
// Matches: backend/proto/services_v2/identity_service.proto DmPermission
enum DmPermission: String, Codable, CaseIterable {
    case anyone = "anyone"
    case followers = "followers"
    case mutuals = "mutuals"
    case nobody = "nobody"

    var displayName: String {
        switch self {
        case .anyone: return "Anyone"
        case .followers: return "Followers Only"
        case .mutuals: return "Mutuals Only"
        case .nobody: return "Nobody"
        }
    }

    var description: String {
        switch self {
        case .anyone: return "Anyone can send you direct messages"
        case .followers: return "Only people you follow can message you"
        case .mutuals: return "Only mutual followers can message you"
        case .nobody: return "No one can send you direct messages"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = DmPermission(rawValue: rawValue.lowercased()) ?? .mutuals
    }
}

// MARK: - Privacy Level Enum
// Matches: backend/proto/services_v2/user_service.proto PrivacyLevel
enum PrivacyLevel: String, Codable, CaseIterable {
    case unspecified = "unspecified"
    case `public` = "public"
    case `private` = "private"
    case friendsOnly = "friends_only"

    var displayName: String {
        switch self {
        case .unspecified: return "Default"
        case .public: return "Public"
        case .private: return "Private"
        case .friendsOnly: return "Friends Only"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = PrivacyLevel(rawValue: rawValue.lowercased()) ?? .public
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
    var displayName: String?
    var bio: String?
    var avatarUrl: String?
    var coverUrl: String?
    var website: String?
    var location: String?
    var isPrivate: Bool?
    var firstName: String?
    var lastName: String?
    var dateOfBirth: String?
    var gender: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case bio
        case avatarUrl = "avatar_url"
        case coverUrl = "cover_url"
        case website
        case location
        case isPrivate = "is_private"
        case firstName = "first_name"
        case lastName = "last_name"
        case dateOfBirth = "date_of_birth"
        case gender
    }
}

// MARK: - Update Settings Request
// Matches: backend/proto/services_v2/identity_service.proto UpdateSettingsRequest
// NOTE: identity-service is now the SINGLE SOURCE OF TRUTH for user settings

struct UpdateSettingsRequest: Codable {
    let userId: String
    var emailNotifications: Bool?
    var pushNotifications: Bool?
    var marketingEmails: Bool?
    var timezone: String?
    var language: String?
    var darkMode: Bool?
    var privacyLevel: String?
    var allowMessages: Bool?
    var showOnlineStatus: Bool?
    /// DM permission setting - controls who can send direct messages
    /// Values: "anyone", "followers", "mutuals", "nobody"
    var dmPermission: String?

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
        case showOnlineStatus = "show_online_status"
        case dmPermission = "dm_permission"
    }
}
