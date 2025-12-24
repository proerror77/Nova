import SwiftUI

// MARK: - UserProfile 用户数据模型
struct UserProfileData {
    let userId: String
    var username: String
    var avatarUrl: String?
    var location: String?
    var profession: String?
    var followingCount: Int
    var followersCount: Int
    var likesCount: Int
    var isVerified: Bool
    var posts: [UserProfilePostData]

    // Alias account support
    var isAlias: Bool = false
    var aliasName: String? = nil

    /// 默认占位数据（用于加载中或预览）
    static let placeholder = UserProfileData(
        userId: "",
        username: "Loading...",
        avatarUrl: nil,
        location: nil,
        profession: nil,
        followingCount: 0,
        followersCount: 0,
        likesCount: 0,
        isVerified: false,
        posts: []
    )

    /// 预览用示例数据
    static let preview = UserProfileData(
        userId: "preview-user-123",
        username: "Juliette",
        avatarUrl: nil,
        location: "England",
        profession: "Artist",
        followingCount: 592,
        followersCount: 1449,
        likesCount: 452,
        isVerified: true,
        posts: []
    )
}

// MARK: - UserProfileView
struct UserProfileView: View {
    // MARK: - 导航控制
    @Binding var showUserProfile: Bool

    // MARK: - 用户数据
    let userId: String  // 要显示的用户ID
    @State private var userData: UserProfileData = .placeholder
    @State private var isLoading = true

    @State private var selectedTab: ProfileTab = .posts
    @State private var isFollowing = true
    @State private var showBlockReportSheet = false

    // MARK: - Services
    private let userService = UserService.shared
    private let contentService = ContentService()

    enum ProfileTab {
        case posts
    }

    // MARK: - 便捷初始化器（兼容旧代码）
    init(showUserProfile: Binding<Bool>, userId: String = "preview-user") {
        self._showUserProfile = showUserProfile
        self.userId = userId
    }

