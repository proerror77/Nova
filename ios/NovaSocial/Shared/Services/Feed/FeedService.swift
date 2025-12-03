import Foundation

// MARK: - Feed Service

/// Manages feed retrieval using feed-service backend
/// Handles paginated feed loading with cursor-based pagination
class FeedService {
    private let client = APIClient.shared

    // MARK: - Feed Retrieval

    /// Fetch user's personalized feed
    /// - Parameters:
    ///   - algo: Algorithm type ("ch" for chronological, "time" for time-based)
    ///   - limit: Number of posts to fetch (1-100, default 20)
    ///   - cursor: Pagination cursor from previous response
    /// - Returns: FeedResponse containing post IDs and pagination info
    func getFeed(algo: FeedAlgorithm = .chronological, limit: Int = 20, cursor: String? = nil) async throws -> FeedResponse {
        var queryParams: [String: String] = [
            "algo": algo.rawValue,
            "limit": String(min(max(limit, 1), 100))
        ]

        if let cursor = cursor {
            queryParams["cursor"] = cursor
        }

        // Use unified APIClient.get() for consistent error handling and auth
        return try await client.get(endpoint: APIConfig.Feed.getFeed, queryParams: queryParams)
    }

    // MARK: - Guest Feed (No Authentication)

    /// Fetch trending/guest feed for unauthenticated users
    /// Uses /api/v2/feed/trending endpoint which doesn't require JWT
    /// - Parameters:
    ///   - limit: Number of posts to fetch (1-50, default 20)
    ///   - cursor: Pagination cursor from previous response
    /// - Returns: FeedResponse containing trending post IDs
    func getTrendingFeed(limit: Int = 20, cursor: String? = nil) async throws -> FeedResponse {
        var queryParams: [String: String] = [
            "limit": String(min(max(limit, 1), 50))  // Guest feed has stricter limit (50 max)
        ]

        if let cursor = cursor {
            queryParams["cursor"] = cursor
        }

        // Use public endpoint that doesn't require authentication
        return try await client.get(endpoint: APIConfig.Feed.getTrending, queryParams: queryParams)
    }

    /// Fetch trending feed with full post details
    func getTrendingFeedWithDetails(limit: Int = 20, cursor: String? = nil) async throws -> FeedWithDetailsResponse {
        let feedResponse = try await getTrendingFeed(limit: limit, cursor: cursor)

        // Convert raw posts to FeedPost objects
        let feedPosts = feedResponse.posts.map { FeedPost(from: $0) }

        return FeedWithDetailsResponse(
            posts: feedPosts,
            postIds: feedResponse.postIds,
            cursor: feedResponse.cursor,
            hasMore: feedResponse.hasMore,
            totalCount: feedResponse.totalCount
        )
    }

    /// Fetch feed with full post details (combines feed + content service)
    func getFeedWithDetails(algo: FeedAlgorithm = .chronological, limit: Int = 20, cursor: String? = nil) async throws -> FeedWithDetailsResponse {
        let feedResponse = try await getFeed(algo: algo, limit: limit, cursor: cursor)

        // Convert raw posts to FeedPost objects
        let feedPosts = feedResponse.posts.map { FeedPost(from: $0) }

        return FeedWithDetailsResponse(
            posts: feedPosts,
            postIds: feedResponse.postIds,
            cursor: feedResponse.cursor,
            hasMore: feedResponse.hasMore,
            totalCount: feedResponse.totalCount
        )
    }
}

// MARK: - Feed Algorithm

enum FeedAlgorithm: String {
    case chronological = "ch"
    case timeBased = "time"
}

// MARK: - Response Models

/// Raw post object from feed-service /api/v2/feed endpoint
/// Matches backend response format exactly
/// Note: Uses APIClient's convertFromSnakeCase for automatic key mapping
struct FeedPostRaw: Codable {
    let id: String
    let userId: String
    let content: String
    let createdAt: Int64
    let rankingScore: Double?
    let likeCount: Int?
    let commentCount: Int?
    let shareCount: Int?
    let mediaUrls: [String]?
    let thumbnailUrls: [String]?
    let mediaType: String?
}

