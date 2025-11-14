import Foundation

// MARK: - Content Service

/// Manages content (posts, bookmarks) using content-service backend
/// Handles post CRUD operations and bookmark management
class ContentService {
    private let client = APIClient.shared

    // MARK: - Posts

    func getPostsByAuthor(authorId: String, limit: Int = 20, offset: Int = 0) async throws -> GetPostsByAuthorResponse {
        struct Request: Codable {
            let author_id: String
            let status: String?
            let limit: Int
            let offset: Int
        }

        let request = Request(author_id: authorId, status: nil, limit: limit, offset: offset)
        return try await client.request(
            endpoint: APIConfig.Content.postsByAuthor,
            body: request
        )
    }

    func createPost(creatorId: String, content: String) async throws -> Post {
        struct Request: Codable {
            let creator_id: String
            let content: String
        }

        struct Response: Codable {
            let post: Post
        }

        let request = Request(creator_id: creatorId, content: content)
        let response: Response = try await client.request(
            endpoint: APIConfig.Content.createPost,
            body: request
        )

        return response.post
    }

    func getPost(postId: String) async throws -> Post? {
        struct Request: Codable {
            let post_id: String
        }

        struct Response: Codable {
            let post: Post?
            let found: Bool
        }

        let request = Request(post_id: postId)
        let response: Response = try await client.request(
            endpoint: APIConfig.Content.getPost,
            body: request
        )

        return response.found ? response.post : nil
    }

    // MARK: - Bookmarks

    func getUserBookmarks(userId: String, limit: Int = 20, offset: Int = 0) async throws -> GetUserBookmarksResponse {
        struct Request: Codable {
            let user_id: String
            let limit: Int
            let offset: Int
        }

        let request = Request(user_id: userId, limit: limit, offset: offset)
        return try await client.request(
            endpoint: APIConfig.Content.bookmarks,
            body: request
        )
    }
}
