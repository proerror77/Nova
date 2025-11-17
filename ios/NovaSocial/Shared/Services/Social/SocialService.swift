import Foundation

// MARK: - Social Service

/// Manages social interactions using social-service backend
/// Handles likes, comments, shares, and feeds
class SocialService {
    private let client = APIClient.shared

    // MARK: - Feeds

    /// Get user's personalized feed
    /// For now, uses ContentService to fetch posts until feed-service is deployed
    func getUserFeed(userId: String, limit: Int = 20, cursor: String? = nil) async throws -> (posts: [Post], nextCursor: String?, hasMore: Bool) {
        // Using ContentService as temporary implementation
        // TODO: Switch to feed-service when deployed
        let contentService = ContentService()
        let offset = cursor.flatMap { Int($0) } ?? 0

        let response = try await contentService.getPostsByAuthor(
            authorId: userId,
            limit: limit,
            offset: offset
        )

        let nextOffset = offset + response.posts.count
        let hasMore = nextOffset < response.totalCount
        let nextCursor = hasMore ? String(nextOffset) : nil

        return (
            posts: response.posts,
            nextCursor: nextCursor,
            hasMore: hasMore
        )
    }

    /// Get explore/discover feed
    /// Returns all recent posts across all users
    func getExploreFeed(limit: Int = 20, cursor: String? = nil) async throws -> (posts: [Post], nextCursor: String?, hasMore: Bool) {
        // Temporary: Use a placeholder user ID for explore feed
        // TODO: Implement proper explore feed endpoint in backend
        return try await getUserFeed(userId: "explore_user", limit: limit, cursor: cursor)
    }

    /// Get trending posts
    /// Returns most liked/commented posts
    func getTrendingPosts(limit: Int = 20) async throws -> [Post] {
        // Temporary: Return explore feed without pagination
        // TODO: Implement proper trending algorithm in backend
        let (posts, _, _) = try await getExploreFeed(limit: limit)
        return posts
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
