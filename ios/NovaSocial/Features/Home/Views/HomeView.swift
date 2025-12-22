import SwiftUI
import Foundation
import PhotosUI

// MARK: - HomeView Navigation State Machine

/// 全螢幕導航狀態 (互斥)
enum HomeFullScreenDestination: Equatable {
    case home
    case notification
    case search
    case newPost
    case generateImage
    case write
    case postDetail(FeedPost)
    case userProfile(String)

    static func == (lhs: HomeFullScreenDestination, rhs: HomeFullScreenDestination) -> Bool {
        switch (lhs, rhs) {
        case (.home, .home), (.notification, .notification), (.search, .search),
             (.newPost, .newPost), (.generateImage, .generateImage), (.write, .write):
            return true
        case (.postDetail(let lPost), .postDetail(let rPost)):
            return lPost.id == rPost.id
        case (.userProfile(let lId), .userProfile(let rId)):
            return lId == rId
        default:
            return false
        }
    }
}

/// Sheet 彈窗狀態
enum HomeSheetType: Identifiable {
    case report
    case comments(FeedPost)
    case camera

    var id: String {
        switch self {
        case .report: return "report"
        case .comments(let post): return "comments_\(post.id)"
        case .camera: return "camera"
        }
    }
}

// MARK: - HomeView

struct HomeView: View {
    @Binding var currentPage: AppPage
    @EnvironmentObject private var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    @StateObject private var feedViewModel = FeedViewModel()

    // MARK: - Consolidated Navigation State (原本 24 個變數 → 6 個)
    @State private var fullScreenDestination: HomeFullScreenDestination = .home
    @State private var activeSheet: HomeSheetType?
    @State private var showPhotoOptions = false
    @State private var showSystemPhotoPicker = false
    @State private var selectedPhotosFromPicker: [PhotosPickerItem] = []
    @State private var showThankYouView = false

    // MARK: - Media Data State (保持獨立，因為是實際數據)
    @State private var selectedMediaItems: [PostMediaItem] = []
    @State private var cameraImage: UIImage?

    // NOTE: Channels are now loaded dynamically via feedViewModel.channels
    // Old hardcoded channels removed - using backend API instead

    // MARK: - Binding Helpers (橋接新舊 API)
    private var showNotificationBinding: Binding<Bool> {
        Binding(
            get: { fullScreenDestination == .notification },
            set: { if !$0 { fullScreenDestination = .home } }
        )
    }

    private var showSearchBinding: Binding<Bool> {
        Binding(
            get: { fullScreenDestination == .search },
            set: { if !$0 { fullScreenDestination = .home } }
        )
    }

    private var showNewPostBinding: Binding<Bool> {
        Binding(
            get: { fullScreenDestination == .newPost },
            set: { newValue in
                if newValue {
                    fullScreenDestination = .newPost
                } else {
                    fullScreenDestination = .home
                    selectedMediaItems = []
                    cameraImage = nil
                }
            }
        )
    }

    private var showGenerateImageBinding: Binding<Bool> {
        Binding(
            get: { fullScreenDestination == .generateImage },
            set: { if !$0 { fullScreenDestination = .home } }
        )
    }

    private var showWriteBinding: Binding<Bool> {
        Binding(
            get: { fullScreenDestination == .write },
            set: { if !$0 { fullScreenDestination = .home } }
        )
    }

    private var showUserProfileBinding: Binding<Bool> {
        Binding(
            get: { if case .userProfile = fullScreenDestination { return true } else { return false } },
            set: { if !$0 { fullScreenDestination = .home } }
        )
    }

    private var currentUserId: String {
        if case .userProfile(let id) = fullScreenDestination { return id }
        return ""
    }

    private var showReportBinding: Binding<Bool> {
        Binding(
            get: { if case .report = activeSheet { return true } else { return false } },
            set: { if !$0 { activeSheet = nil } }
        )
    }

