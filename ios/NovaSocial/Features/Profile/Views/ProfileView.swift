import SwiftUI

struct ProfileView: View {
    @Binding var currentPage: AppPage
    // 全局认证状态从上层注入
    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var profileData = ProfileData()
    @State private var showNewPost = false
    @State private var showSetting = false
    @State private var showPhotoOptions = false
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var selectedImage: UIImage?
    @State private var showGenerateImage = false
    @State private var showWrite = false
    @State private var showShareSheet = false
    @State private var localAvatarImage: UIImage? = nil  // 本地选择的头像
    @State private var showAccountSwitcher = false  // 账户切换弹窗
    @State private var showMyQRCode = false  // 我的二维码弹窗

    // Access AvatarManager
    @StateObject private var avatarManager = AvatarManager.shared

    // Access UserPostsManager for real-time post sync
    private var userPostsManager: UserPostsManager { UserPostsManager.shared }


    // Computed property for user display
    private var displayUser: UserProfile? {
        authManager.currentUser ?? profileData.userProfile
    }

    // 分享内容
    private var shareItems: [Any] {
        guard let userId = displayUser?.id else { return [] }
        let username = displayUser?.username ?? "user"
        let shareUrl = URL(string: "https://nova.social/user/\(userId)") ?? URL(string: "https://nova.social")!
        let shareText = "Check out \(username)'s profile on ICERED!"
        return [shareText, shareUrl]
    }

    var body: some View {
        ZStack {
            // 条件渲染：根据状态切换视图
            if showNewPost {
                NewPostView(
                    showNewPost: $showNewPost,
                    initialImage: selectedImage,
                    onPostSuccess: { post in
                        // 实时同步新帖子到 UserPostsManager
                        userPostsManager.addNewPost(post)
                    }
                )
                    .transition(.identity)
            } else if showGenerateImage {
                GenerateImage01View(showGenerateImage: $showGenerateImage)
                    .transition(.identity)
            } else if showWrite {
                WriteView(showWrite: $showWrite)
                    .transition(.identity)
            } else if showSetting {
                SettingsView(currentPage: $currentPage)
                    .transition(.identity)
            } else {
                profileContent
            }
        }
        .animation(.none, value: showNewPost)
        .animation(.none, value: showGenerateImage)
        .animation(.none, value: showWrite)
        .animation(.none, value: showSetting)
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
    }

