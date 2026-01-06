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
    var savedPosts: [UserProfilePostData]
    var likedPosts: [UserProfilePostData]

    // Alias account support
    var isAlias: Bool = false
    var aliasName: String? = nil

    /// 默认占位数据（用于加载中或预览）
    /// 临时展示完整 UI 信息，方便调整布局
    static let placeholder = UserProfileData(
        userId: "preview-user",
        username: "Juliette",
        avatarUrl: nil,
        location: "England",
        profession: "Artist",
        followingCount: 592,
        followersCount: 1449,
        likesCount: 452,
        isVerified: true,
        posts: [],
        savedPosts: [],
        likedPosts: []
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
        posts: [],
        savedPosts: [],
        likedPosts: []
    )

    /// 從 UserProfile 快取創建（用於快取優先載入，防止抖動）
    init(from profile: UserProfile, posts: [UserProfilePostData] = [], savedPosts: [UserProfilePostData] = [], likedPosts: [UserProfilePostData] = []) {
        self.userId = profile.id
        self.username = profile.displayName ?? profile.username
        self.avatarUrl = profile.avatarUrl
        self.location = profile.location
        self.profession = profile.bio
        self.followingCount = profile.safeFollowingCount
        self.followersCount = profile.safeFollowerCount
        self.likesCount = profile.safePostCount
        self.isVerified = profile.safeIsVerified
        self.posts = posts
        self.savedPosts = savedPosts
        self.likedPosts = likedPosts
    }
}

// MARK: - UserProfileView
struct UserProfileView: View {
    // MARK: - 导航控制
    @Binding var showUserProfile: Bool

    // MARK: - 用户数据
    let userId: String  // 要显示的用户ID
    @State private var userData: UserProfileData? = nil  // 快取優先：初始為 nil，不使用佔位數據
    @State private var isLoading = false  // 初始不顯示載入狀態，等檢查快取後決定
    @State private var isLoadingPosts = false  // 單獨追蹤帖子載入狀態

    @State private var selectedTab: ProfileTab = .posts
    @State private var isFollowing = true
    @State private var showBlockReportSheet = false

    // 標記是否已載入過 Saved/Liked 數據（防止空數組時重複請求）
    @State private var hasLoadedSaved = false
    @State private var hasLoadedLiked = false

    // MARK: - Services
    private let userService = UserService.shared
    private let contentService = ContentService()

    enum ProfileTab {
        case posts
        case saved
        case liked
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

    // MARK: - 导航栏布局配置（可调整位置，使用响应式）
    private var navBarLayout: UserProfileNavBarLayout {
        UserProfileNavBarLayout(
            horizontalPadding: 17.w,      // 左右边距 17pt
            topPadding: 64.h,             // 距离顶部 64.h（响应式，与 Profile 一致）
            bottomPadding: 40.h,
            backButtonSize: 20.s,
            shareIconSize: 24.s
        )
    }

    // MARK: - 用户信息区块垂直位置调整（使用响应式）
    // 正值向下移动，负值向上移动（与 Profile 页面一致）
    private var userInfoBlockVerticalOffset: CGFloat { (-30).h }

    // MARK: - 操作按钮区块垂直位置调整（使用响应式）
    // 正值向下移动，负值向上移动
    private var actionButtonsVerticalOffset: CGFloat { (-40).h }

    // MARK: - 内容区域（Posts）垂直位置调整（使用响应式）
    // 正值向下移动，负值向上移动
    private var contentSectionVerticalOffset: CGFloat { (-40).h }

    // MARK: - 用户信息布局配置（可调整位置，使用响应式）
    private var userInfoLayout: UserProfileUserInfoLayout {
        UserProfileUserInfoLayout(
            topPadding: 0,              // 与 Profile 一致
            bottomPadding: 10.h,        // 与 Profile 一致
            avatarOuterSize: 108.s,
            avatarInnerSize: 100.s,
            usernameFontSize: 20.f,
            usernameTopPadding: 9.h,    // 与 Profile 一致
            locationFontSize: 12.f,
            locationTopPadding: 4.h,
            professionFontSize: 12.f,
            professionTopPadding: 7.h,  // 与 Profile 一致
            statsTopPadding: 8.h,       // 与 Profile 一致
            statsItemWidth: 132.w,      // 与 Profile 一致
            statsFontSize: 16.f,
            statsDividerHeight: 24.h    // 与 Profile 一致
        )
    }

