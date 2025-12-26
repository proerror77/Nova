import Foundation
import SwiftUI
import OSLog

// MARK: - Feed Logger

enum FeedLogger {
    static func debug(_ message: String, file: String = #file) {
        #if DEBUG
        let fileName = (file as NSString).lastPathComponent
        print("[Feed] [\(fileName)] \(message)")
        #endif
    }

    static func error(_ message: String, error: Error? = nil, file: String = #file) {
        #if DEBUG
        let fileName = (file as NSString).lastPathComponent
        if let error = error {
            print("[Feed] [\(fileName)] ERROR: \(message) - \(error)")
        } else {
            print("[Feed] [\(fileName)] ERROR: \(message)")
        }
        #endif
    }
}

// MARK: - Feed ViewModel
// iOS 17+ 使用 @Observable macro 替代 ObservableObject
// 重構後：委派職責給專門的 Handler 類別

@MainActor
@Observable
final class FeedViewModel {
    // MARK: - Observable State

    var posts: [FeedPost] = [] {
        didSet {
            _cachedFeedItems = nil
        }
    }
    var postIds: [String] = []
    var isLoading = false
    var isLoadingMore = false
    var error: String?
    var toastError: String?
    var hasMore = true
    var isRefreshing = false
    var lastRefreshedAt: Date?

    // MARK: - Cached Feed Items

    private var _cachedFeedItems: [FeedItemType]?

    var feedItems: [FeedItemType] {
        if let cached = _cachedFeedItems {
            return cached
        }
        let items = FeedLayoutBuilder.buildFeedItems(from: posts)
        _cachedFeedItems = items
        return items
    }

    // MARK: - Handlers (Delegated Responsibilities)

    private let socialActionsHandler: FeedSocialActionsHandler
    private let imagePrefetcher: FeedImagePrefetcher
    private let postProcessor: FeedPostProcessor
    let channelManager: FeedChannelManager
    private let memoryManager: FeedMemoryManager

    // MARK: - Services

    private let feedService: FeedService
    private let contentService: ContentService
    private let authManager: AuthenticationManager
    private let performanceMonitor = FeedPerformanceMonitor.shared

    // MARK: - Private State

    private var currentCursor: String?
    private var currentAlgorithm: FeedAlgorithm = .chronological

    private var currentUserId: String? {
        KeychainService.shared.get(.userId)
    }

    private var isAuthenticated: Bool {
        authManager.isAuthenticated && !authManager.isGuestMode
    }

    #if DEBUG
    private var loadFeedInvocationCounter: Int = 0
    #endif

    // MARK: - Channel State (Forwarded from ChannelManager)

    var channels: [FeedChannel] { channelManager.channels }
    var selectedChannelId: String? {
        get { channelManager.selectedChannelId }
        set { channelManager.selectedChannelId = newValue }
    }
    var isLoadingChannels: Bool { channelManager.isLoadingChannels }

    // MARK: - Computed Properties

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

    // MARK: - Init

    init(
        feedService: FeedService = FeedService(),
        contentService: ContentService = ContentService(),
        socialService: SocialService = SocialService(),
        authManager: AuthenticationManager? = nil
    ) {
        self.feedService = feedService
        self.contentService = contentService
        self.authManager = authManager ?? AuthenticationManager.shared

        // Initialize handlers
        self.socialActionsHandler = FeedSocialActionsHandler(
            socialService: socialService,
            authManager: self.authManager
        )
        self.imagePrefetcher = FeedImagePrefetcher()
        self.postProcessor = FeedPostProcessor(
            socialService: socialService,
            feedService: feedService,
            authManager: self.authManager
        )
        self.channelManager = FeedChannelManager(feedService: feedService)
        self.memoryManager = FeedMemoryManager()

        // Setup callbacks
        setupHandlerCallbacks()
    }

    private func setupHandlerCallbacks() {
        // Social actions handler callbacks
        socialActionsHandler.onPostUpdate = { [weak self] (postId: String, transform: (FeedPost) -> FeedPost) in
            guard let self = self,
                  let index = self.posts.firstIndex(where: { $0.id == postId }) else { return }
            self.posts[index] = transform(self.posts[index])
        }

        socialActionsHandler.onError = { [weak self] (message: String) in
            self?.toastError = message
        }

        // Channel manager callback
        channelManager.onChannelSelected = { [weak self] (_: String?) in
            await self?.loadFeed(algorithm: self?.currentAlgorithm ?? .chronological)
        }
    }

