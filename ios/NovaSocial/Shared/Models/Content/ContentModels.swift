import Foundation

// MARK: - Content Models
// Matches: backend/proto/services/content_service.proto

struct Post: Codable, Identifiable {
    let id: String
    let authorId: String  // 改为 authorId 以匹配 convertFromSnakeCase
    let content: String
    let title: String?  // Optional post title
    let createdAt: Int64
    let updatedAt: Int64
    let status: String?
    let mediaUrls: [String]?
    let mediaType: String?
    let likeCount: Int?
    let commentCount: Int?
    let shareCount: Int?
    let bookmarkCount: Int?

    // Optional author enrichment fields (populated by graphql-gateway when available)
    let authorUsername: String?
    let authorDisplayName: String?
    let authorAvatarUrl: String?

    // Location and tags (populated by VLM service or user input)
    let location: String?
    let tags: [String]?

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

    /// Create a copy with author information filled in
    func withAuthorInfo(username: String?, displayName: String?, avatarUrl: String?) -> Post {
        Post(
            id: id,
            authorId: authorId,
            content: content,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            status: status,
            mediaUrls: mediaUrls,
            mediaType: mediaType,
            likeCount: likeCount,
            commentCount: commentCount,
            shareCount: shareCount,
            bookmarkCount: bookmarkCount,
            authorUsername: self.authorUsername ?? username,
            authorDisplayName: self.authorDisplayName ?? displayName,
            authorAvatarUrl: self.authorAvatarUrl ?? avatarUrl,
            location: location,
            tags: tags
        )
    }

    /// Formatted tags string for display (e.g., "#Fashion #Sport #Art")
    var formattedTags: String? {
        guard let tags = tags, !tags.isEmpty else { return nil }
        return tags.map { "#\($0)" }.joined(separator: " ")
    }

    /// Check if author info is missing
    var needsAuthorEnrichment: Bool {
        authorDisplayName == nil && authorUsername == nil
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
