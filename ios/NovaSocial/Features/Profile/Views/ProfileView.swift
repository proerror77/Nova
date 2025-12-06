import SwiftUI
import PhotosUI

struct ProfileView: View {
    @Binding var currentPage: AppPage
    // 全局认证状态从上层注入
    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var profileData = ProfileData()
    @State private var showNewPost = false
    @State private var showSetting = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showPhotoOptions = false
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var selectedImage: UIImage?
    @State private var showGenerateImage = false
    @State private var showWrite = false
    @State private var showShareSheet = false
    @State private var localAvatarImage: UIImage? = nil  // 本地选择的头像

    // Access AvatarManager
    @StateObject private var avatarManager = AvatarManager.shared


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
                NewPostView(showNewPost: $showNewPost, initialImage: selectedImage)
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
        .onChange(of: selectedPhotoItem) { oldValue, newValue in
            Task {
                if let photoItem = newValue,
                   let data = try? await photoItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    // 立即显示选中的照片
                    localAvatarImage = image
                    // 同时保存到 AvatarManager
                    avatarManager.savePendingAvatar(image)
                    // 后台上传到服务器
                    await profileData.uploadAvatar(image: image)
                }
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
        }
        .task {
            // Use current user from AuthenticationManager
            if let userId = authManager.currentUser?.id {
                await profileData.loadUserProfile(userId: userId)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            NovaShareSheet(items: shareItems)
        }
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
                // MARK: - 顶部导航栏
                HStack {
                    Spacer()

                    // 右侧：分享和设置图标
                    HStack(spacing: 20) {
                        Button(action: {
                            showShareSheet = true
                        }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 22))
                                .foregroundColor(.white)
                        }

                        Button(action: {
                            currentPage = .setting
                        }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 22))
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .padding(.bottom, 40)

                        // MARK: - 用户信息区域
                        VStack(spacing: 16) {
                            // 头像（居中显示）
                            ZStack(alignment: .bottomTrailing) {
                                // 头像图片 - 优先级：CreateAccount 选择的头像 > 本地选择 > 服务器头像 > 占位符
                                if let pendingAvatar = avatarManager.pendingAvatar {
                                    // 1. 优先显示 CreateAccount 页面选择的头像
                                    Image(uiImage: pendingAvatar)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(Circle())
                                } else if let localImage = localAvatarImage {
                                    // 2. 显示本地选择的照片
                                    Image(uiImage: localImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(Circle())
                                } else if let avatarUrl = profileData.userProfile?.avatarUrl,
                                          let url = URL(string: avatarUrl) {
                                    // 3. 显示服务器上的头像
                                    AsyncImage(url: url) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } placeholder: {
                                        Circle()
                                            .fill(DesignTokens.avatarPlaceholder)
                                    }
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                                } else {
                                    // 4. 默认占位符
                                    Circle()
                                        .fill(DesignTokens.avatarPlaceholder)
                                        .frame(width: 100, height: 100)
                                }

                                // 加号按钮（右下角）
                                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                    ZStack {
                                        Circle()
                                            .fill(DesignTokens.accentColor)
                                            .frame(width: 32, height: 32)

                                        Image(systemName: "plus")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                                .offset(x: 0, y: 0)
                            }
                            .frame(maxWidth: .infinity)  // 居中到整个页面

                            // 用户名
                            Text(displayUser?.displayName ?? displayUser?.username ?? "User")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)

                            // 位置
                            if let location = displayUser?.location, !location.isEmpty {
                                Text(location)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                            }

                            // 简介/职位
                            if let bio = displayUser?.bio, !bio.isEmpty {
                                Text(bio)
                                    .font(.system(size: 14, weight: .light))
                                    .foregroundColor(.white.opacity(0.9))
                            }

                            // MARK: - 统计数据
                                HStack(spacing: 10) {
                                // Following
                                VStack(spacing: 4) {
                                    Text(LocalizedStringKey("Following"))
                                        .font(.system(size: 16))
                                        .foregroundColor(.white)
                                    Text("\(displayUser?.safeFollowingCount ?? 0)")
                                        .font(.system(size: 16))
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)

                                // 分隔线
                                Rectangle()
                                    .fill(.white)
                                    .frame(width: 1, height: 30)

                                // Followers
                                VStack(spacing: 4) {
                                    Text(LocalizedStringKey("Followers"))
                                        .font(.system(size: 16))
                                        .foregroundColor(.white)
                                    Text("\(displayUser?.safeFollowerCount ?? 0)")
                                        .font(.system(size: 16))
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)

                                // 分隔线
                                Rectangle()
                                    .fill(.white)
                                    .frame(width: 1, height: 30)

                                // Posts
                                VStack(spacing: 4) {
                                    Text(LocalizedStringKey("Likes"))
                                        .font(.system(size: 16))
                                        .foregroundColor(.white)
                                    Text("\(displayUser?.safePostCount ?? 0)")
                                        .font(.system(size: 16))
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .padding(.horizontal, 40)
                            .padding(.top, 45)

                            // MARK: - 认证徽章
                            if displayUser?.safeIsVerified == true {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.blue)

                                    Text(LocalizedStringKey("Verified_partner"))
                                        .font(.system(size: 16))
                                        .foregroundColor(.white)
                                }
                                .padding(.top, 8)
                            }
                        }
                        .padding(.bottom, 10)
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
                    if profileData.isLoading {
                        ProgressView()
                            .padding(.top, 40)
                    } else if profileData.hasContent {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(profileData.currentTabPosts) { post in
                                PostGridCard(post: post)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                    } else {
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

                    Color.clear
                        .frame(height: 100)
                }
                .background(DesignTokens.backgroundColor)
        }
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
