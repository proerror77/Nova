
import SwiftUI
import Foundation
import PhotosUI

// MARK: - Feed Tab Model

/// Represents the different feed tab types
enum FeedTab: Identifiable, Hashable {
    case forYou              // Recommended/trending posts (algo=v2)
    case following           // Posts from followed users (algo=ch)
    case interest(String)    // Interest-based channel

    var id: String {
        switch self {
        case .forYou: return "for_you"
        case .following: return "following"
        case .interest(let name): return "interest_\(name)"
        }
    }

    var displayName: String {
        switch self {
        case .forYou: return "For You"
        case .following: return "Following"
        case .interest(let name): return name
        }
    }

    /// The feed algorithm to use for this tab
    var algorithm: FeedAlgorithm {
        switch self {
        case .forYou: return .recommended
        case .following: return .chronological
        case .interest: return .recommended  // Interests use recommended with channel filter
        }
    }

    /// The channel ID to filter by (nil for For You and Following)
    var channelId: String? {
        switch self {
        case .forYou, .following: return nil
        case .interest(let name): return name.lowercased()
        }
    }
}

// MARK: - HomeView

struct HomeView: View {
    @Binding var currentPage: AppPage
    @EnvironmentObject private var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    // iOS 17+ @Observable 使用 @State 替代 @StateObject
    @State private var feedViewModel = FeedViewModel()
    @State private var showReportView = false

    // Deep link navigation support
    private let coordinator = AppCoordinator.shared
    private let contentService = ContentService()
    @State private var showThankYouView = false
    @State private var showNewPost = false
    @State private var showSearch = false
    @State private var showNotification = false
    @State private var showPhotoOptions = false
    @State private var showComments = false
    @State private var selectedPostForComment: FeedPost?
    @State private var showPhotoPicker = false  // Multi-photo picker
    @State private var selectedPhotos: [PhotosPickerItem] = []  // PhotosPicker selection
    @State private var showCamera = false
    @State private var selectedImage: UIImage?
    @State private var selectedMediaItems: [PostMediaItem] = []  // For multi-photo selection
    @State private var isProcessingPhotos = false  // Processing indicator
    @State private var showGenerateImage = false
    @State private var showWrite = false
    @State private var selectedPostForDetail: FeedPost?
    @State private var showPostDetail = false
    @State private var channelBarOffset: CGFloat = 0  // 0 = 显示, -30 = 隐藏
    @State private var lastDragValue: CGFloat = 0  // 追踪上一次拖动位置
    @State private var selectedTab: FeedTab = .forYou
    @State private var showUserProfile = false  // 用户主页跳转
    @State private var selectedUserId: String?  // 选中的用户ID

    // Interest channels (after For You and Following)
    private let interestChannels = ["Fashion", "Travel", "Fitness", "Pets", "Study", "Career", "Tech", "Art"]

    // All feed tabs: For You, Following, then interests
    private var allTabs: [FeedTab] {
        var tabs: [FeedTab] = [.forYou, .following]
        tabs.append(contentsOf: interestChannels.map { .interest($0) })
        return tabs
    }

