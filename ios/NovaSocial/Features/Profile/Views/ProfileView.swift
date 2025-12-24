import SwiftUI
import PhotosUI

// MARK: - Profile View State
/// Enum representing the active overlay/sheet state in ProfileView
/// Using enum instead of multiple booleans prevents state conflicts
enum ProfileActiveSheet: Equatable {
    case none
    case newPost(initialImage: UIImage?)
    case generateImage
    case write
    case settings
    case following
    case followers
    case postDetail(post: Post)
    case imagePicker
    case camera
    case photoOptions
    case accountSwitcher
    case shareSheet
    case editProfile
    case avatarPicker       // 頭像選擇器
    case backgroundPicker   // 背景圖選擇器

    static func == (lhs: ProfileActiveSheet, rhs: ProfileActiveSheet) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none),
             (.generateImage, .generateImage),
             (.write, .write),
             (.settings, .settings),
             (.following, .following),
             (.followers, .followers),
             (.imagePicker, .imagePicker),
             (.camera, .camera),
             (.photoOptions, .photoOptions),
             (.accountSwitcher, .accountSwitcher),
             (.shareSheet, .shareSheet),
             (.editProfile, .editProfile),
             (.avatarPicker, .avatarPicker),
             (.backgroundPicker, .backgroundPicker):
            return true
        case (.newPost(let img1), .newPost(let img2)):
            return img1 === img2
        case (.postDetail(let p1), .postDetail(let p2)):
            return p1.id == p2.id
        default:
            return false
        }
    }
}

struct ProfileView: View {
    @Binding var currentPage: AppPage
    // 全局认证状态从上层注入
    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var profileData = ProfileData()

    // MARK: - 統一的 Sheet 狀態管理
    /// 使用 enum 統一管理所有 overlay/sheet 狀態，避免狀態衝突
    @State private var activeSheet: ProfileActiveSheet = .none

    // MARK: - 非 Sheet 相關狀態
    @State private var selectedImage: UIImage?              // ImagePicker 選中的圖片
    @State private var localAvatarImage: UIImage? = nil     // 本地选择的头像
    @State private var selectedAccountType: AccountDisplayType = .primary  // 当前选择的账户类型
    @State private var showSearchBar = false                // 显示搜索框
    @State private var searchText: String = ""              // 搜索文字
    @State private var showDeleteConfirmation = false       // 显示删除确认
    @State private var postToDelete: Post? = nil            // 待删除的帖子
    @State private var isDeleting = false                   // 正在删除中
    @State private var searchDebounceTask: Task<Void, Never>?  // 搜索防抖任務

    // MARK: - 頭像/背景圖更換狀態
    @State private var avatarPhotoItem: PhotosPickerItem?   // 頭像選擇
    @State private var backgroundPhotoItem: PhotosPickerItem? // 背景圖選擇
    @State private var localBackgroundImage: UIImage? = nil // 本地背景圖
    @State private var isUploadingAvatar = false            // 上傳頭像中
    @State private var isUploadingBackground = false        // 上傳背景中

    // Services
    private let mediaService = MediaService()
    private let identityService = IdentityService()

    // Access AvatarManager - @ObservedObject to observe pendingAvatar changes
    @ObservedObject private var avatarManager = AvatarManager.shared

    // Access UserPostsManager for real-time post sync
    // NOTE: Access singleton directly for @Observable objects to ensure single source of truth
    private var userPostsManager: UserPostsManager { UserPostsManager.shared }


    // Computed property for user display
    private var displayUser: UserProfile? {
        authManager.currentUser ?? profileData.userProfile
    }
    
