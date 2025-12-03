import SwiftUI

// MARK: - Feed 优化使用示例集合

/// 示例 1: 基础 Feed 视图（包含所有优化功能）
struct OptimizedFeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @State private var selectedPost: Post?
    @State private var scrollPosition: UUID?
    @State private var scrollProxy: ScrollViewProxy?
    @State private var showScrollToTopButton = false

    var body: some View {
        NavigationStack {
            ZStack {
                // 骨架屏加载状态
                if viewModel.isLoading && viewModel.posts.isEmpty {
                    ScrollView {
                        SkeletonPostList(count: 3)
                    }
                }
                // 空状态
                else if viewModel.posts.isEmpty {
                    EmptyStateView(
                        icon: "photo.on.rectangle.angled",
                        title: "No Posts Yet",
                        message: "Start following people to see their posts"
                    )
                }
                // 帖子列表
                else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                Color.clear.frame(height: 0).id("top")

                                ForEach(viewModel.posts) { post in
                                    PostCell(
                                        post: post,
                                        onLike: {
                                            viewModel.toggleLike(for: post)
                                        },
                                        onTap: {
                                            scrollPosition = post.id
                                            selectedPost = post
                                        }
                                    )
                                    .id(post.id)
                                    .onAppear {
                                        Task {
                                            await viewModel.loadMoreIfNeeded(currentPost: post)
                                        }
                                    }

                                    Divider()
                                }

                                if viewModel.isLoadingMore {
                                    LoadingMoreIndicator()
                                }
                            }
                        }
                        .refreshable {
                            await viewModel.refreshFeed()
                        }
                        .onAppear {
                            scrollProxy = proxy
                            restoreScrollPosition(proxy)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if showScrollToTopButton {
                            ScrollToTopButton {
                                withAnimation {
                                    scrollProxy?.scrollTo("top", anchor: .top)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Feed")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if viewModel.posts.isEmpty {
                    await viewModel.loadInitialFeed()
                }
            }
        }
    }

    private func restoreScrollPosition(_ proxy: ScrollViewProxy) {
        if let position = scrollPosition {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation {
                    proxy.scrollTo(position, anchor: .top)
                }
            }
        }
    }
}

// MARK: - 示例 2: 自定义骨架屏

/// 示例：紧凑型评论骨架屏
struct CommentSkeletonView: View {
    var body: some View {
        HStack(spacing: 12) {
            // 头像骨架
            SkeletonShape()
                .frame(width: 36, height: 36)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                // 用户名骨架
                SkeletonShape()
                    .frame(width: 80, height: 12)

                // 评论内容骨架
                SkeletonShape()
                    .frame(height: 14)
                    .frame(maxWidth: .infinity)

                SkeletonShape()
                    .frame(height: 14)
                    .frame(maxWidth: 200)
            }
        }
        .padding()
    }
}

/// 示例：网格型帖子骨架屏（Explore 页面）
struct ExploreGridSkeleton: View {
    var columns: Int = 3
    var rows: Int = 4

    private var gridItems: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 2), count: columns)
    }

    var body: some View {
        LazyVGrid(columns: gridItems, spacing: 2) {
            ForEach(0..<(columns * rows), id: \.self) { _ in
                SkeletonShape()
                    .aspectRatio(1, contentMode: .fill)
            }
        }
    }
}

// MARK: - 示例 3: 图片懒加载变体

/// 示例：头像懒加载（圆形）
struct AvatarImageView: View {
    let url: String?
    var size: CGFloat = 40

    var body: some View {
        LazyImageView(
            url: url,
            contentMode: .fill,
            placeholder: Image(systemName: "person.circle.fill")
        )
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

/// 示例：帖子图片（渐进式加载）
struct ProgressivePostImageView: View {
    let thumbnailUrl: String?
    let fullImageUrl: String?

    @State private var loadFullImage = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 缩略图（快速加载）
                if let thumbnailUrl = thumbnailUrl {
                    LazyImageView(url: thumbnailUrl, contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.width)
                        .blur(radius: loadFullImage ? 0 : 10)
                }

                // 高清图（延迟加载）
                if loadFullImage, let fullImageUrl = fullImageUrl {
                    LazyImageView(url: fullImageUrl, contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.width)
                        .transition(.opacity)
                }
            }
            .clipped()
            .onAppear {
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                    withAnimation {
                        loadFullImage = true
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fill)
    }
}

// MARK: - 示例 4: 乐观更新变体

/// 示例：评论乐观更新
struct CommentInputView: View {
    @Binding var text: String
    var onSubmit: (String) -> Void

    @State private var isSubmitting = false
    @State private var optimisticComment: Comment?

    var body: some View {
        HStack {
            TextField("Add a comment...", text: $text)
                .textFieldStyle(.roundedBorder)

            Button {
                handleSubmit()
            } label: {
                if isSubmitting {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "paperplane.fill")
                }
            }
            .disabled(text.isEmpty || isSubmitting)
        }
    }

