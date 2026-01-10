
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
    private let userService = UserService.shared  // For cache invalidation on profile navigation
    @State private var showThankYouView = false
    @State private var showNewPost = false
    @State private var showSearch = false
    @State private var showNotification = false
    @State private var showPhotoOptions = false
    // showComments removed - using selectedPostForComment as source of truth (#231 fix)
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
                PostDetailView(
                    post: post,
                    onDismiss: {
                        showPostDetail = false
                        selectedPostForDetail = nil
                    },
                    onAvatarTapped: { userId in
                        // Close post detail first, then navigate to user profile
                        showPostDetail = false
                        selectedPostForDetail = nil
                        navigateToUserProfile(userId: userId)
                    },
                    onPostDeleted: {
                        // Issue #243: Remove deleted post from feed immediately
                        feedViewModel.removePost(postId: post.id)
                    },
                    onLikeChanged: { isLiked, likeCount in
                        feedViewModel.updateLikeState(postId: post.id, isLiked: isLiked, likeCount: likeCount)
                    },
                    onBookmarkChanged: { isBookmarked, bookmarkCount in
                        feedViewModel.updateBookmarkState(postId: post.id, isBookmarked: isBookmarked, bookmarkCount: bookmarkCount)
                    },
                    onCommentCountUpdated: { postId, actualCount in
                        feedViewModel.updateCommentCount(postId: postId, count: actualCount)
                    }
                )
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

            if let toast = feedViewModel.toastError {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(Font.custom("SFProDisplay-Medium", size: 14.f))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(20)
                        .padding(.bottom, 100)
                }
                .transition(.opacity)
                .animation(.easeInOut, value: feedViewModel.toastError)
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
        // Fix #231: Use .sheet(item:) to guarantee post data availability
        // This eliminates race condition where sheet opens before post is set
        .sheet(item: $selectedPostForComment) { post in
            CommentSheetView(
                post: post,
                isPresented: Binding(
                    get: { selectedPostForComment != nil },
                    set: { if !$0 { selectedPostForComment = nil } }
                ),
                onAvatarTapped: { userId in
                    navigateToUserProfile(userId: userId)
                },
                onCommentCountUpdated: { postId, actualCount in
                    feedViewModel.updateCommentCount(postId: postId, count: actualCount)
                }
            )
            .presentationDetents([.fraction(2.0/3.0), .large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showUserProfile) {
            if let userId = selectedUserId {
                UserProfileView(showUserProfile: $showUserProfile, userId: userId)
            } else {
                // Fallback: auto-dismiss if userId is nil to prevent blank screen
                Color.clear
                    .onAppear {
                        showUserProfile = false
                    }
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
        .onChange(of: feedViewModel.toastError) { _, newValue in
            guard let newValue else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if feedViewModel.toastError == newValue {
                    feedViewModel.toastError = nil
                }
            }
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
            // Navigate to user profile (with cache invalidation for fresh data)
            navigateToUserProfile(userId: userId)
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

    /// Navigate to user profile with fresh data (invalidates cache to fix avatar inconsistency)
    /// Issue #166: Comment section shows fresh avatar from API, but profile page may show cached stale avatar
    private func navigateToUserProfile(userId: String) {
        // Invalidate cached profile data to ensure fresh fetch
        // This fixes the inconsistency where comment avatars (fresh) differ from profile avatars (cached)
        userService.invalidateCache(userId: userId)
        selectedUserId = userId
        showUserProfile = true
    }

    var homeContent: some View {
        ZStack(alignment: .bottom) {
            // 整体内容区域
            VStack(spacing: 0) {
                // MARK: - 导航栏内容区域
                ZStack {
                    VStack(spacing: 0) {
                        // 安全区域留白
                        Spacer()
                            .frame(height: 56.h)
                        
                        // 内容区域：上下 padding 15，左右 padding 16，图标 24x24
                        HStack {
                            Button(action: { showSearch = true }) {
                                Image("search(black)")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 22.s, height: 22.s)
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
                                    .frame(width: 22.s, height: 22.s)
                                    .contentShape(Rectangle())
                            }
                        }
                        .padding(EdgeInsets(top: 15.h, leading: 16.w, bottom: 15.h, trailing: 16.w))
                    }
                    
                    // 底部分隔线
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(Color(red: 0.75, green: 0.75, blue: 0.75))
                            .frame(height: 0.5)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 110.h)
                .background(.white)
                
                // MARK: - Channel 栏（紧贴导航栏底部）
                channelBar
                    .offset(y: channelBarOffset)
                    .frame(height: max(0, 37.h + channelBarOffset))
                    .clipped()

                // MARK: - 内容区域（白色背景）
                ScrollView {
                    VStack(spacing: 0) {
                        // Feed 内容区域
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
                                            navigateToUserProfile(userId: userId)
                                        }
                                    )
                                }

                                // MARK: - Feed Posts + Carousel (Dynamic Layout)
                                // 配置在 FeedLayoutConfig.swift 中修改
                                // 当前设置：每 4 个帖子后显示一次轮播图
                                // 使用 feedViewModel.feedItems 缓存，避免每次渲染重新计算
                                if feedViewModel.isLoading && feedViewModel.posts.isEmpty {
                                    // Skeleton loading state for initial load
                                    ForEach(0..<3, id: \.self) { _ in
                                        FeedPostCardSkeleton()
                                    }
                                } else if !feedViewModel.posts.isEmpty {
                                    ForEach(feedViewModel.feedItems) { item in
                                        switch item {
                                        case .post(let index, let post):
                                            FeedPostCard(
                                                post: post,
                                                showReportView: $showReportView,
                                                onLike: { feedViewModel.toggleLike(postId: post.id) },
                                                onComment: {
                                                    // Setting selectedPostForComment triggers .sheet(item:) automatically
                                                    selectedPostForComment = post
                                                },
                                                onShare: { Task { await feedViewModel.sharePost(postId: post.id) } },
                                                onBookmark: { feedViewModel.toggleBookmark(postId: post.id) }
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
                                                #if DEBUG
                                                print("[HomeView] Post appeared at index \(index)/\(feedViewModel.posts.count), hasMore: \(feedViewModel.hasMore), isLoadingMore: \(feedViewModel.isLoadingMore)")
                                                #endif
                                                // Auto-load more when reaching near the end (3 posts before)
                                                if index >= feedViewModel.posts.count - 3 && feedViewModel.hasMore && !feedViewModel.isLoadingMore {
                                                    #if DEBUG
                                                    print("[HomeView] Triggering loadMore at index \(index)")
                                                    #endif
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
                                } else if !feedViewModel.hasMore && !feedViewModel.posts.isEmpty {
                                    // MARK: - No More Content Indicator
                                    HStack {
                                        Spacer()
                                        Text("— No more posts —")
                                            .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                                            .foregroundColor(DesignTokens.textMuted)
                                        Spacer()
                                    }
                                    .padding(.vertical, 16)
                                }

                                // MARK: - Bottom Padding for TabBar (fixes #252)
                                Color.clear
                                    .frame(height: 80.h)  // TabBar height (72) + extra padding
                            }
                            .background(DesignTokens.backgroundColor)
                        }
                    }
                    .background(Color.white)
                    .scrollIndicators(.hidden)
                    .refreshable {
                        await feedViewModel.refresh()
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { value in
                                let currentY = value.translation.height
                                let delta = currentY - lastDragValue

                                // 始终更新 lastDragValue 以保持准确的 delta 计算
                                lastDragValue = currentY

                                // 向上滑动 (delta < 0) 隐藏 Channel 栏
                                // 向下滑动 (delta > 0) 显示 Channel 栏
                                // 使用较大阈值 (15pt) 避免与 ScrollView 滚动冲突
                                if delta < -15 && channelBarOffset == 0 {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        channelBarOffset = -37.h  // 隐藏
                                    }
                                } else if delta > 15 && channelBarOffset < 0 {
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        channelBarOffset = 0  // 显示
                                    }
                                }
                            }
                            .onEnded { _ in
                                lastDragValue = 0
                            }
                    )
                }
            .background(Color.white)

            // MARK: - 底部导航栏（覆盖在内容上方）
            BottomTabBar(currentPage: $currentPage, showPhotoOptions: $showPhotoOptions, showNewPost: $showNewPost)
        }
        .background(Color.white)
        .ignoresSafeArea(edges: [.top, .bottom])
    }

    // MARK: - Channel Bar
    private var channelBar: some View {
        // Channel 栏 - 可滚动标签
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 28.w) {
                ForEach(allTabs) { tab in
                    Button(action: {
                        selectTab(tab)
                    }) {
                        Text(tab.displayName)
                            .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                            .tracking(0.28)
                            .foregroundColor(selectedTab == tab ? .black : Color(red: 0.53, green: 0.53, blue: 0.53))
                    }
                }
            }
            .padding(EdgeInsets(top: 10.h, leading: 15.w, bottom: 10.h, trailing: 15.w))
        }
        .frame(maxWidth: .infinity)
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

#Preview {
    HomeView(currentPage: .constant(.home))
        .environmentObject(AuthenticationManager.shared)
}
