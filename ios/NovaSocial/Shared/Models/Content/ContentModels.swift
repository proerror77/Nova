import Foundation

// MARK: - Content Models
// Matches: backend/proto/services/content_service.proto

struct Post: Codable, Identifiable {
    let id: String
    let authorId: String  // 改为 authorId 以匹配 convertFromSnakeCase
    let content: String
    let createdAt: Int64
    let updatedAt: Int64
    let status: String?
    let mediaUrls: [String]?
    let mediaType: String?
    let likeCount: Int?
    let commentCount: Int?
    let shareCount: Int?

    // Optional author enrichment fields (populated by graphql-gateway when available)
    let authorUsername: String?
    let authorDisplayName: String?
    let authorAvatarUrl: String?

    // 便利属性，保持向后兼容
    var creatorId: String { authorId }

    // 移除 CodingKeys，让 convertFromSnakeCase 自动处理
    // author_id -> authorId, created_at -> createdAt 等

    /// Convert timestamp to Date for display
    var createdDate: Date {
        Date(timeIntervalSince1970: Double(createdAt))
    }

    /// Display name for the post author
    var displayAuthorName: String {
        if let displayName = authorDisplayName, !displayName.isEmpty {
            return displayName
        }
        if let username = authorUsername, !username.isEmpty {
            return username
        }
        // Fallback to truncated authorId
        return "User \(authorId.prefix(8))"
    }
}

struct Comment: Codable, Identifiable {
    let id: String
    let postId: String
    let creatorId: String
    let content: String
    let createdAt: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case postId = "post_id"
        case creatorId = "creator_id"
        case content
        case createdAt = "created_at"
    }
}

struct PostLike: Codable {
    let userId: String
    let likedAt: Int64

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case likedAt = "liked_at"
    }
}

// MARK: - Request/Response Models

struct CreatePostRequest: Codable {
    let creatorId: String
    let content: String

    enum CodingKeys: String, CodingKey {
        case creatorId = "creator_id"
        case content
    }
}

struct GetPostsByAuthorRequest: Codable {
    let authorId: String
    let status: String?
    let limit: Int
    let offset: Int

    enum CodingKeys: String, CodingKey {
        case authorId = "author_id"
        case status
        case limit
        case offset
    }
}

struct GetPostsByAuthorResponse: Codable {
    let posts: [Post]
    let totalCount: Int
    // Note: CodingKeys removed - APIClient uses .convertFromSnakeCase which automatically
    // converts JSON "total_count" to Swift "totalCount"
}

struct GetUserBookmarksResponse: Codable {
    let postIds: [String]
    let totalCount: Int
    // Note: CodingKeys removed - APIClient uses .convertFromSnakeCase which automatically
    // converts JSON "post_ids" to Swift "postIds"
}

struct LikePostRequest: Codable {
    let postId: String
    let userId: String

    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case userId = "user_id"
    }
}
