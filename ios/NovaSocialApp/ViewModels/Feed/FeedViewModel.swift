import Foundation
import Combine

/// FeedViewModel - Feed 视图模型（统一版本）
///
/// 这是FeedViewModel和FeedViewModelEnhanced的合并版本。
/// 增强功能（状态恢复、滚动位置保存等）可通过 enableStateRestoration 参数可选启用。
///
/// 迁移指南（从 FeedViewModelEnhanced → FeedViewModel）：
/// 旧代码：
///   let vm = FeedViewModelEnhanced()
///
/// 新代码：
///   let vm = FeedViewModel(enableStateRestoration: true)
///
/// Linus原则应用：
/// - 消除了不必要的 *Enhanced 特殊后缀
/// - 零破坏性：所有功能都可选启用
/// - 单一真实来源：只维护一个ViewModel类

@MainActor
final class FeedViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var showError = false

    // 新增：状态恢复（可选）
    @Published var scrollPosition: String?

    // MARK: - Private Properties
    private let feedRepository: FeedRepository
    private var currentCursor: String?
    private var hasMore = true
    private var cancellables = Set<AnyCancellable>()

    // 乐观更新备份 - 用于回滚
    private var optimisticUpdateBackup: [UUID: Post] = [:]

    // 列表缓冲：提前加载阈值（距离底部多少条开始加载）
    private let prefetchThreshold = 5

    // 防止重复加载的标志
    private var isCurrentlyLoading = false

    // 自动重试配置
    private let maxRetries = 3
    private var retryCount = 0

    // 新增：状态持久化管理（可选启用）
    private let stateManager = ViewStateManager.shared
    private let enableStateRestoration: Bool

    // MARK: - Initialization
    init(feedRepository: FeedRepository = FeedRepository(), enableStateRestoration: Bool = false) {
        self.feedRepository = feedRepository
        self.enableStateRestoration = enableStateRestoration

        // 恢复滚动位置（如果启用）
        if enableStateRestoration {
            Task {
                await self.restoreScrollPositionAsync()
            }
        }
    }

    // MARK: - Async State Restoration

    private func restoreScrollPositionAsync() async {
        scrollPosition = await stateManager.getScrollPosition(for: .feed)
    }

    // MARK: - Public Methods

    func loadInitialFeed() async {
        guard !isLoading, !isCurrentlyLoading else { return }

        isLoading = true
        isCurrentlyLoading = true
        errorMessage = nil
        retryCount = 0

        do {
            let newPosts = try await feedRepository.loadFeed(cursor: nil, limit: 20)
            posts = newPosts
            hasMore = !newPosts.isEmpty
            retryCount = 0 // 成功后重置重试计数
        } catch {
            // 自动重试逻辑
            if retryCount < maxRetries {
                retryCount += 1
                try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retryCount)) * 1_000_000_000))
                isLoading = false
                isCurrentlyLoading = false
                await loadInitialFeed()
                return
            }
            showErrorMessage(error.localizedDescription)
        }

        isLoading = false
        isCurrentlyLoading = false
    }

    func refreshFeed() async {
        guard !isRefreshing, !isCurrentlyLoading else { return }

        isRefreshing = true
        isCurrentlyLoading = true
        errorMessage = nil
        currentCursor = nil
        retryCount = 0

        do {
            let newPosts = try await feedRepository.refreshFeed(limit: 20)

            // 平滑过渡动画
            withAnimation(.easeInOut(duration: 0.3)) {
                posts = newPosts
            }

            hasMore = !newPosts.isEmpty
            retryCount = 0
        } catch {
            // 刷新失败时自动重试
            if retryCount < maxRetries {
                retryCount += 1
                try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retryCount)) * 1_000_000_000))
                isRefreshing = false
                isCurrentlyLoading = false
                await refreshFeed()
                return
            }
            showErrorMessage(error.localizedDescription)
        }

        isRefreshing = false
        isCurrentlyLoading = false
    }

    /// 智能预加载：当滚动到距离底部 prefetchThreshold 条时开始加载
    func loadMoreIfNeeded(currentPost: Post) async {
        guard hasMore,
              !isLoadingMore,
              !isCurrentlyLoading,
              let index = posts.firstIndex(where: { $0.id == currentPost.id }),
              posts.count - index <= prefetchThreshold else {
            return
        }

        await loadMore()
    }

    func loadMore() async {
        guard !isLoadingMore, !isCurrentlyLoading, hasMore else { return }

        isLoadingMore = true
        isCurrentlyLoading = true

        do {
            let newPosts = try await feedRepository.loadFeed(
                cursor: currentCursor,
                limit: 20
            )

            // 去重：防止重复加载
            let uniqueNewPosts = newPosts.filter { newPost in
                !posts.contains(where: { $0.id == newPost.id })
            }

            posts.append(contentsOf: uniqueNewPosts)
            hasMore = !newPosts.isEmpty

            if hasMore {
                // Backend expects base64-encoded numeric offset as cursor
                let offset = posts.count
                let cursorData = String(offset).data(using: .utf8) ?? Data()
                currentCursor = cursorData.base64EncodedString()
            }
        } catch {
            showErrorMessage(error.localizedDescription)
        }

        isLoadingMore = false
        isCurrentlyLoading = false
    }

    func toggleLike(for post: Post) {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else {
            return
        }

        let originalPost = posts[index]
        let wasLiked = originalPost.isLiked

        // 1. 备份原始状态（用于回滚）
        optimisticUpdateBackup[post.id] = originalPost

        // 2. 乐观更新 UI（立即反馈）
        let updatedPost = Post(
            id: originalPost.id,
            userId: originalPost.userId,
            imageUrl: originalPost.imageUrl,
            thumbnailUrl: originalPost.thumbnailUrl,
            caption: originalPost.caption,
            likeCount: wasLiked ? originalPost.likeCount - 1 : originalPost.likeCount + 1,
            commentCount: originalPost.commentCount,
            isLiked: !wasLiked,
            createdAt: originalPost.createdAt,
            user: originalPost.user
        )

        withAnimation(.easeInOut(duration: 0.2)) {
            posts[index] = updatedPost
        }

        // 3. 调用 API 持久化（后台执行）
        Task {
            do {
                // TODO: 替换为真实的 PostRepository 调用
                // let postRepository = PostRepository()
                // try await postRepository.toggleLike(postId: post.id)

                // 模拟网络延迟
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5s

                // 成功后清除备份
                optimisticUpdateBackup.removeValue(forKey: post.id)

            } catch {
                // 4. 失败时回滚到原始状态
                await rollbackOptimisticUpdate(for: post.id)
                showErrorMessage("Failed to \(wasLiked ? "unlike" : "like") post")
            }
        }
    }

    func addOptimisticComment(to post: Post, text: String) -> Comment {
        // 创建临时评论（乐观更新）
        let tempComment = Comment(
            id: UUID(),
            postId: post.id,
            userId: UUID(), // TODO: 从用户会话获取
            text: text,
            createdAt: Date(),
            user: nil // TODO: 从用户会话获取
        )

        // 更新 post 的评论数
        if let index = posts.firstIndex(where: { $0.id == post.id }) {
            optimisticUpdateBackup[post.id] = posts[index]

            let updatedPost = Post(
                id: posts[index].id,
                userId: posts[index].userId,
                imageUrl: posts[index].imageUrl,
                thumbnailUrl: posts[index].thumbnailUrl,
                caption: posts[index].caption,
                likeCount: posts[index].likeCount,
                commentCount: posts[index].commentCount + 1,
                isLiked: posts[index].isLiked,
                createdAt: posts[index].createdAt,
                user: posts[index].user
            )

            withAnimation(.easeInOut(duration: 0.2)) {
                posts[index] = updatedPost
            }
        }

        return tempComment
    }

    func rollbackOptimisticComment(for post: Post) {
        if let originalPost = optimisticUpdateBackup[post.id],
           let index = posts.firstIndex(where: { $0.id == post.id }) {
            withAnimation(.easeInOut(duration: 0.2)) {
                posts[index] = originalPost
            }
            optimisticUpdateBackup.removeValue(forKey: post.id)
        }
    }

    func clearError() {
        errorMessage = nil
        showError = false
    }

    // MARK: - State Persistence (新增)

    /// 保存滚动位置
    func saveScrollPosition(_ postId: String) {
        scrollPosition = postId
        if enableStateRestoration {
            Task {
                await stateManager.saveScrollPosition(postId, for: .feed)
            }
        }
    }

    /// 恢复滚动位置
    func restoreScrollPosition() {
        Task {
            scrollPosition = await stateManager.getScrollPosition(for: .feed)
        }
    }

    /// 清除滚动位置
    func clearScrollPosition() {
        scrollPosition = nil
        Task {
            await stateManager.clearScrollPosition(for: .feed)
        }
    }

    // MARK: - Private Helpers

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }

    private func rollbackOptimisticUpdate(for postId: UUID) {
        guard let originalPost = optimisticUpdateBackup[postId],
              let index = posts.firstIndex(where: { $0.id == postId }) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            posts[index] = originalPost
        }

        optimisticUpdateBackup.removeValue(forKey: postId)
    }
}

