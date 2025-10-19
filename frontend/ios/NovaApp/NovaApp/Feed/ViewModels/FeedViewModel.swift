import Foundation

/// Feed ViewModel with pagination + windowed memory management + intelligent preloading
@MainActor
class FeedViewModel: BaseViewModel, PaginatedViewModel {
    @Published var posts: [Post] = []

    private let repository = FeedRepository()
    var currentPage = 0
    var hasMore = true
    let pageSize = 20

    // MARK: - Memory Management
    private let maxPostsInMemory = 100  // 窗口大小：保留最近 100 个帖子
    private let trimThreshold = 150     // 超过 150 个时触发清理

    // MARK: - Preloading
    private var preloadedImageURLs = Set<URL>()
    private let preloadDistance = 5  // 预加载可见范围前后 5 个帖子的图像

    // MARK: - Load Initial
    func loadInitial() async {
        guard !isLoading else { return }

        resetPagination()

        do {
            try await withLoading {
                let result = try await repository.fetchFeed(page: 0, limit: pageSize)
                posts = result.posts
                hasMore = result.hasMore

                // 预加载首屏图像
                preloadImages(for: Array(posts.prefix(preloadDistance)))
            }
        } catch {
            handleError(error)
        }
    }

    // MARK: - Load More (Pagination)
    func loadMore() async {
        guard !isLoadingMore, hasMore else { return }

        currentPage += 1

        do {
            try await withLoadingMore {
                let result = try await repository.fetchFeed(page: currentPage, limit: pageSize)
                posts.append(contentsOf: result.posts)
                hasMore = result.hasMore

                // 内存管理：窗口化清理
                trimPostsIfNeeded()
            }
        } catch {
            handleError(error)
        }
    }

    // MARK: - Refresh (Pull-to-Refresh)
    func refresh() async {
        preloadedImageURLs.removeAll()
        await loadInitial()
    }

    // MARK: - Like/Unlike
    func toggleLike(postId: String) async {
        guard let index = posts.firstIndex(where: { $0.id == postId }) else { return }

        let post = posts[index]
        let wasLiked = post.isLiked

        // Optimistic update
        posts[index].isLiked.toggle()
        posts[index] = Post(
            id: post.id,
            author: post.author,
            imageURL: post.imageURL,
            caption: post.caption,
            likeCount: post.isLiked ? post.likeCount + 1 : post.likeCount - 1,
            commentCount: post.commentCount,
            isLiked: post.isLiked,
            createdAt: post.createdAt
        )

        do {
            if wasLiked {
                try await repository.unlikePost(postId: postId)
                AnalyticsTracker.shared.track(.postUnlike(postId: postId))
            } else {
                try await repository.likePost(postId: postId)
                AnalyticsTracker.shared.track(.postLike(postId: postId))
            }
        } catch {
            // Revert on error
            posts[index] = post
            handleError(error)
        }
    }

    // MARK: - Delete Post
    func deletePost(postId: String) async {
        do {
            try await repository.deletePost(postId: postId)
            posts.removeAll { $0.id == postId }
        } catch {
            handleError(error)
        }
    }

    // MARK: - Memory Management

    /// 窗口化清理：保留最近的帖子，清理旧数据
    private func trimPostsIfNeeded() {
        guard posts.count > trimThreshold else { return }

        let removeCount = posts.count - maxPostsInMemory
        let removedPosts = posts.prefix(removeCount)

        // 清理预加载记录
        removedPosts.forEach { post in
            if let url = post.imageURL {
                preloadedImageURLs.remove(url)
            }
        }

        posts.removeFirst(removeCount)

        print("🧹 Trimmed \(removeCount) posts from memory. Current count: \(posts.count)")
        PerformanceMonitor.shared.logEvent("Posts trimmed: \(removeCount)")
    }

    // MARK: - Intelligent Preloading

    /// 触发预加载（在可见帖子的 onAppear 中调用）
    func handlePostAppear(_ post: Post) {
        guard let postIndex = posts.firstIndex(where: { $0.id == post.id }) else { return }

        // 预加载前后范围内的图像
        let startIndex = max(0, postIndex - preloadDistance)
        let endIndex = min(posts.count - 1, postIndex + preloadDistance)

        let postsToPreload = Array(posts[startIndex...endIndex])
        preloadImages(for: postsToPreload)
    }

    private func preloadImages(for posts: [Post]) {
        let urlsToPreload = posts.compactMap { $0.imageURL }
            .filter { !preloadedImageURLs.contains($0) }

        guard !urlsToPreload.isEmpty else { return }

        // 标记为已预加载
        urlsToPreload.forEach { preloadedImageURLs.insert($0) }

        // 后台预加载
        ImageCacheManager.shared.preload(urls: urlsToPreload, size: .medium)

        print("📥 Preloading \(urlsToPreload.count) images")
    }
}
