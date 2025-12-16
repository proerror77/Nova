import Foundation

// MARK: - Content Service

/// Manages content (posts, bookmarks) using content-service backend
/// Handles post CRUD operations and bookmark management
class ContentService {
    private let client = APIClient.shared

    // MARK: - Posts

    func getPostsByAuthor(authorId: String, limit: Int = 20, offset: Int = 0) async throws -> GetPostsByAuthorResponse {
        // Use GET /api/v2/content/user/{user_id} with query params
        return try await client.get(
            endpoint: APIConfig.Content.postsByUser(authorId),
            queryParams: [
                "limit": String(limit),
                "offset": String(offset)
            ]
        )
    }

    func createPost(creatorId: String, content: String, mediaUrls: [String]? = nil, channelIds: [String]? = nil) async throws -> Post {
        // The graphql-gateway now accepts media_urls as a separate field
        // It extracts user_id from the JWT token (AuthenticatedUser)
        struct Request: Codable {
            let content: String
            let mediaUrls: [String]?
            let mediaType: String?
            let channelIds: [String]?

            enum CodingKeys: String, CodingKey {
                case content
                case mediaUrls = "media_urls"
                case mediaType = "media_type"
                case channelIds = "channel_ids"
            }
        }

        struct Response: Codable {
            let post: Post
        }

        // Determine media type based on URLs
        let mediaType: String? = if let urls = mediaUrls, !urls.isEmpty {
            "image"
        } else {
            nil
        }

        let request = Request(
            content: content,
            mediaUrls: mediaUrls,
            mediaType: mediaType,
            channelIds: channelIds
        )
        let response: Response = try await client.request(
            endpoint: APIConfig.Content.createPost,
            method: "POST",
            body: request
        )

        return response.post
    }

    /// Get single post by ID using GET /api/v2/content/{id}
    func getPost(postId: String) async throws -> Post? {
        struct Response: Codable {
            let post: Post
            let found: Bool?
            // Note: Uses convertFromSnakeCase decoder strategy
        }

        do {
            let response: Response = try await client.request(
                endpoint: APIConfig.Content.getPost(postId),
                method: "GET"
            )
            return response.post
        } catch APIError.notFound {
            return nil
        }
    }

    /// Batch fetch posts by IDs (parallel requests)
    func getPostsByIds(_ ids: [String]) async throws -> [Post] {
        guard !ids.isEmpty else { return [] }

        return try await withThrowingTaskGroup(of: Post?.self) { group in
            for id in ids {
                group.addTask {
                    try? await self.getPost(postId: id)
                }
            }

            var posts: [Post] = []
            for try await post in group {
                if let post = post {
                    posts.append(post)
                }
            }

            // Sort by original ID order
            let idOrder = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
            return posts.sorted { (idOrder[$0.id] ?? Int.max) < (idOrder[$1.id] ?? Int.max) }
        }
    }

    /// Update an existing post
    func updatePost(postId: String, content: String? = nil, visibility: PostVisibility? = nil, commentsEnabled: Bool? = nil) async throws -> Post {
        struct Request: Codable {
            let content: String?
            let visibility: String?
            let commentsEnabled: Bool?

            enum CodingKeys: String, CodingKey {
                case content
                case visibility
                case commentsEnabled = "comments_enabled"
            }
        }

        struct Response: Codable {
            let post: Post
        }

        let request = Request(
            content: content,
            visibility: visibility?.rawValue,
            commentsEnabled: commentsEnabled
        )

        let response: Response = try await client.request(
            endpoint: APIConfig.Content.updatePost(postId),
            method: "PUT",
            body: request
        )

        return response.post
    }

    /// Delete a post
    func deletePost(postId: String) async throws {
        struct Response: Codable {
            let postId: String
            let deletedAt: String

            enum CodingKeys: String, CodingKey {
                case postId = "post_id"
                case deletedAt = "deleted_at"
            }
        }

        let _: Response = try await client.request(
            endpoint: APIConfig.Content.deletePost(postId),
            method: "DELETE"
        )
    }

    /// Get list of recent posts
    func getRecentPosts(limit: Int = 20, excludeUserId: String? = nil) async throws -> [String] {
        var queryParams: [String: String] = [
            "limit": String(limit)
        ]

        if let excludeUserId = excludeUserId {
            queryParams["exclude_user_id"] = excludeUserId
        }

        struct Response: Codable {
            let postIds: [String]

            enum CodingKeys: String, CodingKey {
                case postIds = "post_ids"
            }
        }

        let response: Response = try await client.get(
            endpoint: APIConfig.Content.recentPosts,
            queryParams: queryParams
        )

        return response.postIds
    }

    /// Get list of trending posts
    func getTrendingPosts(limit: Int = 20, excludeUserId: String? = nil) async throws -> [String] {
        var queryParams: [String: String] = [
            "limit": String(limit)
        ]

        if let excludeUserId = excludeUserId {
            queryParams["exclude_user_id"] = excludeUserId
        }

        struct Response: Codable {
            let postIds: [String]

            enum CodingKeys: String, CodingKey {
                case postIds = "post_ids"
            }
        }

        let response: Response = try await client.get(
            endpoint: APIConfig.Content.trendingPosts,
            queryParams: queryParams
        )

        return response.postIds
    }

    // MARK: - Channels

    /// Get list of all channels
    func getAllChannels(limit: Int = 20, offset: Int = 0, category: String? = nil) async throws -> GetChannelsResponse {
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

    /// Get channel details by ID
    func getChannel(channelId: String) async throws -> Channel {
        return try await client.get(endpoint: APIConfig.Channels.getChannelDetails(channelId))
    }

    // MARK: - Bookmarks

    func getUserBookmarks(userId: String, limit: Int = 20, offset: Int = 0) async throws -> GetUserBookmarksResponse {
        return try await client.get(
            endpoint: APIConfig.Social.getBookmarks,
            queryParams: [
                "user_id": userId,
                "limit": String(limit),
                "offset": String(offset)
            ]
        )
    }
}

// MARK: - Supporting Types

/// Post visibility setting
enum PostVisibility: String, Codable {
    case `public` = "public"
    case followers = "followers"
    case `private` = "private"
}

/// Channel model
struct Channel: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let category: String?
    let subscriberCount: Int
    let thumbnailUrl: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case category
        case subscriberCount = "subscriber_count"
        case thumbnailUrl = "thumbnail_url"
        case createdAt = "created_at"
    }
}

/// Channels list response
struct GetChannelsResponse: Codable {
    let channels: [Channel]
    let totalCount: Int
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case channels
        case totalCount = "total_count"
        case hasMore = "has_more"
    }
}
