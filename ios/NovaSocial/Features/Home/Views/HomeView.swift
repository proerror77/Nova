import SwiftUI
import Foundation
import PhotosUI

// MARK: - HomeView

struct HomeView: View {
    @Binding var currentPage: AppPage
    @EnvironmentObject private var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    @StateObject private var feedViewModel = FeedViewModel()
    @State private var showReportView = false
    @State private var showThankYouView = false
    @State private var showNewPost = false
    @State private var showSearch = false
    @State private var showNotification = false
    @State private var showPhotoOptions = false
    @State private var showComments = false
    @State private var selectedPostForComment: FeedPost?
    @State private var showSystemPhotoPicker = false  // 直接打开系统相册
    @State private var selectedPhotosFromPicker: [PhotosPickerItem] = []  // 系统相册选择的照片
    @State private var showCamera = false
    @State private var selectedMediaItems: [PostMediaItem] = []
    @State private var cameraImage: UIImage?  // 相机拍摄的单张图片
    @State private var showGenerateImage = false
    @State private var showWrite = false
    @State private var selectedPostForDetail: FeedPost?
    @State private var showPostDetail = false
    @State private var showToast = false
    @State private var showShareSheet = false
    @State private var selectedPostForShare: FeedPost?

    // MARK: - UserProfile 导航状态
    @State private var showUserProfile = false
    @State private var selectedUserId: String = ""

    // NOTE: Channels are now loaded dynamically via feedViewModel.channels
    // Old hardcoded channels removed - using backend API instead

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
                    initialMediaItems: selectedMediaItems,
                    initialImage: cameraImage,
                    onPostSuccess: { newPost in
                        // Post 成功后直接添加到 Feed 顶部（优化版本，不需要重新加载整个feed）
                        feedViewModel.addNewPost(newPost)
                    }
                )
                .transition(.identity)
                .onDisappear {
                    // 清除选择的媒体项
                    selectedMediaItems = []
                    cameraImage = nil
                }
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
                    onAvatarTapped: { authorId in
                        // 从帖子详情页点击头像跳转用户主页
                        showPostDetail = false
                        selectedPostForDetail = nil
                        selectedUserId = authorId
                        showUserProfile = true
                    }
                )
                .transition(.identity)
            } else if showUserProfile {
                // MARK: - UserProfile 页面
                UserProfileView(
                    showUserProfile: $showUserProfile,
                    userId: selectedUserId
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
                        // 直接打开系统相册选择器
                        showSystemPhotoPicker = true
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
        .animation(.none, value: showUserProfile)
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
                        // 从评论弹窗点击头像跳转用户主页
                        selectedUserId = userId
                        showUserProfile = true
                    }
                )
            }
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera, selectedImage: $cameraImage)
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
                showNewPost = true
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
                        showNewPost = true
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
                    Button(action: { showSearch = true }) {
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
                    Button(action: { showNotification = true }) {
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
                                        showReportView: $showReportView,
                                        onLike: { Task { await feedViewModel.toggleLike(postId: post.id) } },
                                        onComment: {
                                            selectedPostForComment = post
                                            showComments = true
                                        },
                                        onShare: { Task { await feedViewModel.sharePost(postId: post.id) } },
                                        onBookmark: { Task { await feedViewModel.toggleBookmark(postId: post.id) } },
                                        onAvatarTapped: { authorId in
                                            // 点击头像跳转到用户主页
                                            selectedUserId = authorId
                                            showUserProfile = true
                                        }
                                    )
                                    // 让卡片左右贴边显示
                                    .padding(.horizontal, -DesignTokens.spacing16)
                                    .ignoresSafeArea(.container, edges: .horizontal)
                                    .onTapGesture {
                                        selectedPostForDetail = post
                                        showPostDetail = true
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
                BottomTabBar(currentPage: $currentPage, showPhotoOptions: $showPhotoOptions, showNewPost: $showNewPost)
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
