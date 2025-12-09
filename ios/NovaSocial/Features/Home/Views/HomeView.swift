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
        ZStack {
            // 背景色 - 浅灰色 (与 Message 页面一致)
            DesignTokens.backgroundColor
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
                    Image("ICERED-icon")
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

                // MARK: - 顶部分割线
                Divider()
                    .frame(height: 0.5)
                    .background(DesignTokens.dividerColor)

                // MARK: - 可滚动内容区
                ScrollView {
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
                                        .font(.system(size: 14))
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
                                        onBookmark: { feedViewModel.toggleBookmark(postId: post.id) }
                                    )
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
                    }
                    .refreshable {
                        await feedViewModel.refresh()
                    }

                // MARK: - ScrollView 下方间距
                Color.clear
                    .frame(height: 0) // ← 调整 ScrollView 下方的间距
            }
            .safeAreaInset(edge: .bottom) {
                BottomTabBar(currentPage: $currentPage, showPhotoOptions: $showPhotoOptions)
                    .padding(.top, 80)
            }
        }
    }
}

#Preview {
    HomeView(currentPage: .constant(.home))
        .environmentObject(AuthenticationManager.shared)
}