    private func handleSubmit() {
        let commentText = text

        // 1. 乐观更新 UI
        optimisticComment = Comment(
            id: UUID(),
            postId: UUID(),
            userId: UUID(),
            text: commentText,
            createdAt: Date(),
            user: nil
        )

        // 2. 清空输入框
        text = ""
        isSubmitting = true

        // 3. 调用 API
        Task {
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                onSubmit(commentText)
                isSubmitting = false
            } catch {
                // 回滚
                text = commentText
                optimisticComment = nil
                isSubmitting = false
            }
        }

        // 4. 触觉反馈
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
}

// MARK: - 示例 5: 加载状态组件

/// 加载更多指示器
struct LoadingMoreIndicator: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)

            Text("Loading more...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .transition(.opacity)
    }
}

/// 空状态视图
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding()
    }
}

/// 错误重试视图
struct ErrorRetryView: View {
    let message: String
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)

            Text("Oops!")
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                onRetry()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Try Again")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        }
        .padding()
    }
}

// MARK: - 示例 6: 快速返回顶部按钮

struct ScrollToTopButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: {
            action()

            // 触觉反馈
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        }) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)

                Image(systemName: "arrow.up")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
        }
        .padding(.trailing, 20)
        .padding(.bottom, 20)
        .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - 示例 7: 图片缓存管理工具

/// 缓存统计视图（调试用）
struct CacheStatsView: View {
    @State private var hitRate: Double = 0
    @State private var hitCount: Int = 0
    @State private var missCount: Int = 0

    var body: some View {
        VStack(spacing: 12) {
            Text("Image Cache Stats")
                .font(.headline)

            HStack {
                StatItem(title: "Hit Rate", value: String(format: "%.1f%%", hitRate * 100))
                StatItem(title: "Hits", value: "\(hitCount)")
                StatItem(title: "Misses", value: "\(missCount)")
            }

            Button("Clear Cache") {
                ImageCacheManager.shared.clearCache()
                updateStats()
            }
            .buttonStyle(.borderedProminent)

            Button("Refresh Stats") {
                updateStats()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
        .onAppear {
            updateStats()
        }
    }

    private func updateStats() {
        hitRate = ImageCacheManager.shared.hitRate
        hitCount = ImageCacheManager.shared.hitCount
        missCount = ImageCacheManager.shared.missCount
    }
}

struct StatItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 示例 8: 下拉刷新自定义样式

/// 自定义下拉刷新指示器（需要配合 UIKit）
struct CustomRefreshControl: View {
    @Binding var isRefreshing: Bool
    var onRefresh: () async -> Void

    var body: some View {
        ScrollView {
            // 内容
        }
        .refreshable {
            await onRefresh()
        }
    }
}

// MARK: - 示例 9: 智能预加载策略

/// 示例：自定义预加载策略
class SmartPrefetchStrategy {
    private let threshold: Int
    private let batchSize: Int

    init(threshold: Int = 5, batchSize: Int = 20) {
        self.threshold = threshold
        self.batchSize = batchSize
    }

    func shouldLoadMore(currentIndex: Int, totalCount: Int) -> Bool {
        // 当前位置距离底部小于等于阈值
        return totalCount - currentIndex <= threshold
    }

    func calculateNextBatchSize(currentCount: Int) -> Int {
        // 根据当前数量动态调整批次大小
        if currentCount < 20 {
            return 20
        } else if currentCount < 100 {
            return 30
        } else {
            return 50
        }
    }
}

// MARK: - 示例 10: 滚动位置管理器

/// 滚动位置管理器（支持多视图）
class ScrollPositionManager: ObservableObject {
    @Published private var positions: [String: UUID] = [:]

    func savePosition(_ id: UUID, for key: String) {
        positions[key] = id
    }

    func getPosition(for key: String) -> UUID? {
        return positions[key]
    }

    func clearPosition(for key: String) {
        positions.removeValue(forKey: key)
    }

    func clearAll() {
        positions.removeAll()
    }
}

// 使用示例
struct FeedViewWithPositionManager: View {
    @StateObject private var positionManager = ScrollPositionManager()
    @State private var scrollProxy: ScrollViewProxy?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // 内容
            }
            .onAppear {
                scrollProxy = proxy

                // 恢复位置
                if let position = positionManager.getPosition(for: "feed") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            proxy.scrollTo(position, anchor: .top)
                        }
                    }
                }
            }
        }
    }

    private func navigateToDetail(post: Post) {
        // 保存位置
        positionManager.savePosition(post.id, for: "feed")
        // 导航到详情
    }
}

// MARK: - Preview

#Preview("Optimized Feed") {
    OptimizedFeedView()
}

#Preview("Comment Skeleton") {
    VStack(spacing: 0) {
        CommentSkeletonView()
        Divider()
        CommentSkeletonView()
        Divider()
        CommentSkeletonView()
    }
}

#Preview("Explore Grid Skeleton") {
    ExploreGridSkeleton(columns: 3, rows: 4)
}

#Preview("Cache Stats") {
    CacheStatsView()
}

#Preview("Empty State") {
    EmptyStateView(
        icon: "photo.on.rectangle.angled",
        title: "No Posts Yet",
        message: "Start following people to see their posts"
    )
}

#Preview("Error Retry") {
    ErrorRetryView(
        message: "Failed to load posts. Please check your internet connection.",
        onRetry: {}
    )
}