/// Response from feed-service /api/v2/feed endpoint
/// Backend returns full post objects, not just IDs
/// Note: Uses APIClient's convertFromSnakeCase for automatic key mapping
struct FeedResponse: Codable {
    let posts: [FeedPostRaw]
    let hasMore: Bool

    /// Convenience accessor for post IDs
    var postIds: [String] {
        posts.map { $0.id }
    }

    /// Placeholder for cursor-based pagination (backend doesn't return cursor yet)
    var cursor: String? { nil }

    /// Placeholder for total count
    var totalCount: Int? { posts.count }
}

/// Extended feed response with full post details
struct FeedWithDetailsResponse {
    let posts: [FeedPost]
    let postIds: [String]
    let cursor: String?
    let hasMore: Bool
    let totalCount: Int?
}

/// Feed post with full details for UI display
/// Note: Uses APIClient's convertFromSnakeCase for automatic key mapping
struct FeedPost: Identifiable, Codable {
    let id: String
    let authorId: String
    let authorName: String
    let authorAvatar: String?
    let content: String
    let mediaUrls: [String]
    let thumbnailUrls: [String]
    let createdAt: Date
    let likeCount: Int
    let commentCount: Int
    let shareCount: Int
    let isLiked: Bool
    let isBookmarked: Bool

    /// Prefer thumbnails for list performance; fall back to originals when missing.
    var displayMediaUrls: [String] {
        if !thumbnailUrls.isEmpty {
            return thumbnailUrls
        }
        return mediaUrls
    }

    /// Create FeedPost from raw backend response
    init(from raw: FeedPostRaw) {
        self.id = raw.id
        self.authorId = raw.userId
        self.authorName = "User \(raw.userId.prefix(8))"  // Placeholder until user profile fetch
        self.authorAvatar = nil
        self.content = raw.content
        self.mediaUrls = raw.mediaUrls ?? []
        self.thumbnailUrls = raw.thumbnailUrls ?? self.mediaUrls
        self.createdAt = Date(timeIntervalSince1970: Double(raw.createdAt))
        self.likeCount = raw.likeCount ?? 0
        self.commentCount = raw.commentCount ?? 0
        self.shareCount = raw.shareCount ?? 0
        self.isLiked = false
        self.isBookmarked = false
    }

    // Keep existing init for Codable conformance
    init(id: String, authorId: String, authorName: String, authorAvatar: String?,
        content: String, mediaUrls: [String], createdAt: Date,
         likeCount: Int, commentCount: Int, shareCount: Int,
         isLiked: Bool, isBookmarked: Bool) {
        self.id = id
        self.authorId = authorId
        self.authorName = authorName
        self.authorAvatar = authorAvatar
        self.content = content
        self.mediaUrls = mediaUrls
        self.thumbnailUrls = mediaUrls
        self.createdAt = createdAt
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.shareCount = shareCount
        self.isLiked = isLiked
        self.isBookmarked = isBookmarked
    }

    /// Create a copy with optional field overrides (eliminates duplicate creation code)
    func copying(
        likeCount: Int? = nil,
        commentCount: Int? = nil,
        shareCount: Int? = nil,
        isLiked: Bool? = nil,
        isBookmarked: Bool? = nil
    ) -> FeedPost {
        FeedPost(
            id: self.id,
            authorId: self.authorId,
            authorName: self.authorName,
            authorAvatar: self.authorAvatar,
            content: self.content,
            mediaUrls: self.mediaUrls,
            createdAt: self.createdAt,
            likeCount: likeCount ?? self.likeCount,
            commentCount: commentCount ?? self.commentCount,
            shareCount: shareCount ?? self.shareCount,
            isLiked: isLiked ?? self.isLiked,
            isBookmarked: isBookmarked ?? self.isBookmarked
        )
    }
}