    // MARK: - Posts 内容栏固定高度（基于设计稿 375x812，使用响应式）
    // 与 Profile 页面对齐：用户信息区结束于 300pt 处，下方内容占据剩余空间
    private var postsContentHeight: CGFloat { 424.h }

    // MARK: - 顯示數據（快取優先，無數據時顯示空白而非佔位）
    private var displayUsername: String { userData?.username ?? "" }
    private var displayLocation: String? { userData?.location }
    private var displayProfession: String? { userData?.profession }
    private var displayAvatarUrl: String? { userData?.avatarUrl }
    private var displayFollowingCount: Int { userData?.followingCount ?? 0 }
    private var displayFollowersCount: Int { userData?.followersCount ?? 0 }
    private var displayLikesCount: Int { userData?.likesCount ?? 0 }
    private var displayIsVerified: Bool { userData?.isVerified ?? false }
    private var displayPosts: [UserProfilePostData] { userData?.posts ?? [] }
    private var displaySavedPosts: [UserProfilePostData] { userData?.savedPosts ?? [] }
    private var displayLikedPosts: [UserProfilePostData] { userData?.likedPosts ?? [] }

    /// 是否有用戶數據可顯示（快取或已載入）
    private var hasUserData: Bool { userData != nil }

    /// 根据当前选中的标签返回对应的帖子数组
    private var currentTabPosts: [UserProfilePostData] {
        switch selectedTab {
        case .posts:
            return displayPosts
        case .saved:
            return displaySavedPosts
        case .liked:
            return displayLikedPosts
        }
    }

