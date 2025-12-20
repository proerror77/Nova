import Foundation

// MARK: - Relationships Service

/// Manages user relationships and privacy settings via realtime-chat-service
/// Handles blocks, privacy settings, and message requests
class RelationshipsService {
    static let shared = RelationshipsService()
    private let client = APIClient.shared

    private init() {}

    // MARK: - Block Management

    /// Block a user
    /// - Parameters:
    ///   - userId: ID of the user to block
    ///   - reason: Optional reason for blocking
    func blockUser(userId: String, reason: String? = nil) async throws {
        struct Request: Codable {
            let userId: String
            let reason: String?

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case reason
            }
        }

        struct Response: Codable {
            let success: Bool
        }

        let request = Request(userId: userId, reason: reason)
        let _: Response = try await client.request(
            endpoint: APIConfig.Relationships.blockUser,
            method: "POST",
            body: request
        )
    }

    /// Unblock a user
    /// - Parameter userId: ID of the user to unblock
    func unblockUser(userId: String) async throws {
        struct Response: Codable {
            let success: Bool
        }

        let _: Response = try await client.request(
            endpoint: APIConfig.Relationships.unblockUser(userId),
            method: "DELETE"
        )
    }

    /// Get list of blocked users
    /// - Parameters:
    ///   - limit: Maximum number of users to return
    ///   - offset: Pagination offset
    /// - Returns: List of blocked users
    func getBlockedUsers(limit: Int = 20, offset: Int = 0) async throws -> BlockedUsersResponse {
        return try await client.get(
            endpoint: APIConfig.Relationships.getBlockedUsers,
            queryParams: [
                "limit": String(limit),
                "offset": String(offset)
            ]
        )
    }

    // MARK: - Report Management

    /// Report a user or content
    /// - Parameters:
    ///   - targetType: Type of target ("user" or "post")
    ///   - targetId: ID of the user or post to report
    ///   - reason: Reason for reporting
    ///   - details: Optional additional details
    func report(targetType: ReportTargetType, targetId: String, reason: ReportReason, details: String? = nil) async throws {
        struct Request: Codable {
            let targetType: String
            let targetId: String
            let reason: String
            let details: String?

            enum CodingKeys: String, CodingKey {
                case targetType = "target_type"
                case targetId = "target_id"
                case reason
                case details
            }
        }

        struct Response: Codable {
            let success: Bool
            let reportId: String?

            enum CodingKeys: String, CodingKey {
                case success
                case reportId = "report_id"
            }
        }

        let request = Request(
            targetType: targetType.rawValue,
            targetId: targetId,
            reason: reason.rawValue,
            details: details
        )

        let _: Response = try await client.request(
            endpoint: APIConfig.Relationships.report,
            method: "POST",
            body: request
        )
    }

    /// Report a user
    /// - Parameters:
    ///   - userId: ID of the user to report
    ///   - reason: Reason for reporting
    ///   - details: Optional additional details
    func reportUser(userId: String, reason: ReportReason, details: String? = nil) async throws {
        try await report(targetType: .user, targetId: userId, reason: reason, details: details)
    }

    /// Report a post
    /// - Parameters:
    ///   - postId: ID of the post to report
    ///   - reason: Reason for reporting
    ///   - details: Optional additional details
    func reportPost(postId: String, reason: ReportReason, details: String? = nil) async throws {
        try await report(targetType: .post, targetId: postId, reason: reason, details: details)
    }

    // MARK: - Relationship Status

    /// Get relationship status with a user
    /// - Parameter userId: ID of the user to check
    /// - Returns: Relationship status
    func getRelationship(userId: String) async throws -> UserRelationshipStatus {
        return try await client.get(
            endpoint: APIConfig.Relationships.getRelationship(userId)
        )
    }

    // MARK: - Privacy Settings

    /// Get privacy settings for direct messages
    /// - Returns: Current privacy settings
    func getPrivacySettings() async throws -> DMPrivacySettings {
        return try await client.get(endpoint: APIConfig.Relationships.getPrivacySettings)
    }

    /// Update privacy settings for direct messages
    /// - Parameter permission: New DM permission level
    /// - Returns: Updated privacy settings
    func updatePrivacySettings(dmPermission: DMPermission) async throws -> DMPrivacySettings {
        struct Request: Codable {
            let dmPermission: String

            enum CodingKeys: String, CodingKey {
                case dmPermission = "dm_permission"
            }
        }

        let request = Request(dmPermission: dmPermission.rawValue)
        return try await client.request(
            endpoint: APIConfig.Relationships.updatePrivacySettings,
            method: "PUT",
            body: request
        )
    }

    // MARK: - Message Requests

    /// Get pending message requests
    /// - Parameters:
    ///   - limit: Maximum number of requests to return
    ///   - offset: Pagination offset
    /// - Returns: List of message requests
    func getMessageRequests(limit: Int = 20, offset: Int = 0) async throws -> MessageRequestsResponse {
        return try await client.get(
            endpoint: APIConfig.Relationships.getMessageRequests,
            queryParams: [
                "limit": String(limit),
                "offset": String(offset)
            ]
        )
    }

    /// Accept a message request
    /// - Parameter requestId: ID of the message request
    func acceptMessageRequest(requestId: String) async throws {
        struct Response: Codable {
            let success: Bool
        }

        let _: Response = try await client.request(
            endpoint: APIConfig.Relationships.acceptMessageRequest(requestId),
            method: "POST"
        )
    }

    /// Reject a message request
    /// - Parameter requestId: ID of the message request
    func rejectMessageRequest(requestId: String) async throws {
        struct Response: Codable {
            let success: Bool
        }

        let _: Response = try await client.request(
            endpoint: APIConfig.Relationships.rejectMessageRequest(requestId),
            method: "POST"
        )
    }

    // MARK: - Convenience Methods

    /// Check if a user is blocked
    /// - Parameter userId: ID of the user to check
    /// - Returns: True if the user is blocked
    func isUserBlocked(userId: String) async throws -> Bool {
        let relationship = try await getRelationship(userId: userId)
        return relationship.isBlocked
    }

    /// Check if current user can message another user
    /// - Parameter userId: ID of the user to check
    /// - Returns: True if messaging is allowed
    func canMessageUser(userId: String) async throws -> Bool {
        let relationship = try await getRelationship(userId: userId)
        return relationship.canMessage
    }
}

