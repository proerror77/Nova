import Foundation

// MARK: - Social Service

/// Manages social interactions using social-service backend
/// Handles likes, comments, shares, and feeds
class SocialService {
    private let client = APIClient.shared

    // MARK: - Feeds

    // MARK: - Request/Response Models for Feed API

    struct FeedRequest: Codable {
        let userId: String?
        let limit: Int
        let cursor: String?

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case limit
            case cursor
        }
    }

    struct FeedResponse: Codable {
        let posts: [Post]
        let nextCursor: String?
        let hasMore: Bool

        enum CodingKeys: String, CodingKey {
            case posts
            case nextCursor = "next_cursor"
            case hasMore = "has_more"
        }
    }

    /// Get user's personalized feed (v2 API)
    /// GET /api/v2/feed?user_id={userId}&limit={limit}&cursor={cursor}
    /// Calls feed-service which aggregates content from multiple sources
    /// Note: Backend uses GET with query parameters, not POST with JSON body
    func getUserFeed(userId: String, limit: Int = 20, cursor: String? = nil) async throws -> (posts: [Post], nextCursor: String?, hasMore: Bool) {
        // Build query string with URL encoding
        var endpoint = "\(APIConfig.Feed.baseFeed)?user_id=\(userId)&limit=\(limit)"
        if let cursor = cursor, !cursor.isEmpty {
            if let encodedCursor = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                endpoint += "&cursor=\(encodedCursor)"
            }
        }

        let response: FeedResponse = try await client.request(
            endpoint: endpoint,
            method: "GET"
        )

        return (
            posts: response.posts,
            nextCursor: response.nextCursor,
            hasMore: response.hasMore
        )
    }

    /// Get explore/discover feed (v2 API)
    /// GET /api/v2/feed?user_id=explore&limit={limit}
    /// Note: Backend's discover handler is not registered yet, using base feed with "explore" user_id as workaround
    /// TODO: Update to /api/v2/discover when backend handler is registered
    func getExploreFeed(limit: Int = 20, cursor: String? = nil) async throws -> (posts: [Post], nextCursor: String?, hasMore: Bool) {
        // Temporary workaround: use base feed endpoint with special "explore" user_id
        // Backend's get_suggested_users handler exists but is not registered in main.rs
        var endpoint = "\(APIConfig.Feed.baseFeed)?user_id=explore&limit=\(limit)"
        if let cursor = cursor, !cursor.isEmpty {
            if let encodedCursor = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                endpoint += "&cursor=\(encodedCursor)"
            }
        }

        let response: FeedResponse = try await client.request(
            endpoint: endpoint,
            method: "GET"
        )

        return (
            posts: response.posts,
            nextCursor: response.nextCursor,
            hasMore: response.hasMore
        )
    }

    /// Get trending posts (v2 API)
    /// GET /api/v2/feed?user_id=trending&limit={limit}
    /// Note: Backend's trending handlers are not registered yet, using base feed with "trending" user_id as workaround
    /// TODO: Update to /api/v2/trending when backend handlers (get_trending, get_trending_posts) are registered
    func getTrendingPosts(limit: Int = 20) async throws -> [Post] {
        // Temporary workaround: use base feed endpoint with special "trending" user_id
        // Backend's trending handlers exist but are not registered in main.rs:
        // - get_trending()
        // - get_trending_posts()
        // - get_trending_videos()
        let endpoint = "\(APIConfig.Feed.baseFeed)?user_id=trending&limit=\(limit)"

        let response: FeedResponse = try await client.request(
            endpoint: endpoint,
            method: "GET"
        )

        return response.posts
    }

    // MARK: - Likes

    func createLike(postId: String, userId: String) async throws {
        struct Request: Codable {
            let post_id: String
            let user_id: String
        }

        struct Response: Codable {
            let success: Bool
        }

        let request = Request(post_id: postId, user_id: userId)
        let _: Response = try await client.request(
            endpoint: APIConfig.Social.createLike,
            body: request
        )
    }

    func deleteLike(postId: String, userId: String) async throws {
        struct Request: Codable {
            let post_id: String
            let user_id: String
        }

        struct Response: Codable {
            let success: Bool
        }

        let request = Request(post_id: postId, user_id: userId)
        let _: Response = try await client.request(
            endpoint: APIConfig.Social.deleteLike,
            body: request
        )
    }

    func getPostLikes(postId: String, limit: Int = 20, offset: Int = 0) async throws -> (userIds: [String], totalCount: Int) {
        struct Request: Codable {
            let post_id: String
            let limit: Int
            let offset: Int
        }

        struct Response: Codable {
            let user_ids: [String]
            let total_count: Int
        }

        let request = Request(post_id: postId, limit: limit, offset: offset)
        let response: Response = try await client.request(
            endpoint: APIConfig.Social.getLikes,
            body: request
        )

        return (response.user_ids, response.total_count)
    }

    func checkUserLiked(postId: String, userId: String) async throws -> Bool {
        struct Request: Codable {
            let post_id: String
            let user_id: String
        }

        struct Response: Codable {
            let liked: Bool
        }

        let request = Request(post_id: postId, user_id: userId)
        let response: Response = try await client.request(
            endpoint: APIConfig.Social.checkLiked,
            body: request
        )

        return response.liked
    }

    // MARK: - Comments

    func createComment(postId: String, userId: String, content: String) async throws -> Comment {
        struct Request: Codable {
            let post_id: String
            let user_id: String
            let content: String
        }

        struct Response: Codable {
            let comment: Comment
        }

        let request = Request(post_id: postId, user_id: userId, content: content)
        let response: Response = try await client.request(
            endpoint: APIConfig.Social.createComment,
            body: request
        )

        return response.comment
    }

    func deleteComment(commentId: String, userId: String) async throws {
        struct Request: Codable {
            let comment_id: String
            let user_id: String
        }

        struct Response: Codable {
            let success: Bool
        }

        let request = Request(comment_id: commentId, user_id: userId)
        let _: Response = try await client.request(
            endpoint: APIConfig.Social.deleteComment,
            body: request
        )
    }

    func getComments(postId: String, limit: Int = 20, offset: Int = 0) async throws -> (comments: [Comment], totalCount: Int) {
        struct Request: Codable {
            let post_id: String
            let limit: Int
            let offset: Int
        }

        struct Response: Codable {
            let comments: [Comment]
            let total_count: Int
        }

        let request = Request(post_id: postId, limit: limit, offset: offset)
        let response: Response = try await client.request(
            endpoint: APIConfig.Social.getComments,
            body: request
        )

        return (response.comments, response.total_count)
    }
}