    // Computed property for filtered user posts (搜索过滤 - Posts tab)
    private var filteredUserPosts: [Post] {
        guard !searchText.isEmpty else {
            return userPostsManager.userPosts
        }
        return userPostsManager.userPosts.filter { post in
            post.content.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    // Computed property for filtered profile posts (搜索过滤 - Saved/Liked tabs)
    private var filteredProfilePosts: [Post] {
        guard !searchText.isEmpty else {
            return profileData.currentTabPosts
        }
        return profileData.currentTabPosts.filter { post in
            post.content.localizedCaseInsensitiveContains(searchText)
        }
    }

    // 根据选择的账户类型返回显示的用户名
    private var displayUsername: String {
        switch selectedAccountType {
        case .primary:
            return displayUser?.displayName ?? displayUser?.username ?? "User"
        case .alias:
            return "Dreamer"
        }
    }

    // 分享内容
    private var shareItems: [Any] {
        guard let userId = displayUser?.id else { return [] }
        let username = displayUser?.username ?? "user"
        let shareUrl = URL(string: "https://nova.social/user/\(userId)") ?? URL(string: "https://nova.social")!
        let shareText = "Check out \(username)'s profile on Icered!"
        return [shareText, shareUrl]
    }

    var body: some View {
        ZStack {
            // 條件渲染：根據 activeSheet 狀態切換視圖
            switch activeSheet {
            case .newPost(let initialImage):
                NewPostView(
                    showNewPost: Binding(
                        get: { activeSheet != .none },
                        set: { if !$0 { activeSheet = .none } }
                    ),
                    initialImage: initialImage ?? selectedImage,
                    onPostSuccess: { post in
                        // 实时同步新帖子到 UserPostsManager
                        userPostsManager.addNewPost(post)
                    }
                )
                .transition(.identity)

            case .generateImage:
                GenerateImage01View(
                    showGenerateImage: Binding(
                        get: { activeSheet == .generateImage },
                        set: { if !$0 { activeSheet = .none } }
                    )
                )
                .transition(.identity)

            case .write:
                WriteView(
                    showWrite: Binding(
                        get: { activeSheet == .write },
                        set: { if !$0 { activeSheet = .none } }
                    )
                )
                .transition(.identity)

            case .settings:
                SettingsView(currentPage: $currentPage)
                    .transition(.identity)

            case .following:
                ProfileFollowingView(
                    isPresented: Binding(
                        get: { activeSheet == .following },
                        set: { if !$0 { activeSheet = .none } }
                    ),
                    userId: displayUser?.id ?? "",
                    username: displayUser?.username ?? "User",
                    initialTab: .following
                )
                .transition(.identity)

            case .followers:
                ProfileFollowersView(
                    isPresented: Binding(
                        get: { activeSheet == .followers },
                        set: { if !$0 { activeSheet = .none } }
                    )
                )
                .transition(.identity)
                .environmentObject(authManager)

            case .postDetail(let post):
                PostDetailView(
                    post: FeedPost(
                        from: post,
                        authorName: displayUser?.displayName ?? displayUser?.username ?? "User",
                        authorAvatar: displayUser?.avatarUrl
                    ),
                    onDismiss: {
                        activeSheet = .none
                    }
                )
                .transition(.identity)

            case .none, .imagePicker, .camera, .photoOptions, .accountSwitcher, .shareSheet, .editProfile, .avatarPicker, .backgroundPicker:
                // 這些狀態顯示 profileContent，overlay/sheet 另外處理
                profileContent
            }
        }
        .animation(.none, value: activeSheet)
        .sheet(isPresented: Binding(
            get: { activeSheet == .imagePicker },
            set: { if !$0 { activeSheet = .none } }
        )) {
            ImagePicker(sourceType: .photoLibrary, selectedImage: $selectedImage)
        }
        .sheet(isPresented: Binding(
            get: { activeSheet == .camera },
            set: { if !$0 { activeSheet = .none } }
        )) {
            ImagePicker(sourceType: .camera, selectedImage: $selectedImage)
        }
        .onChange(of: selectedImage) { oldValue, newValue in
            // 选择/拍摄照片后，自动跳转到NewPostView
            if newValue != nil {
                activeSheet = .newPost(initialImage: newValue)
            }
        }
    }

    // MARK: - Profile 主内容
    private var profileContent: some View {
        ZStack {
            DesignTokens.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 区域1：用户信息头部（自适应高度）
                userHeaderSection

                // MARK: - 区域2：内容区域
                contentSection
                    .offset(y: contentSectionVerticalOffset)  // 应用垂直偏移
            }
            .safeAreaInset(edge: .bottom) {
                // MARK: - 底部导航栏
                bottomNavigationBar
            }

            // MARK: - 照片选项弹窗
            if activeSheet == .photoOptions {
                PhotoOptionsModal(
                    isPresented: Binding(
                        get: { activeSheet == .photoOptions },
                        set: { if !$0 { activeSheet = .none } }
                    ),
                    onChoosePhoto: {
                        activeSheet = .imagePicker
                    },
                    onTakePhoto: {
                        activeSheet = .camera
                    },
                    onGenerateImage: {
                        activeSheet = .generateImage
                    },
                    onWrite: {
                        activeSheet = .write
                    }
                )
            }

            // MARK: - 账户切换弹窗
            if activeSheet == .accountSwitcher {
                AccountSwitcherSheet(
                    isPresented: Binding(
                        get: { activeSheet == .accountSwitcher },
                        set: { if !$0 { activeSheet = .none } }
                    ),
                    selectedAccountType: $selectedAccountType
                )
                .environmentObject(authManager)
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
        .sheet(isPresented: Binding(
            get: { activeSheet == .shareSheet },
            set: { if !$0 { activeSheet = .none } }
        )) {
            NovaShareSheet(items: shareItems)
        }
        .sheet(isPresented: Binding(
            get: { activeSheet == .editProfile },
            set: { if !$0 { activeSheet = .none } }
        )) {
            EditProfileView(onProfileUpdated: {
                // 刷新個人資料
                Task {
                    if let userId = authManager.currentUser?.id {
                        await profileData.loadUserProfile(userId: userId)
                    }
                }
            })
            .environmentObject(authManager)
        }
        // MARK: - 頭像選擇器
        .photosPicker(
            isPresented: Binding(
                get: { activeSheet == .avatarPicker },
                set: { if !$0 { activeSheet = .none } }
            ),
            selection: $avatarPhotoItem,
            matching: .images
        )
        .onChange(of: avatarPhotoItem) { _, newItem in
            Task {
                await loadAndUploadAvatar(from: newItem)
            }
        }
        // MARK: - 背景圖選擇器
        .photosPicker(
            isPresented: Binding(
                get: { activeSheet == .backgroundPicker },
                set: { if !$0 { activeSheet = .none } }
            ),
            selection: $backgroundPhotoItem,
            matching: .images
        )
        .onChange(of: backgroundPhotoItem) { _, newItem in
            Task {
                await loadBackgroundImage(from: newItem)
            }
        }
        // 上傳中指示器
        .overlay {
            if isUploadingAvatar || isUploadingBackground {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                    Text(isUploadingAvatar ? "上傳頭像中..." : "處理背景圖...")
                        .font(.system(size: 14.f))
                        .foregroundColor(.white)
                }
            }
        }
        .alert("刪除貼文", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) {
                postToDelete = nil
            }
            Button("刪除", role: .destructive) {
                if let post = postToDelete {
                    Task {
                        await deletePost(post)
                    }
                }
            }
        } message: {
            Text("確定要刪除這則貼文嗎？此操作無法撤銷。")
        }
        .overlay {
            if isDeleting {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
            }
        }
    }

    // ==================== 布局配置（可在此调整） ====================
    // 顶部导航栏布局
    private var navBarLayout: ProfileNavBarLayout {
        ProfileNavBarLayout(
            horizontalPadding: 20.s,      // 左右边距
            topPadding: 60.h,             // 顶部边距
            bottomPadding: 40.h,          // 底部边距
            usernameFontSize: 20.f,       // 用户名字体大小
            chevronSize: 12.s,            // 下拉箭头大小
            usernameChevronSpacing: 6.s,  // 用户名和箭头间距
            iconSize: 24.s,               // 图标大小
            iconSpacing: 18.s             // 图标间距
        )
    }

    // 用户信息区域布局
    private var userInfoLayout: ProfileUserInfoLayout {
        ProfileUserInfoLayout(
            containerWidth: 365.w,        // 容器宽度
            verticalSpacing: 7.h,         // 垂直间距
            bottomPadding: 10.h,          // 底部边距
            avatarOuterSize: 108.s,       // 头像外圈大小
            avatarInnerSize: 100.s,       // 头像内圈大小
            avatarBorderWidth: 1,         // 边框宽度（保持1像素）
            usernameFontSize: 20.f,       // 用户名字体大小
            usernameSpacingFromAvatar: 9.h,  // 与头像间距
            locationFontSize: 12.f,       // 位置字体大小
            professionFontSize: 12.f,     // 职业字体大小
            blueVIconSize: 20.s,          // 蓝标大小
            professionIconSpacing: 10.s,  // 蓝标与文字间距
            statsTopPadding: 8.h,         // 统计区顶部间距
            statsLabelFontSize: 16.f,     // 统计标签字体
            statsValueFontSize: 16.f,     // 统计数值字体
            statsItemWidth: 132.w,        // 统计项宽度
            statsItemSpacing: -16.w,      // 统计项间距
            statsDividerHeight: 24.h      // 分隔线高度
        )
    }

    // ==================== 用户信息区块垂直位置调整 ====================
    // 调整此值可单独控制头像、用户名、位置、职业、粉丝统计区块的垂直位置
    // 正值向下移动，负值向上移动
    private let userInfoBlockVerticalOffset: CGFloat = -60  // ← 在此调整垂直偏移量

    // ==================== 内容区域（标签栏+帖子）垂直位置调整 ====================
    // 调整此值可控制 Posts/Saved/Liked 标签栏及下方内容的垂直位置
    // 正值向下移动，负值向上移动
    private let contentSectionVerticalOffset: CGFloat = -60  // ← 在此调整垂直偏移量

    // MARK: - 用户信息头部区域
    private var userHeaderSection: some View {
        ZStack(alignment: .top) {
            // 背景图片 - 只通过右上角按钮更换（移除整体点击）
            ZStack(alignment: .topTrailing) {
                // 背景圖片內容
                Group {
                    if let bgImage = localBackgroundImage {
                        Image(uiImage: bgImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image("Profile-background")
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 980)  // 调整高度
                .clipped()
                .blur(radius: 20.s)
                .overlay(Color.black.opacity(0.3))
                .ignoresSafeArea(edges: .top)
                // 移除 onTapGesture - 避免误触跳转到照片选择器

                // 背景編輯圖標 - 唯一的背景更换入口
                Button(action: { activeSheet = .backgroundPicker }) {
                    Circle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 36.s, height: 36.s)
                        .overlay(
                            Image(systemName: "photo.fill")
                                .font(.system(size: 16.f))
                                .foregroundColor(.white)
                        )
                }
                .padding(.top, 70.h)
                .padding(.trailing, 16.w)
            }
            .frame(height: 380.h)  // 调整背景區域高度

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏（独立组件）
                ProfileTopNavigationBar(
                    username: displayUsername,
                    layout: navBarLayout,
                    onShareTapped: { activeSheet = .shareSheet },
                    onSettingsTapped: { currentPage = .setting },
                    onUsernameTapped: {
                        withAnimation(.easeOut(duration: 0.25)) {
                            activeSheet = .accountSwitcher
                        }
                    }
                )

                // MARK: - 用户信息区域（独立组件）
                // 注意：当用户未填写信息时，组件会自动处理默认显示状态
                ProfileUserInfoSection(
                    avatarImage: avatarManager.pendingAvatar ?? localAvatarImage,
                    avatarUrl: displayUser?.avatarUrl,  // 使用 displayUser 确保与 authManager 同步
                    username: displayUser?.displayName ?? displayUser?.username,  // 未填写时组件显示 "User"
                    location: displayUser?.location,                               // 未填写时不显示
                    profession: displayUser?.bio,                                  // 未填写时不显示
                    isVerified: displayUser?.safeIsVerified ?? false,
                    followingCount: displayUser?.safeFollowingCount ?? 0,
                    followersCount: displayUser?.safeFollowerCount ?? 0,
                    likesCount: userPostsManager.postCount,
                    layout: userInfoLayout,
                    onAvatarTapped: {
                        activeSheet = .avatarPicker  // 點擊頭像更換
                    },
                    onFollowingTapped: {
                        activeSheet = .following  // 点击 Following 跳转
                    },
                    onFollowersTapped: {
                        activeSheet = .followers  // 点击 Followers 跳转
                    }
                )
                .offset(y: userInfoBlockVerticalOffset)  // 应用垂直偏移
            }
        }
    }

    // MARK: - 内容区域
    private var contentSection: some View {
        VStack(spacing: 0) {
            // MARK: - 标签栏（标签独立居中，搜索图标右对齐）
            VStack(spacing: 0) {
                    ZStack {
                        // 标签按钮 - 完全居中
                        HStack(spacing: 40.s) {
                            Button(action: {
                                profileData.selectedTab = .posts
                                Task {
                                    await profileData.loadContent(for: .posts)
                                }
                            }) {
                                Text(LocalizedStringKey("Posts_tab"))
                                    .font(.system(size: 16.f, weight: .bold))
                                    .foregroundColor(profileData.selectedTab == .posts ? DesignTokens.accentColor : DesignTokens.textPrimary)
                            }

                            Button(action: {
                                profileData.selectedTab = .saved
                                Task {
                                    await profileData.loadContent(for: .saved)
                                }
                            }) {
                                Text(LocalizedStringKey("Saved_tab"))
                                    .font(.system(size: 16.f, weight: .bold))
                                    .foregroundColor(profileData.selectedTab == .saved ? DesignTokens.accentColor : DesignTokens.textPrimary)
                            }

                            Button(action: {
                                profileData.selectedTab = .liked
                                Task {
                                    await profileData.loadContent(for: .liked)
                                }
                            }) {
                                Text(LocalizedStringKey("Liked_tab"))
                                    .font(.system(size: 16.f, weight: .bold))
                                    .foregroundColor(profileData.selectedTab == .liked ? DesignTokens.accentColor : DesignTokens.textPrimary)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        // 搜索图标 - 右对齐，使用 Symbol Effect
                        HStack {
                            Spacer()
                            Button(action: {
                                let wasShowingSearch = showSearchBar
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showSearchBar.toggle()
                                }
                                if wasShowingSearch {
                                    searchText = ""
                                    profileData.searchQuery = ""
                                    profileData.isSearching = false
                                }
                            }) {
                                Image(systemName: showSearchBar ? "xmark.circle.fill" : "magnifyingglass")
                                    .font(.system(size: 20.f))
                                    .foregroundColor(DesignTokens.textPrimary)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .padding(.trailing, 20.w)
                        }
                    }
                    .padding(.vertical, 16.h)
                    .background(.white)
                    
                    // MARK: - 搜索框
                    if showSearchBar {
                        HStack(spacing: 10.s) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14.f))
                                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

                            TextField("搜索帖子內容...", text: $searchText)
                                .font(.system(size: 14.f))
                                .foregroundColor(.black)
                                .textFieldStyle(.plain)
                                .onChange(of: searchText) { _, newValue in
                                    // 性能優化：添加 300ms 防抖動避免每次按鍵都觸發搜索
                                    searchDebounceTask?.cancel()
                                    searchDebounceTask = Task {
                                        try? await Task.sleep(for: .milliseconds(300))
                                        guard !Task.isCancelled else { return }
                                        await profileData.searchInProfile(query: newValue)
                                    }
                                }

                            if !searchText.isEmpty {
                                Button(action: {
                                    searchText = ""
                                    profileData.searchQuery = ""
                                    profileData.isSearching = false
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14.f))
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .padding(EdgeInsets(top: 8.h, leading: 12.w, bottom: 8.h, trailing: 12.w))
                        .background(Color(red: 0.95, green: 0.95, blue: 0.95))
                        .cornerRadius(10.s)
                        .padding(.horizontal, 16.w)
                        .padding(.bottom, 8.h)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // 分隔线
                    Rectangle()
                        .fill(DesignTokens.borderColor)
                        .frame(height: 0.5)
                }

                // MARK: - 帖子网格
                ScrollView {
                    if profileData.selectedTab == .posts {
                        // Posts 标签 - 使用 UserPostsManager 实时同步（支持分页）
                        if userPostsManager.isLoading && userPostsManager.userPosts.isEmpty {
                            ProgressView()
                                .padding(.top, 40)
                        } else if userPostsManager.hasPosts {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8.s), GridItem(.flexible(), spacing: 8.s)], spacing: 8.s) {
                                ForEach(filteredUserPosts) { post in
                                    ProfilePostCard(
                                        post: post,
                                        username: displayUser?.displayName ?? displayUser?.username ?? "User",
                                        avatarUrl: displayUser?.avatarUrl,
                                        isOwnPost: true,  // Posts tab 都是自己的帖子
                                        onTap: {
                                            activeSheet = .postDetail(post: post)
                                        },
                                        onDelete: {
                                            postToDelete = post
                                            showDeleteConfirmation = true
                                        }
                                    )
                                    .onAppear {
                                        // 无限滚动：当最后几个帖子出现时，加载更多
                                        if let lastPost = userPostsManager.userPosts.suffix(3).first,
                                           post.id == lastPost.id,
                                           userPostsManager.hasMore,
                                           !userPostsManager.isLoadingMore {
                                            Task {
                                                await userPostsManager.loadMorePosts()
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 8.w)
                            .padding(.top, 8.h)
                            
                            // 加载更多指示器
                            if userPostsManager.isLoadingMore {
                                ProgressView()
                                    .padding(.vertical, 16.h)
                            }
                        } else if !searchText.isEmpty && userPostsManager.hasPosts {
                            // 搜索无结果
                            searchEmptyStateView
                        } else {
                            emptyStateView
                        }
                    } else {
                        // Saved/Liked 标签 - 使用 profileData (支持搜索过滤)
                        if profileData.isLoading {
                            ProgressView()
                                .padding(.top, 40)
                        } else if profileData.hasContent {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8.s), GridItem(.flexible(), spacing: 8.s)], spacing: 8.s) {
                                ForEach(filteredProfilePosts) { post in
                                    ProfilePostCard(
                                        post: post,
                                        username: displayUser?.displayName ?? displayUser?.username ?? "User",
                                        avatarUrl: displayUser?.avatarUrl,
                                        isOwnPost: post.authorId == authManager.currentUser?.id,
                                        onTap: {
                                            activeSheet = .postDetail(post: post)
                                        },
                                        onDelete: {
                                            postToDelete = post
                                            showDeleteConfirmation = true
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 8.w)
                            .padding(.top, 8.h)
                        } else if !searchText.isEmpty && profileData.hasContent {
                            // 搜索无结果
                            searchEmptyStateView
                        } else {
                            emptyStateView
                        }
                    }

                    Color.clear
                        .frame(height: 100.h)
                }
                .background(DesignTokens.backgroundColor)
        }
    }

    // MARK: - 空状态视图
    private var emptyStateView: some View {
        VStack(spacing: 12.h) {
            Image(systemName: "tray")
                .font(.system(size: 48.f))
                .foregroundColor(.gray)
            Text("No posts yet")
                .font(.system(size: 16.f))
                .foregroundColor(.gray)
        }
        .padding(.top, 60.h)
    }

    // MARK: - 搜索无结果视图
    private var searchEmptyStateView: some View {
        VStack(spacing: 12.h) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48.f))
                .foregroundColor(.gray)
                .symbolEffect(.pulse, options: .repeating)
            Text("找不到相關帖子")
                .font(.system(size: 16.f, weight: .medium))
                .foregroundColor(.gray)
            Text("試試其他關鍵詞")
                .font(.system(size: 14.f))
                .foregroundColor(.gray.opacity(0.7))
        }
        .padding(.top, 60.h)
    }

    // MARK: - 删除帖子
    private func deletePost(_ post: Post) async {
        await MainActor.run {
            isDeleting = true
        }

        do {
            // 调用 API 删除帖子
            let contentService = ContentService()
            try await contentService.deletePost(postId: post.id)

            // 从本地状态中移除
            userPostsManager.deletePost(postId: post.id)

            print("✅ Post deleted successfully: \(post.id)")
        } catch {
            print("❌ Failed to delete post: \(error)")
            // TODO: 显示错误提示给用户
        }

        await MainActor.run {
            isDeleting = false
            postToDelete = nil
        }
    }

    // MARK: - 載入並上傳頭像
    private func loadAndUploadAvatar(from item: PhotosPickerItem?) async {
        guard let item = item,
              let userId = authManager.currentUser?.id else { return }

        await MainActor.run {
            isUploadingAvatar = true
        }

        do {
            // 載入圖片數據
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let imageData = image.jpegData(compressionQuality: 0.8) else {
                throw NSError(domain: "ProfileView", code: 1, userInfo: [NSLocalizedDescriptionKey: "無法載入圖片"])
            }

            // 立即顯示本地預覽
            await MainActor.run {
                localAvatarImage = image
                avatarManager.pendingAvatar = image
            }

            // 上傳頭像到 MediaService
            let avatarUrl = try await mediaService.uploadImage(image: imageData, userId: userId)

            // 通過 IdentityService 更新用戶資料
            let updates = UserProfileUpdate(
                displayName: nil,
                bio: nil,
                avatarUrl: avatarUrl,
                coverUrl: nil,
                website: nil,
                location: nil
            )
            let updatedUser = try await identityService.updateUser(userId: userId, updates: updates)

            // 更新 AuthManager 中的當前用戶
            await MainActor.run {
                authManager.updateCurrentUser(updatedUser)
            }

            #if DEBUG
            print("✅ Avatar uploaded successfully: \(avatarUrl)")
            #endif

        } catch {
            #if DEBUG
            print("❌ Failed to upload avatar: \(error)")
            #endif
            // 還原本地狀態
            await MainActor.run {
                localAvatarImage = nil
                avatarManager.pendingAvatar = nil
            }
        }

        await MainActor.run {
            isUploadingAvatar = false
            avatarPhotoItem = nil
        }
    }

    // MARK: - 載入背景圖片（本地預覽）
    private func loadBackgroundImage(from item: PhotosPickerItem?) async {
        guard let item = item else { return }

        await MainActor.run {
            isUploadingBackground = true
        }

        do {
            // 載入圖片數據
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                throw NSError(domain: "ProfileView", code: 2, userInfo: [NSLocalizedDescriptionKey: "無法載入背景圖片"])
            }

            // 顯示本地預覽
            await MainActor.run {
                localBackgroundImage = image
            }

            // TODO: 背景圖上傳到服務器的 API 待實現
            // let backgroundUrl = try await mediaService.uploadBackgroundImage(image: image)
            // try await userService.updateProfile(backgroundUrl: backgroundUrl)

            #if DEBUG
            print("✅ Background image loaded locally")
            #endif

        } catch {
            #if DEBUG
            print("❌ Failed to load background image: \(error)")
            #endif
        }

        await MainActor.run {
            isUploadingBackground = false
            backgroundPhotoItem = nil
        }
    }

