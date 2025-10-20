import Foundation

/// Service for creating and managing posts
final class PostService: Sendable {
    private let httpClient: HTTPClientProtocol
    private let cache: CacheManager

    init(httpClient: HTTPClientProtocol = HTTPClient(), cache: CacheManager = CacheManager()) {
        self.httpClient = httpClient
        self.cache = cache
    }

    /// Creates a new post
    func createPost(caption: String, imageUrl: String? = nil) async throws -> Post {
        guard !caption.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PostCreationError.emptyCaption
        }

        // For MVP, simulate post creation
        // TODO: Implement real API endpoint POST /posts
        let newPost = Post(
            id: UUID().uuidString,
            author: User(
                id: "current_user",
                username: "current_user",
                displayName: "You",
                avatarUrl: nil,
                bio: nil,
                followersCount: 0,
                followingCount: 0,
                postsCount: 0
            ),
            caption: caption,
            imageUrl: imageUrl,
            likeCount: 0,
            commentCount: 0,
            isLiked: false,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )

        // Clear feed cache to ensure fresh data
        cache.clearAll()

        return newPost
    }

    /// Updates an existing post
    func updatePost(postId: String, caption: String) async throws {
        guard !caption.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PostCreationError.emptyCaption
        }

        // For MVP, simulate update
        // TODO: Implement real API endpoint PUT /posts/:id
        cache.clearAll()
    }

    /// Deletes a post
    func deletePost(postId: String) async throws {
        // For MVP, simulate deletion
        // TODO: Implement real API endpoint DELETE /posts/:id
        cache.clearAll()
    }

    /// Gets maximum allowed caption length
    static let maxCaptionLength: Int = 500
}

// MARK: - Error Types

enum PostCreationError: LocalizedError {
    case emptyCaption
    case tooLongCaption
    case invalidImage
    case networkError
    case serverError

    var errorDescription: String? {
        switch self {
        case .emptyCaption:
            return "Please enter some text for your post"
        case .tooLongCaption:
            return "Caption is too long (max \(PostService.maxCaptionLength) characters)"
        case .invalidImage:
            return "Invalid image selected"
        case .networkError:
            return "Network error. Please try again"
        case .serverError:
            return "Server error. Please try again later"
        }
    }
}
