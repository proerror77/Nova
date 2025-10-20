import Foundation

/// 公共 API 响应模型
///
/// Linus 原则: "消除重复就是消除 bug"
/// 每个 Repository 都定义自己的 Response 是垃圾代码
/// 这里统一定义,一处修改,全局生效

// MARK: - Generic Wrappers

/// 单个实体响应
struct EntityResponse<T: Codable>: Codable {
    let data: T

    init(data: T) {
        self.data = data
    }
}

/// 列表响应(带分页)
struct ListResponse<T: Codable>: Codable {
    let items: [T]
    let nextCursor: String?
    let total: Int?

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
        case total
    }
}

/// 操作成功响应(无数据返回)
struct SuccessResponse: Codable {
    let success: Bool
    let message: String?
}

// MARK: - Auth Responses

struct AuthResponse: Codable {
    let user: User
    let tokens: AuthTokens
}

struct AuthTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

struct RefreshTokenResponse: Codable {
    let accessToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}

// MARK: - Post Responses

struct PostResponse: Codable {
    let post: Post
}

struct PostsResponse: Codable {
    let posts: [Post]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case posts
        case nextCursor = "next_cursor"
    }
}

/// 点赞响应
struct LikeResponse: Codable {
    let liked: Bool
    let likeCount: Int

    enum CodingKeys: String, CodingKey {
        case liked
        case likeCount = "like_count"
    }
}

/// 评论响应
struct CommentResponse: Codable {
    let comment: Comment
}

struct CommentsResponse: Codable {
    let comments: [Comment]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case comments
        case nextCursor = "next_cursor"
    }
}

// MARK: - User Responses

struct UserResponse: Codable {
    let user: User
}

struct UsersResponse: Codable {
    let users: [User]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case users
        case nextCursor = "next_cursor"
    }
}

/// 关注响应
struct FollowResponse: Codable {
    let following: Bool
    let followerCount: Int

    enum CodingKeys: String, CodingKey {
        case following
        case followerCount = "follower_count"
    }
}

// MARK: - Upload Responses

struct UploadURLResponse: Codable {
    let uploadUrl: String
    let fileKey: String

    enum CodingKeys: String, CodingKey {
        case uploadUrl = "upload_url"
        case fileKey = "file_key"
    }
}

// MARK: - Feed Responses

struct FeedResponse: Codable {
    let posts: [Post]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case posts
        case nextCursor = "next_cursor"
    }
}

// MARK: - Notification Responses

struct NotificationsResponse: Codable {
    let notifications: [Notification]
    let nextCursor: String?
    let unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case notifications
        case nextCursor = "next_cursor"
        case unreadCount = "unread_count"
    }
}