    var body: some View {
        ZStack {
            // 条件渲染：根据状态即时切换视图
            if showNotification {
                NotificationView(showNotification: $showNotification)
                    .transition(.identity)
            } else if showSearch {
                SearchView(showSearch: $showSearch)
                    .transition(.identity)
            } else if showNewPost {
                NewPostView(
                    showNewPost: $showNewPost,
                    initialMediaItems: selectedMediaItems.isEmpty ? nil : selectedMediaItems,
                    initialImage: selectedImage,
                    onPostSuccess: { newPost in
                        // Post 成功后直接添加到 Feed 顶部（优化版本，不需要重新加载整个feed）
                        feedViewModel.addNewPost(newPost)
                        // Clear selected media after posting
                        selectedMediaItems = []
                        selectedImage = nil
                    }
                )
                .transition(.identity)
            } else if showGenerateImage {
                GenerateImage01View(showGenerateImage: $showGenerateImage)
                    .transition(.identity)
            } else if showWrite {
                WriteView(showWrite: $showWrite, currentPage: $currentPage)
                    .transition(.identity)
            } else if showPostDetail, let post = selectedPostForDetail {
                PostDetailView(post: post, onDismiss: {
                    showPostDetail = false
                    selectedPostForDetail = nil
                })
                .transition(.identity)
            } else {
                homeContent
            }

            // MARK: - 照片选项弹窗
            if showPhotoOptions {
                PhotoOptionsModal(
                    isPresented: $showPhotoOptions,
                    onChoosePhoto: {
                        showPhotoPicker = true  // Open multi-photo picker
                    },
                    onTakePhoto: {
                        showCamera = true
                    },
                    onGenerateImage: {
                        showGenerateImage = true
                    },
                    onWrite: {
                        showWrite = true
                    }
                )
            }
        }
        .animation(.none, value: showNotification)
        .animation(.none, value: showSearch)
        .animation(.none, value: showNewPost)
        .animation(.none, value: showGenerateImage)
        .animation(.none, value: showWrite)
        .animation(.none, value: showPostDetail)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showReportView) {
            ReportModal(isPresented: $showReportView, showThankYouView: $showThankYouView)
        }
        .sheet(isPresented: $showComments) {
            if let post = selectedPostForComment {
                CommentSheetView(
                    post: post,
                    isPresented: $showComments,
                    onAvatarTapped: { userId in
                        selectedUserId = userId
                        showUserProfile = true
                    },
                    onCommentCountUpdated: { postId, actualCount in
                        feedViewModel.updateCommentCount(postId: postId, count: actualCount)
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $showUserProfile) {
            if let userId = selectedUserId {
                UserProfileView(showUserProfile: $showUserProfile, userId: userId)
            }
        }
        // System PhotosPicker - user selects 1-5 photos, taps blue checkmark to confirm
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotos,
            maxSelectionCount: 5,
            matching: .any(of: [.images, .livePhotos, .videos])
        )
        .onChange(of: selectedPhotos) { oldValue, newValue in
            guard !newValue.isEmpty else { return }
            Task {
                await processSelectedPhotos(newValue)
            }
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera, selectedImage: $selectedImage)
        }
        .onChange(of: selectedImage) { oldValue, newValue in
            // 拍摄照片后，自动跳转到NewPostView
            if newValue != nil {
                showNewPost = true
            }
        }
        .onAppear {
            // Load feed when view appears with the correct algorithm for selected tab
            if feedViewModel.posts.isEmpty {
                Task { await feedViewModel.loadFeed(algorithm: selectedTab.algorithm) }
            }
            // Check for pending deep link navigation
            handlePendingNavigation()
        }
        .onChange(of: coordinator.homePath) { _, newPath in
            handlePendingNavigation()
        }
    }

    // MARK: - Deep Link Navigation

    /// Handle pending navigation from AppCoordinator
    private func handlePendingNavigation() {
        guard let route = coordinator.homePath.last else { return }

        switch route {
        case .post(let postId):
            // Navigate to post detail
            Task {
                await navigateToPost(id: postId)
            }
        case .profile(let userId):
            // Navigate to user profile
            selectedUserId = userId
            showUserProfile = true
            // Remove the route after handling
            coordinator.homePath.removeAll { $0 == route }
        default:
            break
        }
    }

    /// Load and display a post by ID
    private func navigateToPost(id postId: String) async {
        do {
            if let post = try await contentService.getPost(postId: postId) {
                await MainActor.run {
                    // Convert Post to FeedPost for PostDetailView
                    let feedPost = FeedPost(
                        from: post,
                        authorName: post.displayAuthorName,
                        authorAvatar: post.authorAvatarUrl
                    )
                    selectedPostForDetail = feedPost
                    showPostDetail = true
                    // Remove the route after handling
                    coordinator.homePath.removeAll {
                        if case .post = $0 { return true }
                        return false
                    }
                }
            } else {
                #if DEBUG
                print("[HomeView] Post not found: \(postId)")
                #endif
            }
        } catch {
            #if DEBUG
            print("[HomeView] Failed to load post \(postId): \(error)")
            #endif
        }
    }

