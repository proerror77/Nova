import Foundation

/// Service for handling post interactions like likes and comments
final class PostInteractionService {
    private let apiClient: APIClient
    private let interceptor: RequestInterceptor
    private let cache: CacheManager

    init(
        apiClient: APIClient = APIClient(baseURL: APIConfig.baseURL),
        cache: CacheManager = CacheManager()
    ) {
        self.apiClient = apiClient
        self.interceptor = RequestInterceptor(apiClient: apiClient)
        self.cache = cache
    }

    // MARK: - Like Operations

    /// Likes a post
    func likePost(postId: String) async throws {
        let endpoint = APIEndpoint(
            path: "/api/v1/posts/\(postId)/like",
            method: .post
        )

        try await interceptor.executeNoResponseWithRetry(endpoint)

        cache.set(true, for: likeCacheKey(postId: postId))
    }

    /// Unlikes a post
    func unlikePost(postId: String) async throws {
        let endpoint = APIEndpoint(
            path: "/api/v1/posts/\(postId)/like",
            method: .delete
        )

        try await interceptor.executeNoResponseWithRetry(endpoint)

        cache.clear(for: likeCacheKey(postId: postId))
    }

    /// Checks if current user liked a post
    func isPostLiked(postId: String) -> Bool {
        let liked: Bool? = cache.get(for: likeCacheKey(postId: postId))
        return liked ?? false
    }

    // MARK: - Comment Operations

    /// Fetches comments for a post
    func getComments(postId: String, page: Int = 0, limit: Int = 20) async throws -> [Comment] {
        let cacheKey = commentsCacheKey(postId: postId, page: page)

        if let cached: [Comment] = cache.get(for: cacheKey) {
            return cached
        }

        let offset = max(page, 0) * max(limit, 1)

        let endpoint = APIEndpoint(
            path: "/api/v1/posts/\(postId)/comments",
            method: .get,
            queryItems: [
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "offset", value: "\(offset)")
            ]
        )

        let response: CommentListResponse = try await interceptor.executeWithRetry(endpoint)
        let comments = response.comments.map(makeComment)

        cache.set(comments, for: cacheKey)

        return comments
    }

    /// Creates a comment on a post
    func createComment(postId: String, text: String) async throws {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PostInteractionError.invalidInput
        }

        let request = CreateCommentRequest(content: text)

        let endpoint = APIEndpoint(
            path: "/api/v1/posts/\(postId)/comments",
            method: .post,
            body: request
        )

        _ = try await interceptor.executeWithRetry(endpoint) as CommentItem

        // Clear the first page cache so the new comment appears on refresh
        cache.clear(for: commentsCacheKey(postId: postId, page: 0))
    }

    /// Deletes a comment
    func deleteComment(commentId: String) async throws {
        let endpoint = APIEndpoint(
            path: "/api/v1/comments/\(commentId)",
            method: .delete
        )

        try await interceptor.executeNoResponseWithRetry(endpoint)

        cache.clearAll()
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
    let id: UUID
    let postId: UUID
    let userId: UUID
    let text: String
    let createdAt: Date
    let user: User?
    let likeCount: Int

    init(
        id: UUID,
        postId: UUID,
        userId: UUID,
        text: String,
        createdAt: Date,
        user: User?,
        likeCount: Int = 0
    ) {
        self.id = id
        self.postId = postId
        self.userId = userId
        self.text = text
        self.createdAt = createdAt
        self.user = user
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

// MARK: - Networking Helpers

private extension PostInteractionService {
    func likeCacheKey(postId: String) -> String {
        "post_like_\(postId)"
    }

    func commentsCacheKey(postId: String, page: Int) -> String {
        "post_comments_\(postId)_page_\(page)"
    }

    func makeComment(from item: CommentItem) -> Comment {
        let formatter = ISO8601DateFormatter()

        let commentId = UUID(uuidString: item.id) ?? UUID()
        let postId = UUID(uuidString: item.postId) ?? UUID()
        let userId = UUID(uuidString: item.userId) ?? UUID()
        let createdAt = formatter.date(from: item.createdAt) ?? Date()

        let author: User? = item.username.map { username in
            User(
                id: item.userId,
                username: username,
                displayName: username,
                avatarUrl: item.avatarUrl
            )
        }

        return Comment(
            id: commentId,
            postId: postId,
            userId: userId,
            text: item.content,
            createdAt: createdAt,
            user: author,
            likeCount: item.likeCount ?? 0
        )
    }
}

// MARK: - Network DTOs

private struct CommentListResponse: Decodable {
    let comments: [CommentItem]
    let totalCount: Int
    let limit: Int
    let offset: Int

    enum CodingKeys: String, CodingKey {
        case comments
        case totalCount = "total_count"
        case limit
        case offset
    }
}

private struct CommentItem: Decodable {
    let id: String
    let postId: String
    let userId: String
    let username: String?
    let avatarUrl: String?
    let content: String
    let parentCommentId: String?
    let createdAt: String
    let updatedAt: String
    let isEdited: Bool
    let likeCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case postId = "post_id"
        case userId = "user_id"
        case username
        case avatarUrl = "avatar_url"
        case content
        case parentCommentId = "parent_comment_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isEdited = "is_edited"
        case likeCount = "like_count"
    }
}

private struct CreateCommentRequest: Encodable {
    let content: String
    let parentCommentId: String? = nil

    enum CodingKeys: String, CodingKey {
        case content
        case parentCommentId = "parent_comment_id"
    }
}
