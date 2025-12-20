import Foundation
import SwiftUI
import OSLog

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
    @Published var isRefreshing = false  // Explicit refresh state for UI feedback
    @Published var lastRefreshedAt: Date?  // Track last refresh time

    // MARK: - Channel State
    @Published var channels: [FeedChannel] = []
    @Published var selectedChannelId: String? = nil  // nil = "For You" / all content
    @Published var isLoadingChannels = false

    // MARK: - Private Properties

    private let feedService: FeedService
    private let contentService: ContentService
    private let socialService: SocialService
    private let authManager: AuthenticationManager
    private let performanceMonitor = FeedPerformanceMonitor.shared
    private var currentCursor: String?
    private var currentAlgorithm: FeedAlgorithm = .chronological
    private var currentUserId: String? {
        KeychainService.shared.get(.userId)
    }

    // Track ongoing like operations to prevent concurrent calls for the same post
    private var ongoingLikeOperations: Set<String> = []

    // Track recently created posts to preserve them after refresh (optimistic update)
    // Posts are kept for 5 minutes to allow backend indexing
    private var recentlyCreatedPosts: [(post: FeedPost, createdAt: Date)] = []
    private let recentPostRetentionDuration: TimeInterval = 300  // 5 minutes

    // MARK: - Memory Management

    // Maximum number of posts to keep in memory to prevent excessive memory usage
    private let maxPostsInMemory = 100
    
    #if DEBUG
    private var loadFeedInvocationCounter: Int = 0
    #endif

    // Track ongoing bookmark operations to prevent concurrent calls for the same post
    private var ongoingBookmarkOperations: Set<String> = []

    // Image prefetch target size for feed cards
    private let prefetchTargetSize = CGSize(width: 750, height: 1000)

    // Prefetch throttling (debounce)
    private var lastPrefetchTime: Date = .distantPast
    private let prefetchDebounceInterval: TimeInterval = 0.5

    // MARK: - Image Prefetching

    // Track failed prefetch URLs to avoid repeated attempts
    private var failedPrefetchUrls: Set<String> = []
    private let maxPrefetchRetries = 2

    /// Prefetch images for upcoming posts to improve scroll performance
    private func prefetchImagesForPosts(_ posts: [FeedPost], startIndex: Int = 0, count: Int = 5) {
        let endIndex = min(startIndex + count, posts.count)
        guard startIndex < endIndex else { return }

        let upcomingPosts = posts[startIndex..<endIndex]
        let urls = upcomingPosts.flatMap { $0.displayMediaUrls }
            .filter { !failedPrefetchUrls.contains($0) }  // Skip previously failed URLs

        guard !urls.isEmpty else { return }

        // Start tracking image prefetch
        let signpostID = performanceMonitor.beginImagePrefetch(urlCount: urls.count)

        // Run prefetch asynchronously with low priority and error handling
        // Use Task instead of Task.detached to maintain MainActor context for failedPrefetchUrls access
        Task(priority: .utility) { [urls, prefetchTargetSize, weak self] in
            var successCount = 0
            var failCount = 0

            do {
                await ImageCacheService.shared.prefetch(urls: urls, targetSize: prefetchTargetSize, priority: .low)
                successCount = urls.count
            } catch {
                // Log prefetch errors in debug mode, mark URLs as failed
                FeedLogger.debug("Prefetch failed for \(urls.count) URLs: \(error.localizedDescription)")
                failCount = urls.count

                // Already on MainActor, can safely access failedPrefetchUrls
                guard let self = self else { return }
                // Mark failed URLs to avoid repeated attempts
                for url in urls {
                    self.failedPrefetchUrls.insert(url)
                }
                // Limit failed URL cache size
                if self.failedPrefetchUrls.count > 100 {
                    self.failedPrefetchUrls.removeFirst()
                }
            }

            // Track prefetch completion
            self?.performanceMonitor.endImagePrefetch(signpostID: signpostID, successCount: successCount, failCount: failCount)
        }
    }

    /// Called when a post appears on screen - prefetch next batch
    func onPostAppear(at index: Int) {
        // Prefetch images for the next 5 posts
        prefetchImagesForPosts(posts, startIndex: index + 1, count: 5)
    }

    /// Smart prefetch with visibility tracking for optimal performance
    /// Uses debouncing to prevent excessive prefetch calls during rapid scrolling
    func onVisiblePostsChanged(visibleIndices: Set<Int>) {
        guard !posts.isEmpty else { return }

        // Debounce: skip if called too frequently (within 0.5 seconds)
        let now = Date()
        guard now.timeIntervalSince(lastPrefetchTime) > prefetchDebounceInterval else {
            return
        }
        lastPrefetchTime = now

        let sortedIndices = visibleIndices.sorted()
        guard let _ = sortedIndices.first,
              let lastVisible = sortedIndices.last else { return }

        // Get URLs for currently visible posts (high priority)
        let visibleUrls = sortedIndices
            .filter { $0 < posts.count }
            .flatMap { posts[$0].displayMediaUrls }
            .filter { !failedPrefetchUrls.contains($0) }

        // Get URLs for upcoming posts (prefetch with low priority)
        let prefetchStart = lastVisible + 1
        let prefetchEnd = min(prefetchStart + 8, posts.count)
        let upcomingUrls = (prefetchStart..<prefetchEnd)
            .flatMap { posts[$0].displayMediaUrls }
            .filter { !failedPrefetchUrls.contains($0) }

        // Use smart prefetch for optimal loading with error handling
        // Use Task instead of Task.detached to maintain MainActor context for failedPrefetchUrls access
        Task(priority: .utility) { [visibleUrls, upcomingUrls, prefetchTargetSize, weak self] in
            do {
                await ImageCacheService.shared.smartPrefetch(
                    visibleUrls: visibleUrls,
                    upcomingUrls: upcomingUrls,
                    targetSize: prefetchTargetSize
                )
            } catch {
                FeedLogger.debug("Smart prefetch failed: \(error.localizedDescription)")
                // Already on MainActor, can safely access failedPrefetchUrls
                guard let self = self else { return }
                // Mark failed URLs
                for url in visibleUrls + upcomingUrls {
                    self.failedPrefetchUrls.insert(url)
                }
            }
        }
    }

    /// Clear failed prefetch cache (called on refresh)
    func clearPrefetchFailures() {
        failedPrefetchUrls.removeAll()
    }

    // MARK: - Public Methods

    /// Check if user is authenticated (has valid token and is not in guest mode)
    private var isAuthenticated: Bool {
        authManager.isAuthenticated && !authManager.isGuestMode
    }

    /// Formatted string showing when feed was last refreshed
    var lastRefreshedText: String? {
        guard let lastRefresh = lastRefreshedAt else { return nil }
        let interval = Date().timeIntervalSince(lastRefresh)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: lastRefresh)
        }
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
        isGuestFallback: Bool = false,
        forceRefresh: Bool = false
    ) async {
        guard !isLoading else { return }

        // Start performance tracking
        let loadStartTime = Date()
        let signpostID = performanceMonitor.beginFeedLoad(source: .initial, fromCache: false)

        isLoading = true
        error = nil
        currentAlgorithm = algorithm
        currentCursor = nil

        #if DEBUG
        loadFeedInvocationCounter += 1
        let invocationId = loadFeedInvocationCounter
        print("[FeedVM] loadFeed #\(invocationId) start auth=\(isAuthenticated) guestFallback=\(isGuestFallback) channelId=\(selectedChannelId ?? "nil") forceRefresh=\(forceRefresh)")
        #endif

        // OPTIMIZATION: Return cached data first for instant display (unless force refresh)
        if !forceRefresh {
            if let cachedResponse = await FeedCacheService.shared.getCachedFeed(
                algo: algorithm,
                channelId: selectedChannelId,
                cursor: nil
            ) {
                #if DEBUG
                print("[FeedVM] loadFeed #\(invocationId) using cached data (\(cachedResponse.posts.count) posts)")
                #endif

                // Track cache hit
                performanceMonitor.recordCacheAccess(hit: true)

                var cachedPosts = cachedResponse.posts.map { FeedPost(from: $0) }
                cachedPosts = syncCurrentUserAvatar(cachedPosts)
                mergeRecentlyCreatedPosts(into: &cachedPosts)

                var seenIds = Set<String>()
                self.posts = cachedPosts.filter { post in
                    guard !seenIds.contains(post.id) else { return false }
                    seenIds.insert(post.id)
                    return true
                }
                self.postIds = cachedResponse.postIds
                self.hasMore = cachedResponse.hasMore

                // Prefetch images for cached posts
                prefetchImagesForPosts(self.posts, startIndex: 0, count: 10)

                // Load bookmark status asynchronously (non-blocking)
                loadBookmarkStatusAsync(for: self.posts.map { $0.id })
            } else {
                // Track cache miss
                performanceMonitor.recordCacheAccess(hit: false)
            }
        }

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

            #if DEBUG
            let responsePreview = response.posts.prefix(5).map { "\($0.id.prefix(8))(\($0.mediaUrls?.count ?? 0))" }.joined(separator: ",")
            print("[FeedVM] loadFeed #\(invocationId) response posts=\(response.posts.count) preview=[\(responsePreview)] (format: idPrefix(mediaCount))")
            #endif

            // Cache the response for future use
            await FeedCacheService.shared.cacheFeed(
                response,
                algo: algorithm,
                channelId: selectedChannelId,
                cursor: nil
            )

            // Feed API now returns full post objects directly
            self.postIds = response.postIds
            self.currentCursor = response.cursor
            self.hasMore = response.hasMore

            // Convert raw posts to FeedPost objects directly
            var allPosts = response.posts.map { FeedPost(from: $0) }

            // DEBUG: Log posts after API conversion
            #if DEBUG
            print("[FeedVM] loadFeed AFTER API conversion: \(allPosts.count) posts")
            for post in allPosts.prefix(3) {
                print("[FeedVM]   -> \(post.id.prefix(8)): mediaUrls=\(post.mediaUrls.count), thumbnailUrls=\(post.thumbnailUrls.count)")
            }
            #endif

            // Sync current user's avatar for their own posts (ensures latest avatar is shown)
            allPosts = syncCurrentUserAvatar(allPosts)

            // DEBUG: Log posts before merge
            #if DEBUG
            print("[FeedVM] BEFORE merge: \(allPosts.count) posts, recentlyCreatedPosts=\(recentlyCreatedPosts.count)")
            for post in allPosts.prefix(3) {
                print("[FeedVM]   -> \(post.id.prefix(8)): mediaUrls=\(post.mediaUrls.count)")
            }
            #endif

            // Merge recently created posts that may not be in server response yet
            mergeRecentlyCreatedPosts(into: &allPosts)

            // DEBUG: Log posts after merge
            #if DEBUG
            print("[FeedVM] AFTER merge: \(allPosts.count) posts")
            for post in allPosts.prefix(3) {
                print("[FeedVM]   -> \(post.id.prefix(8)): mediaUrls=\(post.mediaUrls.count)")
            }
            #endif

            // Client-side deduplication: Remove duplicate posts by ID
            var seenIds = Set<String>()
            self.posts = allPosts.filter { post in
                guard !seenIds.contains(post.id) else { return false }
                seenIds.insert(post.id)
                return true
            }

            // DEBUG: Log what posts are being set
            #if DEBUG
            for post in self.posts.prefix(5) {
                print("[FeedVM] Post \(post.id.prefix(8)) set with mediaUrls=\(post.mediaUrls), thumbnailUrls=\(post.thumbnailUrls)")
            }

            let responseIdSet = Set(response.posts.map { $0.id })
            let finalIdSet = Set(self.posts.map { $0.id })
            let missingFromFinal = responseIdSet.subtracting(finalIdSet)
            if !missingFromFinal.isEmpty {
                let preview = missingFromFinal.prefix(10).map { String($0.prefix(8)) }.joined(separator: ",")
                print("[FeedVM] ⚠️ loadFeed #\(invocationId) missingFromFinal=\(missingFromFinal.count) preview=[\(preview)]")
            } else {
                print("[FeedVM] loadFeed #\(invocationId) missingFromFinal=0")
            }
            #endif

            // Prefetch images for first batch of posts
            prefetchImagesForPosts(self.posts, startIndex: 0, count: 10)

            // OPTIMIZATION: Load bookmark status asynchronously (non-blocking)
            // This allows the feed to display immediately while bookmarks load in background
            loadBookmarkStatusAsync(for: self.posts.map { $0.id })

            self.error = nil

            // Track successful load
            let duration = Date().timeIntervalSince(loadStartTime)
            performanceMonitor.endFeedLoad(signpostID: signpostID, success: true, postCount: self.posts.count, duration: duration)
        } catch let apiError as APIError {
            // Track error
            performanceMonitor.recordError(apiError, context: "loadFeed")
            // Handle unauthorized: try token refresh or fallback to guest mode
            if case .unauthorized = apiError, isAuthenticated, !isGuestFallback {
                let refreshed = await authManager.attemptTokenRefresh()
                if refreshed {
                    // Retry after token refresh
                    isLoading = false
                    await loadFeed(algorithm: algorithm, isGuestFallback: isGuestFallback)
                    return
                } else {
                    // Token refresh failed - gracefully degrade to guest mode without logging out
                    // User stays authenticated but sees guest content until next successful API call
                    FeedLogger.debug("Token refresh failed, falling back to guest feed")
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

                    // Merge recently created posts that may not be in server response yet
                    mergeRecentlyCreatedPosts(into: &allPosts)

                    var seenIds = Set<String>()
                    self.posts = allPosts.filter { post in
                        guard !seenIds.contains(post.id) else { return false }
                        seenIds.insert(post.id)
                        return true
                    }

                    // OPTIMIZATION: Load bookmark status asynchronously (non-blocking)
                    loadBookmarkStatusAsync(for: self.posts.map { $0.id })

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

                // Track failed load
                let duration = Date().timeIntervalSince(loadStartTime)
                performanceMonitor.endFeedLoad(signpostID: signpostID, success: false, postCount: 0, duration: duration)
            }
        } catch {
            // Track error
            performanceMonitor.recordError(error, context: "loadFeed")

            self.error = "Failed to load feed: \(error.localizedDescription)"
            self.posts = []

            // Track failed load
            let duration = Date().timeIntervalSince(loadStartTime)
            performanceMonitor.endFeedLoad(signpostID: signpostID, success: false, postCount: 0, duration: duration)
        }

        isLoading = false
    }

    /// Load more posts (pagination)
    /// Uses cursor-based pagination with base64-encoded offset from backend
    func loadMore() async {
        guard !isLoadingMore, hasMore else { return }

        // Must have a cursor to load more (first page is loaded via loadFeed)
        guard currentCursor != nil else {
            #if DEBUG
            print("[Feed] loadMore skipped: no cursor available")
            #endif
            hasMore = false
            return
        }

        isLoadingMore = true

        do {
            // Use cursor-based pagination: pass the cursor from previous response
            let response = try await feedService.getFeed(
                algo: currentAlgorithm,
                limit: 20,
                cursor: currentCursor,
                channelId: selectedChannelId
            )

            self.postIds.append(contentsOf: response.postIds)
            self.currentCursor = response.cursor
            self.hasMore = response.hasMore

            #if DEBUG
            print("[Feed] loadMore response: \(response.posts.count) posts, hasMore=\(response.hasMore), nextCursor=\(response.cursor ?? "nil")")
            #endif

            // Convert raw posts to FeedPost objects directly
            var newPosts = response.posts.map { FeedPost(from: $0) }

            // Sync current user's avatar for their own posts
            newPosts = syncCurrentUserAvatar(newPosts)

            // Client-side deduplication: Only add posts that aren't already in the feed
            let existingIds = Set(self.posts.map { $0.id })
            let uniqueNewPosts = newPosts.filter { !existingIds.contains($0.id) }

            // If no new unique posts, stop pagination (backend returned duplicates or empty)
            if uniqueNewPosts.isEmpty {
                self.hasMore = false
                #if DEBUG
                print("[Feed] loadMore returned no new unique posts, stopping pagination")
                #endif
            } else {
                self.posts.append(contentsOf: uniqueNewPosts)

                #if DEBUG
                print("[Feed] loadMore added \(uniqueNewPosts.count) new posts, total: \(self.posts.count)")
                #endif

                // OPTIMIZATION: Load bookmark status asynchronously for new posts
                loadBookmarkStatusAsync(for: uniqueNewPosts.map { $0.id })

                // Enforce memory limit after adding new posts
                enforceMemoryLimit()
            }

        } catch {
            // Don't stop pagination on error - allow retry
            #if DEBUG
            print("[Feed] loadMore error: \(error)")
            #endif
        }

        isLoadingMore = false
    }

    /// Refresh feed (pull-to-refresh)
    /// 下拉刷新时静默忽略取消错误，只在真正的网络错误时显示提示
    func refresh() async {
        guard !isLoading && !isRefreshing else { return }

        // Start performance tracking for refresh
        let refreshStartTime = Date()
        let signpostID = performanceMonitor.beginFeedLoad(source: .refresh, fromCache: false)

        isLoading = true
        isRefreshing = true
        clearPrefetchFailures()  // Reset failed prefetch cache on refresh
        // 刷新时不立即清除错误，只有在成功或真正的错误时才更新

        do {
            let response: FeedResponse
            if isAuthenticated {
                // Pass channel filter if selected
                response = try await feedService.getFeed(algo: currentAlgorithm, limit: 20, cursor: nil, channelId: selectedChannelId)
            } else {
                response = try await feedService.getTrendingFeed(limit: 20, cursor: nil)
            }

            // Cache the refreshed response
            await FeedCacheService.shared.cacheFeed(
                response,
                algo: currentAlgorithm,
                channelId: selectedChannelId,
                cursor: nil
            )

            // 成功后更新数据
            self.postIds = response.postIds
            self.currentCursor = response.cursor
            self.hasMore = response.hasMore

            var allPosts = response.posts.map { FeedPost(from: $0) }

            // Sync current user's avatar for their own posts
            allPosts = syncCurrentUserAvatar(allPosts)

            var seenIds = Set<String>()
            self.posts = allPosts.filter { post in
                guard !seenIds.contains(post.id) else { return false }
                seenIds.insert(post.id)
                return true
            }

            // OPTIMIZATION: Load bookmark status asynchronously (non-blocking)
            loadBookmarkStatusAsync(for: self.posts.map { $0.id })

            // 成功时清除错误并更新刷新时间
            self.error = nil
            self.lastRefreshedAt = Date()

            // Track successful refresh
            let duration = Date().timeIntervalSince(refreshStartTime)
            performanceMonitor.endFeedLoad(signpostID: signpostID, success: true, postCount: self.posts.count, duration: duration)

        } catch let apiError as APIError {
            // Track error
            performanceMonitor.recordError(apiError, context: "refresh")
            // 检查是否是取消错误（用户快速滑动导致）
            if case .networkError(let underlyingError) = apiError {
                let nsError = underlyingError as NSError
                if nsError.code == NSURLErrorCancelled {
                    // 静默忽略取消的请求，保持当前数据
                    isLoading = false
                    isRefreshing = false
                    return
                }
            }
            // 非取消错误：只有当前没有数据时才显示错误
            if posts.isEmpty {
                self.error = apiError.localizedDescription

                // Track failed refresh
                let duration = Date().timeIntervalSince(refreshStartTime)
                performanceMonitor.endFeedLoad(signpostID: signpostID, success: false, postCount: 0, duration: duration)
            }
        } catch {
            // Track error
            performanceMonitor.recordError(error, context: "refresh")

            let nsError = error as NSError
            // 检查是否是取消错误
            if nsError.code == NSURLErrorCancelled || nsError.localizedDescription.lowercased().contains("cancelled") {
                // 静默忽略取消的请求
                isLoading = false
                isRefreshing = false
                return
            }
            // 非取消错误：只有当前没有数据时才显示错误
            if posts.isEmpty {
                self.error = "Failed to refresh: \(error.localizedDescription)"

                // Track failed refresh
                let duration = Date().timeIntervalSince(refreshStartTime)
                performanceMonitor.endFeedLoad(signpostID: signpostID, success: false, postCount: 0, duration: duration)
            }
        }

        isLoading = false
        isRefreshing = false
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

        // Reload feed with new channel filter (track as channel switch)
        let loadStartTime = Date()
        let signpostID = performanceMonitor.beginFeedLoad(source: .channelSwitch, fromCache: false)

        await loadFeed(algorithm: currentAlgorithm)

        // Note: loadFeed handles its own tracking, but we track the overall channel switch duration here
        let duration = Date().timeIntervalSince(loadStartTime)
        FeedLogger.debug("Channel switch completed in \(String(format: "%.2f", duration))s")
    }

    /// Add a newly created post to the top of the feed (optimistic update)
    /// This avoids the need to refresh the entire feed after posting
    func addNewPost(_ post: Post) {
        // Use current user info for the new post
        let currentUser = authManager.currentUser
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

        #if DEBUG
        print("[FeedVM] addNewPost id=\(post.id.prefix(8)) mediaUrlsCount=\(post.mediaUrls?.count ?? 0) firstUrl=\(post.mediaUrls?.first ?? "nil")")
        #endif

        // Add to the top of the feed
        self.posts.insert(feedPost, at: 0)
        self.postIds.insert(post.id, at: 0)

        // Track recently created post to preserve after refresh
        cleanupExpiredRecentPosts()
        recentlyCreatedPosts.append((post: feedPost, createdAt: Date()))

        // Invalidate feed cache to ensure fresh data on next load
        Task.detached(priority: .utility) {
            await FeedCacheService.shared.invalidateCacheOnNewPost()
        }

        // Enforce memory limit
        enforceMemoryLimit()
    }
    
    /// Clean up expired recently created posts
    private func cleanupExpiredRecentPosts() {
        let now = Date()
        recentlyCreatedPosts.removeAll { now.timeIntervalSince($0.createdAt) > recentPostRetentionDuration }
    }

    /// Enforce memory limit by removing oldest posts when exceeding maxPostsInMemory
    /// This prevents excessive memory usage in long scrolling sessions
    private func enforceMemoryLimit() {
        guard posts.count > maxPostsInMemory else { return }

        let excessCount = posts.count - maxPostsInMemory
        // Remove oldest posts (from the end of the array)
        posts.removeLast(excessCount)
        postIds.removeLast(excessCount)

        #if DEBUG
        print("[FeedVM] Enforced memory limit: removed \(excessCount) oldest posts, now at \(posts.count) posts")
        #endif
    }

    /// Load bookmark status asynchronously without blocking the main feed display
    /// This optimization allows the feed to render immediately while bookmark states load in background
    private func loadBookmarkStatusAsync(for postIds: [String]) {
        guard isAuthenticated, !postIds.isEmpty else { return }

        // Use Task instead of Task.detached to maintain MainActor context
        Task(priority: .utility) { [weak self] in
            guard let self = self else { return }

            do {
                let bookmarkedIds = try await self.socialService.batchCheckBookmarked(postIds: postIds)

                // Already on MainActor, can safely update state
                self.updateBookmarkStates(bookmarkedIds)

                #if DEBUG
                print("[FeedVM] Async bookmark load complete: \(bookmarkedIds.count) bookmarked")
                #endif
            } catch {
                #if DEBUG
                print("[FeedVM] Async bookmark load failed: \(error)")
                #endif
                // Silently fail - bookmarks are non-critical for feed display
            }
        }
    }

    /// Update bookmark states for posts
    private func updateBookmarkStates(_ bookmarkedIds: Set<String>) {
        for i in posts.indices {
            if bookmarkedIds.contains(posts[i].id) && !posts[i].isBookmarked {
                posts[i] = posts[i].copying(isBookmarked: true)
            }
        }
    }
    
    /// Merge recently created posts that are not in the server response
    private func mergeRecentlyCreatedPosts(into posts: inout [FeedPost]) {
        cleanupExpiredRecentPosts()
        
        let serverPostIds = Set(posts.map { $0.id })
        let missingPosts = recentlyCreatedPosts
            .filter { !serverPostIds.contains($0.post.id) }
            .map { $0.post }
        
        if !missingPosts.isEmpty {
            // Insert missing recent posts at the top
            posts.insert(contentsOf: missingPosts, at: 0)
            FeedLogger.debug("Preserved \(missingPosts.count) recently created post(s) after refresh")
        }
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
                // Session issue - show error instead of forcing logout
                // APIClient's token refresh should handle re-authentication
                self.toastError = "Please try again."
                #if DEBUG
                print("[Feed] Toggle like error: Unauthorized, will retry on next action")
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
                // Session issue - show error instead of forcing logout
                self.toastError = "Please try again."
                #if DEBUG
                print("[Feed] Toggle bookmark error: Unauthorized, will retry on next action")
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
        guard let currentUserId = authManager.currentUser?.id,
              let currentUserAvatar = authManager.currentUser?.avatarUrl else {
            return posts
        }

        return posts.map { post in
            if post.authorId == currentUserId {
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
            // Session issue - show error instead of forcing logout
            // APIClient's token refresh mechanism will handle re-authentication
            self.toastError = "Please try again."
            FeedLogger.debug("Toggle \(action) error: Unauthorized, will retry on next action")
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

    // MARK: - Performance Monitoring

    /// Get current performance metrics for debugging
    func getPerformanceMetrics() -> FeedMetrics {
        return performanceMonitor.getMetrics()
    }

    /// Log performance metrics report to console (debug builds only)
    func logPerformanceMetrics() {
        #if DEBUG
        performanceMonitor.logMetrics()
        #endif
    }

    /// Reset performance metrics (for testing or new session)
    func resetPerformanceMetrics() {
        performanceMonitor.resetMetrics()
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
