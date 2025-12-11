import Foundation
import SwiftUI

// MARK: - Feed ViewModel

@MainActor
class FeedViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var posts: [FeedPost] = []
    @Published var postIds: [String] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var error: String?
    @Published var toastError: String?  // Transient error for toast notifications
    @Published var hasMore = true

    // MARK: - Private Properties

    private let feedService: FeedService
    private let contentService: ContentService
    private let socialService: SocialService
    private let authManager: AuthenticationManager
    private var currentCursor: String?
    private var currentAlgorithm: FeedAlgorithm = .chronological
    private var currentUserId: String? {
        KeychainService.shared.get(.userId)
    }

    // MARK: - Public Methods

    /// Check if user is authenticated (has valid token and is not in guest mode)
    private var isAuthenticated: Bool {
        authManager.isAuthenticated && !authManager.isGuestMode
    }

    /// Load initial feed - uses Guest Feed (trending) when not authenticated
    /// - Parameters:
    ///   - algorithm: Feed ranking algorithm
    ///   - isGuestFallback: Internal flag to indicate we already fell back to guest feed once.
    ///     This prevents infinite retry loops when even guest feed returns unauthorized.
    init(
        feedService: FeedService = FeedService(),
        contentService: ContentService = ContentService(),
        socialService: SocialService = SocialService(),
        authManager: AuthenticationManager? = nil
    ) {
        self.feedService = feedService
        self.contentService = contentService
        self.socialService = socialService
        self.authManager = authManager ?? AuthenticationManager.shared
    }

    func loadFeed(
        algorithm: FeedAlgorithm = .chronological,
        isGuestFallback: Bool = false
    ) async {
        guard !isLoading else { return }

        isLoading = true
        error = nil
        currentAlgorithm = algorithm
        currentCursor = nil

        do {
            // Use Guest Feed API when not authenticated, otherwise use authenticated Feed API
            let response: FeedResponse
            if isAuthenticated {
                response = try await feedService.getFeed(algo: algorithm, limit: 20, cursor: nil)
            } else {
                // Guest Mode: fetch trending posts without authentication
                response = try await feedService.getTrendingFeed(limit: 20, cursor: nil)
            }

            // Feed API now returns full post objects directly
            self.postIds = response.postIds
            self.currentCursor = response.cursor
            self.hasMore = response.hasMore

            // Convert raw posts to FeedPost objects directly
            let allPosts = response.posts.map { FeedPost(from: $0) }

            // Client-side deduplication: Remove duplicate posts by ID
            var seenIds = Set<String>()
            self.posts = allPosts.filter { post in
                guard !seenIds.contains(post.id) else { return false }
                seenIds.insert(post.id)
                return true
            }

            self.error = nil
        } catch let apiError as APIError {
            // Handle unauthorized: try token refresh or fallback to guest mode
            if case .unauthorized = apiError, isAuthenticated, !isGuestFallback {
                let refreshed = await authManager.attemptTokenRefresh()
                if refreshed {
                    // Retry after token refresh
                    isLoading = false
                    await loadFeed(algorithm: algorithm, isGuestFallback: isGuestFallback)
                    return
                } else {
                    // Token refresh failed - gracefully degrade to guest mode
                    await authManager.logout()
                    isLoading = false
                    await loadFeed(algorithm: algorithm, isGuestFallback: true)
                    return
                }
            } else if case .serverError(let statusCode, _) = apiError, statusCode == 500 {
                // Backend feed-service unreachable or gRPC error (e.g. \"tcp connect error\")
                // Fallback: load guest/trending feed instead of showing a hard error.
                do {
                    let fallbackResponse = try await feedService.getTrendingFeed(limit: 20, cursor: nil)

                    self.postIds = fallbackResponse.postIds
                    self.currentCursor = fallbackResponse.cursor
                    self.hasMore = fallbackResponse.hasMore

                    let allPosts = fallbackResponse.posts.map { FeedPost(from: $0) }
                    var seenIds = Set<String>()
                    self.posts = allPosts.filter { post in
                        guard !seenIds.contains(post.id) else { return false }
                        seenIds.insert(post.id)
                        return true
                    }

                    self.error = nil
                } catch {
                    self.error = apiError.localizedDescription
                    self.posts = []
                }
                isLoading = false
                return
            } else {
                // Show error and stop retrying
                self.error = apiError.localizedDescription
                self.posts = []
            }
        } catch {
            self.error = "Failed to load feed: \(error.localizedDescription)"
            self.posts = []
        }

        isLoading = false
    }

    /// Load more posts (pagination)
    func loadMore() async {
        // Note: Backend doesn't support cursor pagination yet, so this is disabled
        guard !isLoadingMore, hasMore else { return }

        isLoadingMore = true

        do {
            let response = try await feedService.getFeed(algo: currentAlgorithm, limit: 20, cursor: currentCursor)

            self.postIds.append(contentsOf: response.postIds)
            self.currentCursor = response.cursor
            self.hasMore = response.hasMore

            // Convert raw posts to FeedPost objects directly
            let newPosts = response.posts.map { FeedPost(from: $0) }

            // Client-side deduplication: Only add posts that aren't already in the feed
            let existingIds = Set(self.posts.map { $0.id })
            let uniqueNewPosts = newPosts.filter { !existingIds.contains($0.id) }
            self.posts.append(contentsOf: uniqueNewPosts)

        } catch {
            // Silently handle errors to avoid disrupting user experience
        }

        isLoadingMore = false
    }

    /// Refresh feed (pull-to-refresh)
    /// 下拉刷新时静默忽略取消错误，只在真正的网络错误时显示提示
    func refresh() async {
        guard !isLoading else { return }

        isLoading = true
        // 刷新时不立即清除错误，只有在成功或真正的错误时才更新

        do {
            let response: FeedResponse
            if isAuthenticated {
                response = try await feedService.getFeed(algo: currentAlgorithm, limit: 20, cursor: nil)
            } else {
                response = try await feedService.getTrendingFeed(limit: 20, cursor: nil)
            }

            // 成功后更新数据
            self.postIds = response.postIds
            self.currentCursor = response.cursor
            self.hasMore = response.hasMore

            let allPosts = response.posts.map { FeedPost(from: $0) }
            var seenIds = Set<String>()
            self.posts = allPosts.filter { post in
                guard !seenIds.contains(post.id) else { return false }
                seenIds.insert(post.id)
                return true
            }

            // 成功时清除错误
            self.error = nil

        } catch let apiError as APIError {
            // 检查是否是取消错误（用户快速滑动导致）
            if case .networkError(let underlyingError) = apiError {
                let nsError = underlyingError as NSError
                if nsError.code == NSURLErrorCancelled {
                    // 静默忽略取消的请求，保持当前数据
                    isLoading = false
                    return
                }
            }
            // 非取消错误：只有当前没有数据时才显示错误
            if posts.isEmpty {
                self.error = apiError.localizedDescription
            }
        } catch {
            let nsError = error as NSError
            // 检查是否是取消错误
            if nsError.code == NSURLErrorCancelled || nsError.localizedDescription.lowercased().contains("cancelled") {
                // 静默忽略取消的请求
                isLoading = false
                return
            }
            // 非取消错误：只有当前没有数据时才显示错误
            if posts.isEmpty {
                self.error = "Failed to refresh: \(error.localizedDescription)"
            }
        }

        isLoading = false
    }

    /// Add a newly created post to the top of the feed (optimistic update)
    /// This avoids the need to refresh the entire feed after posting
    func addNewPost(_ post: Post) {
        let feedPost = FeedPost(
            id: post.id,
            authorId: post.authorId,
            authorName: "User \(post.authorId.prefix(8))",
            authorAvatar: nil,
            content: post.content,
            mediaUrls: post.mediaUrls ?? [],
            createdAt: post.createdDate,
            likeCount: post.likeCount ?? 0,
            commentCount: post.commentCount ?? 0,
            shareCount: post.shareCount ?? 0,
            isLiked: false,
            isBookmarked: false
        )

        // Add to the top of the feed
        self.posts.insert(feedPost, at: 0)
        self.postIds.insert(post.id, at: 0)
    }

    /// Switch feed algorithm
    func switchAlgorithm(to algorithm: FeedAlgorithm) async {
        guard algorithm != currentAlgorithm else { return }
        await loadFeed(algorithm: algorithm)
    }

    // MARK: - Social Actions

    /// Toggle like on a post
    func toggleLike(postId: String) async {
        guard let index = posts.firstIndex(where: { $0.id == postId }),
              let userId = currentUserId else { return }

        let post = posts[index]
        let wasLiked = post.isLiked

        // Optimistic update
        posts[index] = post.copying(
            likeCount: wasLiked ? post.likeCount - 1 : post.likeCount + 1,
            isLiked: !wasLiked
        )

        do {
            if wasLiked {
                try await socialService.deleteLike(postId: postId, userId: userId)
            } else {
                try await socialService.createLike(postId: postId, userId: userId)
            }
        } catch let error as APIError {
            // Revert on failure
            posts[index] = post

            // Handle specific error cases
            switch error {
            case .unauthorized:
                // Session expired - notify user to re-login
                self.toastError = "Session expired. Please log in again."
                #if DEBUG
                print("[Feed] Toggle like error: Session expired, user needs to re-login")
                #endif
            case .noConnection:
                self.toastError = "No internet connection. Please try again."
            default:
                self.toastError = "Failed to like post. Please try again."
                #if DEBUG
                print("[Feed] Toggle like error: \(error)")
                #endif
            }
        } catch {
            // Revert on failure
            posts[index] = post
            self.toastError = "Failed to like post. Please try again."
            #if DEBUG
            print("[Feed] Toggle like error: \(error)")
            #endif
        }
    }

    /// Share a post - records share to backend and returns post for native share sheet
    /// - Returns: The post to share, or nil if not found
    func sharePost(postId: String) async -> FeedPost? {
        guard let index = posts.firstIndex(where: { $0.id == postId }),
              let userId = currentUserId else { return nil }

        let post = posts[index]

        // Record share to backend (don't block on this)
        Task {
            do {
                try await socialService.createShare(postId: postId, userId: userId)
                // Update share count on success
                await MainActor.run {
                    if let idx = posts.firstIndex(where: { $0.id == postId }) {
                        posts[idx] = posts[idx].copying(shareCount: posts[idx].shareCount + 1)
                    }
                }
            } catch {
                #if DEBUG
                print("[Feed] Share post error: \(error)")
                #endif
            }
        }

        return post
    }

    /// Toggle bookmark on a post
    func toggleBookmark(postId: String) async {
        guard let index = posts.firstIndex(where: { $0.id == postId }),
              let userId = currentUserId else { return }

        let post = posts[index]
        let wasBookmarked = post.isBookmarked

        // Optimistic update
        posts[index] = post.copying(isBookmarked: !wasBookmarked)

        do {
            if wasBookmarked {
                try await socialService.deleteBookmark(postId: postId)
            } else {
                try await socialService.createBookmark(postId: postId, userId: userId)
            }
        } catch let error as APIError {
            // Revert on failure
            posts[index] = post

            // Handle specific error cases
            switch error {
            case .unauthorized:
                self.toastError = "Session expired. Please log in again."
                #if DEBUG
                print("[Feed] Toggle bookmark error: Session expired")
                #endif
            case .noConnection:
                self.toastError = "No internet connection. Please try again."
            case .notFound:
                // Backend bookmark API not deployed yet - keep local state
                posts[index] = post.copying(isBookmarked: !wasBookmarked)
                #if DEBUG
                print("[Feed] Bookmark API not available, using local state only")
                #endif
            default:
                self.toastError = "Failed to bookmark post. Please try again."
                #if DEBUG
                print("[Feed] Toggle bookmark error: \(error)")
                #endif
            }
        } catch {
            // Revert on failure
            posts[index] = post
            self.toastError = "Failed to bookmark post. Please try again."
            #if DEBUG
            print("[Feed] Toggle bookmark error: \(error)")
            #endif
        }
    }

    // MARK: - Private Methods

    /// Fetch post details from content-service and social stats
    private func fetchPostDetails(postIds: [String]) async -> [FeedPost] {
        guard !postIds.isEmpty else { return [] }

        // Fetch content from content-service
        let rawPosts: [Post]
        do {
            rawPosts = try await contentService.getPostsByIds(postIds)
        } catch {
            #if DEBUG
            print("[Feed] Failed to fetch posts: \(error)")
            #endif
            return []
        }

        // Fetch social stats
        let stats: [String: PostStats]
        do {
            stats = try await socialService.batchGetStats(postIds: postIds)
        } catch {
            #if DEBUG
            print("[Feed] Failed to fetch stats: \(error)")
            #endif
            stats = [:]
        }

        // Convert to FeedPost with stats
        return rawPosts.map { post in
            let postStats = stats[post.id]
            // Convert Unix timestamp (milliseconds) to Date
            let createdDate = Date(timeIntervalSince1970: Double(post.createdAt) / 1000.0)
            return FeedPost(
                id: post.id,
                authorId: post.creatorId,
                authorName: "User \(post.creatorId.prefix(8))",  // TODO: Fetch user profile
                authorAvatar: nil,
                content: post.content,
                mediaUrls: [],  // TODO: Fetch media from post
                createdAt: createdDate,
                likeCount: postStats?.likeCount ?? 0,
                commentCount: postStats?.commentCount ?? 0,
                shareCount: postStats?.shareCount ?? 0,
                isLiked: postStats?.isLiked ?? false,
                isBookmarked: false
            )
        }
    }
}

// MARK: - Feed State

enum FeedState {
    case idle
    case loading
    case loaded
    case error(String)
    case empty
}
