import SwiftUI
import Foundation

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
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var selectedImage: UIImage?
    @State private var showGenerateImage = false
    @State private var showWrite = false
    @State private var selectedPostForDetail: FeedPost?
    @State private var showPostDetail = false
    @State private var showChannelBar = true
    @State private var lastScrollOffset: CGFloat = 0
    @State private var selectedChannel: String = "Fashion"

    // Channel 列表
    private let channels = ["Fashion", "Travel", "Fitness", "Pets", "Study", "Career", "Tech", "Art"]

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
                    initialImage: selectedImage,
                    onPostSuccess: { newPost in
                        // Post 成功后直接添加到 Feed 顶部（优化版本，不需要重新加载整个feed）
                        feedViewModel.addNewPost(newPost)
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
                        showImagePicker = true
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
                CommentSheetView(post: post, isPresented: $showComments)
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(sourceType: .photoLibrary, selectedImage: $selectedImage)
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera, selectedImage: $selectedImage)
        }
        .onChange(of: selectedImage) { oldValue, newValue in
            // 选择/拍摄照片后，自动跳转到NewPostView
            if newValue != nil {
                showNewPost = true
            }
        }
        .onAppear {
            // Load feed when view appears
            if feedViewModel.posts.isEmpty {
                Task { await feedViewModel.loadFeed() }
            }
        }
    }

    var homeContent: some View {
        ZStack(alignment: .top) {
            // 背景色
            DesignTokens.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏（延伸到安全区域顶部）
                ZStack(alignment: .bottom) {
                    // 白色背景延伸到顶部（覆盖Dynamic Island区域）
                    Rectangle()
                        .fill(.white)
                        .ignoresSafeArea(edges: .top)

                    // 导航内容（在安全区域内）
                    HStack {
                        Button(action: { showSearch = true }) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 22, weight: .regular))
                                .frame(width: 24, height: 24)
                                .foregroundColor(DesignTokens.textPrimary)
                        }
                        Spacer()
                        Image("Icered-icon")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 20)
                            .foregroundColor(.black)
                        Spacer()
                        Button(action: { showNotification = true }) {
                            Image(systemName: "bell")
                                .font(.system(size: 22, weight: .regular))
                                .frame(width: 24, height: 24)
                                .foregroundColor(DesignTokens.textPrimary)
                        }
                    }
                    .frame(width: 343)
                    .padding(.bottom, 10)
                }
                .frame(height: 50)

                // MARK: - Channel 栏
                if showChannelBar {
                    channelBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // MARK: - 内容区域（固定背景 + 滚动内容）
                ZStack(alignment: .top) {
                    // 固定背景图片
                    Image("promo-banner-bg")
                        .resizable()
                        .scaledToFill()
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)
                        .clipped()

                    // 可滚动内容区
                    ScrollView {
                        VStack(spacing: 0) {
                            // 滚动位置检测
                            GeometryReader { geometry in
                                Color.clear
                                    .preference(key: ScrollOffsetPreferenceKey.self, value: geometry.frame(in: .named("scroll")).minY)
                            }
                            .frame(height: 0)
                            // MARK: - Promo Banner 内容 (Icon + 文字，随滚动移动)
                            VStack(spacing: 8) {
                                Image("home-icon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 50, height: 40)

                                Text("This is ICERED.")
                                    .font(.custom("SF Pro Display", size: 24))
                                    .tracking(0.24)
                                    .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                            }
                            .frame(height: 180)
                            .frame(maxWidth: .infinity)

                            // Feed 内容区域（白色背景，覆盖背景图）
                            VStack(spacing: DesignTokens.spacing20) {
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
                                        .font(Typography.regular14)
                                        .foregroundColor(.gray)
                                        .multilineTextAlignment(.center)

                                    if error.contains("Session expired") || error.contains("login") {
                                        // Session expired - show login button
                                        Button("Login") {
                                            Task {
                                                await authManager.logout()
                                            }
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
                                        onBookmark: { Task { await feedViewModel.toggleBookmark(postId: post.id) } }
                                    )
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
                            .background(DesignTokens.backgroundColor)
                        }
                    }
                    .refreshable {
                        await feedViewModel.refresh()
                    }
                    .coordinateSpace(name: "scroll")
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
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

                // MARK: - ScrollView 下方间距
                Color.clear
                    .frame(height: 0)
            }
            .safeAreaInset(edge: .bottom) {
                BottomTabBar(currentPage: $currentPage, showPhotoOptions: $showPhotoOptions, showNewPost: $showNewPost)
                    .padding(.top, 80)
            }
        }
    }

    // MARK: - Channel Bar
    private var channelBar: some View {
        ZStack {
            // 白色背景（无阴影）
            Rectangle()
                .fill(.white)

            HStack(spacing: 0) {
                // 可滚动的 Channel 列表
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 28) {
                        ForEach(channels, id: \.self) { channel in
                            Button(action: {
                                selectedChannel = channel
                                // TODO: 根据 channel 筛选 feed
                            }) {
                                Text(channel)
                                    .font(.custom("SF Pro Display", size: 14))
                                    .foregroundColor(selectedChannel == channel ? .black : Color(red: 0.53, green: 0.53, blue: 0.53))
                                    .fontWeight(selectedChannel == channel ? .semibold : .regular)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.trailing, 60) // 为右侧渐变留出空间
                }

                Spacer(minLength: 0)
            }

            // 右侧渐变遮罩 + 箭头
            HStack(spacing: 0) {
                Spacer()

                // 渐变遮罩
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.8),
                        Color.white
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 60)

                // 箭头按钮
                Button(action: {
                    // TODO: 展开更多 channels
                }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                }
                .frame(width: 30)
                .background(.white)
            }
        }
        .frame(height: 36)
        // 只在底部添加阴影
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.black.opacity(0),
                            Color.black.opacity(0.08)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 4)
                .offset(y: 4)
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