    // MARK: - 底部导航栏
    private var bottomNavigationBar: some View {
        BottomTabBar(
            currentPage: $currentPage,
            showPhotoOptions: Binding(
                get: { activeSheet == .photoOptions },
                set: { if $0 { activeSheet = .photoOptions } else { activeSheet = .none } }
            ),
            showNewPost: Binding(
                get: { if case .newPost = activeSheet { return true } else { return false } },
                set: { if $0 { activeSheet = .newPost(initialImage: nil) } else { activeSheet = .none } }
            )
        )
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
            HStack(spacing: 8.s) {
                Circle()
                    .fill(DesignTokens.avatarPlaceholder)
                    .frame(width: 24.s, height: 24.s)

                VStack(alignment: .leading, spacing: 2.h) {
                    Text(displayUsername)
                        .font(.system(size: 12.f, weight: .semibold))
                        .foregroundColor(.black)

                    Text(formattedDate)
                        .font(.system(size: 10.f))
                        .foregroundColor(.gray)
                }

                Spacer()
            }
            .padding(.horizontal, 12.w)
            .padding(.top, 12.h)

            // 图片占位符 - TODO: 当 Post 模型支持 mediaUrls 后加载真实图片
            Rectangle()
                .fill(DesignTokens.avatarPlaceholder)
                .frame(height: 200.h)
                .cornerRadius(8.s)
                .padding(.horizontal, 12.w)
                .padding(.top, 8.h)

            // 实际帖子内容
            Text(post.content.isEmpty ? "No content" : post.content)
                .font(.system(size: 13.f, weight: .medium))
                .foregroundColor(.black)
                .lineLimit(2)
                .padding(.horizontal, 12.w)
                .padding(.top, 8.h)
                .padding(.bottom, 12.h)
        }
        .background(.white)
        .cornerRadius(12.s)
        .shadow(color: .black.opacity(0.05), radius: 3.s, y: 1)
    }
}

// MARK: - Previews

#Preview("Profile - Default") {
    ProfileView(currentPage: .constant(.account))
        .environmentObject(AuthenticationManager.shared)
}

#Preview("Profile - Light Mode") {
    ProfileView(currentPage: .constant(.account))
        .environmentObject(AuthenticationManager.shared)
        .preferredColorScheme(.light)
}
