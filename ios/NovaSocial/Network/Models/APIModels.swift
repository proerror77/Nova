import Foundation

// MARK: - Authentication Models

struct AuthTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

struct LoginRequest: Codable {
    let email: String
    let password: String
}

struct RegisterRequest: Codable {
    let email: String
    let password: String
    let username: String
}

struct AuthResponse: Codable {
    let user: User
    let tokens: AuthTokens
}

// MARK: - User Models

struct User: Codable, Identifiable, Equatable {
    let id: UUID
    let username: String
    let email: String
    let displayName: String?
    let bio: String?
    let avatarUrl: String?
    let isVerified: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, username, email, bio
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case isVerified = "is_verified"
        case createdAt = "created_at"
    }

    static func == (lhs: User, rhs: User) -> Bool {
        lhs.id == rhs.id
    }
}

struct UserStats: Codable {
    let postCount: Int
    let followerCount: Int
    let followingCount: Int
    let isFollowing: Bool

    enum CodingKeys: String, CodingKey {
        case postCount = "post_count"
        case followerCount = "follower_count"
        case followingCount = "following_count"
        case isFollowing = "is_following"
    }
}

struct UserProfile: Codable {
    let user: User
    let stats: UserStats
}

// MARK: - Post Models

struct Post: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let imageUrl: String
    let thumbnailUrl: String?
    let caption: String?
    let likeCount: Int
    let commentCount: Int
    let isLiked: Bool
    let createdAt: Date
    let user: User?

    enum CodingKeys: String, CodingKey {
        case id, caption, user
        case userId = "user_id"
        case imageUrl = "image_url"
        case thumbnailUrl = "thumbnail_url"
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case isLiked = "is_liked"
        case createdAt = "created_at"
    }

    static func == (lhs: Post, rhs: Post) -> Bool {
        lhs.id == rhs.id
    }
}

struct CreatePostRequest: Codable {
    let fileKey: String
    let caption: String?

    enum CodingKeys: String, CodingKey {
        case fileKey = "file_key"
        case caption
    }
}

struct UploadURLRequest: Codable {
    let contentType: String

    enum CodingKeys: String, CodingKey {
        case contentType = "content_type"
    }
}

struct UploadURLResponse: Codable {
    let uploadUrl: String
    let fileKey: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case uploadUrl = "upload_url"
        case fileKey = "file_key"
        case expiresIn = "expires_in"
    }
}

// MARK: - Posts Upload (init/complete)

struct PostUploadInitRequest: Codable {
    let filename: String
    let contentType: String
    let fileSize: Int
    let caption: String?

    enum CodingKeys: String, CodingKey {
        case filename
        case contentType = "content_type"
        case fileSize = "file_size"
        case caption
    }
}

struct PostUploadInitResponse: Codable {
    let presignedUrl: String
    let postId: String
    let uploadToken: String
    let expiresIn: Int
    let instructions: String?

    enum CodingKeys: String, CodingKey {
        case presignedUrl = "presigned_url"
        case postId = "post_id"
        case uploadToken = "upload_token"
        case expiresIn = "expires_in"
        case instructions
    }
}

struct PostUploadCompleteRequest: Codable {
    let postId: String
    let uploadToken: String
    let fileHash: String
    let fileSize: Int

    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case uploadToken = "upload_token"
        case fileHash = "file_hash"
        case fileSize = "file_size"
    }
}

struct PostUploadCompleteResponse: Codable {
    let postId: String
    let status: String
    let message: String?
    let imageKey: String?

    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case status
        case message
        case imageKey = "image_key"
    }
}

// MARK: - Comment Models

struct Comment: Codable, Identifiable, Equatable {
    let id: UUID
    let postId: UUID
    let userId: UUID
    let text: String
    let createdAt: Date
    let user: User?

    enum CodingKeys: String, CodingKey {
        case id, text, user
        case postId = "post_id"
        case userId = "user_id"
        case createdAt = "created_at"
    }

    static func == (lhs: Comment, rhs: Comment) -> Bool {
        lhs.id == rhs.id
    }
}

struct CreateCommentRequest: Codable {
    let text: String
}

// MARK: - Feed Models

struct FeedResponse: Codable {
    let posts: [Post]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case posts
        case nextCursor = "next_cursor"
    }
}

// MARK: - Notification Models

enum NotificationType: String, Codable {
    case like
    case comment
    case follow
    case mention
}

struct Notification: Codable, Identifiable, Equatable {
    let id: UUID
    let type: NotificationType
    let actorId: UUID
    let postId: UUID?
    let isRead: Bool
    let createdAt: Date
    let actor: User?
    let post: Post?

    enum CodingKeys: String, CodingKey {
        case id, type, actor, post
        case actorId = "actor_id"
        case postId = "post_id"
        case isRead = "is_read"
        case createdAt = "created_at"
    }

    static func == (lhs: Notification, rhs: Notification) -> Bool {
        lhs.id == rhs.id
    }
}

struct NotificationResponse: Codable {
    let notifications: [Notification]
    let nextCursor: String?
    let unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case notifications
        case nextCursor = "next_cursor"
        case unreadCount = "unread_count"
    }
}

// MARK: - Error Response

struct ErrorResponse: Codable {
    let code: String
    let message: String
}

// MARK: - Generic List Response

struct ListResponse<T: Codable>: Codable {
    let items: [T]
    let nextCursor: String?
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
    }
}