    var body: some View {
        ZStack {
            // 条件渲染：根据状态即时切换视图 (使用狀態機)
            switch fullScreenDestination {
            case .notification:
                NotificationView(showNotification: showNotificationBinding)
                    .transition(.identity)

            case .search:
                SearchView(showSearch: showSearchBinding)
                    .transition(.identity)

            case .newPost:
                NewPostView(
                    showNewPost: showNewPostBinding,
                    initialMediaItems: selectedMediaItems,
                    initialImage: cameraImage,
                    onPostSuccess: { newPost in
                        feedViewModel.addNewPost(newPost)
                    }
                )
                .transition(.identity)

            case .generateImage:
                GenerateImage01View(showGenerateImage: showGenerateImageBinding)
                    .transition(.identity)

            case .write:
                WriteView(showWrite: showWriteBinding, currentPage: $currentPage)
                    .transition(.identity)

            case .postDetail(let post):
                PostDetailView(
                    post: post,
                    onDismiss: {
                        fullScreenDestination = .home
                    },
                    onAvatarTapped: { authorId in
                        fullScreenDestination = .userProfile(authorId)
                    }
                )
                .transition(.identity)

            case .userProfile(let userId):
                UserProfileView(
                    showUserProfile: showUserProfileBinding,
                    userId: userId
                )
                .transition(.identity)

            case .home:
                homeContent
            }

            // MARK: - 照片选项弹窗
            if showPhotoOptions {
                PhotoOptionsModal(
                    isPresented: $showPhotoOptions,
                    onChoosePhoto: {
                        showSystemPhotoPicker = true
                    },
                    onTakePhoto: {
                        activeSheet = .camera
                    },
                    onGenerateImage: {
                        fullScreenDestination = .generateImage
                    },
                    onWrite: {
                        fullScreenDestination = .write
                    }
                )
            }
        }
        .animation(.none, value: fullScreenDestination)
        .navigationBarBackButtonHidden(true)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .report:
                ReportModal(isPresented: showReportBinding, showThankYouView: $showThankYouView)
            case .comments(let post):
                CommentSheetView(
                    post: post,
                    isPresented: Binding(
                        get: { activeSheet != nil },
                        set: { if !$0 { activeSheet = nil } }
                    ),
                    onAvatarTapped: { userId in
                        activeSheet = nil
                        // 方案B: 判断是否点击自己的头像
                        if userId == authManager.currentUser?.id {
                            // 点击自己的头像 → 进入我的主页 (Profile tab)
                            currentPage = .account
                        } else {
                            // 点击他人头像 → 进入他人主页 (UserProfileView)
                            fullScreenDestination = .userProfile(userId)
                        }
                    }
                )
            case .camera:
                ImagePicker(sourceType: .camera, selectedImage: $cameraImage)
            }
        }
        .photosPicker(
            isPresented: $showSystemPhotoPicker,
            selection: $selectedPhotosFromPicker,
            maxSelectionCount: 5,
            matching: .any(of: [.images, .livePhotos])
        )
        .onChange(of: cameraImage) { oldValue, newValue in
            // 相机拍摄后，跳转到NewPostView
            if newValue != nil {
                fullScreenDestination = .newPost
            }
        }
        .onChange(of: selectedPhotosFromPicker) { oldValue, newValue in
            // 从系统相册选择后，加载图片并跳转到 NewPostView
            guard !newValue.isEmpty else { return }
            Task {
                do {
                    let mediaItems = try await LivePhotoManager.shared.loadMedia(from: newValue, maxCount: 5)
                    await MainActor.run {
                        selectedMediaItems = mediaItems
                        selectedPhotosFromPicker = []  // 清空以便下次选择
                        fullScreenDestination = .newPost
                    }
                } catch {
                    #if DEBUG
                    print("[HomeView] Failed to load photos: \(error)")
                    #endif
                    selectedPhotosFromPicker = []
                }
            }
        }
        .task {
            // Load feed when view appears
            if feedViewModel.posts.isEmpty {
                await feedViewModel.loadFeed()
            }
        }
    }

    var homeContent: some View {
        ZStack {
            // 背景色 - 白色
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack {
                    Button(action: { fullScreenDestination = .search }) {
                        Image(systemName: "magnifyingglass")
                            .frame(width: 24, height: 24)
                            .foregroundColor(DesignTokens.textPrimary)
                    }
                    Spacer()
                    Image("Icered-icon")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 18)
                    Spacer()
                    Button(action: { fullScreenDestination = .notification }) {
                        Image(systemName: "bell")
                            .frame(width: 24, height: 24)
                            .foregroundColor(DesignTokens.textPrimary)
                    }
                }
                .frame(height: DesignTokens.topBarHeight)
                .padding(.horizontal, 16)
                .background(DesignTokens.surface)

                // MARK: - Channel 栏
                channelBar

                // MARK: - 可滚动内容区
                ScrollView {
                        LazyVStack(spacing: DesignTokens.spacing20) {
                            // MARK: - Promo Banner (活动/广告区域)
                            PromoBannerView(onTap: {
                                // TODO: 处理广告点击事件
                            })
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, -16) // 突破外层 padding，贴紧屏幕边缘

                            // MARK: - Loading State
                            if feedViewModel.isLoading && feedViewModel.posts.isEmpty {
                                ProgressView("Loading feed...")
                                    .padding()
                            }

                            // MARK: - Error State
                            if let error = feedViewModel.error {
                                VStack(spacing: 12) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.system(size: 40))
                                        .foregroundColor(.orange)
                                    Text(error)
                                        .font(.system(size: 14))
                                        .foregroundColor(.gray)
                                        .multilineTextAlignment(.center)

                                    if error.contains("Session expired") || error.contains("login") {
                                        // Session expired - show login button
                                        Button {
                                            Task {
                                                await authManager.logout()
                                            }
                                        } label: {
                                            Text("Login")
                                        }
                                        .font(.system(size: DesignTokens.fontMedium, weight: .medium))
                                        .foregroundColor(DesignTokens.textOnAccent)
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, DesignTokens.spacing10)
                                        .background(DesignTokens.accentColor)
                                        .cornerRadius(DesignTokens.buttonCornerRadius)
                                    } else {
                                        Button("Retry") {
                                            Task { await feedViewModel.loadFeed() }
                                        }
                                        .foregroundColor(DesignTokens.accentColor)
                                    }
                                }
                                .padding()
                            }

                            // MARK: - Feed Posts + Carousel (Dynamic Layout)
                            // 配置在 FeedLayoutConfig.swift 中修改
                            // 当前设置：每 4 个帖子后显示一次轮播图
                            ForEach(FeedLayoutBuilder.buildFeedItems(from: feedViewModel.posts)) { item in
                                switch item {
                                case .post(let index, let post):
                                    FeedPostCard(
                                        post: post,
                                        showReportView: showReportBinding,
                                        onLike: { Task { await feedViewModel.toggleLike(postId: post.id) } },
                                        onComment: {
                                            activeSheet = .comments(post)
                                        },
                                        onShare: { Task { await feedViewModel.sharePost(postId: post.id) } },
                                        onBookmark: { Task { await feedViewModel.toggleBookmark(postId: post.id) } },
                                        onAvatarTapped: { authorId in
                                            fullScreenDestination = .userProfile(authorId)
                                        }
                                    )
                                    // 让卡片左右贴边显示
                                    .padding(.horizontal, -DesignTokens.spacing16)
                                    .ignoresSafeArea(.container, edges: .horizontal)
                                    .onTapGesture {
                                        fullScreenDestination = .postDetail(post)
                                    }
                                    .onAppear {
                                        // Prefetch images for upcoming posts
                                        feedViewModel.onPostAppear(at: index)

                                        // Auto-load more when reaching near the end (3 posts before)
                                        if index >= feedViewModel.posts.count - 3 && feedViewModel.hasMore && !feedViewModel.isLoadingMore {
                                            Task { await feedViewModel.loadMore() }
                                        }
                                    }

                                case .carousel:
                                    HottestBankerSection(onSeeAllTapped: {
                                        currentPage = .rankingList
                                    })
                                }
                            }

                            // MARK: - Empty State (no posts in feed)
                            if feedViewModel.posts.isEmpty && !feedViewModel.isLoading && feedViewModel.error == nil {
                                VStack(spacing: DesignTokens.spacing16) {
                                    Image(systemName: "square.stack.3d.up.slash")
                                        .font(.system(size: 50))
                                        .foregroundColor(DesignTokens.accentColor.opacity(0.6))

                                    Text(LocalizedStringKey("No posts yet"))
                                        .font(.system(size: DesignTokens.fontTitle, weight: .semibold))
                                        .foregroundColor(DesignTokens.textPrimary)

                                    Text(LocalizedStringKey("Be the first to share something!"))
                                        .font(.system(size: DesignTokens.fontMedium))
                                        .foregroundColor(DesignTokens.textSecondary)
                                        .multilineTextAlignment(.center)

                                    Button(action: { showPhotoOptions = true }) {
                                        Text(LocalizedStringKey("Create Post"))
                                            .font(.system(size: DesignTokens.fontMedium, weight: .medium))
                                            .foregroundColor(DesignTokens.textOnAccent)
                                            .padding(.horizontal, 24)
                                            .padding(.vertical, DesignTokens.spacing10)
                                            .background(DesignTokens.accentColor)
                                            .cornerRadius(DesignTokens.buttonCornerRadius)
                                    }
                                    .padding(.top, DesignTokens.spacing8)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
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
                        .padding(.vertical, DesignTokens.spacing16)
                        .padding(.horizontal)
                    }
                    .refreshable {
                        await feedViewModel.refresh()
                    }

                // MARK: - ScrollView 下方间距
                Color.clear
                    .frame(height: 0) // ← 调整 ScrollView 下方的间距
            }
            .safeAreaInset(edge: .bottom) {
                BottomTabBar(currentPage: $currentPage, showPhotoOptions: $showPhotoOptions, showNewPost: showNewPostBinding)
                    .padding(.top, 80)
            }
        }
    }

    // MARK: - Channel Bar (Dynamic from Backend)
    private var channelBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                // "For You" option - shows all content (no channel filter)
                Button(action: {
                    Task { await feedViewModel.selectChannel(nil) }
                }) {
                    Text("For You")
                        .font(.system(size: 14))
                        .lineSpacing(20)
                        .foregroundColor(feedViewModel.selectedChannelId == nil ? .black : Color(red: 0.53, green: 0.53, blue: 0.53))
                        .fontWeight(feedViewModel.selectedChannelId == nil ? .medium : .regular)
                }

                // Dynamic channels from backend
                ForEach(feedViewModel.channels) { channel in
                    Button(action: {
                        Task { await feedViewModel.selectChannel(channel.id) }
                    }) {
                        Text(channel.name)
                            .font(.system(size: 14))
                            .lineSpacing(20)
                            .foregroundColor(feedViewModel.selectedChannelId == channel.id ? .black : Color(red: 0.53, green: 0.53, blue: 0.53))
                            .fontWeight(feedViewModel.selectedChannelId == channel.id ? .medium : .regular)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 36)
        .background(.white)
        .task {
            // Load channels when view appears
            if feedViewModel.channels.isEmpty {
                await feedViewModel.loadChannels()
            }
        }
    }
}

// MARK: - Previews

#Preview("Home - Default") {
    HomeView(currentPage: .constant(.home))
        .environmentObject(AuthenticationManager.shared)
}

#Preview("Home - Dark Mode") {
    HomeView(currentPage: .constant(.home))
        .environmentObject(AuthenticationManager.shared)
        .preferredColorScheme(.dark)
}