// MARK: - Models

/// Blocked users response
struct BlockedUsersResponse: Codable {
    let users: [BlockedUserInfo]
    let total: Int
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case users
        case total
        case hasMore = "has_more"
    }
}

/// Blocked user information
struct BlockedUserInfo: Codable, Identifiable {
    let id: String
    let userId: String
    let username: String
    let displayName: String?
    let avatarUrl: String?
    let blockedAt: Date
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case username
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case blockedAt = "blocked_at"
        case reason
    }
}

/// User relationship status (用户之间的关系状态)
struct UserRelationshipStatus: Codable {
    let userId: String
    let isFollowing: Bool
    let isFollowedBy: Bool
    let isBlocked: Bool
    let isBlockedBy: Bool
    let isMuted: Bool
    let canMessage: Bool
    let hasPendingRequest: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case isFollowing = "is_following"
        case isFollowedBy = "is_followed_by"
        case isBlocked = "is_blocked"
        case isBlockedBy = "is_blocked_by"
        case isMuted = "is_muted"
        case canMessage = "can_message"
        case hasPendingRequest = "has_pending_request"
    }
}

/// DM privacy settings
struct DMPrivacySettings: Codable {
    let dmPermission: String
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case dmPermission = "dm_permission"
        case updatedAt = "updated_at"
    }

    var permission: DMPermission {
        DMPermission(rawValue: dmPermission) ?? .anyone
    }
}

/// DM permission levels
enum DMPermission: String, Codable, CaseIterable {
    case anyone = "anyone"
    case followers = "followers"
    case mutuals = "mutuals"
    case nobody = "nobody"

    var displayName: String {
        switch self {
        case .anyone: return "所有人"
        case .followers: return "仅关注者"
        case .mutuals: return "仅互相关注"
        case .nobody: return "不接受私信"
        }
    }
}

/// Message requests response
struct MessageRequestsResponse: Codable {
    let requests: [MessageRequest]
    let total: Int
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case requests
        case total
        case hasMore = "has_more"
    }
}

/// Message request model
struct MessageRequest: Codable, Identifiable {
    let id: String
    let senderId: String
    let senderUsername: String
    let senderDisplayName: String?
    let senderAvatarUrl: String?
    let previewMessage: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case senderId = "sender_id"
        case senderUsername = "sender_username"
        case senderDisplayName = "sender_display_name"
        case senderAvatarUrl = "sender_avatar_url"
        case previewMessage = "preview_message"
        case createdAt = "created_at"
    }
}

// MARK: - Report Types

/// Report target type
enum ReportTargetType: String, Codable {
    case user = "user"
    case post = "post"
    case comment = "comment"
    case message = "message"
}

/// Report reason
enum ReportReason: String, Codable, CaseIterable, Identifiable {
    case spam = "spam"
    case harassment = "harassment"
    case hateSpeech = "hate_speech"
    case violence = "violence"
    case nudity = "nudity"
    case falseInfo = "false_information"
    case scam = "scam"
    case impersonation = "impersonation"
    case intellectualProperty = "intellectual_property"
    case selfHarm = "self_harm"
    case other = "other"

    var id: String { rawValue }

    /// Display name in Traditional Chinese
    var displayName: String {
        switch self {
        case .spam: return "垃圾訊息"
        case .harassment: return "騷擾或霸凌"
        case .hateSpeech: return "仇恨言論"
        case .violence: return "暴力或危險內容"
        case .nudity: return "裸露或色情內容"
        case .falseInfo: return "虛假資訊"
        case .scam: return "詐騙"
        case .impersonation: return "假冒身份"
        case .intellectualProperty: return "侵犯智慧財產權"
        case .selfHarm: return "自殘或自殺"
        case .other: return "其他"
        }
    }

    /// Description for each reason
    var description: String {
        switch self {
        case .spam: return "重複發送或無意義的內容"
        case .harassment: return "針對特定用戶的騷擾、威脅或霸凌行為"
        case .hateSpeech: return "基於種族、宗教、性別等的歧視性言論"
        case .violence: return "鼓勵或美化暴力行為"
        case .nudity: return "包含不當的裸露或性暗示內容"
        case .falseInfo: return "故意散播虛假或誤導性資訊"
        case .scam: return "試圖詐騙或欺騙他人"
        case .impersonation: return "假冒他人身份"
        case .intellectualProperty: return "未經授權使用受版權保護的內容"
        case .selfHarm: return "鼓勵自殘或自殺行為"
        case .other: return "其他違規行為"
        }
    }
}
