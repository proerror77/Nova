import SwiftUI
import PhotosUI

struct ProfileView: View {
    @Binding var currentPage: AppPage
    // Use ObservedObject for shared singleton (not StateObject which implies ownership)
    @ObservedObject private var authManager = AuthenticationManager.shared
    @State private var profileData = ProfileData()
    @State private var showNewPost = false
    @State private var showSetting = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showPhotoOptions = false
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var selectedImage: UIImage?

    // Computed property for user display
    private var displayUser: UserProfile? {
        authManager.currentUser ?? profileData.userProfile
    }

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部背景区域
                ZStack(alignment: .top) {
                    // 背景图片
                    Image("Account-background")
                        .resizable()
                        .scaledToFill()
                        .frame(height: 500)
                        .clipped()
                        .blur(radius: 20)
                        .overlay(
                            Color.black.opacity(0.3)
                        )
                        .ignoresSafeArea(edges: .top)

                    VStack(spacing: 0) {
                        // MARK: - 顶部导航栏
                        HStack {
                            // 左侧：用户名 + 下拉箭头
                            HStack(spacing: 8) {
                                Text(displayUser?.displayName ?? displayUser?.username ?? "User")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.white)

                                Image(systemName: "chevron.down")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                            }

                            Spacer()

                            // 右侧：分享和设置图标
                            HStack(spacing: 20) {
                                Button(action: {
                                    profileData.shareProfile()
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
                        .padding(.bottom, 30)

                        // MARK: - 用户信息区域
                        VStack(spacing: 16) {
                            // 头像
                            ZStack(alignment: .bottomTrailing) {
                                // 外圈白色边框
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 110, height: 110)

                                // 头像图片
                                if let avatarUrl = profileData.userProfile?.avatarUrl,
                                   let url = URL(string: avatarUrl) {
                                    AsyncImage(url: url) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } placeholder: {
                                        Circle()
                                            .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                                    }
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                                } else {
                                    Circle()
                                        .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                                        .frame(width: 100, height: 100)
                                }

                                // 加号按钮
                                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                    ZStack {
                                        Circle()
                                            .fill(Color(red: 0.82, green: 0.11, blue: 0.26))
                                            .frame(width: 32, height: 32)

                                        Image(systemName: "plus")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                                .offset(x: -5, y: -5)
                            }

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
                            HStack(spacing: 0) {
                                // Following
                                VStack(spacing: 4) {
                                    Text("Following")
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
                                    Text("Followers")
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
                                    Text("Posts")
                                        .font(.system(size: 16))
                                        .foregroundColor(.white)
                                    Text("\(displayUser?.safePostCount ?? 0)")
                                        .font(.system(size: 16))
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .padding(.horizontal, 40)
                            .padding(.top, 10)

                            // MARK: - 认证徽章
                            if displayUser?.safeIsVerified == true {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.blue)

                                    Text("Verified Icered Partner")
                                        .font(.system(size: 16))
                                        .foregroundColor(.white)
                                }
                                .padding(.top, 8)
                            }
                        }
                        .padding(.bottom, 40)
                    }
                }
                .frame(height: 500)

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
                                Text("Posts")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(profileData.selectedTab == .posts ? Color(red: 0.82, green: 0.11, blue: 0.26) : .black)
                            }

                            Button(action: {
                                profileData.selectedTab = .saved
                                Task {
                                    await profileData.loadContent(for: .saved)
                                }
                            }) {
                                Text("Saved")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(profileData.selectedTab == .saved ? Color(red: 0.82, green: 0.11, blue: 0.26) : .black)
                            }

                            Button(action: {
                                profileData.selectedTab = .liked
                                Task {
                                    await profileData.loadContent(for: .liked)
                                }
                            }) {
                                Text("Liked")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(profileData.selectedTab == .liked ? Color(red: 0.82, green: 0.11, blue: 0.26) : .black)
                            }
                        }

                        Spacer()

