import Foundation
import Observation

/// FeedService - 现代化的 Feed 数据服务
/// 使用 @Observable 和状态机模式，遵循 SwiftUI 最佳实践
@MainActor
@Observable
final class FeedService {
    // MARK: - State Machine

    enum LoadingState: Equatable {
        case idle
        case loading
        case refreshing
        case loadingMore

        var isLoading: Bool {
            switch self {
            case .idle: return false
            case .loading, .refreshing, .loadingMore: return true
            }
        }
    }

    enum FeedState: Equatable {
        case empty
        case loaded(posts: [Post], hasMore: Bool)
        case error(String)
    }

    // MARK: - Observable State

    private(set) var loadingState: LoadingState = .idle
    private(set) var feedState: FeedState = .empty

    // MARK: - Dependencies

    private let repository: FeedRepository
    private let interactionService: PostInteractionService

    // MARK: - Private State

    private var currentCursor: String?
    private let prefetchThreshold = 5
    private let maxRetries = 3

    // MARK: - Initialization

    init(
        repository: FeedRepository = FeedRepository(),
        interactionService: PostInteractionService = PostInteractionService()
    ) {
        self.repository = repository
        self.interactionService = interactionService
    }

    // MARK: - Computed Properties

    var posts: [Post] {
        if case .loaded(let posts, _) = feedState {
            return posts
        }
        return []
    }

    var hasMore: Bool {
        if case .loaded(_, let hasMore) = feedState {
            return hasMore
        }
        return false
    }

    var errorMessage: String? {
        if case .error(let message) = feedState {
            return message
        }
        return nil
    }

    // MARK: - Public API

    func loadInitialFeed() async {
        guard !loadingState.isLoading else { return }

        loadingState = .loading

        do {
            let posts = try await retryWithBackoff {
                try await self.repository.loadFeed(cursor: nil, limit: 20)
            }

            currentCursor = posts.last?.id.uuidString
            feedState = .loaded(posts: posts, hasMore: !posts.isEmpty)
            loadingState = .idle

        } catch {
            feedState = .error(error.localizedDescription)
            loadingState = .idle
        }
    }

    func refreshFeed() async {
        guard !loadingState.isLoading else { return }

        loadingState = .refreshing
        currentCursor = nil

        do {
            let posts = try await retryWithBackoff {
                try await self.repository.refreshFeed(limit: 20)
            }

            currentCursor = posts.last?.id.uuidString
            feedState = .loaded(posts: posts, hasMore: !posts.isEmpty)
            loadingState = .idle

        } catch {
            feedState = .error(error.localizedDescription)
            loadingState = .idle
        }
    }

    func loadMoreIfNeeded(currentPost: Post) async {
        guard hasMore,
              case .loaded(let posts, _) = feedState,
              let index = posts.firstIndex(where: { $0.id == currentPost.id }),
              posts.count - index <= prefetchThreshold else {
            return
        }

        await loadMore()
    }

    func loadMore() async {
        guard !loadingState.isLoading,
              hasMore else {
            return
        }

        loadingState = .loadingMore

        do {
            let newPosts = try await repository.loadFeed(cursor: currentCursor, limit: 20)

            // 去重并更新状态
            if case .loaded(let existingPosts, _) = feedState {
                let uniqueNewPosts = newPosts.filter { newPost in
                    !existingPosts.contains(where: { $0.id == newPost.id })
                }

                let allPosts = existingPosts + uniqueNewPosts
                currentCursor = allPosts.last?.id.uuidString
                feedState = .loaded(posts: allPosts, hasMore: !newPosts.isEmpty)
            }

            loadingState = .idle

        } catch {
            feedState = .error(error.localizedDescription)
            loadingState = .idle
        }
    }

    // MARK: - Post Interactions

    func toggleLike(for post: Post) async {
        guard case .loaded(let posts, let hasMore) = feedState,
              let index = posts.firstIndex(where: { $0.id == post.id }) else {
            return
        }

        // 乐观更新：使用值类型的 immutable 更新
        let updatedPost = post.toggled()
        var newPosts = posts
        newPosts[index] = updatedPost
        feedState = .loaded(posts: newPosts, hasMore: hasMore)

        // 后台持久化
        do {
            if post.isLiked {
                try await interactionService.unlikePost(postId: post.id.uuidString)
            } else {
                try await interactionService.likePost(postId: post.id.uuidString)
            }
        } catch {
            // 失败时回滚
            var rolledBack = posts
            rolledBack[index] = post
            feedState = .loaded(posts: rolledBack, hasMore: hasMore)
        }
    }

    func incrementCommentCount(for post: Post) {
        guard case .loaded(let posts, let hasMore) = feedState,
              let index = posts.firstIndex(where: { $0.id == post.id }) else {
            return
        }

        let updatedPost = post.withIncrementedComments()
        var newPosts = posts
        newPosts[index] = updatedPost
        feedState = .loaded(posts: newPosts, hasMore: hasMore)
    }

    func clearError() {
        if case .error = feedState {
            feedState = .empty
        }
    }

    // MARK: - Private Helpers

    private func retryWithBackoff<T>(
        maxAttempts: Int = 3,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 0..<maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error

                if attempt < maxAttempts - 1 {
                    let delay = pow(2.0, Double(attempt)) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: UInt64(delay))
                }
            }
        }

        throw lastError ?? NSError(domain: "FeedService", code: -1)
    }
}

// MARK: - Post Extensions

extension Post {
    /// 切换点赞状态（不可变更新）
    func toggled() -> Post {
        Post(
            id: id,
            userId: userId,
            imageUrl: imageUrl,
            thumbnailUrl: thumbnailUrl,
            caption: caption,
            likeCount: isLiked ? likeCount - 1 : likeCount + 1,
            commentCount: commentCount,
            isLiked: !isLiked,
            createdAt: createdAt,
            user: user
        )
    }

    /// 增加评论数（不可变更新）
    func withIncrementedComments() -> Post {
        Post(
            id: id,
            userId: userId,
            imageUrl: imageUrl,
            thumbnailUrl: thumbnailUrl,
            caption: caption,
            likeCount: likeCount,
            commentCount: commentCount + 1,
            isLiked: isLiked,
            createdAt: createdAt,
            user: user
        )
    }
}
