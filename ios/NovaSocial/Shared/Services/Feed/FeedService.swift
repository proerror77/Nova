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
    ///   - channelId: Optional channel ID or slug to filter feed by channel
    /// - Returns: FeedResponse containing post IDs and pagination info
    func getFeed(algo: FeedAlgorithm = .chronological, limit: Int = 20, cursor: String? = nil, channelId: String? = nil) async throws -> FeedResponse {
        var queryParams: [String: String] = [
            "algo": algo.rawValue,
            "limit": String(min(max(limit, 1), 100))
        ]

        if let cursor = cursor {
            queryParams["cursor"] = cursor
        }

        // Add channel filter if provided
        if let channelId = channelId {
            queryParams["channel_id"] = channelId
        }

        // Use unified APIClient.get() for consistent error handling and auth
        return try await client.get(endpoint: APIConfig.Feed.getFeed, queryParams: queryParams)
    }

    // MARK: - Channels

    /// Fetch available channels for feed navigation
    /// - Parameters:
    ///   - enabledOnly: If true, only return enabled channels (default: true)
    ///   - limit: Maximum number of channels to return (default: 50)
    /// - Returns: Array of FeedChannel sorted by display order
    func getChannels(enabledOnly: Bool = true, limit: Int = 50) async throws -> [FeedChannel] {
        var queryParams: [String: String] = [
            "limit": String(limit),
            "enabled_only": String(enabledOnly)
        ]

        struct Response: Codable {
            let channels: [FeedChannel]
            let total: Int?
        }

        let response: Response = try await client.get(
            endpoint: APIConfig.Channels.getAllChannels,
            queryParams: queryParams
        )

        // Sort by display order (lower = first)
        return response.channels.sorted { $0.displayOrder < $1.displayOrder }
    }

    /// Get AI-powered channel suggestions based on post content
    /// - Parameters:
    ///   - content: The post text content
    ///   - hashtags: Optional hashtags from Alice image analysis
    ///   - themes: Optional themes from Alice image analysis
    /// - Returns: Array of channel suggestions with confidence scores
    func suggestChannels(content: String, hashtags: [String]? = nil, themes: [String]? = nil) async throws -> [ChannelSuggestion] {
        struct Request: Codable {
            let content: String
            let hashtags: [String]
            let themes: [String]
        }

        struct Response: Codable {
            let suggestions: [ChannelSuggestion]
        }

        let request = Request(
            content: content,
            hashtags: hashtags ?? [],
            themes: themes ?? []
        )

        let response: Response = try await client.request(
            endpoint: APIConfig.Channels.suggestChannels,
            method: "POST",
            body: request
        )

        return response.suggestions
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

    // MARK: - User Feed

    /// Fetch a specific user's feed (their posts)
    /// - Parameters:
    ///   - userId: The user ID whose feed to fetch
    ///   - limit: Number of posts to fetch (1-100, default 20)
    ///   - cursor: Pagination cursor from previous response
    /// - Returns: FeedResponse containing the user's posts
    func getUserFeed(userId: String, limit: Int = 20, cursor: String? = nil) async throws -> FeedResponse {
        var queryParams: [String: String] = [
            "limit": String(min(max(limit, 1), 100))
        ]

        if let cursor = cursor {
            queryParams["cursor"] = cursor
        }

        return try await client.get(endpoint: APIConfig.Feed.getUserFeed(userId), queryParams: queryParams)
    }

    /// Fetch user feed with full post details
    func getUserFeedWithDetails(userId: String, limit: Int = 20, cursor: String? = nil) async throws -> FeedWithDetailsResponse {
        let feedResponse = try await getUserFeed(userId: userId, limit: limit, cursor: cursor)

        let feedPosts = feedResponse.posts.map { FeedPost(from: $0) }

        return FeedWithDetailsResponse(
            posts: feedPosts,
            postIds: feedResponse.postIds,
            cursor: feedResponse.cursor,
            hasMore: feedResponse.hasMore,
            totalCount: feedResponse.totalCount
        )
    }

    // MARK: - Explore Feed

    /// Fetch explore feed for discovering new content
    /// - Parameters:
    ///   - limit: Number of posts to fetch (1-100, default 20)
    ///   - cursor: Pagination cursor from previous response
    /// - Returns: FeedResponse containing explore/discovery posts
    func getExploreFeed(limit: Int = 20, cursor: String? = nil) async throws -> FeedResponse {
        var queryParams: [String: String] = [
            "limit": String(min(max(limit, 1), 100))
        ]

        if let cursor = cursor {
            queryParams["cursor"] = cursor
        }

        return try await client.get(endpoint: APIConfig.Feed.getExplore, queryParams: queryParams)
    }

    /// Fetch explore feed with full post details
    func getExploreFeedWithDetails(limit: Int = 20, cursor: String? = nil) async throws -> FeedWithDetailsResponse {
        let feedResponse = try await getExploreFeed(limit: limit, cursor: cursor)

        let feedPosts = feedResponse.posts.map { FeedPost(from: $0) }

        return FeedWithDetailsResponse(
            posts: feedPosts,
            postIds: feedResponse.postIds,
            cursor: feedResponse.cursor,
            hasMore: feedResponse.hasMore,
            totalCount: feedResponse.totalCount
        )
    }

    // MARK: - Authenticated Trending Feed

    /// Fetch trending feed (requires authentication)
    /// - Parameters:
    ///   - limit: Number of posts to fetch (1-100, default 20)
    ///   - cursor: Pagination cursor from previous response
    /// - Returns: FeedResponse containing trending posts
    func getAuthenticatedTrendingFeed(limit: Int = 20, cursor: String? = nil) async throws -> FeedResponse {
        var queryParams: [String: String] = [
            "limit": String(min(max(limit, 1), 100))
        ]

        if let cursor = cursor {
            queryParams["cursor"] = cursor
        }

        return try await client.get(endpoint: APIConfig.Feed.getTrendingFeed, queryParams: queryParams)
    }

    // MARK: - Recommendations

    /// Get recommended creators for the user to follow
    func getRecommendedCreators(limit: Int = 20) async throws -> [RecommendedCreator] {
        struct Response: Codable {
            let creators: [RecommendedCreator]
        }

        let response: Response = try await client.get(
            endpoint: APIConfig.Feed.getRecommendedCreators,
            queryParams: ["limit": String(limit)]
        )

        return response.creators
    }

    /// Rank posts using feed-service ranking algorithm
    func rankPosts(userId: String, posts: [String], context: RankingContext? = nil) async throws -> [RankedPost] {
        struct Request: Codable {
            let userId: String
            let posts: [String]
            let context: RankingContext?

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case posts
                case context
            }
        }

        struct Response: Codable {
            let rankedPosts: [RankedPost]

            enum CodingKeys: String, CodingKey {
                case rankedPosts = "ranked_posts"
            }
        }

        let request = Request(userId: userId, posts: posts, context: context)

        let response: Response = try await client.request(
            endpoint: APIConfig.Feed.rankPosts,
            method: "POST",
            body: request
        )

        return response.rankedPosts
    }

    /// Invalidate feed cache for a user (e.g., after follow/unfollow)
    func invalidateFeedCache(userId: String, eventType: String) async throws {
        struct Request: Codable {
            let userId: String
            let eventType: String

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case eventType = "event_type"
            }
        }

        struct Response: Codable {
            let success: Bool
        }

        let request = Request(userId: userId, eventType: eventType)

        let _: Response = try await client.request(
            endpoint: APIConfig.Feed.invalidateCache,
            method: "POST",
            body: request
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

    // Author information (optional for backward compatibility)
    let authorUsername: String?
    let authorDisplayName: String?
    let authorAvatar: String?
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

// MARK: - Media Type

/// Media type for feed posts
enum FeedMediaType: String, Codable {
    case image = "image"
    case video = "video"
    case livePhoto = "live_photo"  // Live Photo (still image + short video)
    case mixed = "mixed"  // Post contains both images and videos
    
    /// Determine media type from URL extension
    static func from(url: String) -> FeedMediaType {
        let lowercased = url.lowercased()
        if lowercased.contains(".mp4") || lowercased.contains(".m4v") || lowercased.contains(".webm") {
            return .video
        }
        // MOV could be Live Photo video or regular video
        if lowercased.contains(".mov") {
            return .video
        }
        return .image
    }
    
    /// Determine media type from array of URLs
    static func from(urls: [String]) -> FeedMediaType {
        guard !urls.isEmpty else { return .image }
        
        let types = urls.map { FeedMediaType.from(url: $0) }
        let hasVideo = types.contains(.video)
        let hasImage = types.contains(.image)
        
        if hasVideo && hasImage {
            return .mixed
        } else if hasVideo {
            return .video
        }
        return .image
    }
    
    /// Check if this is a Live Photo type
    var isLivePhoto: Bool {
        self == .livePhoto
    }
}

/// Feed post with full details for UI display
/// Note: Uses APIClient's convertFromSnakeCase for automatic key mapping
/// Equatable for efficient SwiftUI diffing
struct FeedPost: Identifiable, Codable, Equatable {
    // MARK: - Equatable (only compare fields that affect UI)
    static func == (lhs: FeedPost, rhs: FeedPost) -> Bool {
        lhs.id == rhs.id &&
        lhs.likeCount == rhs.likeCount &&
        lhs.commentCount == rhs.commentCount &&
        lhs.isLiked == rhs.isLiked &&
        lhs.isBookmarked == rhs.isBookmarked
    }
    let id: String
    let authorId: String
    let authorName: String
    let authorAvatar: String?
    let content: String
    let mediaUrls: [String]
    let thumbnailUrls: [String]
    let mediaType: FeedMediaType
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
    
    /// Check if this post contains video content
    var hasVideo: Bool {
        mediaType == .video || mediaType == .mixed
    }
    
    /// Check if this post is a Live Photo
    var isLivePhoto: Bool {
        mediaType == .livePhoto
    }
    
    /// Get the first video URL if available
    var firstVideoUrl: URL? {
        guard hasVideo else { return nil }
        return mediaUrls.first { FeedMediaType.from(url: $0) == .video }
            .flatMap { URL(string: $0) }
    }
    
    /// Get thumbnail URL for video (first thumbnail or nil)
    var videoThumbnailUrl: URL? {
        guard hasVideo else { return nil }
        return thumbnailUrls.first.flatMap { URL(string: $0) }
    }
    
    /// Get Live Photo image URL (first URL for live_photo type)
    var livePhotoImageUrl: URL? {
        guard isLivePhoto, let first = mediaUrls.first else { return nil }
        return URL(string: first)
    }
    
    /// Get Live Photo video URL (second URL for live_photo type)
    var livePhotoVideoUrl: URL? {
        guard isLivePhoto, mediaUrls.count >= 2 else { return nil }
        return URL(string: mediaUrls[1])
    }

    /// Create FeedPost from raw backend response
    init(from raw: FeedPostRaw) {
        self.id = raw.id
        self.authorId = raw.userId

        // Use real author information from backend with graceful fallback
        // Priority: display_name > username > placeholder
        if let displayName = raw.authorDisplayName, !displayName.isEmpty {
            self.authorName = displayName
        } else if let username = raw.authorUsername, !username.isEmpty {
            self.authorName = username
        } else {
            // Fallback to placeholder for backward compatibility
            self.authorName = "User \(raw.userId.prefix(8))"
        }

        self.authorAvatar = raw.authorAvatar
        self.content = raw.content
        self.mediaUrls = raw.mediaUrls ?? []
        self.thumbnailUrls = raw.thumbnailUrls ?? self.mediaUrls
        // Determine media type from backend or infer from URLs
        if let rawType = raw.mediaType {
            self.mediaType = FeedMediaType(rawValue: rawType) ?? FeedMediaType.from(urls: self.mediaUrls)
        } else {
            self.mediaType = FeedMediaType.from(urls: self.mediaUrls)
        }
        self.createdAt = Date(timeIntervalSince1970: Double(raw.createdAt))
        self.likeCount = raw.likeCount ?? 0
        self.commentCount = raw.commentCount ?? 0
        self.shareCount = raw.shareCount ?? 0
        self.isLiked = false
        self.isBookmarked = false
    }

    // Keep existing init for Codable conformance and manual creation
    init(id: String, authorId: String, authorName: String, authorAvatar: String?,
        content: String, mediaUrls: [String], mediaType: FeedMediaType? = nil, createdAt: Date,
         likeCount: Int, commentCount: Int, shareCount: Int,
         isLiked: Bool, isBookmarked: Bool) {
        self.id = id
        self.authorId = authorId
        self.authorName = authorName
        self.authorAvatar = authorAvatar
        self.content = content
        self.mediaUrls = mediaUrls
        self.thumbnailUrls = mediaUrls
        // Use provided type or infer from URLs
        self.mediaType = mediaType ?? FeedMediaType.from(urls: mediaUrls)
        self.createdAt = createdAt
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.shareCount = shareCount
        self.isLiked = isLiked
        self.isBookmarked = isBookmarked
    }

    /// Create a copy with optional field overrides (eliminates duplicate creation code)
    func copying(
        authorAvatar: String?? = nil,  // Double optional: nil = keep original, .some(nil) = set to nil, .some(value) = update
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
            authorAvatar: authorAvatar ?? self.authorAvatar,
            content: self.content,
            mediaUrls: self.mediaUrls,
            mediaType: self.mediaType,
            createdAt: self.createdAt,
            likeCount: likeCount ?? self.likeCount,
            commentCount: commentCount ?? self.commentCount,
            shareCount: shareCount ?? self.shareCount,
            isLiked: isLiked ?? self.isLiked,
            isBookmarked: isBookmarked ?? self.isBookmarked
        )
    }

    /// Create FeedPost from content-service Post model (for Profile page navigation)
    init(from post: Post, authorName: String, authorAvatar: String?) {
        self.id = post.id
        self.authorId = post.authorId
        self.authorName = authorName
        self.authorAvatar = authorAvatar
        self.content = post.content
        self.mediaUrls = post.mediaUrls ?? []
        self.thumbnailUrls = post.mediaUrls ?? []
        self.mediaType = FeedMediaType.from(urls: post.mediaUrls ?? [])
        self.createdAt = Date(timeIntervalSince1970: Double(post.createdAt))
        self.likeCount = post.likeCount ?? 0
        self.commentCount = post.commentCount ?? 0
        self.shareCount = post.shareCount ?? 0
        self.isLiked = false
        self.isBookmarked = false
    }
}

