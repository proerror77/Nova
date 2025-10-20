import Foundation

/// Service for handling post interactions like likes and comments
final class PostInteractionService: Sendable {
    private let httpClient: HTTPClientProtocol
    private let cache: CacheManager

    init(httpClient: HTTPClientProtocol = HTTPClient(), cache: CacheManager = CacheManager()) {
        self.httpClient = httpClient
        self.cache = cache
    }

    // MARK: - Like Operations

    /// Likes a post
    func likePost(postId: String) async throws {
        // For MVP, simulate like action
        // TODO: Implement real API endpoint /posts/:id/like
        let cacheKey = "post_like_\(postId)"
        cache.set(true, for: cacheKey)
    }

    /// Unlikes a post
    func unlikePost(postId: String) async throws {
        // For MVP, simulate unlike action
        // TODO: Implement real API endpoint /posts/:id/unlike
        let cacheKey = "post_like_\(postId)"
        cache.clear(for: cacheKey)
    }

    /// Checks if current user liked a post
    func isPostLiked(postId: String) -> Bool {
        let cacheKey = "post_like_\(postId)"
        let liked: Bool? = cache.get(for: cacheKey)
        return liked ?? false
    }

    // MARK: - Comment Operations

    /// Fetches comments for a post
    func getComments(postId: String, page: Int = 0, limit: Int = 20) async throws -> [Comment] {
        let cacheKey = "post_comments_\(postId)_page_\(page)"

        // Check cache first
        if let cached: [Comment] = cache.get(for: cacheKey) {
            return cached
        }

        // For MVP, return empty comments
        // TODO: Implement real API endpoint /posts/:id/comments
        let mockComments: [Comment] = []
        cache.set(mockComments, for: cacheKey)
        return mockComments
    }

    /// Creates a comment on a post
    func createComment(postId: String, text: String) async throws {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PostInteractionError.invalidInput
        }

        // For MVP, simulate comment creation
        // TODO: Implement real API endpoint POST /posts/:id/comments
    }

    /// Deletes a comment
    func deleteComment(postId: String, commentId: String) async throws {
        // For MVP, simulate comment deletion
        // TODO: Implement real API endpoint DELETE /posts/:id/comments/:commentId
    }

    // MARK: - Share Operations

    /// Shares a post
    func sharePost(postId: String) async throws {
        // For MVP, just track the share
        let cacheKey = "post_shares_\(postId)"
        if let currentShares: Int = cache.get(for: cacheKey) {
            cache.set(currentShares + 1, for: cacheKey)
        } else {
            cache.set(1, for: cacheKey)
        }
    }

    /// Gets share count for a post
    func getShareCount(postId: String) -> Int {
        let cacheKey = "post_shares_\(postId)"
        let count: Int? = cache.get(for: cacheKey)
        return count ?? 0
    }
}

// MARK: - Post Interaction Models

struct Comment: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let postId: String
    let author: User
    let text: String
    let createdAt: String
    let likeCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case postId = "post_id"
        case author
        case text
        case createdAt = "created_at"
        case likeCount = "like_count"
    }

    init(
        id: String,
        postId: String,
        author: User,
        text: String,
        createdAt: String,
        likeCount: Int = 0
    ) {
        self.id = id
        self.postId = postId
        self.author = author
        self.text = text
        self.createdAt = createdAt
        self.likeCount = likeCount
    }
}

// MARK: - Errors

enum PostInteractionError: LocalizedError {
    case invalidInput
    case notFound
    case unauthorized
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidInput:
            return "Invalid input provided"
        case .notFound:
            return "Resource not found"
        case .unauthorized:
            return "You don't have permission to perform this action"
        case .serverError(let code):
            return "Server error: \(code)"
        }
    }
}