    // MARK: - Feed Loading

    func loadFeed(
        algorithm: FeedAlgorithm = .chronological,
        isGuestFallback: Bool = false,
        forceRefresh: Bool = false
    ) async {
        guard !isLoading else { return }

        let loadStartTime = Date()
        let signpostState = performanceMonitor.beginFeedLoad(source: .initial, fromCache: false)

        isLoading = true
        error = nil
        currentAlgorithm = algorithm
        currentCursor = nil

        #if DEBUG
        loadFeedInvocationCounter += 1
        let invocationId = loadFeedInvocationCounter
        FeedLogger.debug("loadFeed #\(invocationId) start auth=\(isAuthenticated) guestFallback=\(isGuestFallback) channelId=\(selectedChannelId ?? "nil")")
        #endif

        // Try cached data first (unless force refresh)
        if !forceRefresh {
            await loadFromCacheIfAvailable(algorithm: algorithm)
        }

        do {
            let response = try await fetchFeed(algorithm: algorithm)
            await processFeedResponse(response, algorithm: algorithm)

            self.error = nil

            let duration = Date().timeIntervalSince(loadStartTime)
            performanceMonitor.endFeedLoad(signpostID: signpostState, success: true, postCount: posts.count, duration: duration)

        } catch let apiError as APIError {
            await handleLoadError(apiError, algorithm: algorithm, isGuestFallback: isGuestFallback, signpostState: signpostState, startTime: loadStartTime)
        } catch {
            performanceMonitor.recordError(error, context: "loadFeed")
            self.error = "Failed to load feed: \(error.localizedDescription)"
            self.posts = []

            let duration = Date().timeIntervalSince(loadStartTime)
            performanceMonitor.endFeedLoad(signpostID: signpostState, success: false, postCount: 0, duration: duration)
        }

        isLoading = false
    }

    func loadMore() async {
        guard !isLoadingMore, hasMore, currentCursor != nil else {
            if currentCursor == nil {
                hasMore = false
            }
            return
        }

        isLoadingMore = true

        do {
            let response = try await feedService.getFeed(
                algo: currentAlgorithm,
                limit: 20,
                cursor: currentCursor,
                channelId: selectedChannelId
            )

            postIds.append(contentsOf: response.postIds)
            currentCursor = response.cursor
            hasMore = response.hasMore

            var newPosts = response.posts.map { FeedPost(from: $0) }
            newPosts = postProcessor.syncCurrentUserProfile(newPosts)

            let existingIds = Set(posts.map { $0.id })
            let uniqueNewPosts = newPosts.filter { !existingIds.contains($0.id) }

            if !uniqueNewPosts.isEmpty {
                posts.append(contentsOf: uniqueNewPosts)

                loadAsyncEnrichments(for: uniqueNewPosts)
                memoryManager.enforceMemoryLimit(posts: &posts, postIds: &postIds)
            }

        } catch {
            FeedLogger.error("loadMore failed", error: error)
        }

        isLoadingMore = false
    }

