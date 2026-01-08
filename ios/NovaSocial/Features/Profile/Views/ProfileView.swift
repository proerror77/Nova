import SwiftUI
import AVFoundation
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
    @State private var deleteErrorMessage: String? = nil    // 刪除失敗錯誤訊息
    @State private var showDeleteError = false              // 顯示刪除失敗提示
    @State private var showCameraPermissionAlert = false    // 相机权限提示
    @State private var searchDebounceTask: Task<Void, Never>?  // 搜索防抖任務

    // MARK: - 用戶導航狀態 (Issue #165)
    @State private var showUserProfile = false              // 顯示其他用戶主頁
    @State private var selectedUserId: String?              // 選中的用戶 ID
    private let userService = UserService.shared            // 用於 cache invalidation

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
                    },
                    onAvatarTapped: { userId in
                        // Close post detail first, then navigate to user profile
                        activeSheet = .none
                        navigateToUserProfile(userId: userId)
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
            set: { newValue in
                // 只有当 activeSheet 仍然是 .imagePicker 时才重置为 .none
                // 避免覆盖已经被 .onChange(of: selectedImage) 设置的 .newPost 状态
                if !newValue && activeSheet == .imagePicker {
                    activeSheet = .none
                }
            }
        )) {
            ImagePicker(sourceType: .photoLibrary, selectedImage: $selectedImage)
        }
        .sheet(isPresented: Binding(
            get: { activeSheet == .camera },
            set: { newValue in
                // 只有当 activeSheet 仍然是 .camera 时才重置为 .none
                // 避免覆盖已经被 .onChange(of: selectedImage) 设置的 .newPost 状态
                if !newValue && activeSheet == .camera {
                    activeSheet = .none
                }
            }
        )) {
            ImagePicker(sourceType: .camera, selectedImage: $selectedImage)
        }
        .onChange(of: selectedImage) { oldValue, newValue in
            // 选择/拍摄照片后，自动跳转到NewPostView
            if newValue != nil {
                activeSheet = .newPost(initialImage: newValue)
            }
        }
        // MARK: - User Profile Navigation (Issue #165)
        .fullScreenCover(isPresented: $showUserProfile) {
            if let userId = selectedUserId {
                UserProfileView(showUserProfile: $showUserProfile, userId: userId)
            } else {
                Color.clear
                    .onAppear {
                        showUserProfile = false
                    }
            }
        }
    }

    /// Navigate to user profile with cache invalidation (Issue #165)
    private func navigateToUserProfile(userId: String) {
        userService.invalidateCache(userId: userId)
        selectedUserId = userId
        showUserProfile = true
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
                        set: { newValue in
                            // 只有当 activeSheet 仍然是 .photoOptions 时才重置为 .none
                            // 避免覆盖已经被 onTakePhoto/onChoosePhoto 等设置的新状态
                            if !newValue && activeSheet == .photoOptions {
                                activeSheet = .none
                            }
                        }
                    ),
                    onChoosePhoto: {
                        activeSheet = .imagePicker
                    },
                    onTakePhoto: {
                        checkCameraPermissionAndOpen()
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
                    Text(isUploadingAvatar ? "Uploading avatar..." : "Processing background...")
                        .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                        .foregroundColor(.white)
                }
            }
        }
        .alert("Delete Post", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                postToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let post = postToDelete {
                    Task {
                        await deletePost(post)
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete this post? This action cannot be undone.")
        }
        .alert("Delete Failed", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) {
                deleteErrorMessage = nil
            }
        } message: {
            Text(deleteErrorMessage ?? "Failed to delete post. Please try again later.")
        }
        // MARK: - Camera Permission Alert
        .alert("Camera Access Required", isPresented: $showCameraPermissionAlert) {
            Button("Open Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Please allow camera access in Settings to take photos.")
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
    private let contentSectionVerticalOffset: CGFloat = 0  // ← 移除偏移，让内容紧跟头部

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
                        .font(.custom("SFProDisplay-Regular", size: 16.f).weight(.semibold))
                        .foregroundColor(.white)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12.f))
                        .foregroundColor(.white)
                        .frame(width: 24.s, height: 24.s)
                }
            }

            Spacer()

            // 右侧：分享 + 设置图标
            HStack(spacing: 0) {
                Button(action: { activeSheet = .shareSheet }) {
                    Image("share")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24.s, height: 24.s)
                        .frame(width: 40.s, height: 40.s)
                }
                .frame(width: 48.s, height: 48.s)

                Button(action: { currentPage = .setting }) {
                    Image("Setting(white)")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24.s, height: 24.s)
                        .frame(width: 40.s, height: 40.s)
                }
                .frame(width: 48.s, height: 48.s)
            }
        }
        .padding(.horizontal, 16.w)
        .frame(height: 48.h)
        .padding(.top, 47.h)  // 安全区域顶部距离
    }

    // MARK: - 用户信息区域（与 UserProfile 结构一致）
    private var userInfoSection: some View {
        VStack(spacing: 8.h) {
            // 头像区域
            Button(action: { activeSheet = .avatarPicker }) {
                ZStack(alignment: .bottomTrailing) {
                    // 头像容器
                    HStack(spacing: 8.s) {
                        AvatarView(
                            image: avatarManager.pendingAvatar ?? localAvatarImage,
                            url: displayUser?.avatarUrl,
                            size: 100.s,
                            name: displayUser?.displayName ?? displayUser?.username
                        )
                    }
                    .padding(4.s)
                    .frame(width: 109.s, height: 109.s)
                    .cornerRadius(54.s)
                    .overlay(
                        RoundedRectangle(cornerRadius: 54.s)
                            .inset(by: 1)
                            .stroke(.white, lineWidth: 1)
                    )
                    
                    // 添加头像按钮
                    Image("AddAvatar")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24.s, height: 24.s)
                        .offset(x: -4.s, y: -4.s)
                }
                .frame(width: 109.s, height: 109.s)
            }
            
            // 用户名 + 位置
            VStack(spacing: 8.h) {
                Text(displayUser?.displayName ?? displayUser?.username ?? "User")
                    .font(.custom("SFProDisplay-Regular", size: 16.f).weight(.semibold))
                    .foregroundColor(.white)
                
                Text(displayUser?.location?.isEmpty == false ? displayUser!.location! : " ")
                    .font(.custom("SFProDisplay-Regular", size: 14.f).weight(.light))
                    .foregroundColor(.white)
            }
            
            // 职业 + 认证图标
            HStack(spacing: 4.s) {
                Text(displayUser?.bio?.isEmpty == false ? displayUser!.bio! : " ")
                    .font(.custom("SFProDisplay-Regular", size: 14.f).weight(.light))
                    .foregroundColor(.white)
                
                if displayUser?.safeIsVerified == true {
                    Image("BlueV")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12.s, height: 12.s)
                }
            }
            
            // Following / Followers / Halo 统计区域
            HStack {
                // Following
                Button(action: { activeSheet = .following }) {
                    VStack(spacing: 0) {
                        Text("\(displayUser?.safeFollowingCount ?? 0)")
                            .font(Font.custom("SFProDisplay-Semibold", size: 16.f))
                            .foregroundColor(.white)
                        Text("Following")
                            .font(Font.custom("SFProDisplay-Light", size: 14.f))
                            .foregroundColor(.white)
                    }
                }
                
                Spacer()
                
                // 第一条分隔线 (距左124pt, 距右251pt)
                Rectangle()
                    .fill(.white)
                    .frame(width: 0.5, height: 24.h)
                
                Spacer()
                
                // Followers
                Button(action: { activeSheet = .followers }) {
                    VStack(spacing: 0) {
                        Text("\(displayUser?.safeFollowerCount ?? 0)")
                            .font(Font.custom("SFProDisplay-Semibold", size: 16.f))
                            .foregroundColor(.white)
                        Text("Followers")
                            .font(Font.custom("SFProDisplay-Light", size: 14.f))
                            .foregroundColor(.white)
                    }
                }
                
                Spacer()
                
                // 第二条分隔线 (距左251pt, 距右124pt)
                Rectangle()
                    .fill(.white)
                    .frame(width: 0.5, height: 24.h)
                
                Spacer()
                
                // Halo
                VStack(spacing: 0) {
                    Text("\(displayUser?.safePostCount ?? 0)")
                        .font(Font.custom("SFProDisplay-Semibold", size: 16.f))
                        .foregroundColor(.white)
                    Text("Halo")
                        .font(Font.custom("SFProDisplay-Light", size: 14.f))
                        .foregroundColor(.white)
                }
            }
            .padding(EdgeInsets(top: 0, leading: 34.w, bottom: 16.h, trailing: 61.w))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 用户信息头部区域
    private var userHeaderSection: some View {
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
                                .font(.custom("SFProDisplay-Regular", size: 16.f).weight(.semibold))
                                .foregroundColor(.white)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12.f))
                                .foregroundColor(.white)
                                .frame(width: 24.s, height: 24.s)
                        }
                    }

                    Spacer()

                    // 右侧：分享 + 设置图标
                    HStack(spacing: 0) {
                        Button(action: { activeSheet = .shareSheet }) {
                            Image("share")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24.s, height: 24.s)
                                .frame(width: 40.s, height: 40.s)
                        }
                        .frame(width: 48.s, height: 48.s)

                        Button(action: { currentPage = .setting }) {
                            Image("Setting(white)")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24.s, height: 24.s)
                                .frame(width: 40.s, height: 40.s)
                        }
                        .frame(width: 48.s, height: 48.s)
                    }
                }
                .padding(.horizontal, 16.w)
                .frame(height: 48.h)
                .padding(.top, 47.h)  // 安全区域顶部距离

                // MARK: - 用户信息区域
                VStack(spacing: 8.h) {
                    // 头像区域
                    Button(action: { activeSheet = .avatarPicker }) {
                        ZStack(alignment: .bottomTrailing) {
                            // 头像容器
                            HStack(spacing: 8.s) {
                                AvatarView(
                                    image: avatarManager.pendingAvatar ?? localAvatarImage,
                                    url: displayUser?.avatarUrl,
                                    size: 100.s,
                                    name: displayUser?.displayName ?? displayUser?.username
                                )
                            }
                            .padding(4.s)
                            .frame(width: 109.s, height: 109.s)
                            .cornerRadius(54.s)
                            .overlay(
                                RoundedRectangle(cornerRadius: 54.s)
                                    .inset(by: 1)
                                    .stroke(.white, lineWidth: 1)
                            )
                            
                            // 添加头像按钮
                            Image("AddAvatar")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24.s, height: 24.s)
                                .offset(x: -4.s, y: -4.s)
                        }
                        .frame(width: 109.s, height: 109.s)
                    }
                    
                    // 用户名 + 位置
                    VStack(spacing: 8.h) {
                        Text(displayUser?.displayName ?? displayUser?.username ?? "User")
                            .font(.custom("SFProDisplay-Regular", size: 16.f).weight(.semibold))
                            .foregroundColor(.white)
                        
                        Text(displayUser?.location?.isEmpty == false ? displayUser!.location! : " ")
                            .font(.custom("SFProDisplay-Regular", size: 14.f).weight(.light))
                            .foregroundColor(.white)
                    }
                    
                    // 职业 + 认证图标
                    HStack(spacing: 4.s) {
                        Text(displayUser?.bio?.isEmpty == false ? displayUser!.bio! : " ")
                            .font(.custom("SFProDisplay-Regular", size: 14.f).weight(.light))
                            .foregroundColor(.white)
                        
                        if displayUser?.safeIsVerified == true {
                            Image("BlueV")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 12.s, height: 12.s)
                        }
                    }
                    
                    // Following / Followers / Halo 统计区域
                    HStack {
                        // Following
                        Button(action: { activeSheet = .following }) {
                            VStack(spacing: 0) {
                                Text("\(displayUser?.safeFollowingCount ?? 0)")
                                    .font(Font.custom("SFProDisplay-Semibold", size: 16.f))
                                    .foregroundColor(.white)
                                Text("Following")
                                    .font(Font.custom("SFProDisplay-Light", size: 14.f))
                                    .foregroundColor(.white)
                            }
                        }
                        
                        Spacer()
                        
                        // 第一条分隔线 (距左124pt, 距右251pt)
                        Rectangle()
                            .fill(.white)
                            .frame(width: 0.5, height: 24.h)
                        
                        Spacer()
                        
                        // Followers
                        Button(action: { activeSheet = .followers }) {
                            VStack(spacing: 0) {
                                Text("\(displayUser?.safeFollowerCount ?? 0)")
                                    .font(Font.custom("SFProDisplay-Semibold", size: 16.f))
                                    .foregroundColor(.white)
                                Text("Followers")
                                    .font(Font.custom("SFProDisplay-Light", size: 14.f))
                                    .foregroundColor(.white)
                            }
                        }
                        
                        Spacer()
                        
                        // 第二条分隔线 (距左251pt, 距右124pt)
                        Rectangle()
                            .fill(.white)
                            .frame(width: 0.5, height: 24.h)
                        
                        Spacer()
                        
                        // Halo
                        VStack(spacing: 0) {
                            Text("\(userPostsManager.postCount)")
                                .font(Font.custom("SFProDisplay-Semibold", size: 16.f))
                                .foregroundColor(.white)
                            Text("Halo")
                                .font(Font.custom("SFProDisplay-Light", size: 14.f))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(EdgeInsets(top: 0, leading: 34.w, bottom: 16.h, trailing: 61.w))
                }
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .background(
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
                
                // 遮罩层
                Rectangle()
                    .foregroundColor(.clear)
                    .background(Color.black.opacity(0.20))
            }
            .clipped()
        )
        .clipped()
    }

    // MARK: - 内容区域
    private var contentSection: some View {
        VStack(spacing: 0) {
            // MARK: - 标签栏
            VStack(alignment: .leading, spacing: 8.h) {
                HStack(spacing: 42.s) {
                    HStack(spacing: 40.s) {
                        Button(action: {
                            profileData.selectedTab = .posts
                            Task {
                                await profileData.loadContent(for: .posts)
                            }
                        }) {
                            Text("Posts")
                                .font(.custom("SFProDisplay-Regular", size: 16.f).weight(.semibold))
                                .foregroundColor(profileData.selectedTab == .posts ? Color(red: 0.87, green: 0.11, blue: 0.26) : .black)
                        }
                        
                        Button(action: {
                            profileData.selectedTab = .saved
                            Task {
                                await profileData.loadContent(for: .saved)
                            }
                        }) {
                            Text("Saved")
                                .font(.custom("SFProDisplay-Regular", size: 16.f).weight(.semibold))
                                .foregroundColor(profileData.selectedTab == .saved ? Color(red: 0.87, green: 0.11, blue: 0.26) : .black)
                        }
                        
                        Button(action: {
                            profileData.selectedTab = .liked
                            Task {
                                await profileData.loadContent(for: .liked)
                            }
                        }) {
                            Text("Liked")
                                .font(.custom("SFProDisplay-Regular", size: 16.f).weight(.semibold))
                                .foregroundColor(profileData.selectedTab == .liked ? Color(red: 0.87, green: 0.11, blue: 0.26) : .black)
                        }
                    }
                    .frame(width: 211.w, height: 24.h)
                }
            }
            .padding(EdgeInsets(top: 12.h, leading: 82.w, bottom: 12.h, trailing: 82.w))
            .frame(maxWidth: .infinity)
            .frame(height: 48.h)
            .background(.white)
            .overlay(
                Rectangle()
                    .inset(by: 0.25)
                    .stroke(Color(red: 0.75, green: 0.75, blue: 0.75), lineWidth: 0.25)
            )

            // MARK: - 帖子网格
            // Posts: 用户发布的帖子 | Saved: 收藏的帖子 | Liked: 点赞的帖子
            if profileData.isLoading && filteredProfilePosts.isEmpty {
                // Skeleton loading state
                ScrollView {
                    ProfilePostsGridSkeleton(itemCount: 6)
                        .padding(.horizontal, 5.s)
                        .padding(.top, 5.s)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.97, green: 0.97, blue: 0.97))
            } else if filteredProfilePosts.isEmpty {
                emptyStateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0.97, green: 0.97, blue: 0.97))
            } else {
                ScrollView {
                    HStack(alignment: .top, spacing: 5.s) {
                        LazyVGrid(columns: [
                            GridItem(.fixed(180.w), spacing: 5.s),
                            GridItem(.fixed(180.w), spacing: 5.s)
                        ], spacing: 5.s) {
                            ForEach(filteredProfilePosts) { post in
                                // Posts tab: 使用当前用户信息（因为是自己的帖子）
                                // Saved/Liked tabs: 使用帖子的作者信息（带后备）
                                let isOwnPost = profileData.selectedTab == .posts
                                let authorName = isOwnPost
                                    ? (displayUser?.displayName ?? displayUser?.username ?? "Me")
                                    : post.displayAuthorName
                                let authorAvatar = isOwnPost
                                    ? displayUser?.avatarUrl
                                    : post.authorAvatarUrl

                                PostCard(
                                    imageUrl: post.displayThumbnailUrl,
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
                    }
                    .padding(5.s)
                    .padding(.bottom, 100.h)  // 底部留出空间给 TabBar
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.97, green: 0.97, blue: 0.97))
            }
        }
    }

    // MARK: - 空状态视图
    private var emptyStateView: some View {
        VStack(spacing: 12.h) {
            Image(systemName: "tray")
                .font(.system(size: 48.f))
                .foregroundColor(.gray)
            Text("No posts yet")
                .font(Font.custom("SFProDisplay-Regular", size: 16.f))
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
            Text("No matching posts found")
                .font(Font.custom("SFProDisplay-Medium", size: 16.f))
                .foregroundColor(.gray)
            Text("Try different keywords")
                .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                .foregroundColor(.gray.opacity(0.7))
        }
        .padding(.top, 60.h)
    }

    // MARK: - 检查相机权限并打开
    private func checkCameraPermissionAndOpen() {
        // 首先检查设备是否有相机
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            print("⚠️ Camera not available on this device")
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // 已授权，直接打开相机
            activeSheet = .camera
        case .notDetermined:
            // 未决定，请求权限
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        activeSheet = .camera
                    } else {
                        showCameraPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            // 已拒绝或受限，显示提示
            showCameraPermissionAlert = true
        @unknown default:
            showCameraPermissionAlert = true
        }
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

            #if DEBUG
            print("[ProfileView] Post deleted successfully: \(post.id)")
            #endif
        } catch {
            #if DEBUG
            print("[ProfileView] Failed to delete post: \(error)")
            #endif
            // 顯示錯誤提示給用戶
            await MainActor.run {
                deleteErrorMessage = "Failed to delete post. Please check your connection and try again."
                showDeleteError = true
            }
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
                        .font(Font.custom("SFProDisplay-Semibold", size: 12.f))
                        .foregroundColor(.black)

                    Text(formattedDate)
                        .font(Font.custom("SFProDisplay-Regular", size: 10.f))
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
                .font(Font.custom("SFProDisplay-Medium", size: 13.f))
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
    // 在 Preview 渲染前设置 mock 数据
    let previewAuthManager = AuthenticationManager.shared
    previewAuthManager.currentUser = PreviewData.Users.currentUser
    previewAuthManager.isAuthenticated = true
    
    return ProfileView(currentPage: .constant(.account))
        .environmentObject(previewAuthManager)
}
