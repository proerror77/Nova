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
                NewPostView(showNewPost: $showNewPost)
                    .transition(.identity)
            } else if showGenerateImage {
                GenerateImage01View(showGenerateImage: $showGenerateImage)
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
                    }
                )
            }
        }
        .animation(.none, value: showNotification)
        .animation(.none, value: showSearch)
        .animation(.none, value: showNewPost)
        .animation(.none, value: showGenerateImage)
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
        .onAppear {
            // Load feed when view appears
            if feedViewModel.posts.isEmpty {
                Task { await feedViewModel.loadFeed() }
            }
        }
    }

    var homeContent: some View {
        ZStack {
            // 背景色
            DesignTokens.backgroundColor
                .ignoresSafeArea()

            NavigationStack {
                VStack(spacing: 0) {
                    // MARK: - 顶部导航栏
                    HStack {
                        Button(action: { showSearch = true }) {
                            Image("Back-icon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                        }
                        Spacer()
                        Image("ICERED-icon")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 18)
                        Spacer()
                        Button(action: { showNotification = true }) {
                            Image("Notice-icon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                        }
                    }
                    .frame(height: DesignTokens.topBarHeight)
                    .padding(.horizontal, 16)
                    .background(Color.white)

                    Divider()

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

                            // MARK: - Feed Posts (Dynamic)
                            ForEach(Array(feedViewModel.posts.enumerated()), id: \.element.id) { index, post in
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

                            // MARK: - 标题部分
                            ZStack {
                                Button(action: {
                                    currentPage = .rankingList
                                }) {
                                    Text(LocalizedStringKey("View more"))
                                        .font(Font.custom("Helvetica Neue", size: 9))
                                        .underline()
                                        .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                                }
                                .offset(x: 150, y: 12)

                                Text(LocalizedStringKey("Hottest Banker in H.K."))
                                    .font(Font.custom("Helvetica Neue", size: 20).weight(.bold))
                                    .foregroundColor(.black)
                                    .offset(x: 0, y: -5.50)
                            }
                            .frame(width: 343, height: 35)

                            // MARK: - 轮播卡片容器 (水平滚动)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 20) {
                                    // 卡片 1
                                    CarouselCardItem(
                                        rankNumber: "1",
                                        name: "Lucy Liu",
                                        company: "Morgan Stanley",
                                        votes: "2293",
                                        imageAssetName: "PollCard-1"
                                    )

                                    // 卡片 2
                                    CarouselCardItem(
                                        rankNumber: "2",
                                        name: "Lucy Liu",
                                        company: "Morgan Stanley",
                                        votes: "2293",
                                        imageAssetName: "PollCard-2"
                                    )

                                    // 卡片 3
                                    CarouselCardItem(
                                        rankNumber: "3",
                                        name: "Lucy Liu",
                                        company: "Morgan Stanley",
                                        votes: "2293",
                                        imageAssetName: "PollCard-3"
                                    )

                                    // 卡片 4
                                    CarouselCardItem(
                                        rankNumber: "4",
                                        name: "Lucy Liu",
                                        company: "Morgan Stanley",
                                        votes: "2293",
                                        imageAssetName: "PollCard-4"
                                    )

                                    // 卡片 5
                                    CarouselCardItem(
                                        rankNumber: "5",
                                        name: "Lucy Liu",
                                        company: "Morgan Stanley",
                                        votes: "2293",
                                        imageAssetName: "PollCard-5"
                                    )
                                }
                                .padding(.horizontal)
                            }
                            .frame(height: 320)

                            // MARK: - 分页指示点
                            HStack(spacing: DesignTokens.spacing8) {
                                Circle()
                                    .fill(DesignTokens.indicatorActive)
                                    .frame(width: DesignTokens.spacing6, height: DesignTokens.spacing6)

                                ForEach(0..<4, id: \.self) { _ in
                                    Circle()
                                        .fill(DesignTokens.indicatorInactive)
                                        .frame(width: DesignTokens.spacing6, height: DesignTokens.spacing6)
                                }
                            }
                        }
                        .padding(.vertical, DesignTokens.spacing16)
                        .padding(.horizontal)
                    }
                    .refreshable {
                        await feedViewModel.refresh()
                    }
                    .padding(.bottom, DesignTokens.bottomBarHeight + DesignTokens.spacing12)
                }
                .safeAreaInset(edge: .bottom) {
                    BottomTabBar(currentPage: $currentPage, showPhotoOptions: $showPhotoOptions)
                        .padding(.top, 4)
                }
            }
        }
    }
}

#Preview {
    HomeView(currentPage: .constant(.home))
        .environmentObject(AuthenticationManager.shared)
}
