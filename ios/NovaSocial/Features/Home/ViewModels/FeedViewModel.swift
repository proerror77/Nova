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

            #if DEBUG
            // Debug: Log raw response to check media_urls
            for (index, rawPost) in response.posts.prefix(3).enumerated() {
                print("[Feed] Post[\(index)] id=\(rawPost.id.prefix(8)), content=\(rawPost.content.prefix(20)), media_urls=\(rawPost.mediaUrls ?? []), media_type=\(rawPost.mediaType ?? "nil")")
            }
            #endif

            // Convert raw posts to FeedPost objects directly (no separate content-service call needed)
            self.posts = response.posts.map { FeedPost(from: $0) }

            self.error = nil
        } catch let apiError as APIError {
            #if DEBUG
            print("[Feed] API Error: \(apiError)")
            #endif

            // Handle unauthorized:
            // 1) If currently authenticated and we have not yet fallen back to guest feed:
            //    - Try token refresh once.
            //    - On failure, logout and retry once in guest mode.
            // 2) If already in guest mode or guest fallback, surface an error instead of looping.
            if case .unauthorized = apiError, isAuthenticated, !isGuestFallback {
                let refreshed = await authManager.attemptTokenRefresh()
                if refreshed {
                    // Retry after token refresh
                    isLoading = false
                    await loadFeed(algorithm: algorithm, isGuestFallback: isGuestFallback)
                    return
                } else {
                    // Token refresh failed - gracefully degrade to guest mode
                    #if DEBUG
                    print("[Feed] Token refresh failed, falling back to guest feed")
                    #endif
                    await authManager.logout()
                    // Reload as guest - this time mark as guest fallback to avoid infinite loop
                    isLoading = false
                    await loadFeed(algorithm: algorithm, isGuestFallback: true)
                    return
                }
            } else {
                // Guest feed or repeated unauthorized: show error and stop retrying
                self.error = apiError.localizedDescription
                self.posts = []
            }
        } catch {
            self.error = "Failed to load feed: \(error.localizedDescription)"
            self.posts = []
            #if DEBUG
            print("[Feed] Error: \(error)")
            #endif
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
            self.posts.append(contentsOf: newPosts)

        } catch {
            #if DEBUG
            print("[Feed] Load more error: \(error)")
            #endif
        }

        isLoadingMore = false
    }

    /// Refresh feed (pull-to-refresh)
    func refresh() async {
        await loadFeed(algorithm: currentAlgorithm)
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
        } catch {
            // Revert on failure
            posts[index] = post
            #if DEBUG
            print("[Feed] Toggle like error: \(error)")
            #endif
        }
    }

    /// Share a post
    func sharePost(postId: String) async {
        guard let index = posts.firstIndex(where: { $0.id == postId }),
              let userId = currentUserId else { return }

        let post = posts[index]

        do {
            try await socialService.createShare(postId: postId, userId: userId)
            // Update share count
            posts[index] = post.copying(shareCount: post.shareCount + 1)
        } catch {
            #if DEBUG
            print("[Feed] Share post error: \(error)")
            #endif
        }
    }

    /// Toggle bookmark on a post
    func toggleBookmark(postId: String) {
        guard let index = posts.firstIndex(where: { $0.id == postId }) else { return }

        let post = posts[index]
        // Local toggle only - backend bookmark API TBD
        posts[index] = post.copying(isBookmarked: !post.isBookmarked)
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