    var homeContent: some View {
        ZStack(alignment: .bottom) {
            ZStack(alignment: .top) {
            // 背景色
            DesignTokens.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏（忽略安全区域，紧贴顶部）
                ZStack(alignment: .bottom) {
                    // 白色背景 - 延伸到安全区域顶部
                    Color.white
                        .ignoresSafeArea(edges: .top)
                    
                    // 导航图标 - 左: 搜索, 中: ICERED logo, 右: 通知
                    HStack {
                        Button(action: { showSearch = true }) {
                            Image("search(black)")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24.s, height: 24.s)
                                .contentShape(Rectangle())
                        }
                        
                        Spacer()
                        
                        // 中间 ICERED logo
                        Image("ICERED-icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 102.w, height: 16.s)
                        
                        Spacer()
                        
                        Button(action: { showNotification = true }) {
                            Image("bell")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24.s, height: 24.s)
                                .contentShape(Rectangle())
                        }
                    }
                    .frame(width: 343.w, height: 24.s)
                    .padding(.bottom, 12.h)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50.h)
                
                // MARK: - 顶部分隔线（始终可见）
                Rectangle()
                    .fill(Color(red: 0.75, green: 0.75, blue: 0.75))
                    .frame(width: 375.w, height: 0.5)
                    .frame(maxWidth: .infinity)

                // MARK: - Channel 栏容器（可滑动隐藏）
                channelBar
                    .offset(y: channelBarOffset)
                    .frame(height: max(0, 30.h + channelBarOffset))
                    .clipped()

                // MARK: - 内容区域（固定背景 + 滚动内容）
                ZStack(alignment: .top) {
                    // 固定背景图片 - 填满屏幕宽度，从顶部对齐
                    Image("promo-banner-bg")
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, alignment: .top)
                        .frame(height: 400.h, alignment: .top)
                        .offset(y: -100.h)  // 调整垂直位置：正数向下，负数向上
                        .clipped()
                        .allowsHitTesting(false)

                    // 可滚动内容区
                    ScrollView {
                        VStack(spacing: 0) {
                            // MARK: - Promo Banner 内容 (Icon + 文字，距离 Channel 栏 45pt)
                            VStack(spacing: 21.h) {
                                Image("home-icon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 54.s, height: 27.s)
                                
                                Text("This is Icered.")
                                    .font(.system(size: 24.f))
                                    .tracking(0.72)
                                    .lineSpacing(20)
                                    .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .padding(.top, 45.h)
                            .frame(maxWidth: .infinity)
                            
                            // 距离 Post 卡片 68pt 的间距
                            Spacer()
                                .frame(height: 68.h)

                            // Feed 内容区域（白色背景，覆盖背景图）
                            // 使用 LazyVStack 优化长列表性能 - 只渲染可见区域
                            LazyVStack(spacing: 0) {
                                // MARK: - Error State
                                if let error = feedViewModel.error, feedViewModel.posts.isEmpty {
                                    FeedErrorView(
                                        errorMessage: error,
                                        onRetry: {
                                            await feedViewModel.loadFeed()
                                        },
                                        onLogin: {
                                            Task {
                                                await authManager.logout()
                                            }
                                        }
                                    )
                                }

                                // MARK: - Suggested Creators Section (Following tab)
                                if feedViewModel.showSuggestedCreators && !feedViewModel.suggestedCreators.isEmpty {
                                    SuggestedCreatorsSection(
                                        creators: feedViewModel.suggestedCreators,
                                        onFollow: { userId in
                                            await feedViewModel.followSuggestedCreator(userId: userId)
                                        },
                                        onCreatorTap: { userId in
                                            selectedUserId = userId
                                            showUserProfile = true
                                        }
                                    )
                                }

                                // MARK: - Feed Posts + Carousel (Dynamic Layout)
                                // 配置在 FeedLayoutConfig.swift 中修改
                                // 当前设置：每 4 个帖子后显示一次轮播图
                                // 使用 feedViewModel.feedItems 缓存，避免每次渲染重新计算
                                if !feedViewModel.posts.isEmpty {
                                    ForEach(feedViewModel.feedItems) { item in
                                        switch item {
                                        case .post(let index, let post):
                                            FeedPostCard(
                                                post: post,
                                                showReportView: $showReportView,
                                                onLike: { Task { await feedViewModel.toggleLike(postId: post.id) } },
                                                onComment: {
                                                    selectedPostForComment = post
                                                    showComments = true
                                                },
                                                onShare: { Task { await feedViewModel.sharePost(postId: post.id) } },
                                                onBookmark: { Task { await feedViewModel.toggleBookmark(postId: post.id) } }
                                            )
                                            // 🚀 性能優化：使用穩定的 ID 避免不必要的視圖重建
                                            // 之前用 likeCount/isLiked 等組合 ID 會導致每次狀態變化時整個卡片重建
                                            // 現在用穩定的 post.id，SwiftUI 會智能更新變化的部分
                                            .id(post.id)
                                            .onTapGesture {
                                                selectedPostForDetail = post
                                                showPostDetail = true
                                            }
                                            .onAppear {
                                                // Auto-load more when reaching near the end (3 posts before)
                                                if index >= feedViewModel.posts.count - 3 && feedViewModel.hasMore && !feedViewModel.isLoadingMore {
                                                    Task { await feedViewModel.loadMore() }
                                                }
                                            }

                                        case .carousel:
                                            // HottestBankerSection 已隐藏，组件保留在 Components 文件夹中
                                            EmptyView()
                                        }
                                    }
                                }

                                // MARK: - Empty State (no posts in feed)
                                if feedViewModel.posts.isEmpty && !feedViewModel.isLoading && feedViewModel.error == nil {
                                    EmptyFeedView(
                                        onRefresh: {
                                            await feedViewModel.refresh()
                                        },
                                        onCreatePost: {
                                            showPhotoOptions = true
                                        }
                                    )
                                }

                                // MARK: - Loading More Indicator
                                if feedViewModel.isLoadingMore {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                            .tint(DesignTokens.accentColor)
                                        Spacer()
                                    }
                                    .padding()
                                }

                            }
                            .background(DesignTokens.backgroundColor)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .refreshable {
                        await feedViewModel.refresh()
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let currentY = value.translation.height
                                let delta = currentY - lastDragValue

                                // 向上滑动 (delta < 0) 隐藏 Channel 栏
                                // 向下滑动 (delta > 0) 显示 Channel 栏
                                // 使用极短动画让过渡更自然但不拖慢响应
                                if delta < -2 && channelBarOffset == 0 {
                                    withAnimation(.easeOut(duration: 0.1)) {
                                        channelBarOffset = -30.h  // 隐藏
                                    }
                                    lastDragValue = currentY
                                } else if delta > 2 && channelBarOffset < 0 {
                                    withAnimation(.easeOut(duration: 0.1)) {
                                        channelBarOffset = 0  // 显示
                                    }
                                    lastDragValue = currentY
                                }
                            }
                            .onEnded { _ in
                                lastDragValue = 0
                            }
                    )
                }
            }
            }

            // MARK: - 底部导航栏（覆盖在内容上方）
            BottomTabBar(currentPage: $currentPage, showPhotoOptions: $showPhotoOptions, showNewPost: $showNewPost)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Channel Bar
    private var channelBar: some View {
        // Channel 栏 - 响应式布局，保留 tab 切换功能
        ZStack {
            // 白色背景
            Rectangle()
                .foregroundColor(.clear)
                .frame(maxWidth: .infinity)
                .frame(height: 30.h)
                .background(.white)

            // 可滚动的 Tab 列表
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20.w) {
                    ForEach(allTabs) { tab in
                        Button(action: {
                            selectTab(tab)
                        }) {
                            Text(tab.displayName)
                                .font(.system(size: 10.f))
                                .foregroundColor(selectedTab == tab ? .black : Color(red: 0.53, green: 0.53, blue: 0.53))
                        }
                    }
                }
                .padding(.horizontal, 16.w)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 30.h)
        .background(.white)
    }