                        Button(action: {
                            Task {
                                await profileData.searchInProfile(query: "")
                            }
                        }) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 20))
                                .foregroundColor(.black)
                        }
                        .padding(.trailing, 20)
                    }
                    .padding(.vertical, 16)
                    .background(.white)

                    // 分隔线
                    Rectangle()
                        .fill(Color(red: 0.74, green: 0.74, blue: 0.74))
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
                .background(Color(red: 0.96, green: 0.96, blue: 0.96))
            }
            .overlay(alignment: .bottom) {
                // MARK: - 底部导航栏
                HStack(spacing: -20) {
                    // Home
                    VStack(spacing: 2) {
                        Image("home-icon-black")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 22)
                        Text("Home")
                            .font(.system(size: 9))
                            .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        currentPage = .home
                    }

                    // Message
                    VStack(spacing: 4) {
                        Image("Message-icon-black")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                        Text("Message")
                            .font(.system(size: 9))
                            .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        currentPage = .message
                    }

                    // New Post
                    NewPostButtonComponent(showNewPost: $showPhotoOptions)

                    // Alice
                    VStack(spacing: -12) {
                        Image("alice-button-off")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                        Text("")
                            .font(.system(size: 9))
                    }
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        currentPage = .alice
                    }

                    // Account (高亮状态)
                    VStack(spacing: -12) {
                        Image("Account-button-on")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                        Text("")
                            .font(.system(size: 9))
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 60)
                .padding(.bottom, 20)
                .background(Color.white)
                .border(Color(red: 0.74, green: 0.74, blue: 0.74), width: 0.5)
            }

            // MARK: - 照片选项弹窗
            if showPhotoOptions {
                photoOptionsModal
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(sourceType: .photoLibrary, selectedImage: $selectedImage)
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera, selectedImage: $selectedImage)
        }
        .onChange(of: selectedPhotoItem) { oldValue, newValue in
            Task {
                if let photoItem = newValue,
                   let data = try? await photoItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await profileData.uploadAvatar(image: image)
                }
            }
        }
        .task {
            // Use current user from AuthenticationManager
            if let userId = authManager.currentUser?.id {
                await profileData.loadUserProfile(userId: userId)
            }
        }
        .sheet(isPresented: $showNewPost) {
            NewPostView(showNewPost: $showNewPost)
        }
    }

    // MARK: - 照片选项弹窗
    private var photoOptionsModal: some View {
        ZStack {
            // 半透明背景遮罩
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    showPhotoOptions = false
                }

            // 弹窗内容
            VStack {
                Spacer()

                ZStack() {
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 375, height: 270)
                        .background(.white)
                        .cornerRadius(11)
                        .offset(x: 0, y: 0)
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 56, height: 7)
                        .background(Color(red: 0.82, green: 0.11, blue: 0.26))
                        .cornerRadius(3.50)
                        .offset(x: -0.50, y: -120.50)

                    // Choose Photo
                    Button(action: {
                        showPhotoOptions = false
                        showImagePicker = true
                    }) {
                        Text("Choose Photo")
                            .font(Font.custom("Helvetica Neue", size: 18).weight(.medium))
                            .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18))
                    }
                    .offset(x: 0, y: -79)

                    // Take Photo
                    Button(action: {
                        showPhotoOptions = false
                        showCamera = true
                    }) {
                        Text("Take Photo")
                            .font(Font.custom("Helvetica Neue", size: 18).weight(.medium))
                            .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18))
                    }
                    .offset(x: 0.50, y: -21)

                    // Generate image
                    Button(action: {
                        // 生成图片操作
                        showPhotoOptions = false
                    }) {
                        Text("Generate image")
                            .font(Font.custom("Helvetica Neue", size: 18).weight(.medium))
                            .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18))
                    }
                    .offset(x: 0, y: 37)

                    // Cancel
                    Button(action: {
                        showPhotoOptions = false
                    }) {
                        Text("Cancel")
                            .font(Font.custom("Helvetica Neue", size: 18).weight(.medium))
                            .lineSpacing(20)
                            .foregroundColor(.black)
                    }
                    .offset(x: -0.50, y: 105)

                    // 分隔线
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 375, height: 0)
                        .overlay(
                            Rectangle()
                                .stroke(Color(red: 0.93, green: 0.93, blue: 0.93), lineWidth: 3)
                        )
                        .offset(x: 0, y: 75)
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 375, height: 0)
                        .overlay(
                            Rectangle()
                                .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.20)
                        )
                        .offset(x: 0, y: -50)
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 375, height: 0)
                        .overlay(
                            Rectangle()
                                .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.20)
                        )
                        .offset(x: 0, y: 8)
                }
                .frame(width: 375, height: 270)
                .padding(.bottom, 50)
            }
        }
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
                    .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
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
                .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
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
}