    // MARK: - Profile 主内容
    private var profileContent: some View {
        ZStack {
            DesignTokens.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: -240) {
                // MARK: - 区域1：用户信息头部（独立高度控制）
                userHeaderSection
                    .frame(height: 600)  // 可独立调整此高度

                // MARK: - 区域2：内容区域（独立高度控制）
                contentSection
            }
            .safeAreaInset(edge: .bottom) {
                // MARK: - 底部导航栏
                bottomNavigationBar
                    .padding(.top, -80) // ← 调整底部导航栏向上移动
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

            // MARK: - 账户切换弹窗
            if showAccountSwitcher {
                AccountSwitcherSheet(
                    isPresented: $showAccountSwitcher,
                    onAccountSelected: { accountType in
                        // 处理账户切换
                        withAnimation(.easeOut(duration: 0.25)) {
                            showAccountSwitcher = false
                        }
                    },
                    onAddAliasAccount: {
                        // 添加匿名账户
                        withAnimation(.easeOut(duration: 0.25)) {
                            showAccountSwitcher = false
                        }
                    },
                    onGoToAccountCenter: {
                        // 前往账户中心
                        withAnimation(.easeOut(duration: 0.25)) {
                            showAccountSwitcher = false
                        }
                    }
                )
            }
        }
        .task {
            // Use current user from AuthenticationManager
            if let userId = authManager.currentUser?.id {
                await profileData.loadUserProfile(userId: userId)
                // 同时加载用户帖子到 UserPostsManager
                await userPostsManager.loadUserPosts(userId: userId)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityShareSheet(activityItems: shareItems)
        }
        .sheet(isPresented: $showMyQRCode) {
            MyQRCodeView()
        }
    }

    // ==================== 布局配置（可在此调整） ====================
    // 顶部导航栏布局
    private var navBarLayout: ProfileNavBarLayout {
        ProfileNavBarLayout(
            horizontalPadding: 20,      // 左右边距
            topPadding: 60,             // 顶部边距
            bottomPadding: 40,          // 底部边距
            usernameFontSize: 20,       // 用户名字体大小
            chevronSize: 12,            // 下拉箭头大小
            usernameChevronSpacing: 6,  // 用户名和箭头间距
            iconSize: 24,               // 图标大小
            iconSpacing: 18             // 图标间距
        )
    }

    // 用户信息区域布局
    private var userInfoLayout: ProfileUserInfoLayout {
        ProfileUserInfoLayout(
            containerWidth: 365,        // 容器宽度
            verticalSpacing: 7,         // 垂直间距
            bottomPadding: 10,          // 底部边距
            avatarOuterSize: 108,       // 头像外圈大小
            avatarInnerSize: 100,       // 头像内圈大小
            avatarBorderWidth: 1,       // 边框宽度
            usernameFontSize: 20,       // 用户名字体大小
            usernameSpacingFromAvatar: 9,  // 与头像间距
            locationFontSize: 12,       // 位置字体大小
            professionFontSize: 12,     // 职业字体大小
            blueVIconSize: 20,          // 蓝标大小
            professionIconSpacing: 10,  // 蓝标与文字间距
            statsTopPadding: 16,        // 统计区顶部间距
            statsLabelFontSize: 16,     // 统计标签字体
            statsValueFontSize: 16,     // 统计数值字体
            statsItemWidth: 132,        // 统计项宽度
            statsItemSpacing: -16,      // 统计项间距
            statsDividerHeight: 24      // 分隔线高度
        )
    }

    // MARK: - 用户信息头部区域
    private var userHeaderSection: some View {
        ZStack(alignment: .top) {
            // 背景图片
            Image("Profile-background")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .clipped()
                .blur(radius: 20)
                .overlay(
                    Color.black.opacity(0.3)
                )
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏（独立组件）
                ProfileTopNavigationBar(
                    username: displayUser?.displayName ?? displayUser?.username ?? "User",
                    layout: navBarLayout,
                    onShareTapped: { showShareSheet = true },
                    onQRCodeTapped: { showMyQRCode = true },
                    onSettingsTapped: { currentPage = .setting },
                    onUsernameTapped: {
                        withAnimation(.easeOut(duration: 0.25)) {
                            showAccountSwitcher = true
                        }
                    }
                )

                // MARK: - 用户信息区域（独立组件）
                // 注意：当用户未填写信息时，组件会自动处理默认显示状态
                ProfileUserInfoSection(
                    avatarImage: avatarManager.pendingAvatar ?? localAvatarImage,
                    avatarUrl: profileData.userProfile?.avatarUrl,
                    username: displayUser?.displayName ?? displayUser?.username,  // 未填写时组件显示 "User"
                    location: displayUser?.location,                               // 未填写时不显示
                    profession: displayUser?.bio,                                  // 未填写时不显示
                    isVerified: displayUser?.safeIsVerified ?? false,
                    followingCount: displayUser?.safeFollowingCount ?? 0,
                    followersCount: displayUser?.safeFollowerCount ?? 0,
                    likesCount: displayUser?.safePostCount ?? 0,
                    layout: userInfoLayout
                )
            }
        }
    }