    func refresh() async {
        guard !isLoading && !isRefreshing else { return }

        let refreshStartTime = Date()
        let signpostState = performanceMonitor.beginFeedLoad(source: .refresh, fromCache: false)

        isLoading = true
        isRefreshing = true
        imagePrefetcher.clearPrefetchFailures()

        do {
            let response: FeedResponse
            if isAuthenticated {
                response = try await feedService.getFeed(algo: currentAlgorithm, limit: 20, cursor: nil, channelId: selectedChannelId)
            } else {
                response = try await feedService.getTrendingFeed(limit: 20, cursor: nil)
            }

            await FeedCacheService.shared.cacheFeed(response, algo: currentAlgorithm, channelId: selectedChannelId, cursor: nil)

            postIds = response.postIds
            currentCursor = response.cursor
            hasMore = response.hasMore

            var allPosts = response.posts.map { FeedPost(from: $0) }
            allPosts = postProcessor.syncCurrentUserProfile(allPosts)
            posts = postProcessor.deduplicatePosts(allPosts)

            loadAsyncEnrichments(for: posts)

            self.error = nil
            lastRefreshedAt = Date()

            let duration = Date().timeIntervalSince(refreshStartTime)
            performanceMonitor.endFeedLoad(signpostID: signpostState, success: true, postCount: posts.count, duration: duration)

        } catch {
            if !isCancelledError(error) && posts.isEmpty {
                self.error = "Failed to refresh: \(error.localizedDescription)"

                let duration = Date().timeIntervalSince(refreshStartTime)
                performanceMonitor.endFeedLoad(signpostID: signpostState, success: false, postCount: 0, duration: duration)
            }
        }

        isLoading = false
        isRefreshing = false
    }

    // MARK: - Channel Management (Delegated)

    func loadChannels() async {
        await channelManager.loadChannels()
    }

    func selectChannel(_ channelId: String?) async {
        await channelManager.selectChannel(channelId)
    }

    // MARK: - Social Actions (Delegated)

    func toggleLike(postId: String) async {
        guard let post = posts.first(where: { $0.id == postId }) else { return }
        await socialActionsHandler.toggleLike(postId: postId, currentPost: post)
    }

    func toggleBookmark(postId: String) async {
        guard let post = posts.first(where: { $0.id == postId }) else { return }
        await socialActionsHandler.toggleBookmark(postId: postId, currentPost: post)
    }

    func sharePost(postId: String) async -> FeedPost? {
        guard let post = posts.first(where: { $0.id == postId }) else { return nil }
        return await socialActionsHandler.sharePost(postId: postId, currentPost: post)
    }

    func incrementCommentCount(postId: String) {
        socialActionsHandler.incrementCommentCount(postId: postId)
    }

    // MARK: - Image Prefetching (Delegated)

    func onPostAppear(at index: Int) {
        imagePrefetcher.onPostAppear(at: index, posts: posts)
    }

    func onVisiblePostsChanged(visibleIndices: Set<Int>) {
        imagePrefetcher.onVisiblePostsChanged(visibleIndices: visibleIndices, posts: posts)
    }

    func clearPrefetchFailures() {
        imagePrefetcher.clearPrefetchFailures()
    }

    // MARK: - New Post

    func addNewPost(_ post: Post) {
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

        posts.insert(feedPost, at: 0)
        postIds.insert(post.id, at: 0)

        memoryManager.addRecentlyCreatedPost(feedPost)

        Task.detached(priority: .utility) {
            await FeedCacheService.shared.invalidateCacheOnNewPost()
        }

        memoryManager.enforceMemoryLimit(posts: &posts, postIds: &postIds)
    }

    // MARK: - Algorithm

    func switchAlgorithm(to algorithm: FeedAlgorithm) async {
        guard algorithm != currentAlgorithm else { return }
        await loadFeed(algorithm: algorithm)
    }

    // MARK: - Performance Monitoring

    func getPerformanceMetrics() -> FeedMetrics {
        performanceMonitor.getMetrics()
    }

    func logPerformanceMetrics() {
        #if DEBUG
        performanceMonitor.logMetrics()
        #endif
    }

    func resetPerformanceMetrics() {
        performanceMonitor.resetMetrics()
    }

    // MARK: - Private Helpers

    private func loadFromCacheIfAvailable(algorithm: FeedAlgorithm) async {
        if let cachedResponse = await FeedCacheService.shared.getCachedFeed(
            algo: algorithm,
            channelId: selectedChannelId,
            cursor: nil
        ) {
            performanceMonitor.recordCacheAccess(hit: true)

            var cachedPosts = cachedResponse.posts.map { FeedPost(from: $0) }
            cachedPosts = postProcessor.syncCurrentUserProfile(cachedPosts)

            let missingPosts = memoryManager.getMissingRecentPosts(serverPostIds: Set(cachedPosts.map { $0.id }))
            if !missingPosts.isEmpty {
                cachedPosts.insert(contentsOf: missingPosts, at: 0)
            }

            posts = postProcessor.deduplicatePosts(cachedPosts)
            postIds = cachedResponse.postIds
            hasMore = cachedResponse.hasMore

            imagePrefetcher.prefetchImagesForPosts(posts, startIndex: 0, count: 10)
            loadAsyncEnrichments(for: posts)
        } else {
            performanceMonitor.recordCacheAccess(hit: false)
        }
    }

