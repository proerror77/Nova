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

    /// Account type used when post was created: "primary" (real name) or "alias"
    let authorAccountType: String?

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
            tags: tags,
            authorAccountType: authorAccountType
        )
    }

    /// Create a copy with bookmark count ensured to be at least minCount
    /// Used for posts loaded from Saved tab where we know they are bookmarked
    func withMinBookmarkCount(_ minCount: Int) -> Post {
        let currentCount = bookmarkCount ?? 0
        guard currentCount < minCount else { return self }
        return Post(
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
            bookmarkCount: minCount,
            authorUsername: authorUsername,
            authorDisplayName: authorDisplayName,
            authorAvatarUrl: authorAvatarUrl,
            location: location,
            tags: tags,
            authorAccountType: authorAccountType
        )
    }

    /// Create a copy with updated stats from social-service
    /// Used to sync accurate like/comment/share counts
    func withStats(likeCount: Int, commentCount: Int, shareCount: Int) -> Post {
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
            authorUsername: authorUsername,
            authorDisplayName: authorDisplayName,
            authorAvatarUrl: authorAvatarUrl,
            location: location,
            tags: tags,
            authorAccountType: authorAccountType
        )
    }

    // MARK: - Initializers

    /// Memberwise initializer (required because we have custom inits)
    init(
        id: String,
        authorId: String,
        content: String,
        title: String? = nil,
        createdAt: Int64,
        updatedAt: Int64,
        status: String? = nil,
        mediaUrls: [String]? = nil,
        mediaType: String? = nil,
        likeCount: Int? = nil,
        commentCount: Int? = nil,
        shareCount: Int? = nil,
        bookmarkCount: Int? = nil,
        authorUsername: String? = nil,
        authorDisplayName: String? = nil,
        authorAvatarUrl: String? = nil,
        location: String? = nil,
        tags: [String]? = nil,
        authorAccountType: String? = nil
    ) {
        self.id = id
        self.authorId = authorId
        self.content = content
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.mediaUrls = mediaUrls
        self.mediaType = mediaType
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.shareCount = shareCount
        self.bookmarkCount = bookmarkCount
        self.authorUsername = authorUsername
        self.authorDisplayName = authorDisplayName
        self.authorAvatarUrl = authorAvatarUrl
        self.location = location
        self.tags = tags
        self.authorAccountType = authorAccountType
    }

    /// Create Post from FeedPost (for ProfileData compatibility)
    /// - Parameters:
    ///   - feedPost: The FeedPost from feed-service
    ///   - isLiked: Whether the current user has liked this post
    ///   - isBookmarked: Whether the current user has bookmarked this post
    init(from feedPost: FeedPost, isLiked: Bool = false, isBookmarked: Bool = false) {
        self.id = feedPost.id
        self.authorId = feedPost.authorId
        self.content = feedPost.content
        self.title = feedPost.title
        self.createdAt = Int64(feedPost.createdAt.timeIntervalSince1970)
        self.updatedAt = Int64(feedPost.createdAt.timeIntervalSince1970)
        self.status = "published"
        self.mediaUrls = feedPost.mediaUrls
        self.mediaType = feedPost.mediaType.rawValue
        self.likeCount = feedPost.likeCount
        self.commentCount = feedPost.commentCount
        self.shareCount = feedPost.shareCount
        // Ensure bookmarkCount is at least 1 when user has bookmarked the post
        self.bookmarkCount = isBookmarked ? max(feedPost.bookmarkCount, 1) : feedPost.bookmarkCount
        self.authorUsername = nil  // FeedPost uses authorName directly
        self.authorDisplayName = feedPost.authorName
        self.authorAvatarUrl = feedPost.authorAvatar
        self.location = feedPost.location
        self.tags = feedPost.tags
        self.authorAccountType = feedPost.authorAccountType
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

    /// Returns the appropriate thumbnail URL for grid display
    /// For video posts, returns the thumbnail URL (second in mediaUrls array)
    /// For image/live_photo posts, returns the first media URL
    var displayThumbnailUrl: String? {
        guard let urls = mediaUrls, !urls.isEmpty else { return nil }

        let firstUrl = urls[0].lowercased()

        // Check if first URL is a video
        let isVideo = firstUrl.contains(".mp4") ||
                      firstUrl.contains(".m4v") ||
                      firstUrl.contains(".mov") ||
                      firstUrl.contains(".webm")

        if isVideo {
            // For video posts, thumbnail is the second URL
            return urls.count > 1 ? urls[1] : nil
        }

        // For image/live_photo, use the first URL
        return urls[0]
    }

    /// Check if this post contains video content
    var isVideoPost: Bool {
        guard let urls = mediaUrls, !urls.isEmpty else { return false }
        let firstUrl = urls[0].lowercased()
        return firstUrl.contains(".mp4") ||
               firstUrl.contains(".m4v") ||
               firstUrl.contains(".mov") ||
               firstUrl.contains(".webm")
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
