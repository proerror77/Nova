import Foundation
import Combine

@MainActor
final class FeedViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var showError = false

    // MARK: - Private Properties
    private let feedRepository: FeedRepository
    private var currentCursor: String?
    private var hasMore = true
    private var cancellables = Set<AnyCancellable>()

    // 乐观更新备份 - 用于回滚
    private var optimisticUpdateBackup: [UUID: Post] = [:]

    // 防止同一个post的like操作并发执行
    private var likeOperations: [UUID: Task<Void, Never>] = [:]

    // 列表缓冲：提前加载阈值（距离底部多少条开始加载）
    private let prefetchThreshold = 5

    // 防止重复加载的标志
    private var isCurrentlyLoading = false

    // 自动重试配置
    private let maxRetries = 3
    private var retryCount = 0

    // MARK: - Initialization
    init(feedRepository: FeedRepository = FeedRepository()) {
        self.feedRepository = feedRepository
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

            if hasMore, let lastPost = posts.last {
                currentCursor = lastPost.id.uuidString
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

        // 防止同一个post的like操作并发执行
        if likeOperations[post.id] != nil {
            return
        }

        let originalPost = posts[index]
        let wasLiked = originalPost.isLiked

        optimisticUpdateBackup[post.id] = originalPost

        // 乐观更新UI
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

        let task = Task {
            do {
                let postRepository = PostRepository()
                if wasLiked {
                    _ = try await postRepository.unlikePost(id: post.id)
                } else {
                    _ = try await postRepository.likePost(id: post.id)
                }

                optimisticUpdateBackup.removeValue(forKey: post.id)
            } catch {
                await rollbackOptimisticUpdate(for: post.id)
                showErrorMessage("Failed to \(wasLiked ? "unlike" : "like") post")
            }
        }

        likeOperations[post.id] = task

        Task {
            await task.value
            likeOperations.removeValue(forKey: post.id)
        }
    }

    func submitComment(to post: Post, text: String) async {
        guard let userId = AuthManager.shared.currentUser?.id else {
            showErrorMessage("User not authenticated")
            return
        }

        // 1. 乐观更新 UI
        let tempComment = addOptimisticComment(to: post, text: text)

        // 2. 调用 API 持久化
        Task {
            do {
                let postRepository = PostRepository()
                let comment = try await postRepository.createComment(postId: post.id, text: text)

                print("[FeedViewModel] ✅ Comment posted: \(comment.id)")
                // 成功后清除备份
                optimisticUpdateBackup.removeValue(forKey: post.id)

            } catch {
                // 3. 失败时回滚
                rollbackOptimisticComment(for: post)
                showErrorMessage("Failed to post comment: \(error.localizedDescription)")
            }
        }
    }

    func addOptimisticComment(to post: Post, text: String) -> Comment {
        // 创建临时评论（乐观更新）
        let currentUser = AuthManager.shared.currentUser
        let tempComment = Comment(
            id: UUID(),
            postId: post.id,
            userId: currentUser?.id ?? UUID(),
            text: text,
            createdAt: Date(),
            user: currentUser
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
