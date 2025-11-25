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
        var urlComponents = URLComponents(string: "\(APIConfig.current.baseURL)\(APIConfig.Feed.getFeed)")

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "algo", value: algo.rawValue),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 100)))
        ]

        if let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }

        urlComponents?.queryItems = queryItems

        guard let url = urlComponents?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add auth token from client
        if let token = UserDefaults.standard.string(forKey: "authToken") {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = APIConfig.current.timeout
        let session = URLSession(configuration: config)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(FeedResponse.self, from: data)
        case 401:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: message)
        }
    }

    /// Fetch feed with full post details (combines feed + content service)
    func getFeedWithDetails(algo: FeedAlgorithm = .chronological, limit: Int = 20, cursor: String? = nil) async throws -> FeedWithDetailsResponse {
        let feedResponse = try await getFeed(algo: algo, limit: limit, cursor: cursor)

        // TODO: Batch fetch post details from content-service
        // For now, return feed response with empty post details
        return FeedWithDetailsResponse(
            posts: [],  // Will be populated when content-service integration is complete
            postIds: feedResponse.posts,
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

/// Response from feed-service /api/v2/feed endpoint
struct FeedResponse: Codable {
    let posts: [String]  // Array of post UUIDs
    let cursor: String?
    let hasMore: Bool
    let totalCount: Int

    enum CodingKeys: String, CodingKey {
        case posts
        case cursor
        case hasMore = "has_more"
        case totalCount = "total_count"
    }
}

/// Extended feed response with full post details
struct FeedWithDetailsResponse {
    let posts: [FeedPost]
    let postIds: [String]
    let cursor: String?
    let hasMore: Bool
    let totalCount: Int
}

/// Feed post with full details
struct FeedPost: Identifiable, Codable {
    let id: String
    let authorId: String
    let authorName: String
    let authorAvatar: String?
    let content: String
    let mediaUrls: [String]
    let createdAt: Date
    let likeCount: Int
    let commentCount: Int
    let shareCount: Int
    let isLiked: Bool
    let isBookmarked: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case authorId = "author_id"
        case authorName = "author_name"
        case authorAvatar = "author_avatar"
        case content
        case mediaUrls = "media_urls"
        case createdAt = "created_at"
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case shareCount = "share_count"
        case isLiked = "is_liked"
        case isBookmarked = "is_bookmarked"
    }
}
