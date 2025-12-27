
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
    @State private var showChannelBar = true
    @State private var lastScrollOffset: CGFloat = 0
    @State private var selectedTab: FeedTab = .forYou
    @State private var scrollDebounceTask: Task<Void, Never>?  // 滾動防抖任務
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
                
                // MARK: - 顶部分隔线（距离顶部 98pt）
                Rectangle()
                    .fill(Color(red: 0.75, green: 0.75, blue: 0.75))
                    .frame(width: 375.w, height: 0.5)
                    .frame(maxWidth: .infinity)

                // MARK: - Channel 栏
                if showChannelBar {
                    channelBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

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
                            // 滚动位置检测
                            GeometryReader { geometry in
                                Color.clear
                                    .preference(key: ScrollOffsetPreferenceKey.self, value: geometry.frame(in: .named("scroll")).minY)
                            }
                            .frame(height: 0)
                            // MARK: - Promo Banner 内容 (Icon + 文字，距离 Channel 栏 45pt)
                            VStack(spacing: 21.h) {
                                Image("home-icon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 54.s, height: 27.s)
                                
                                Text("This is Icered.")
                                    .font(.custom("SF Pro Display", size: 24.f))
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
                    .refreshable {
                        await feedViewModel.refresh()
                    }
                    .coordinateSpace(name: "scroll")
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                        // 性能優化：添加防抖避免每幀都觸發動畫計算
                        scrollDebounceTask?.cancel()
                        scrollDebounceTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(16)) // ~1 frame
                            guard !Task.isCancelled else { return }

                            let delta = offset - lastScrollOffset
                            // 向上滚动 (offset 变小，delta < 0) 隐藏 Channel 栏
                            // 向下滚动/下拉 (offset 变大，delta > 0) 显示 Channel 栏
                            if abs(delta) > 10 {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    if delta < -10 {
                                        showChannelBar = false
                                    } else if delta > 10 || offset > -50 {
                                        showChannelBar = true
                                    }
                                }
                                lastScrollOffset = offset
                            }
                        }
                    }
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
                // 只在底部添加阴影
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.black.opacity(0),
                            Color.black.opacity(0.10)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 4)
                    .offset(y: 4)
                }
            
            // 可滚动的 Tab 列表
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20.w) {
                    ForEach(allTabs) { tab in
                        Button(action: {
                            selectTab(tab)
                        }) {
                            Text(tab.displayName)
                                .font(.custom("SF Pro Display", size: 10.f))
                                .foregroundColor(selectedTab == tab ? .black : Color(red: 0.53, green: 0.53, blue: 0.53))
                        }
                    }
                }
                .padding(.horizontal, 16.w)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 30.h)
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

// MARK: - Scroll Offset Preference Key
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    HomeView(currentPage: .constant(.home))
        .environmentObject(AuthenticationManager.shared)
}

