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

    func createPost(creatorId: String, content: String, mediaUrls: [String]? = nil) async throws -> Post {
        struct Request: Codable {
            let creator_id: String
            let content: String
            let media_urls: [String]?
            let media_type: String?
        }

        struct Response: Codable {
            let post: Post
        }

        let mediaType = mediaUrls?.isEmpty == false ? "image" : nil
        let request = Request(
            creator_id: creatorId,
            content: content,
            media_urls: mediaUrls,
            media_type: mediaType
        )
        let response: Response = try await client.request(
            endpoint: APIConfig.Content.createPost,
            body: request
        )

        return response.post
    }

    /// Get single post by ID using GET /api/v2/content/{id}
    func getPost(postId: String) async throws -> Post? {
        do {
            let post: Post = try await client.request(
                endpoint: APIConfig.Content.getPost(postId),
                method: "GET"
            )
            return post
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
