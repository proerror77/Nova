import Foundation

// MARK: - Trending Service

/// Manages trending content retrieval using feed-service backend
/// Handles trending posts, videos, streams, and categories
class TrendingService {
    private let client = APIClient.shared

    // MARK: - Trending Content

    /// Fetch overall trending content
    /// - Parameters:
    ///   - limit: Number of items to fetch (default 20)
    ///   - cursor: Pagination cursor
    /// - Returns: TrendingResponse containing mixed trending content
    func getTrending(limit: Int = 20, cursor: String? = nil) async throws -> TrendingResponse {
        var queryParams: [String: String] = [
            "limit": String(min(max(limit, 1), 100))
        ]

        if let cursor = cursor {
            queryParams["cursor"] = cursor
        }

        return try await client.get(endpoint: APIConfig.Trending.getTrending, queryParams: queryParams)
    }

    /// Fetch trending videos
    func getTrendingVideos(limit: Int = 20, cursor: String? = nil) async throws -> TrendingVideosResponse {
        var queryParams: [String: String] = [
            "limit": String(min(max(limit, 1), 100))
        ]

        if let cursor = cursor {
            queryParams["cursor"] = cursor
        }

        return try await client.get(endpoint: APIConfig.Trending.getVideos, queryParams: queryParams)
    }

    /// Fetch trending posts
    func getTrendingPosts(limit: Int = 20, cursor: String? = nil) async throws -> TrendingPostsResponse {
        var queryParams: [String: String] = [
            "limit": String(min(max(limit, 1), 100))
        ]

        if let cursor = cursor {
            queryParams["cursor"] = cursor
        }

        return try await client.get(endpoint: APIConfig.Trending.getPosts, queryParams: queryParams)
    }

    /// Fetch trending streams (live)
    func getTrendingStreams(limit: Int = 20) async throws -> TrendingStreamsResponse {
        let queryParams: [String: String] = [
            "limit": String(min(max(limit, 1), 50))
        ]

        return try await client.get(endpoint: APIConfig.Trending.getStreams, queryParams: queryParams)
    }

    /// Fetch trending categories
    func getTrendingCategories() async throws -> TrendingCategoriesResponse {
        return try await client.get(endpoint: APIConfig.Trending.getCategories)
    }

    // MARK: - Engagement Tracking

    /// Record user engagement with trending content
    /// - Parameters:
    ///   - contentId: ID of the content engaged with
    ///   - contentType: Type of content (post, video, stream)
    ///   - engagementType: Type of engagement (view, like, share, click)
    func recordEngagement(contentId: String, contentType: String, engagementType: String) async throws {
        struct Request: Codable {
            let contentId: String
            let contentType: String
            let engagementType: String
        }

        struct EmptyResponse: Codable {}

        let request = Request(
            contentId: contentId,
            contentType: contentType,
            engagementType: engagementType
        )

        let _: EmptyResponse = try await client.request(
            endpoint: APIConfig.Trending.recordEngagement,
            method: "POST",
            body: request
        )
    }
}

// MARK: - Response Models

/// Generic trending response
struct TrendingResponse: Codable {
    let items: [TrendingItem]
    let cursor: String?
    let hasMore: Bool
}

/// Individual trending item (can be post, video, or stream)
struct TrendingItem: Codable, Identifiable {
    let id: String
    let type: String  // "post", "video", "stream"
    let title: String?
    let content: String?
    let thumbnailUrl: String?
    let authorId: String
    let authorName: String?
    let authorAvatarUrl: String?
    let viewCount: Int
    let likeCount: Int
    let commentCount: Int
    let shareCount: Int
    let createdAt: Int64
    let trendingScore: Double?
}

/// Trending videos response
struct TrendingVideosResponse: Codable {
    let videos: [TrendingVideo]
    let cursor: String?
    let hasMore: Bool
}

struct TrendingVideo: Codable, Identifiable {
    let id: String
    let title: String
    let thumbnailUrl: String?
    let videoUrl: String?
    let duration: Int?  // seconds
    let authorId: String
    let authorName: String?
    let authorAvatarUrl: String?
    let viewCount: Int
    let likeCount: Int
    let createdAt: Int64
}

/// Trending posts response
struct TrendingPostsResponse: Codable {
    let posts: [TrendingPost]
    let cursor: String?
    let hasMore: Bool
}

struct TrendingPost: Codable, Identifiable {
    let id: String
    let content: String
    let mediaUrls: [String]?
    let authorId: String
    let authorName: String?
    let authorAvatarUrl: String?
    let likeCount: Int
    let commentCount: Int
    let shareCount: Int
    let createdAt: Int64
}

/// Trending streams response
struct TrendingStreamsResponse: Codable {
    let streams: [TrendingStream]
    let hasMore: Bool
}

struct TrendingStream: Codable, Identifiable {
    let id: String
    let title: String
    let thumbnailUrl: String?
    let streamUrl: String?
    let hostId: String
    let hostName: String?
    let hostAvatarUrl: String?
    let viewerCount: Int
    let startedAt: Int64
    let isLive: Bool
}

/// Trending categories response
struct TrendingCategoriesResponse: Codable {
    let categories: [TrendingCategory]
}

struct TrendingCategory: Codable, Identifiable {
    let id: String
    let name: String
    let iconUrl: String?
    let postCount: Int
    let trendingScore: Double?
}