    // MARK: - Tab Selection Handler
    private func selectTab(_ tab: FeedTab) {
        guard selectedTab != tab else { return }
        selectedTab = tab

        // Switch feed algorithm based on tab type:
        // - For You: recommended algorithm (v2)
        // - Following: chronological algorithm (ch) - shows posts from followed users
        // - Interests: recommended algorithm with channel filter
        Task {
            // First set the channel filter (will be used by loadFeed)
            feedViewModel.selectedChannelId = tab.channelId

            // Load suggested creators when switching to Following tab
            if tab == .following {
                feedViewModel.showSuggestedCreators = true
                await feedViewModel.loadSuggestedCreators()
            } else {
                feedViewModel.showSuggestedCreators = false
            }

            // Then load feed with the appropriate algorithm
            await feedViewModel.loadFeed(algorithm: tab.algorithm, forceRefresh: true)
        }
    }

    // MARK: - Process Selected Photos

    private func processSelectedPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }

        await MainActor.run {
            isProcessingPhotos = true
        }

        do {
            let mediaItems = try await LivePhotoManager.shared.loadMedia(from: items, maxCount: 5)

            await MainActor.run {
                isProcessingPhotos = false
                selectedMediaItems = mediaItems
                selectedPhotos = []  // Clear selection for next time
                showNewPost = true
            }
        } catch {
            #if DEBUG
            print("[HomeView] Failed to process photos: \(error)")
            #endif

            await MainActor.run {
                isProcessingPhotos = false
                selectedPhotos = []
            }
        }
    }
}