// MARK: - Recommendation Models

/// Recommended creator/user to follow
struct RecommendedCreator: Codable, Identifiable {
    let id: String  // user_id
    let username: String
    let displayName: String
    let avatarUrl: String?
    let bio: String?
    let followerCount: Int
    let isVerified: Bool
    let relevanceScore: Double  // How relevant this creator is to the user (0.0 - 1.0)
    let reason: String?  // Why this creator is recommended (e.g., "Popular in your network")

    enum CodingKeys: String, CodingKey {
        case id = "user_id"
        case username
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case bio
        case followerCount = "follower_count"
        case isVerified = "is_verified"
        case relevanceScore = "relevance_score"
        case reason
    }
}

/// Ranked post with scoring information
struct RankedPost: Codable, Identifiable {
    let id: String  // post_id
    let score: Double  // Ranking score
    let rank: Int?  // Position in ranked list

    enum CodingKeys: String, CodingKey {
        case id = "post_id"
        case score
        case rank
    }
}

/// Context for ranking posts
struct RankingContext: Codable {
    let location: String?
    let deviceType: String?
    let timeOfDay: Int?  // Hour of day (0-23)

    enum CodingKeys: String, CodingKey {
        case location
        case deviceType = "device_type"
        case timeOfDay = "time_of_day"
    }
}

