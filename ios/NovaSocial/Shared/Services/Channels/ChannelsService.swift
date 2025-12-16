import Foundation

// MARK: - Channels Service

/// Manages channel subscriptions and content
/// Handles channel listing, subscription, and content retrieval
class ChannelsService {
    static let shared = ChannelsService()
    private let client = APIClient.shared

    private init() {}

    // MARK: - Get All Channels

    /// Get list of all available channels
    /// - Parameters:
    ///   - limit: Maximum number of channels to return
    ///   - offset: Pagination offset
    ///   - category: Optional category filter
    /// - Returns: List of channels
    func getAllChannels(
        limit: Int = 20,
        offset: Int = 0,
        category: String? = nil
    ) async throws -> ChannelsListResponse {
        var queryParams: [String: String] = [
            "limit": String(limit),
            "offset": String(offset)
        ]

        if let category = category {
            queryParams["category"] = category
        }

        return try await client.get(
            endpoint: APIConfig.Channels.getAllChannels,
            queryParams: queryParams
        )
    }

    // MARK: - Get User Channels

    /// Get channels subscribed by a user
    /// - Parameters:
    ///   - userId: User ID
    ///   - limit: Maximum number of channels to return
    ///   - offset: Pagination offset
    /// - Returns: List of subscribed channels
    func getUserChannels(
        userId: String,
        limit: Int = 20,
        offset: Int = 0
    ) async throws -> ChannelsListResponse {
        return try await client.get(
            endpoint: APIConfig.Channels.getUserChannels(userId),
            queryParams: [
                "limit": String(limit),
                "offset": String(offset)
            ]
        )
    }

    // MARK: - Get Channel Details

    /// Get channel details by ID
    /// - Parameter channelId: Channel ID
    /// - Returns: Channel details
    func getChannelDetails(channelId: String) async throws -> ChannelDetail {
        return try await client.get(
            endpoint: APIConfig.Channels.getChannelDetails(channelId)
        )
    }

    // MARK: - Subscribe/Unsubscribe

    /// Subscribe to a channel
    /// - Parameter channelId: Channel ID to subscribe to
    func subscribeChannel(channelId: String) async throws {
        struct Request: Codable {
            let channelId: String

            enum CodingKeys: String, CodingKey {
                case channelId = "channel_id"
            }
        }

        struct Response: Codable {
            let success: Bool
        }

        let request = Request(channelId: channelId)
        let _: Response = try await client.request(
            endpoint: APIConfig.Channels.subscribeChannel,
            method: "POST",
            body: request
        )
    }

    /// Unsubscribe from a channel
    /// - Parameter channelId: Channel ID to unsubscribe from
    func unsubscribeChannel(channelId: String) async throws {
        struct Request: Codable {
            let channelId: String

            enum CodingKeys: String, CodingKey {
                case channelId = "channel_id"
            }
        }

        struct Response: Codable {
            let success: Bool
        }

        let request = Request(channelId: channelId)
        let _: Response = try await client.request(
            endpoint: APIConfig.Channels.unsubscribeChannel,
            method: "DELETE",
            body: request
        )
    }

    // MARK: - Check Subscription

    /// Check if user is subscribed to a channel
    /// - Parameter channelId: Channel ID to check
    /// - Returns: True if subscribed
    func isSubscribed(channelId: String) async throws -> Bool {
        struct Response: Codable {
            let subscribed: Bool
        }

        let response: Response = try await client.get(
            endpoint: "\(APIConfig.Channels.getChannelDetails(channelId))/subscribed"
        )

        return response.subscribed
    }

    // MARK: - Channel Content

    /// Get posts from a channel
    /// - Parameters:
    ///   - channelId: Channel ID
    ///   - limit: Maximum number of posts to return
    ///   - cursor: Pagination cursor
    /// - Returns: Channel posts response
    func getChannelPosts(
        channelId: String,
        limit: Int = 20,
        cursor: String? = nil
    ) async throws -> ChannelPostsResponse {
        var queryParams: [String: String] = [
            "limit": String(limit)
        ]

        if let cursor = cursor {
            queryParams["cursor"] = cursor
        }

        return try await client.get(
            endpoint: "\(APIConfig.Channels.getChannelDetails(channelId))/posts",
            queryParams: queryParams
        )
    }

    // MARK: - Recommended Channels

    /// Get recommended channels for user
    /// - Parameter limit: Maximum number of recommendations
    /// - Returns: List of recommended channels
    func getRecommendedChannels(limit: Int = 10) async throws -> [ChannelSummary] {
        struct Response: Codable {
            let channels: [ChannelSummary]
        }

        let response: Response = try await client.get(
            endpoint: "\(APIConfig.Channels.getAllChannels)/recommended",
            queryParams: ["limit": String(limit)]
        )

        return response.channels
    }

    // MARK: - Search Channels

    /// Search for channels
    /// - Parameters:
    ///   - query: Search query
    ///   - limit: Maximum number of results
    /// - Returns: List of matching channels
    func searchChannels(query: String, limit: Int = 20) async throws -> [ChannelSummary] {
        struct Response: Codable {
            let channels: [ChannelSummary]
        }

        let response: Response = try await client.get(
            endpoint: "\(APIConfig.Channels.getAllChannels)/search",
            queryParams: [
                "q": query,
                "limit": String(limit)
            ]
        )

        return response.channels
    }
}

// MARK: - Models

/// Channel summary for lists
struct ChannelSummary: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let category: String?
    let thumbnailUrl: String?
    let subscriberCount: Int
    let isSubscribed: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case category
        case thumbnailUrl = "thumbnail_url"
        case subscriberCount = "subscriber_count"
        case isSubscribed = "is_subscribed"
    }
}

/// Detailed channel information
struct ChannelDetail: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let category: String?
    let thumbnailUrl: String?
    let coverUrl: String?
    let subscriberCount: Int
    let postCount: Int
    let isSubscribed: Bool
    let isVerified: Bool
    let createdAt: Date
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case category
        case thumbnailUrl = "thumbnail_url"
        case coverUrl = "cover_url"
        case subscriberCount = "subscriber_count"
        case postCount = "post_count"
        case isSubscribed = "is_subscribed"
        case isVerified = "is_verified"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Channels list response
struct ChannelsListResponse: Codable {
    let channels: [ChannelSummary]
    let total: Int
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case channels
        case total
        case hasMore = "has_more"
    }
}

/// Channel posts response
struct ChannelPostsResponse: Codable {
    let posts: [ChannelPost]
    let nextCursor: String?
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case posts
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
    }
}

/// Post in a channel
struct ChannelPost: Codable, Identifiable {
    let id: String
    let content: String
    let mediaUrls: [String]?
    let authorId: String
    let authorUsername: String?
    let authorAvatarUrl: String?
    let likeCount: Int
    let commentCount: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case content
        case mediaUrls = "media_urls"
        case authorId = "author_id"
        case authorUsername = "author_username"
        case authorAvatarUrl = "author_avatar_url"
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case createdAt = "created_at"
    }
}
