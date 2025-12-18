import Foundation
import SwiftUI
import Combine

// MARK: - Feed Logger
enum FeedLogger {
    static func debug(_ message: String) {
        #if DEBUG
        print("[Feed] \(message)")
        #endif
    }

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

    // Combine subscriptions for notifications
    private var cancellables = Set<AnyCancellable>()

    // Image prefetch target size for feed cards
    private let prefetchTargetSize = CGSize(width: 750, height: 1000)

    // MARK: - Image Prefetching

    /// Prefetch images for upcoming posts to improve scroll performance
    private func prefetchImagesForPosts(_ posts: [FeedPost], startIndex: Int = 0, count: Int = 5) {
        let endIndex = min(startIndex + count, posts.count)
        guard startIndex < endIndex else { return }

        let upcomingPosts = posts[startIndex..<endIndex]
        let urls = upcomingPosts.flatMap { $0.displayMediaUrls }

        guard !urls.isEmpty else { return }

        // Run prefetch asynchronously to avoid blocking main actor
        Task.detached(priority: .utility) { [urls, prefetchTargetSize] in
            await ImageCacheService.shared.prefetch(urls: urls, targetSize: prefetchTargetSize)
        }
    }

    /// Called when a post appears on screen - prefetch next batch
    func onPostAppear(at index: Int) {
        // Prefetch images for the next 5 posts
        prefetchImagesForPosts(posts, startIndex: index + 1, count: 5)
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

        // 订阅头像更新通知
        setupAvatarUpdateObserver()
    }

    // MARK: - Avatar Update Observer

    /// 设置头像更新通知监听器
    /// 当任何用户的头像更新时，自动更新 Feed 中该用户的所有帖子头像
    private func setupAvatarUpdateObserver() {
        NotificationCenter.default.publisher(for: .userAvatarDidUpdate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self else { return }

                // 从通知中提取用户 ID 和新头像 URL
                guard let userInfo = notification.userInfo,
                      let userId = userInfo[AvatarNotificationKey.userId.rawValue] as? String else {
                    return
                }

                let avatarUrl = userInfo[AvatarNotificationKey.avatarUrl.rawValue] as? String

                // 更新 Feed 中该用户的所有帖子头像
                self.updateAvatarForUser(userId: userId, avatarUrl: avatarUrl)
            }
            .store(in: &cancellables)

        FeedLogger.debug("Avatar update observer setup complete")
    }

    /// 更新指定用户在 Feed 中的所有帖子头像
    /// - Parameters:
    ///   - userId: 需要更新头像的用户 ID
    ///   - avatarUrl: 新的头像 URL
    private func updateAvatarForUser(userId: String, avatarUrl: String?) {
        var updatedCount = 0

        posts = posts.map { post in
            if post.authorId == userId {
                updatedCount += 1
                return post.copying(authorAvatar: avatarUrl)
            }
            return post
        }

        if updatedCount > 0 {
            FeedLogger.debug("Updated avatar for \(updatedCount) posts from user \(userId)")
        }
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
                // Pass channel filter if selected
                response = try await feedService.getFeed(algo: algorithm, limit: 20, cursor: nil, channelId: selectedChannelId)
            } else {
                // Guest Mode: fetch trending posts without authentication
                response = try await feedService.getTrendingFeed(limit: 20, cursor: nil)
            }

            // Feed API now returns full post objects directly
            self.postIds = response.postIds
            self.currentCursor = response.cursor
            self.hasMore = response.hasMore

            // Convert raw posts to FeedPost objects directly
            var allPosts = response.posts.map { FeedPost(from: $0) }

            // Sync current user's avatar for their own posts (ensures latest avatar is shown)
            allPosts = syncCurrentUserAvatar(allPosts)

            // Fetch bookmark status for authenticated users
            if isAuthenticated, !allPosts.isEmpty {
                let postIds = allPosts.map { $0.id }
                if let bookmarkedIds = try? await socialService.batchCheckBookmarked(postIds: postIds) {
                    allPosts = allPosts.map { post in
                        bookmarkedIds.contains(post.id) ? post.copying(isBookmarked: true) : post
                    }
                }
            }

            // Client-side deduplication: Remove duplicate posts by ID
            var seenIds = Set<String>()
            self.posts = allPosts.filter { post in
                guard !seenIds.contains(post.id) else { return false }
                seenIds.insert(post.id)
                return true
            }