    // MARK: - 内容区域
    private var contentSection: some View {
        VStack(spacing: 0) {
            // MARK: - 标签栏
            VStack(spacing: 0) {
                    HStack {
                        Spacer()

                        HStack(spacing: 40) {
                            Button(action: {
                                profileData.selectedTab = .posts
                                Task {
                                    await profileData.loadContent(for: .posts)
                                }
                            }) {
                                Text(LocalizedStringKey("Posts_tab"))
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(profileData.selectedTab == .posts ? DesignTokens.accentColor : DesignTokens.textPrimary)
                            }

                            Button(action: {
                                profileData.selectedTab = .saved
                                Task {
                                    await profileData.loadContent(for: .saved)
                                }
                            }) {
                                Text(LocalizedStringKey("Saved_tab"))
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(profileData.selectedTab == .saved ? DesignTokens.accentColor : DesignTokens.textPrimary)
                            }

                            Button(action: {
                                profileData.selectedTab = .liked
                                Task {
                                    await profileData.loadContent(for: .liked)
                                }
                            }) {
                                Text(LocalizedStringKey("Liked_tab"))
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(profileData.selectedTab == .liked ? DesignTokens.accentColor : DesignTokens.textPrimary)
                            }
                        }
                        .frame(maxWidth: .infinity)  // 居中三个标签

                        Spacer()

                        Button(action: {
                            Task {
                                await profileData.searchInProfile(query: "")
                            }
                        }) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 20))
                                .foregroundColor(DesignTokens.textPrimary)
                        }
                        .padding(.trailing, 20)
                    }
                    .padding(.vertical, 16)
                    .background(.white)

                    // 分隔线
                    Rectangle()
                        .fill(DesignTokens.borderColor)
                        .frame(height: 0.5)
                }

                // MARK: - 帖子网格
                ScrollView {
                    if profileData.selectedTab == .posts {
                        // Posts 标签 - 使用 UserPostsManager 实时同步
                        if userPostsManager.isLoading {
                            ProgressView()
                                .padding(.top, 40)
                        } else if userPostsManager.hasPosts {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                                ForEach(userPostsManager.userPosts) { post in
                                    ProfilePostCard(
                                        post: post,
                                        username: displayUser?.displayName ?? displayUser?.username ?? "User",
                                        avatarUrl: displayUser?.avatarUrl
                                    )
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.top, 8)
                        } else {
                            emptyStateView
                        }
                    } else {
                        // Saved/Liked 标签 - 使用 profileData
                        if profileData.isLoading {
                            ProgressView()
                                .padding(.top, 40)
                        } else if profileData.hasContent {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                                ForEach(profileData.currentTabPosts) { post in
                                    ProfilePostCard(
                                        post: post,
                                        username: displayUser?.displayName ?? displayUser?.username ?? "User",
                                        avatarUrl: displayUser?.avatarUrl
                                    )
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.top, 8)
                        } else {
                            emptyStateView
                        }
                    }

                    Color.clear
                        .frame(height: 100)
                }
                .background(DesignTokens.backgroundColor)
        }
    }

    // MARK: - 空状态视图
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            Text("No posts yet")
                .font(.system(size: 16))
                .foregroundColor(.gray)
        }
        .padding(.top, 60)
    }

    // MARK: - 底部导航栏
    private var bottomNavigationBar: some View {
        BottomTabBar(currentPage: $currentPage, showPhotoOptions: $showPhotoOptions)
    }

}

// MARK: - 帖子卡片组件
struct PostGridCard: View {
    let post: Post

    private var formattedDate: String {
        let date = Date(timeIntervalSince1970: TimeInterval(post.createdAt))
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h"
        } else if interval < 604800 {
            return "\(Int(interval / 86400))d"
        } else {
            return "\(Int(interval / 604800))w"
        }
    }

    private var displayUsername: String {
        // Show first 8 characters of creator ID as placeholder
        "User \(post.creatorId.prefix(8))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部用户信息
            HStack(spacing: 8) {
                Circle()
                    .fill(DesignTokens.avatarPlaceholder)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayUsername)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black)

                    Text(formattedDate)
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            // 图片占位符 - TODO: 当 Post 模型支持 mediaUrls 后加载真实图片
            Rectangle()
                .fill(DesignTokens.avatarPlaceholder)
                .frame(height: 200)
                .cornerRadius(8)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            // 实际帖子内容
            Text(post.content.isEmpty ? "No content" : post.content)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.black)
                .lineLimit(2)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
        .background(.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }
}

#Preview {
    ProfileView(currentPage: .constant(.account))
        .environmentObject(AuthenticationManager.shared)
}