    // MARK: - 布局配置
    private let headerBackgroundColor = Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50)
    private let contentBackgroundColor = Color(red: 0.96, green: 0.96, blue: 0.96)
    private let accentColor = Color(red: 0.82, green: 0.11, blue: 0.26)
    private let buttonColor = Color(red: 0.87, green: 0.11, blue: 0.26)

    // MARK: - 导航栏布局配置（可调整位置）
    private var navBarLayout: UserProfileNavBarLayout {
        UserProfileNavBarLayout(
            horizontalPadding: 20,      // 与 Profile 一致
            topPadding: 60,             // 与 Profile 一致
            bottomPadding: 40,          // 与 Profile 一致
            backButtonSize: 20,
            shareIconSize: 24
        )
    }

    // MARK: - 用户信息区块垂直位置调整
    // 正值向下移动，负值向上移动（与 Profile 页面一致）
    private let userInfoBlockVerticalOffset: CGFloat = -30

    // MARK: - 操作按钮区块垂直位置调整
    // 正值向下移动，负值向上移动
    private let actionButtonsVerticalOffset: CGFloat = -40

    // MARK: - 内容区域（Posts）垂直位置调整
    // 正值向下移动，负值向上移动
    private let contentSectionVerticalOffset: CGFloat = -40

    // MARK: - 用户信息布局配置（可调整位置）
    private var userInfoLayout: UserProfileUserInfoLayout {
        UserProfileUserInfoLayout(
            topPadding: 0,              // 与 Profile 一致
            bottomPadding: 10,          // 与 Profile 一致
            avatarOuterSize: 108,
            avatarInnerSize: 100,
            usernameFontSize: 20,
            usernameTopPadding: 9,      // 与 Profile 一致
            locationFontSize: 12,
            locationTopPadding: 4,
            professionFontSize: 12,
            professionTopPadding: 7,    // 与 Profile 一致
            statsTopPadding: 8,         // 与 Profile 一致
            statsItemWidth: 132,        // 与 Profile 一致
            statsFontSize: 16,
            statsDividerHeight: 24      // 与 Profile 一致
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            // MARK: - 背景层（贴紧屏幕边缘）
            VStack(spacing: 0) {
                // 头部背景 - 完全贴边
                Image("UserProfile-background")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 520)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .blur(radius: 15)
                    .overlay(Color.black.opacity(0.2))

                // 内容区域背景 - 填充剩余空间
                contentBackgroundColor
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()

            // MARK: - 内容层（居中对齐）
            VStack(spacing: 0) {
                // 顶部导航栏（使用组件）
                UserProfileTopNavigationBar(
                    isVerified: userData.isVerified,
                    layout: navBarLayout,
                    onBackTapped: {
                        showUserProfile = false
                    },
                    onShareTapped: {
                        // 分享操作
                    },
                    onMoreTapped: {
                        showBlockReportSheet = true
                    }
                )

                // 用户信息区域（使用组件）- 居中
                UserProfileUserInfoSection(
                    avatarUrl: userData.avatarUrl,
                    username: userData.username,
                    location: userData.location,
                    profession: userData.profession,
                    followingCount: userData.followingCount,
                    followersCount: userData.followersCount,
                    likesCount: userData.likesCount,
                    isAlias: userData.isAlias,
                    aliasName: userData.aliasName,
                    layout: userInfoLayout,
                    onFollowingTapped: {
                        // 点击 Following
                    },
                    onFollowersTapped: {
                        // 点击 Followers
                    },
                    onLikesTapped: {
                        // 点击 Likes
                    }
                )
                .frame(maxWidth: .infinity)  // 确保居中
                .offset(y: userInfoBlockVerticalOffset)  // 应用垂直偏移（与 Profile 一致）

                // 操作按钮（使用组件）- 居中
                UserProfileActionButtons(
                    isFollowing: $isFollowing,
                    onFollowTapped: {
                        // 关注操作
                    },
                    onAddFriendsTapped: {
                        // 添加好友操作
                    },
                    onMessageTapped: {
                        // 消息操作
                    }
                )
                .frame(maxWidth: .infinity)  // 确保居中
                .offset(y: actionButtonsVerticalOffset)  // 第 36 行调整

                // 内容区域（使用组件）
                UserProfileContentSection(
                    posts: userData.posts,
                    onSearchTapped: {
                        // 搜索操作
                    },
                    onPostTapped: { postId in
                        // 点击帖子
                    }
                )
                .padding(.top, contentSectionVerticalOffset)  // 使用 padding 代替 offset，不会产生布局空白
            }
            .frame(maxWidth: .infinity)  // 整体居中
            .ignoresSafeArea(edges: .bottom)  // 内容层延伸到底部
        }
        .task {
            await loadUserData()
        }
        .sheet(isPresented: $showBlockReportSheet) {
            BlockReportSheet(
                userId: userId,
                username: userData.username,
                onBlocked: {
                    // 封鎖後關閉個人資料頁面
                    showUserProfile = false
                },
                onReported: {
                    // 舉報後可選擇是否關閉
                }
            )
        }
    }

    // MARK: - 加载用户数据
    private func loadUserData() async {
        isLoading = true

        #if DEBUG
        print("[UserProfile] 🔍 Loading profile for userId: \(userId)")
        #endif

        do {
            // 1. 加载用户资料
            let userProfile = try await userService.getUser(userId: userId)

            #if DEBUG
            print("[UserProfile] ✅ API returned user: id=\(userProfile.id), username=\(userProfile.username), displayName=\(userProfile.displayName ?? "nil")")
            #endif

            // 2. 加载用户发布的帖子
            let postsResponse = try await contentService.getPostsByAuthor(authorId: userId, limit: 50, offset: 0)

            // 3. 将 Post 转换为 UserProfilePostData
            let userPosts = postsResponse.posts.map { post in
                UserProfilePostData(
                    id: post.id,
                    avatarUrl: userProfile.avatarUrl,
                    username: userProfile.displayName ?? userProfile.username,
                    likeCount: post.likeCount ?? 0,
                    imageUrl: post.mediaUrls?.first,
                    content: post.content
                )
            }

            // 4. 更新 UI
            await MainActor.run {
                userData = UserProfileData(
                    userId: userProfile.id,
                    username: userProfile.displayName ?? userProfile.username,
                    avatarUrl: userProfile.avatarUrl,
                    location: userProfile.location,
                    profession: userProfile.bio,
                    followingCount: userProfile.safeFollowingCount,
                    followersCount: userProfile.safeFollowerCount,
                    likesCount: userProfile.safePostCount,
                    isVerified: userProfile.safeIsVerified,
                    posts: userPosts
                )
                isLoading = false
            }

            #if DEBUG
            print("[UserProfile] Loaded \(userPosts.count) posts for user: \(userProfile.username)")
            #endif

        } catch {
            #if DEBUG
            print("[UserProfile] Failed to load user data: \(error)")
            #endif

            // 加载失败时使用占位数据
            await MainActor.run {
                userData = .placeholder
                isLoading = false
            }
        }
    }
}

// MARK: - Previews
#Preview("UserProfile") {
    UserProfileView(showUserProfile: .constant(true))
}