// MARK: - View State Manager (状态管理器)

/// 视图状态管理器 - 管理应用级别的状态持久化
actor ViewStateManager {
    static let shared = ViewStateManager()

    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Scroll Position

    enum ViewType: String {
        case feed
        case explore
        case profile
        case notifications
    }

    func saveScrollPosition(_ postId: String, for viewType: ViewType) {
        let key = "scroll_position_\(viewType.rawValue)"
        defaults.set(postId, forKey: key)
    }

    func getScrollPosition(for viewType: ViewType) -> String? {
        let key = "scroll_position_\(viewType.rawValue)"
        return defaults.string(forKey: key)
    }

    func clearScrollPosition(for viewType: ViewType) {
        let key = "scroll_position_\(viewType.rawValue)"
        defaults.removeObject(forKey: key)
    }

    // MARK: - Tab Selection

    func saveSelectedTab(_ index: Int) {
        defaults.set(index, forKey: "selected_tab")
    }

    func getSelectedTab() -> Int {
        defaults.integer(forKey: "selected_tab")
    }

    // MARK: - Filter Preferences

    func saveFilterPreferences(_ preferences: [String: Any], for viewType: ViewType) {
        let key = "filter_preferences_\(viewType.rawValue)"
        defaults.set(preferences, forKey: key)
    }

    func getFilterPreferences(for viewType: ViewType) -> [String: Any]? {
        let key = "filter_preferences_\(viewType.rawValue)"
        return defaults.dictionary(forKey: key)
    }
}