// MARK: - Suggested Creators Section

/// A horizontal scrollable section showing recommended creators to follow
/// Used in the Following tab when user doesn't follow many people
struct SuggestedCreatorsSection: View {
    let creators: [RecommendedCreator]
    let onFollow: (String) async -> Void
    let onCreatorTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Suggested for you")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)

                Spacer()
            }
            .padding(.horizontal, 16)

            // Horizontal scroll of creator cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(creators) { creator in
                        SuggestedCreatorCard(
                            creator: creator,
                            onFollow: { await onFollow(creator.id) },
                            onTap: { onCreatorTap(creator.id) }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 16)
        .background(Color.white)
    }
}

// MARK: - Suggested Creator Card

/// A compact card for displaying a suggested creator
struct SuggestedCreatorCard: View {
    let creator: RecommendedCreator
    let onFollow: () async -> Void
    let onTap: () -> Void

    @State private var isFollowing = false
    @State private var isFollowed = false

    var body: some View {
        VStack(spacing: 8) {
            // Avatar
            Button(action: onTap) {
                AvatarView(image: nil, url: creator.avatarUrl, size: 60)
            }

            // Name
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    Text(creator.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black)
                        .lineLimit(1)

                    if creator.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.blue)
                    }
                }

                Text("@\(creator.username)")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }

            // Follower count
            Text("\(formatFollowerCount(creator.followerCount)) followers")
                .font(.system(size: 10))
                .foregroundColor(.gray)

            // Follow button
            Button(action: {
                guard !isFollowing && !isFollowed else { return }
                isFollowing = true
                Task {
                    await onFollow()
                    await MainActor.run {
                        isFollowed = true
                        isFollowing = false
                    }
                }
            }) {
                if isFollowing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 70, height: 28)
                } else if isFollowed {
                    Text("Following")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                        .frame(width: 70, height: 28)
                        .background(Color(red: 0.95, green: 0.95, blue: 0.95))
                        .cornerRadius(14)
                } else {
                    Text("Follow")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 70, height: 28)
                        .background(DesignTokens.accentColor)
                        .cornerRadius(14)
                }
            }
            .disabled(isFollowing || isFollowed)
        }
        .frame(width: 100)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(Color(red: 0.98, green: 0.98, blue: 0.98))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(red: 0.92, green: 0.92, blue: 0.92), lineWidth: 1)
        )
    }

    private func formatFollowerCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

#Preview {
    HomeView(currentPage: .constant(.home))
        .environmentObject(AuthenticationManager.shared)
}

