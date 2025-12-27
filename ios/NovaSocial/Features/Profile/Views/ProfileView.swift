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
    case postDetail(post: Post, authorName: String, authorAvatar: String?)
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
        case (.postDetail(let p1, _, _), .postDetail(let p2, _, _)):
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
    // 優先使用 profileData.userProfile（從 API 載入的最新數據）
    // 回退到 authManager.currentUser（登入時的緩存數據）
    private var displayUser: UserProfile? {
        profileData.userProfile ?? authManager.currentUser
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

            case .postDetail(let post, let authorName, let authorAvatar):
                PostDetailView(
                    post: FeedPost(
                        from: post,
                        authorName: authorName,
                        authorAvatar: authorAvatar
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
        ZStack(alignment: .bottom) {
            // 主内容区域
            VStack(spacing: 0) {
                // MARK: - 区域1：用户信息头部（自适应高度）
                userHeaderSection

                // MARK: - 区域2：内容区域
                contentSection
                    .frame(maxHeight: .infinity)  // 填满剩余空间
                    .offset(y: contentSectionVerticalOffset)  // 应用垂直偏移
            }

            // MARK: - 底部导航栏（覆盖在内容上方，忽略安全区域）
            bottomNavigationBar
        }
        .ignoresSafeArea(edges: [.top, .bottom])
        // MARK: - 照片选项弹窗
        .overlay {
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
        }
        // MARK: - 账户切换弹窗
        .overlay {
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
                #if DEBUG
                print("[ProfileView] Loading profile for userId: \(userId)")
                #endif
                await profileData.loadUserProfile(userId: userId)
                await userPostsManager.loadUserPosts(userId: userId)
                #if DEBUG
                print("[ProfileView] Profile loaded: posts=\(profileData.posts.count), userProfile=\(profileData.userProfile?.username ?? "nil")")
                #endif
            } else {
                #if DEBUG
                print("[ProfileView] No userId found in authManager.currentUser")
                #endif
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

    // ==================== 用户信息区块垂直位置调整 ====================
    // 调整此值可单独控制头像、用户名、位置、职业、粉丝统计区块的垂直位置
    // 正值向下移动，负值向上移动
    private let userInfoBlockVerticalOffset: CGFloat = 0  // ← 在此调整垂直偏移量

    // ==================== 内容区域（标签栏+帖子）垂直位置调整 ====================
    // 调整此值可控制 Posts/Saved/Liked 标签栏及下方内容的垂直位置
    // 正值向下移动，负值向上移动
    private let contentSectionVerticalOffset: CGFloat = 20  // ← 向下偏移 8pt，与用户信息区域保持 8pt 间距

    // MARK: - 背景层（与 UserProfile 结构一致）
    private var profileBackgroundSection: some View {
        ZStack {
            // 背景图片
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

            // 第一层遮罩 - 暖色调
            Rectangle()
                .foregroundColor(.clear)
                .background(Color(red: 0, green: 0, blue: 0).opacity(0))

            // 第二层遮罩 - 黑色
            Rectangle()
                .foregroundColor(.clear)
                .background(Color(red: 0, green: 0, blue: 0).opacity(0.20))
        }
        .clipped()
    }

    // MARK: - 顶部导航栏（与 UserProfile 结构一致）
    private var profileNavigationBar: some View {
        HStack {
            // 左侧：用户名 + 下拉箭头
            Button(action: {
                withAnimation(.easeOut(duration: 0.25)) {
                    activeSheet = .accountSwitcher
                }
            }) {
                HStack(spacing: 4.s) {
                    Text(displayUsername)
                        .font(.system(size: 16.f, weight: .semibold))
                        .foregroundColor(.white)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12.f))
                        .foregroundColor(.white)
                }
            }

            Spacer()

            // 右侧：分享 + 设置图标
            HStack(spacing: 18.s) {
                Button(action: { activeSheet = .shareSheet }) {
                    Image("share")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24.s, height: 24.s)
                }

                Button(action: { currentPage = .setting }) {
                    Image("Setting(white)")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24.s, height: 24.s)
                }
            }
        }
        .padding(.horizontal, 17.w)
        .padding(.top, 64.h)  // 距离手机绝对顶部 64pt（与 UserProfile 一致）
    }

    // MARK: - 用户信息区域（与 UserProfile 结构一致）
    private var userInfoSection: some View {
        VStack(spacing: 8.h) {
            VStack(spacing: 8.h) {
                // 头像
                Button(action: { activeSheet = .avatarPicker }) {
                    ZStack {
                        // 头像图片 - 使用 AvatarView 组件统一处理
                        AvatarView(
                            image: avatarManager.pendingAvatar ?? localAvatarImage,
                            url: displayUser?.avatarUrl,
                            size: 100.s,
                            name: displayUser?.displayName ?? displayUser?.username
                        )
                    }
                    .frame(width: 108.s, height: 108.s)
                    .overlay(
                        Circle()
                            .inset(by: 1)
                            .stroke(.white, lineWidth: 2)
                    )
                    .overlay(
                        // 添加头像图标
                        Image("AddAvatar")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24.s, height: 24.s)
                            .offset(x: 38.s, y: 38.s)
                    )
                }

                // 用户名
                Text(displayUser?.displayName ?? displayUser?.username ?? "User")
                    .font(.system(size: 16.f, weight: .semibold))
                    .foregroundColor(.white)

                // 地区
                Text(displayUser?.location ?? " ")
                    .font(.system(size: 14.f, weight: .light))
                    .foregroundColor(.white)
                    .frame(height: 17.h)
            }
            .frame(width: 130.w, height: 158.h)

            // 职业 + 蓝标
            HStack(spacing: 4.s) {
                Text(displayUser?.bio ?? " ")
                    .font(.system(size: 14.f, weight: .light))
                    .foregroundColor(Color(red: 0.97, green: 0.97, blue: 0.97))

                if displayUser?.bio != nil && !displayUser!.bio!.isEmpty {
                    Image("Blue-v")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14.s, height: 14.s)
                }
            }
            .frame(height: 17.h)

            // 统计数据
            HStack(spacing: -16.s) {
                // Following
                VStack(spacing: 1.h) {
                    Text("\(displayUser?.safeFollowingCount ?? 0)")
                        .font(.system(size: 16.f, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Following")
                        .font(.system(size: 14.f, weight: .light))
                        .foregroundColor(.white)
                }
                .frame(width: 132.w, height: 40.h)
                .contentShape(Rectangle())
                .onTapGesture {
                    activeSheet = .following
                }

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
                    Text("\(displayUser?.safeFollowerCount ?? 0)")
                        .font(.system(size: 16.f, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Followers")
                        .font(.system(size: 14.f, weight: .light))
                        .foregroundColor(.white)
                }
                .frame(width: 132.w, height: 40.h)
                .contentShape(Rectangle())
                .onTapGesture {
                    activeSheet = .followers
                }

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
                    Text("\(displayUser?.safePostCount ?? 0)")
                        .font(.system(size: 16.f, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Halo")
                        .font(.system(size: 14.f, weight: .light))
                        .foregroundColor(.white)
                }
                .frame(width: 118.w, height: 40.h)
            }
            .frame(height: 40.h)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240.h)
    }

    // MARK: - 用户信息头部区域（保留供旧代码兼容，但不再使用）
    private var userHeaderSection: some View {
        ZStack(alignment: .top) {
            // 背景图片 - 只通过右上角按钮更换（移除整体点击）
            // 背景圖片內容 - 带双层遮罩效果
            ZStack {
                // 背景图片
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

                // 第一层遮罩 - 暖色调
                Rectangle()
                    .foregroundColor(.clear)
                    .background(Color(red: 0, green: 0, blue: 0).opacity(0))

                // 第二层遮罩 - 黑色
                Rectangle()
                    .foregroundColor(.clear)
                    .background(Color(red: 0, green: 0, blue: 0).opacity(0.20))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .ignoresSafeArea()
            .frame(height: 331.h)  // 距离屏幕顶部 331px

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack {
                    // 左侧：用户名 + 下拉箭头
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.25)) {
                            activeSheet = .accountSwitcher
                        }
                    }) {
                        HStack(spacing: 4.s) {
                            Text(displayUsername)
                                .font(.system(size: 16.f, weight: .semibold))
                                .foregroundColor(.white)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12.f))
                                .foregroundColor(.white)
                        }
                    }

                    Spacer()

                    // 右侧：分享 + 设置图标
                    HStack(spacing: 18.s) {
                        Button(action: { activeSheet = .shareSheet }) {
                            Image("share")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24.s, height: 24.s)
                        }

                        Button(action: { currentPage = .setting }) {
                            Image("Setting(white)")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24.s, height: 24.s)
                        }
                    }
                }
                .padding(.horizontal, 17.w)
                .padding(.top, 64.h)  // 距离手机顶部 64pt（忽略安全区域后）

                // MARK: - 用户信息区域
                VStack(spacing: 8.h) {
                    VStack(spacing: 8.h) {
                        // 头像（距离导航栏 16px）
                        Button(action: { activeSheet = .avatarPicker }) {
                            ZStack {
                                // 头像图片 - 使用 AvatarView 组件统一处理
                                AvatarView(
                                    image: avatarManager.pendingAvatar ?? localAvatarImage,
                                    url: displayUser?.avatarUrl,
                                    size: 100.s,
                                    name: displayUser?.displayName ?? displayUser?.username
                                )
                            }
                            .frame(width: 108.s, height: 108.s)
                            .overlay(
                                Circle()
                                    .inset(by: 1)
                                    .stroke(.white, lineWidth: 2)
                            )
                            .overlay(
                                // 添加头像图标 - 在白线前层
                                Image("AddAvatar")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 24.s, height: 24.s)
                                    .offset(x: 38.s, y: 38.s)
                            )
                        }

                        // 用户名
                        Text(displayUser?.displayName ?? displayUser?.username ?? "User")
                            .font(.system(size: 16.f, weight: .semibold))
                            .foregroundColor(.white)

                        // 位置（未填写时显示空白，保留位置）
                        Text(displayUser?.location?.isEmpty == false ? displayUser!.location! : " ")
                            .font(Font.custom("SF Pro Display", size: 14.f).weight(.light))
                            .foregroundColor(.white)
                    }
                    .frame(width: 130.w)

                    // 职业 + 认证图标（未填写时显示空白，保留位置）
                    HStack(spacing: 10.s) {
                        Text(displayUser?.bio?.isEmpty == false ? displayUser!.bio! : " ")
                            .font(Font.custom("SF Pro Display", size: 14.f).weight(.light))
                            .foregroundColor(.white)
                        if displayUser?.safeIsVerified == true {
                            Image("BlueV")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24.s, height: 24.s)
                        }
                    }

                    // Following / Followers / Halo
                    HStack(spacing: -2) {
                        // Following
                        Button(action: { activeSheet = .following }) {
                            VStack(spacing: 1.h) {
                                Text("\(displayUser?.safeFollowingCount ?? 0)")
                                    .font(.system(size: 16.f, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("Following")
                                    .font(.system(size: 14.f, weight: .light))
                                    .foregroundColor(.white)
                            }
                            .frame(width: 125.w, height: 40.h)
                        }

                        // 分隔线
                        Rectangle()
                            .fill(.white.opacity(0.5))
                            .frame(width: 1, height: 24.h)

                        // Followers
                        Button(action: { activeSheet = .followers }) {
                            VStack(spacing: 1.h) {
                                Text("\(displayUser?.safeFollowerCount ?? 0)")
                                    .font(.system(size: 16.f, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("Followers")
                                    .font(.system(size: 14.f, weight: .light))
                                    .foregroundColor(.white)
                            }
                            .frame(width: 132.w, height: 40.h)
                        }

                        // 分隔线
                        Rectangle()
                            .fill(.white.opacity(0.5))
                            .frame(width: 1, height: 24.h)

                        // Halo
                        VStack(spacing: 1.h) {
                            Text("\(userPostsManager.postCount)")
                                .font(.system(size: 16.f, weight: .semibold))
                                .foregroundColor(.white)
                            Text("Halo")
                                .font(.system(size: 14.f, weight: .light))
                                .foregroundColor(.white)
                        }
                        .frame(width: 118.w, height: 40.h)
                    }
                    .frame(height: 40.h)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 240.h)
                .padding(.top, 0)
            }
            .ignoresSafeArea(edges: .top)  // 让导航栏从屏幕绝对顶部开始计算
        }
        .frame(height: 300.h)  // 整个头部区域高度，Posts栏紧随其后（间距8px）
    }

    // MARK: - 内容区域
    private var contentSection: some View {
        VStack(spacing: 0) {
            // 顶部分隔线
            Rectangle()
                .fill(Color(red: 0.74, green: 0.74, blue: 0.74))
                .frame(height: 0.5)

            // MARK: - 标签栏
            HStack(spacing: 42.s) {
                // 标签按钮
                HStack(spacing: 40.s) {
                    Button(action: {
                        profileData.selectedTab = .posts
                        Task {
                            await profileData.loadContent(for: .posts)
                        }
                    }) {
                        Text("Posts")
                            .font(.system(size: 16.f, weight: .semibold))
                            .foregroundColor(profileData.selectedTab == .posts ? Color(red: 0.87, green: 0.11, blue: 0.26) : .black)
                    }

                    Button(action: {
                        profileData.selectedTab = .saved
                        Task {
                            await profileData.loadContent(for: .saved)
                        }
                    }) {
                        Text("Saved")
                            .font(.system(size: 16.f, weight: .semibold))
                            .foregroundColor(profileData.selectedTab == .saved ? Color(red: 0.87, green: 0.11, blue: 0.26) : .black)
                    }

                    Button(action: {
                        profileData.selectedTab = .liked
                        Task {
                            await profileData.loadContent(for: .liked)
                        }
                    }) {
                        Text("Liked")
                            .font(.system(size: 16.f, weight: .semibold))
                            .foregroundColor(profileData.selectedTab == .liked ? Color(red: 0.87, green: 0.11, blue: 0.26) : .black)
                    }
                }
                .frame(width: 211.w, height: 24.h)

                // 搜索图标
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
                    if showSearchBar {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20.f))
                            .foregroundColor(.black)
                    } else {
                        Image("search(gray)")
                            .resizable()
                            .scaledToFit()
                    }
                }
                .frame(width: 24.s, height: 24.s)
            }
            .padding(.top, 12.h)
            .padding(.bottom, 16.h)
            .padding(.leading, 82.w)
            .padding(.trailing, 16.w)
            .frame(maxWidth: .infinity)

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

            // MARK: - 帖子网格
            // Posts: 用户发布的帖子 | Saved: 收藏的帖子 | Liked: 点赞的帖子
            if profileData.isLoading && filteredProfilePosts.isEmpty {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredProfilePosts.isEmpty {
                if !searchText.isEmpty {
                    searchEmptyStateView
                } else {
                    emptyStateView
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 5.s), GridItem(.flexible(), spacing: 5.s)], spacing: 5.s) {
                        ForEach(filteredProfilePosts) { post in
                            // Posts tab: 使用当前用户信息（因为是自己的帖子）
                            // Saved/Liked tabs: 使用帖子的作者信息（带后备）
                            let isOwnPost = profileData.selectedTab == .posts
                            let authorName = isOwnPost
                                ? (displayUser?.displayName ?? displayUser?.username ?? "Me")
                                : post.displayAuthorName  // 使用 Post 的 displayAuthorName 属性
                            let authorAvatar = isOwnPost
                                ? displayUser?.avatarUrl
                                : post.authorAvatarUrl

                            PostCard(
                                imageUrl: post.mediaUrls?.first,
                                imageName: "PostCardImage",
                                title: "\(authorName) \(post.content)",
                                authorName: authorName,
                                authorAvatarUrl: authorAvatar,
                                likeCount: post.likeCount ?? 0,
                                onTap: {
                                    activeSheet = .postDetail(post: post, authorName: authorName, authorAvatar: authorAvatar)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 5.w)
                    .padding(.top, 5.h)
                    .padding(.bottom, 100.h)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
        }
        .background(Color(red: 0.96, green: 0.96, blue: 0.96))  // 整个内容区域灰色背景
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

#Preview("Profile") {
    ProfileView(currentPage: .constant(.account))
        .environmentObject(AuthenticationManager.shared)
}