    private func fetchFeed(algorithm: FeedAlgorithm) async throws -> FeedResponse {
        if isAuthenticated {
            return try await feedService.getFeed(algo: algorithm, limit: 20, cursor: nil, channelId: selectedChannelId)
        } else {
            return try await feedService.getTrendingFeed(limit: 20, cursor: nil)
        }
    }

    private func processFeedResponse(_ response: FeedResponse, algorithm: FeedAlgorithm) async {
        await FeedCacheService.shared.cacheFeed(response, algo: algorithm, channelId: selectedChannelId, cursor: nil)

        postIds = response.postIds
        currentCursor = response.cursor
        hasMore = response.hasMore

        var allPosts = response.posts.map { FeedPost(from: $0) }
        allPosts = postProcessor.syncCurrentUserProfile(allPosts)

        let missingPosts = memoryManager.getMissingRecentPosts(serverPostIds: Set(allPosts.map { $0.id }))
        if !missingPosts.isEmpty {
            allPosts.insert(contentsOf: missingPosts, at: 0)
        }

        posts = postProcessor.deduplicatePosts(allPosts)

        imagePrefetcher.prefetchImagesForPosts(posts, startIndex: 0, count: 10)
        loadAsyncEnrichments(for: posts)
    }

    private func loadAsyncEnrichments(for posts: [FeedPost]) {
        let postIds = posts.map { $0.id }

        postProcessor.loadBookmarkStatusAsync(for: postIds) { [weak self] (bookmarkedIds: Set<String>) in
            guard let self = self else { return }
            self.postProcessor.updateBookmarkStates(bookmarkedIds, in: &self.posts)
        }

        postProcessor.fetchMissingAuthorProfilesAsync(for: posts) { [weak self] (profiles: [String: AuthorProfile]) in
            guard let self = self else { return }
            self.postProcessor.updateAuthorProfiles(profiles, in: &self.posts)
        }
    }

    private func handleLoadError(
        _ apiError: APIError,
        algorithm: FeedAlgorithm,
        isGuestFallback: Bool,
        signpostState: OSSignpostIntervalState,
        startTime: Date
    ) async {
        performanceMonitor.recordError(apiError, context: "loadFeed")

        if case .unauthorized = apiError, isAuthenticated, !isGuestFallback {
            let refreshed = await authManager.attemptTokenRefresh()
            if refreshed {
                isLoading = false
                await loadFeed(algorithm: algorithm, isGuestFallback: isGuestFallback)
                return
            } else {
                isLoading = false
                await loadFeed(algorithm: algorithm, isGuestFallback: true)
                return
            }
        } else if case .serverError(let statusCode, _) = apiError, (500...503).contains(statusCode) {
            await handleServerErrorFallback()
        } else {
            self.error = apiError.localizedDescription
            self.posts = []

            let duration = Date().timeIntervalSince(startTime)
            performanceMonitor.endFeedLoad(signpostID: signpostState, success: false, postCount: 0, duration: duration)
        }
    }

    private func handleServerErrorFallback() async {
        do {
            let fallbackResponse = try await feedService.getTrendingFeed(limit: 20, cursor: nil)

            postIds = fallbackResponse.postIds
            currentCursor = fallbackResponse.cursor
            hasMore = fallbackResponse.hasMore

            var allPosts = fallbackResponse.posts.map { FeedPost(from: $0) }
            allPosts = postProcessor.syncCurrentUserProfile(allPosts)
            posts = postProcessor.deduplicatePosts(allPosts)

            loadAsyncEnrichments(for: posts)
            self.error = nil
        } catch {
            self.error = "Feed service unavailable"
            self.posts = []
        }
    }

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
}

// MARK: - Feed State

enum FeedState {
    case idle
    case loading
    case loaded
    case error(String)
    case empty
}