    var body: some View {
        GeometryReader { geometry in
            // 计算 Posts 背景板距离顶部的距离
            let postsTopOffset = geometry.size.height - postsContentHeight
            
            ZStack {
                // MARK: - 背景层（响应式设计）
                Group {
                    ZStack {
                        // 背景图片
                        Image("UserProfile-background")
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                        
                        // 颜色叠加层
                        Rectangle()
                            .foregroundColor(.clear)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .background(Color(red: 0, green: 0, blue: 0).opacity(0))
                        
                        Rectangle()
                            .foregroundColor(.clear)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .background(Color(red: 0, green: 0, blue: 0).opacity(0.30))
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }

                // MARK: - 白色背景模块（紧贴底部）
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(.white)
                        .frame(height: 424.h)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)

                // MARK: - 灰色背景模块（紧贴底部）
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(Color(red: 0.96, green: 0.96, blue: 0.96))
                        .frame(height: 376.h)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)

                // MARK: - 用户信息层（距离按钮栏12pt）
                // 只有當有用戶數據時才顯示，否則顯示骨架屏
                if hasUserData {
                    VStack {
                        Spacer()
                        VStack(spacing: 8.h) {
                            // 头像和基本信息
                            VStack(spacing: 8.h) {
                                // 头像
                                HStack(spacing: 8.s) {
                                    if let avatarUrl = displayAvatarUrl, let url = URL(string: avatarUrl) {
                                        CachedAsyncImage(url: url) { image in
                                            image
                                                .resizable()
                                                .scaledToFill()
                                        } placeholder: {
                                            Ellipse()
                                                .foregroundColor(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                                        }
                                        .frame(width: 100.s, height: 100.s)
                                        .clipShape(Ellipse())
                                    } else {
                                        Ellipse()
                                            .foregroundColor(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                                            .frame(width: 100.s, height: 100.s)
                                    }
                                }
                                .padding(4.s)
                                .frame(width: 108.s, height: 108.s)
                                .cornerRadius(54.s)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 54.s)
                                        .inset(by: 1)
                                        .stroke(.white, lineWidth: 1)
                                )

                                // 用户名
                                Text(displayUsername)
                                    .font(Font.custom("SFProDisplay-Semibold", size: 16.f))
                                    .foregroundColor(.white)

                                // 地区（保留固定位置）
                                Text(displayLocation ?? " ")
                                    .font(Font.custom("SFProDisplay-Light", size: 14.f))
                                    .foregroundColor(.white)
                                    .frame(height: 17.h) // 固定高度
                            }
                            .frame(width: 130.w, height: 158.h)

                            // 职业（保留固定位置，带蓝标认证图标在文字后面）
                            HStack(spacing: 4.s) {
                                Text(displayProfession ?? " ")
                                    .font(Font.custom("SFProDisplay-Light", size: 14.f))
                                    .foregroundColor(.white)
                                if displayProfession != nil {
                                    Image("Blue-v")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 14.s, height: 14.s)
                                }
                            }
                            .frame(height: 17.h) // 固定高度

                            // 统计数据
                            HStack(spacing: -24) {
                                // Following
                                VStack(spacing: 1.h) {
                                    Text("\(displayFollowingCount)")
                                        .font(Font.custom("SFProDisplay-Semibold", size: 16.f))
                                        .foregroundColor(.white)
                                    Text("Following")
                                        .font(Font.custom("SFProDisplay-Light", size: 14.f))
                                        .foregroundColor(.white)
                                }
                                .frame(width: 125.w, height: 40.h)

                                // 分隔线
                                Rectangle()
                                    .foregroundColor(.clear)
                                    .frame(width: 24.s, height: 0)
                                    .overlay(
                                        Rectangle()
                                            .stroke(.white, lineWidth: 0.5)
                                            .frame(width: 0.5, height: 24.h)
                                    )

                                // Followers
                                VStack(spacing: 1.h) {
                                    Text("\(displayFollowersCount)")
                                        .font(Font.custom("SFProDisplay-Semibold", size: 16.f))
                                        .foregroundColor(.white)
                                    Text("Followers")
                                        .font(Font.custom("SFProDisplay-Light", size: 14.f))
                                        .foregroundColor(.white)
                                }
                                .frame(width: 132.w, height: 40.h)

                                // 分隔线
                                Rectangle()
                                    .foregroundColor(.clear)
                                    .frame(width: 24.s, height: 0)
                                    .overlay(
                                        Rectangle()
                                            .stroke(.white, lineWidth: 0.5)
                                            .frame(width: 0.5, height: 24.h)
                                    )

                                // Halo
                                VStack(spacing: 1.h) {
                                    Text("\(displayLikesCount)")
                                        .font(Font.custom("SFProDisplay-Semibold", size: 16.f))
                                        .foregroundColor(.white)
                                    Text("Halo")
                                        .font(Font.custom("SFProDisplay-Light", size: 14.f))
                                        .foregroundColor(.white)
                                }
                                .frame(width: 118.w, height: 40.h)
                            }
                            .frame(height: 40.h)
                        }
                        .frame(width: 375.w, height: 240.h)

                        Spacer()
                            .frame(height: 493.h) // 让头像顶部距离屏幕顶部 79pt（812 - 79 - 240 = 493）
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .zIndex(4)
                } else if isLoading {
                    // 骨架屏：用戶信息區載入中
                    VStack {
                        Spacer()
                        VStack(spacing: 8.h) {
                            // 頭像骨架
                            Circle()
                                .fill(Color.white.opacity(0.3))
                                .frame(width: 108.s, height: 108.s)
                                .overlay(ShimmerEffect())
                                .clipShape(Circle())

                            // 用戶名骨架
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.3))
                                .frame(width: 100.w, height: 20.h)
                                .overlay(ShimmerEffect())

                            // 位置骨架
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 60.w, height: 14.h)
                                .overlay(ShimmerEffect())

                            // 統計數據骨架
                            HStack(spacing: 40.w) {
                                ForEach(0..<3, id: \.self) { _ in
                                    VStack(spacing: 4.h) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.white.opacity(0.3))
                                            .frame(width: 40.w, height: 18.h)
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.white.opacity(0.2))
                                            .frame(width: 60.w, height: 12.h)
                                    }
                                }
                            }
                            .padding(.top, 16.h)
                        }
                        .frame(width: 375.w, height: 240.h)

                        Spacer()
                            .frame(height: 493.h)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .zIndex(4)
                }

                // MARK: - 操作按钮层（距离白色背景顶部12pt）
                VStack {
                    Spacer()
                    HStack(spacing: 10.w) {
                        // Follow 按钮
                        Button(action: {
                            isFollowing.toggle()
                        }) {
                            Text(isFollowing ? "Following" : "Follow")
                                .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                                .tracking(0.24)
                                .foregroundColor(.white)
                        }
                        .frame(width: 105.w, height: 34.h)
                        .background(Color(red: 0.87, green: 0.11, blue: 0.26))
                        .cornerRadius(57.s)

                        // Add friends 按钮
                        Button(action: {
                            // 添加好友操作
                        }) {
                            Text("Add friends")
                                .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                                .tracking(0.24)
                                .foregroundColor(.white)
                        }
                        .frame(width: 105.w, height: 34.h)
                        .cornerRadius(57.s)
                        .overlay(
                            RoundedRectangle(cornerRadius: 57.s)
                                .inset(by: 0.50)
                                .stroke(.white, lineWidth: 0.50)
                        )

                        // Message 按钮
                        Button(action: {
                            // 消息操作
                        }) {
                            Text("Message")
                                .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                                .tracking(0.24)
                                .foregroundColor(.white)
                        }
                        .frame(width: 105.w, height: 34.h)
                        .cornerRadius(57.s)
                        .overlay(
                            RoundedRectangle(cornerRadius: 57.s)
                                .inset(by: 0.50)
                                .stroke(.white, lineWidth: 0.50)
                        )
                    }
                    Spacer()
                        .frame(height: 445.h) // 白色背景高度424 + 间距21 = 445.h（按钮距离Posts区域21pt）
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .zIndex(3)

                // MARK: - Posts内容区域（标签栏 + 帖子网格，参考Profile页结构）
                VStack {
                    Spacer()
                        .frame(height: postsTopOffset)
                    
                    // 标签栏和帖子网格在同一个VStack中
                    VStack(spacing: 0) {
                        // 标签栏
                        HStack(spacing: 40.s) {
                            Button(action: {
                                selectedTab = .posts
                            }) {
                                Text("Posts")
                                    .font(Font.custom("SFProDisplay-Semibold", size: 16.f))
                                    .foregroundColor(selectedTab == .posts ? Color(red: 0.87, green: 0.11, blue: 0.26) : .black)
                            }

                            Button(action: {
                                selectedTab = .saved
                                Task { await loadSavedPosts() }
                            }) {
                                Text("Saved")
                                    .font(Font.custom("SFProDisplay-Semibold", size: 16.f))
                                    .foregroundColor(selectedTab == .saved ? Color(red: 0.87, green: 0.11, blue: 0.26) : .black)
                            }

                            Button(action: {
                                selectedTab = .liked
                                Task { await loadLikedPosts() }
                            }) {
                                Text("Liked")
                                    .font(Font.custom("SFProDisplay-Semibold", size: 16.f))
                                    .foregroundColor(selectedTab == .liked ? Color(red: 0.87, green: 0.11, blue: 0.26) : .black)
                            }
                        }
                        .frame(height: 24.h)
                        .padding(.top, 12.h)
                        .padding(.bottom, 16.h)
                        .frame(maxWidth: .infinity)
                        
                        // 分隔线
                        Rectangle()
                            .fill(DesignTokens.borderColor)
                            .frame(height: 0.5)
                        
                        // 帖子网格
                        ScrollView(.vertical, showsIndicators: false) {
                            if isLoadingPosts && displayPosts.isEmpty {
                                // 骨架屏加载状态（只在沒有快取帖子時顯示）
                                ProfilePostsGridSkeleton(itemCount: 6)
                                    .padding(.horizontal, 5.w)
                                    .padding(.top, 5.h)
                            } else if displayPosts.isEmpty {
                                // 空狀態
                                VStack(spacing: 12.h) {
                                    Image(systemName: "photo.on.rectangle.angled")
                                        .font(.system(size: 40.f))
                                        .foregroundColor(.gray)
                                    Text("No posts yet")
                                        .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                                        .foregroundColor(.gray)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60.h)
                            } else {
                                LazyVGrid(
                                    columns: [
                                        GridItem(.flexible(), spacing: 5.w),
                                        GridItem(.flexible(), spacing: 5.w)
                                    ],
                                    spacing: 5.h
                                ) {
                                    // 根据选中的标签显示对应内容
                                    ForEach(currentTabPosts) { post in
                                        PostCard(
                                            imageUrl: post.imageUrl,
                                            imageName: "PostCardImage",
                                            title: "\(post.username) \(post.content)",
                                            authorName: post.username,
                                            authorAvatarUrl: post.avatarUrl,
                                            likeCount: post.likeCount,
                                            onTap: {
                                                // 点击帖子
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal, 5.w)
                                .padding(.top, 5.h)
                                .padding(.bottom, 100.h)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()  // 裁剪超出内容，防止截断效果
                    }
                    .background(Color(red: 0.96, green: 0.96, blue: 0.96))
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .ignoresSafeArea(.all, edges: .bottom)
                .zIndex(2)

            // MARK: - 导航栏层（仅导航栏，帖子内容已移至正确位置的网格层）
            VStack(spacing: 0) {
                // 顶部导航栏（使用组件）
                UserProfileTopNavigationBar(
                    isVerified: userData?.isVerified ?? false,
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
                Spacer()
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
        }
        .ignoresSafeArea(edges: [.top, .bottom])  // 忽略上下安全区域（与 Profile 一致）
        .task {
            await loadUserData()
        }
        .sheet(isPresented: $showBlockReportSheet) {
            BlockReportSheet(
                userId: userId,
                username: userData?.username ?? "",
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
        #if DEBUG
        print("[UserProfile] 🔍 Loading profile for userId: \(userId)")
        #endif

        // 🔑 快取優先：先檢查快取，立即顯示已有數據，防止抖動
        if let cached = userService.getCachedUser(userId: userId) {
            await MainActor.run {
                userData = UserProfileData(from: cached)
            }
            #if DEBUG
            print("[UserProfile] ✅ Using cached profile for: \(cached.username)")
            #endif
        }

        // 只有沒有快取時才顯示載入狀態
        if userData == nil {
            await MainActor.run { isLoading = true }
        }

        // 標記正在載入帖子
        await MainActor.run { isLoadingPosts = true }

        do {
            // 1. 加载用户资料（會自動使用快取或從網路獲取）
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
                    imageUrl: post.displayThumbnailUrl,
                    content: post.content
                )
            }

            // 4. 更新 UI（靜默刷新，不會閃爍）
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
                    posts: userPosts,
                    savedPosts: [],
                    likedPosts: []
                )
                isLoading = false
                isLoadingPosts = false
            }

            #if DEBUG
            print("[UserProfile] Loaded \(userPosts.count) posts for user: \(userProfile.username)")
            #endif

        } catch {
            #if DEBUG
            print("[UserProfile] Failed to load user data: \(error)")
            #endif

            // 加载失败时使用占位数据（僅當完全沒有數據時）
            await MainActor.run {
                if userData == nil {
                    userData = .placeholder
                }
                isLoading = false
                isLoadingPosts = false
            }
        }
    }

    // MARK: - 加载收藏的帖子
    private func loadSavedPosts() async {
        // 如果已经加载过，跳过（使用 flag 而非 isEmpty，防止空數組時重複請求）
        guard !hasLoadedSaved else { return }

        await MainActor.run { hasLoadedSaved = true }

        #if DEBUG
        print("[UserProfile] 🔖 Loading saved posts for userId: \(userId)")
        #endif

        do {
            let response = try await contentService.getUserSavedPosts(userId: userId, limit: 50, offset: 0)

            // 将 Post 转换为 UserProfilePostData
            let savedPosts = response.posts.map { post in
                UserProfilePostData(
                    id: post.id,
                    avatarUrl: post.authorAvatarUrl,
                    username: post.displayAuthorName,
                    likeCount: post.likeCount ?? 0,
                    imageUrl: post.displayThumbnailUrl,
                    content: post.content
                )
            }

            await MainActor.run {
                userData?.savedPosts = savedPosts
            }

            #if DEBUG
            print("[UserProfile] ✅ Loaded \(savedPosts.count) saved posts")
            #endif

        } catch {
            #if DEBUG
            print("[UserProfile] ❌ Failed to load saved posts: \(error)")
            #endif
        }
    }

    // MARK: - 加载点赞的帖子
    private func loadLikedPosts() async {
        // 如果已经加载过，跳过（使用 flag 而非 isEmpty，防止空數組時重複請求）
        guard !hasLoadedLiked else { return }

        await MainActor.run { hasLoadedLiked = true }

        #if DEBUG
        print("[UserProfile] ❤️ Loading liked posts for userId: \(userId)")
        #endif

        do {
            let response = try await contentService.getUserLikedPosts(userId: userId, limit: 50, offset: 0)

            // 将 Post 转换为 UserProfilePostData
            let likedPosts = response.posts.map { post in
                UserProfilePostData(
                    id: post.id,
                    avatarUrl: post.authorAvatarUrl,
                    username: post.displayAuthorName,
                    likeCount: post.likeCount ?? 0,
                    imageUrl: post.displayThumbnailUrl,
                    content: post.content
                )
            }

            await MainActor.run {
                userData?.likedPosts = likedPosts
            }

            #if DEBUG
            print("[UserProfile] ✅ Loaded \(likedPosts.count) liked posts")
            #endif

        } catch {
            #if DEBUG
            print("[UserProfile] ❌ Failed to load liked posts: \(error)")
            #endif
        }
    }
}

// MARK: - Previews
#Preview("UserProfile") {
    UserProfileView(showUserProfile: .constant(true))
}