            // Prefetch images for first batch of posts
            prefetchImagesForPosts(self.posts, startIndex: 0, count: 10)

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
            } else if case .serverError(let statusCode, _) = apiError, (500...503).contains(statusCode) {
                // Backend feed-service unreachable, bad gateway (502), or service unavailable (503)
                // Fallback: load guest/trending feed instead of showing a hard error.
                do {
                    let fallbackResponse = try await feedService.getTrendingFeed(limit: 20, cursor: nil)

                    self.postIds = fallbackResponse.postIds
                    self.currentCursor = fallbackResponse.cursor
                    self.hasMore = fallbackResponse.hasMore

                    var allPosts = fallbackResponse.posts.map { FeedPost(from: $0) }

                    // Sync current user's avatar for their own posts
                    allPosts = syncCurrentUserAvatar(allPosts)

                    // Fetch bookmark status for authenticated users
                    if isAuthenticated, !allPosts.isEmpty {
                        let postIds = allPosts.map { $0.id }
                        if let bookmarkedIds = try? await socialService.batchCheckBookmarked(postIds: postIds) {
                            allPosts = allPosts.map { post in
                                bookmarkedIds.contains(post.id) ? post.copying(isBookmarked: true) : post
                            }
                        }
                    }

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
            var newPosts = response.posts.map { FeedPost(from: $0) }

            // Sync current user's avatar for their own posts
            newPosts = syncCurrentUserAvatar(newPosts)

            // Fetch bookmark status for authenticated users
            if isAuthenticated, !newPosts.isEmpty {
                let postIds = newPosts.map { $0.id }
                if let bookmarkedIds = try? await socialService.batchCheckBookmarked(postIds: postIds) {
                    newPosts = newPosts.map { post in
                        bookmarkedIds.contains(post.id) ? post.copying(isBookmarked: true) : post
                    }
                }
            }

            // Client-side deduplication: Only add posts that aren't already in the feed
            let existingIds = Set(self.posts.map { $0.id })
            let uniqueNewPosts = newPosts.filter { !existingIds.contains($0.id) }

            // If no new unique posts, stop pagination (backend returned duplicates or empty)
            if uniqueNewPosts.isEmpty {
                self.hasMore = false
                #if DEBUG
                print("[Feed] loadMore returned no new posts, stopping pagination")
                #endif
            } else {
                self.posts.append(contentsOf: uniqueNewPosts)
            }

        } catch {
            // Stop pagination on error to prevent infinite retry loop
            // Backend doesn't support cursor pagination yet, so errors here are expected
            self.hasMore = false
            #if DEBUG
            print("[Feed] loadMore error (stopping pagination): \(error)")
            #endif
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
                // Pass channel filter if selected
                response = try await feedService.getFeed(algo: currentAlgorithm, limit: 20, cursor: nil, channelId: selectedChannelId)
            } else {
                response = try await feedService.getTrendingFeed(limit: 20, cursor: nil)
            }

            // 成功后更新数据
            self.postIds = response.postIds
            self.currentCursor = response.cursor
            self.hasMore = response.hasMore

            var allPosts = response.posts.map { FeedPost(from: $0) }

            // Sync current user's avatar for their own posts
            allPosts = syncCurrentUserAvatar(allPosts)

            // Fetch bookmark status for authenticated users
            if isAuthenticated, !allPosts.isEmpty {
                let postIds = allPosts.map { $0.id }
                if let bookmarkedIds = try? await socialService.batchCheckBookmarked(postIds: postIds) {
                    allPosts = allPosts.map { post in
                        bookmarkedIds.contains(post.id) ? post.copying(isBookmarked: true) : post
                    }
                }
            }

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
        // Prevent concurrent like operations for the same post
        guard !ongoingLikeOperations.contains(postId) else {
            #if DEBUG
            print("[Feed] toggleLike skipped - operation already in progress for postId: \(postId)")
            #endif
            return
        }
        ongoingLikeOperations.insert(postId)
        defer { ongoingLikeOperations.remove(postId) }

        #if DEBUG
        print("[Feed] toggleLike called for postId: \(postId)")
        print("[Feed] currentUserId: \(currentUserId ?? "nil")")
        print("[Feed] isAuthenticated: \(isAuthenticated)")
        #endif

        guard let index = posts.firstIndex(where: { $0.id == postId }),
              let userId = currentUserId else {
            #if DEBUG
            print("[Feed] toggleLike early return - postId not found or userId is nil")
            #endif
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
            // Revert on failure
            posts[index] = post

            // Handle specific error cases
            switch error {
            case .unauthorized:
                // Session expired - logout to redirect to login page
                await authManager.logout()
                #if DEBUG
                print("[Feed] Toggle like error: Session expired, logging out")
                #endif
            case .noConnection:
                self.toastError = "No internet connection. Please try again."
            case .serviceUnavailable:
                self.toastError = "Service temporarily unavailable. Please try again later."
                #if DEBUG
                print("[Feed] Toggle like error: Service unavailable (503)")
                #endif
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

    /// Increment comment count for a post (called when a comment is successfully added)
    func incrementCommentCount(postId: String) {
        guard let index = posts.firstIndex(where: { $0.id == postId }) else { return }
        let post = posts[index]
        posts[index] = post.copying(commentCount: post.commentCount + 1)
    }

    /// Toggle bookmark on a post
    func toggleBookmark(postId: String) async {
        // Prevent concurrent bookmark operations for the same post
        guard !ongoingBookmarkOperations.contains(postId) else {
            #if DEBUG
            print("[Feed] toggleBookmark skipped - operation already in progress for postId: \(postId)")
            #endif
            return
        }
        ongoingBookmarkOperations.insert(postId)
        defer { ongoingBookmarkOperations.remove(postId) }

        #if DEBUG
        print("[Feed] toggleBookmark called for postId: \(postId)")
        print("[Feed] currentUserId: \(currentUserId ?? "nil")")
        #endif

        guard let index = posts.firstIndex(where: { $0.id == postId }),
              let userId = currentUserId else {
            #if DEBUG
            print("[Feed] toggleBookmark early return - postId not found or userId is nil")
            #endif
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
            // Handle specific error cases - some errors should keep local state
            switch error {
            case .unauthorized:
                // Revert on auth error
                posts[index] = post
                // Session expired - logout to redirect to login page
                await authManager.logout()
                #if DEBUG
                print("[Feed] Toggle bookmark error: Session expired, logging out")
                #endif
            case .noConnection:
                // Revert on connection error
                posts[index] = post
                self.toastError = "No internet connection. Please try again."
            case .notFound, .serverError, .serviceUnavailable:
                // Backend bookmark API not deployed yet or temporarily unavailable - keep local state (don't revert)
                #if DEBUG
                print("[Feed] Bookmark API not available (\(error)), using local state only")
                #endif
            default:
                // Revert on other errors
                posts[index] = post
                self.toastError = "Failed to bookmark post. Please try again."
                #if DEBUG
                print("[Feed] Toggle bookmark error: \(error)")
                #endif
            }
        } catch {
            // Revert on unknown failure
            posts[index] = post
            self.toastError = "Failed to bookmark post. Please try again."
            #if DEBUG
            print("[Feed] Toggle bookmark error: \(error)")
            #endif
        }
    }

    // MARK: - Private Methods

    /// Process posts: sync current user avatar, enrich with bookmark status and deduplicate
    private func processAndDeduplicatePosts(_ posts: [FeedPost]) async -> [FeedPost] {
        let syncedPosts = syncCurrentUserAvatar(posts)
        let enrichedPosts = await enrichWithBookmarkStatus(syncedPosts)
        return deduplicatePosts(enrichedPosts)
    }

    /// Sync current user's avatar for their own posts
    /// This ensures the Feed shows the latest avatar after user updates it locally
    private func syncCurrentUserAvatar(_ posts: [FeedPost]) -> [FeedPost] {
        #if DEBUG
        print("[Feed] syncCurrentUserAvatar called with \(posts.count) posts")
        print("[Feed] currentUser id: \(authManager.currentUser?.id ?? "nil")")
        print("[Feed] currentUser avatarUrl: \(authManager.currentUser?.avatarUrl ?? "nil")")
        #endif

        guard let currentUserId = authManager.currentUser?.id,
              let currentUserAvatar = authManager.currentUser?.avatarUrl else {
            #if DEBUG
            print("[Feed] syncCurrentUserAvatar: skipped - currentUser or avatarUrl is nil")
            #endif
            return posts
        }

        return posts.map { post in
            if post.authorId == currentUserId {
                #if DEBUG
                print("[Feed] Syncing avatar for post \(post.id) - old: \(post.authorAvatar ?? "nil"), new: \(currentUserAvatar)")
                #endif
                return post.copying(authorAvatar: currentUserAvatar)
            }
            return post
        }
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