// MARK: - Channel Models

/// Channel for feed navigation and filtering
/// Represents a content category or topic that users can browse
struct FeedChannel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let slug: String
    let description: String?
    let category: String?
    let iconUrl: String?
    let displayOrder: Int
    let isEnabled: Bool
    let subscriberCount: Int?

    // Note: CodingKeys removed - APIClient uses .convertFromSnakeCase which automatically
    // converts snake_case keys (display_order, icon_url, etc.) to camelCase properties.
    // Having explicit CodingKeys conflicts with this automatic conversion.

    // Default initializer for fallback/mock data
    init(id: String, name: String, slug: String, description: String? = nil,
         category: String? = nil, iconUrl: String? = nil,
         displayOrder: Int = 100, isEnabled: Bool = true, subscriberCount: Int? = nil) {
        self.id = id
        self.name = name
        self.slug = slug
        self.description = description
        self.category = category
        self.iconUrl = iconUrl
        self.displayOrder = displayOrder
        self.isEnabled = isEnabled
        self.subscriberCount = subscriberCount
    }

    // Fallback channels when API is unavailable
    static let fallbackChannels: [FeedChannel] = [
        FeedChannel(id: "fashion", name: "Fashion", slug: "fashion", displayOrder: 1),
        FeedChannel(id: "travel", name: "Travel", slug: "travel", displayOrder: 2),
        FeedChannel(id: "fitness", name: "Fitness", slug: "fitness", displayOrder: 3),
        FeedChannel(id: "pets", name: "Pets", slug: "pets", displayOrder: 4),
        FeedChannel(id: "study", name: "Study", slug: "study", displayOrder: 5),
        FeedChannel(id: "career", name: "Career", slug: "career", displayOrder: 6),
        FeedChannel(id: "tech", name: "Tech", slug: "tech", displayOrder: 7)
    ]
}

/// AI-powered channel suggestion for post classification
struct ChannelSuggestion: Codable, Identifiable {
    let id: String
    let name: String
    let slug: String
    /// Confidence score (0.0 - 1.0)
    let confidence: Float
    /// Keywords that matched the post content
    let matchedKeywords: [String]
}
