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

    // MARK: - Channel State
    @Published var channels: [FeedChannel] = []
    @Published var selectedChannelId: String? = nil  // nil = "For You" / all content
    @Published var isLoadingChannels = false

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

    // Track ongoing like operations to prevent concurrent calls for the same post
    private var ongoingLikeOperations: Set<String> = []

    // Track ongoing bookmark operations to prevent concurrent calls for the same post
    private var ongoingBookmarkOperations: Set<String> = []

    // MARK: - Initialization

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

    // MARK: - Computed Properties

    /// Check if user is authenticated (has valid token and is not in guest mode)
    private var isAuthenticated: Bool {
        authManager.isAuthenticated && !authManager.isGuestMode
    }

    // MARK: - Public Methods

    /// Load initial feed - uses Guest Feed (trending) when not authenticated
    /// - Parameters:
    ///   - algorithm: Feed ranking algorithm
    ///   - isGuestFallback: Internal flag to indicate we already fell back to guest feed once.
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
            let response: FeedResponse
            if isAuthenticated {
                // Pass channel filter if selected
                response = try await feedService.getFeed(algo: algorithm, limit: 20, cursor: nil, channelId: selectedChannelId)
            } else {
                response = try await feedService.getTrendingFeed(limit: 20, cursor: nil)
            }

            updateFeedState(from: response)
            self.posts = await processAndDeduplicatePosts(response.posts.map { FeedPost(from: $0) })
            self.error = nil

        } catch let apiError as APIError {
            if case .unauthorized = apiError, isAuthenticated, !isGuestFallback {
                let refreshed = await authManager.attemptTokenRefresh()
                if refreshed {
                    isLoading = false
                    await loadFeed(algorithm: algorithm, isGuestFallback: isGuestFallback)
                    return
                } else {
                    await authManager.logout()
                    isLoading = false
                    await loadFeed(algorithm: algorithm, isGuestFallback: true)
                    return
                }
            } else if case .serverError(let statusCode, _) = apiError, statusCode == 500 {
                // Fallback to trending feed on server error
                await handleServerErrorFallback(originalError: apiError)
                isLoading = false
                return
            } else {
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
        guard !isLoadingMore, hasMore else { return }

        isLoadingMore = true

        do {
            let response = try await feedService.getFeed(algo: currentAlgorithm, limit: 20, cursor: currentCursor)

            self.postIds.append(contentsOf: response.postIds)
            self.currentCursor = response.cursor
            self.hasMore = response.hasMore

            let newPosts = await enrichWithBookmarkStatus(response.posts.map { FeedPost(from: $0) })

            // Client-side deduplication: Only add posts that aren't already in the feed
            let existingIds = Set(self.posts.map { $0.id })
            let uniqueNewPosts = newPosts.filter { !existingIds.contains($0.id) }

            if uniqueNewPosts.isEmpty {
                self.hasMore = false
                FeedLogger.debug("loadMore returned no new posts, stopping pagination")
            } else {
                self.posts.append(contentsOf: uniqueNewPosts)
            }

        } catch {
            self.hasMore = false
            FeedLogger.debug("loadMore error (stopping pagination): \(error)")
        }

        isLoadingMore = false
    }

    /// Refresh feed (pull-to-refresh)
    func refresh() async {
        guard !isLoading else { return }

        isLoading = true

        do {
            let response: FeedResponse
            if isAuthenticated {
                // Pass channel filter if selected
                response = try await feedService.getFeed(algo: currentAlgorithm, limit: 20, cursor: nil, channelId: selectedChannelId)
            } else {
                response = try await feedService.getTrendingFeed(limit: 20, cursor: nil)
            }

            updateFeedState(from: response)
            self.posts = await processAndDeduplicatePosts(response.posts.map { FeedPost(from: $0) })
            self.error = nil

        } catch let apiError as APIError {
            if isCancelledError(apiError) {
                isLoading = false
                return
            }
            if posts.isEmpty {
                self.error = apiError.localizedDescription
            }
        } catch {
            if isCancelledError(error) {
                isLoading = false
                return
            }
            if posts.isEmpty {
                self.error = "Failed to refresh: \(error.localizedDescription)"
            }
        }

        isLoading = false
    }

    // MARK: - Channel Management

    /// Load available channels from backend
    func loadChannels() async {
        guard !isLoadingChannels else { return }
        isLoadingChannels = true

        do {
            channels = try await feedService.getChannels(enabledOnly: true)
            FeedLogger.debug("Loaded \(channels.count) channels")
        } catch {
            FeedLogger.error("Failed to load channels", error: error)
            // Use fallback channels when API is unavailable
            channels = FeedChannel.fallbackChannels
        }

        isLoadingChannels = false
    }

    /// Select a channel and reload feed
    /// - Parameter channelId: Channel ID to filter by, or nil for "For You" (all content)
    func selectChannel(_ channelId: String?) async {
        guard selectedChannelId != channelId else { return }

        selectedChannelId = channelId

        // Track channel selection for analytics
        if let channelId = channelId,
           let channel = channels.first(where: { $0.id == channelId }) {
            FeedLogger.debug("Selected channel: \(channel.name) (\(channelId))")
            // TODO: Add analytics tracking
            // AnalyticsService.shared.track(.channelTabClick, properties: ["channel_id": channelId, "channel_name": channel.name])
        } else {
            FeedLogger.debug("Selected: For You (all content)")
        }

        // Reload feed with new channel filter
        await loadFeed(algorithm: currentAlgorithm)
    }

    /// Add a newly created post to the top of the feed (optimistic update)
    func addNewPost(_ post: Post) {
        let currentUser = AuthenticationManager.shared.currentUser
        let authorName = currentUser?.displayName ?? currentUser?.username ?? "User \(post.authorId.prefix(8))"
        let authorAvatar = currentUser?.avatarUrl

        let feedPost = FeedPost(
            id: post.id,
            authorId: post.authorId,
            authorName: authorName,
            authorAvatar: authorAvatar,
            content: post.content,
            mediaUrls: post.mediaUrls ?? [],
            createdAt: post.createdDate,
            likeCount: post.likeCount ?? 0,
            commentCount: post.commentCount ?? 0,
            shareCount: post.shareCount ?? 0,
            isLiked: false,
            isBookmarked: false
        )

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
        guard !ongoingLikeOperations.contains(postId) else {
            FeedLogger.debug("toggleLike skipped - operation already in progress for postId: \(postId)")
            return
        }
        ongoingLikeOperations.insert(postId)
        defer { ongoingLikeOperations.remove(postId) }

        FeedLogger.debug("toggleLike called for postId: \(postId)")
        FeedLogger.debug("currentUserId: \(currentUserId ?? "nil")")
        FeedLogger.debug("isAuthenticated: \(isAuthenticated)")

        guard let index = posts.firstIndex(where: { $0.id == postId }),
              let userId = currentUserId else {
            FeedLogger.debug("toggleLike early return - postId not found or userId is nil")
            return
        }

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
            posts[index] = post
            await handleSocialActionError(error, action: "like")
        } catch {
            posts[index] = post
            self.toastError = "Failed to like post. Please try again."
            FeedLogger.debug("Toggle like error: \(error)")
        }
    }

    /// Share a post - records share to backend and returns post for native share sheet
    func sharePost(postId: String) async -> FeedPost? {
        guard let index = posts.firstIndex(where: { $0.id == postId }),
              let userId = currentUserId else { return nil }

        let post = posts[index]

        Task {
            do {
                try await socialService.createShare(postId: postId, userId: userId)
                await MainActor.run {
                    if let idx = posts.firstIndex(where: { $0.id == postId }) {
                        posts[idx] = posts[idx].copying(shareCount: posts[idx].shareCount + 1)
                    }
                }
            } catch {
                FeedLogger.debug("Share post error: \(error)")
            }
        }

        return post
    }

    /// Toggle bookmark on a post
    func toggleBookmark(postId: String) async {
        guard !ongoingBookmarkOperations.contains(postId) else {
            FeedLogger.debug("toggleBookmark skipped - operation already in progress for postId: \(postId)")
            return
        }
        ongoingBookmarkOperations.insert(postId)
        defer { ongoingBookmarkOperations.remove(postId) }

        FeedLogger.debug("toggleBookmark called for postId: \(postId)")
        FeedLogger.debug("currentUserId: \(currentUserId ?? "nil")")

        guard let index = posts.firstIndex(where: { $0.id == postId }),
              let userId = currentUserId else {
            FeedLogger.debug("toggleBookmark early return - postId not found or userId is nil")
            return
        }

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
            switch error {
            case .unauthorized:
                posts[index] = post
                await authManager.logout()
                FeedLogger.debug("Toggle bookmark error: Session expired, logging out")
            case .noConnection:
                posts[index] = post
                self.toastError = "No internet connection. Please try again."
            case .notFound, .serverError, .serviceUnavailable:
                // Keep local state when backend API is unavailable
                FeedLogger.debug("Bookmark API not available (\(error)), using local state only")
            default:
                posts[index] = post
                self.toastError = "Failed to bookmark post. Please try again."
                FeedLogger.debug("Toggle bookmark error: \(error)")
            }
        } catch {
            posts[index] = post
            self.toastError = "Failed to bookmark post. Please try again."
            FeedLogger.debug("Toggle bookmark error: \(error)")
        }
    }

    // MARK: - Private Helper Methods

    /// Process posts: enrich with bookmark status and deduplicate
    private func processAndDeduplicatePosts(_ posts: [FeedPost]) async -> [FeedPost] {
        let enrichedPosts = await enrichWithBookmarkStatus(posts)
        return deduplicatePosts(enrichedPosts)
    }

    /// Enrich posts with bookmark status for authenticated users
    private func enrichWithBookmarkStatus(_ posts: [FeedPost]) async -> [FeedPost] {
        guard isAuthenticated, !posts.isEmpty else { return posts }

        let postIds = posts.map { $0.id }
        guard let bookmarkedIds = try? await socialService.batchCheckBookmarked(postIds: postIds) else {
            return posts
        }

        return posts.map { post in
            bookmarkedIds.contains(post.id) ? post.copying(isBookmarked: true) : post
        }
    }

    /// Remove duplicate posts by ID
    /// Runs on background thread to avoid blocking UI with large datasets
    private func deduplicatePosts(_ posts: [FeedPost]) -> [FeedPost] {
        // For small datasets, process directly
        guard posts.count > 50 else {
            var seenIds = Set<String>()
            return posts.filter { post in
                guard !seenIds.contains(post.id) else { return false }
                seenIds.insert(post.id)
                return true
            }
        }

        // For large datasets, process on background thread (handled by caller)
        var seenIds = Set<String>()
        return posts.filter { post in
            guard !seenIds.contains(post.id) else { return false }
            seenIds.insert(post.id)
            return true
        }
    }

    /// Update feed state from response
    private func updateFeedState(from response: FeedResponse) {
        self.postIds = response.postIds
        self.currentCursor = response.cursor
        self.hasMore = response.hasMore
    }

    /// Handle server error by falling back to trending feed
    private func handleServerErrorFallback(originalError: APIError) async {
        do {
            let fallbackResponse = try await feedService.getTrendingFeed(limit: 20, cursor: nil)
            updateFeedState(from: fallbackResponse)
            self.posts = await processAndDeduplicatePosts(fallbackResponse.posts.map { FeedPost(from: $0) })
            self.error = nil
        } catch {
            self.error = originalError.localizedDescription
            self.posts = []
        }
    }

    /// Handle social action errors with appropriate user feedback
    private func handleSocialActionError(_ error: APIError, action: String) async {
        switch error {
        case .unauthorized:
            await authManager.logout()
            FeedLogger.debug("Toggle \(action) error: Session expired, logging out")
        case .noConnection:
            self.toastError = "No internet connection. Please try again."
        case .serviceUnavailable:
            self.toastError = "Service temporarily unavailable. Please try again later."
            FeedLogger.debug("Toggle \(action) error: Service unavailable (503)")
        default:
            self.toastError = "Failed to \(action) post. Please try again."
            FeedLogger.debug("Toggle \(action) error: \(error)")
        }
    }

    /// Check if error is a cancelled request error
    private func isCancelledError(_ error: Error) -> Bool {
        if let apiError = error as? APIError, case .networkError(let underlyingError) = apiError {
            let nsError = underlyingError as NSError
            if nsError.code == NSURLErrorCancelled {
                return true
            }
        }
        let nsError = error as NSError
        return nsError.code == NSURLErrorCancelled || nsError.localizedDescription.lowercased().contains("cancelled")
    }

    /// Fetch post details from content-service and social stats (legacy method)
    private func fetchPostDetails(postIds: [String]) async -> [FeedPost] {
        guard !postIds.isEmpty else { return [] }

        let rawPosts: [Post]
        do {
            rawPosts = try await contentService.getPostsByIds(postIds)
        } catch {
            FeedLogger.debug("Failed to fetch posts: \(error)")
            return []
        }

        let stats: [String: PostStats]
        do {
            stats = try await socialService.batchGetStats(postIds: postIds)
        } catch {
            FeedLogger.debug("Failed to fetch stats: \(error)")
            stats = [:]
        }

        return rawPosts.map { post in
            let postStats = stats[post.id]
            let createdDate = Date(timeIntervalSince1970: Double(post.createdAt) / 1000.0)
            return FeedPost(
                id: post.id,
                authorId: post.creatorId,
                authorName: "User \(post.creatorId.prefix(8))",
                authorAvatar: nil,
                content: post.content,
                mediaUrls: [],
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


// MARK: - Feed Logger

/// Unified logger for Feed-related debug output
enum FeedLogger {
    /// Log debug message (only in DEBUG builds)
    static func debug(_ message: String) {
        #if DEBUG
        print("[Feed] \(message)")
        #endif
    }
    
    /// Log error with context
    static func error(_ message: String, error: Error? = nil) {
        #if DEBUG
        if let error = error {
            print("[Feed] ERROR: \(message) - \(error)")
        } else {
            print("[Feed] ERROR: \(message)")
        }
        #endif
    }
}
