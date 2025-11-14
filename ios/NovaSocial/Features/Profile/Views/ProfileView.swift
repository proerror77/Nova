import SwiftUI
import PhotosUI

struct ProfileView: View {
    @Binding var currentPage: AppPage
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showNewPost = false
    @State private var showSetting = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            if showNewPost {
                NewPostView(showNewPost: $showNewPost)
                    .transition(.identity)
            } else {
                accountContent
            }
        }
    }

    private var accountContent: some View {
        ZStack {
            // MARK: - 背景色
            Color(red: 0.97, green: 0.96, blue: 0.96)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 个人资料区域（带背景图）
                ZStack(alignment: .top) {
                    // 背景图片区域
                    ZStack {
                        // 降级方案：如果图片加载失败，显示颜色背景
                        Rectangle()
                            .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))

                        // 真实图片
                        Image("Account-background")
                            .resizable()
                            .scaledToFill()
                    }
                    .frame(height: 460)
                    .clipped()
                    .overlay(
                        Color.black.opacity(0.30)  // 半透明黑色遮罩，让文字更清晰
                    )
                    .ignoresSafeArea(edges: .top)

                    VStack(spacing: 0) {
                        // MARK: - 顶部导航栏
                        HStack {
                            HStack(spacing: 11) {
                                Text(viewModel.userProfile?.displayName ?? viewModel.userProfile?.username ?? "Loading...")
                                    .font(Font.custom("Helvetica Neue", size: 21).weight(.medium))
                                    .foregroundColor(.white)

                                Image(systemName: "chevron.down")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                            }

                            Spacer()

                            HStack(spacing: 19) {
                                Button(action: {
                                    viewModel.shareProfile()
                                }) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                }

                                Button(action: {
                                    showSetting = true
                                }) {
                                    Image(systemName: "gearshape")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .frame(height: DesignTokens.topBarHeight)
                        .padding(.horizontal, 16)
                        .padding(.top, -10)
                        .padding(.bottom, 10)  // 👈 调整这个数值来控制顶部导航栏和头像之间的距离

                        // MARK: - 个人资料信息
                        VStack(spacing: 20) {
                            VStack(spacing: 13) {
                                // 头像
                                ZStack {
                                    Circle()
                                        .fill(.white)
                                        .frame(width: 140, height: 140)

                                    // 头像图片
                                    if let avatarUrl = viewModel.userProfile?.avatarUrl,
                                       let url = URL(string: avatarUrl) {
                                        AsyncImage(url: url) { image in
                                            image
                                                .resizable()
                                                .scaledToFill()
                                        } placeholder: {
                                            Circle()
                                                .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                                        }
                                        .frame(width: 136, height: 136)
                                        .clipShape(Circle())
                                    } else {
                                        Circle()
                                            .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                                            .frame(width: 136, height: 136)
                                    }

                                    // + 号按钮 - 上传头像
                                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                        ZStack {
                                            Circle()
                                                .fill(Color(red: 0.82, green: 0.11, blue: 0.26))
                                                .frame(width: 35, height: 35)

                                            Image(systemName: "plus")
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .offset(x: 45, y: 45)
                                }

                                // 用户名和位置
                                Text(viewModel.userProfile?.displayName ?? viewModel.userProfile?.username ?? "")
                                    .font(Font.custom("Helvetica Neue", size: 21).weight(.bold))
                                    .foregroundColor(.white)

                                if let location = viewModel.userProfile?.location {
                                    Text(location)
                                        .font(Font.custom("Helvetica Neue", size: 14))
                                        .foregroundColor(.white)
                                }
                            }

                            // MARK: - 统计数据
                            HStack(spacing: 0) {
                                // Following
                                VStack(spacing: 1) {
                                    Text("Following")
                                        .font(Font.custom("Helvetica Neue", size: 16.50))
                                        .foregroundColor(.white)
                                    Text("\(viewModel.userProfile?.followingCount ?? 0)")
                                        .font(Font.custom("Helvetica Neue", size: 16.50))
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)

                                // 分隔线
                                Rectangle()
                                    .fill(.white)
                                    .frame(width: 0.25, height: 26)

                                // Followers
                                VStack(spacing: 1) {
                                    Text("Followers")
                                        .font(Font.custom("Helvetica Neue", size: 16.50))
                                        .foregroundColor(.white)
                                    Text("\(viewModel.userProfile?.followerCount ?? 0)")
                                        .font(Font.custom("Helvetica Neue", size: 16.50))
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)

                                // 分隔线
                                Rectangle()
                                    .fill(.white)
                                    .frame(width: 0.25, height: 26)

                                // Posts
                                VStack(spacing: 1) {
                                    Text("Posts")
                                        .font(Font.custom("Helvetica Neue", size: 16.50))
                                        .foregroundColor(.white)
                                    Text("\(viewModel.userProfile?.postCount ?? 0)")
                                        .font(Font.custom("Helvetica Neue", size: 16.50))
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .padding(.horizontal, 5)
                        }
                        .padding(.bottom, 45)
                    }
                }

                // MARK: - 内容区域
                VStack(spacing: 0) {
                    // MARK: - 标签栏
                    HStack {
                        Spacer()

                        HStack(spacing: 42) {
                            Button(action: {
                                viewModel.selectedTab = .posts
                                Task {
                                    await viewModel.loadContent(for: .posts)
                                }
                            }) {
                                Text("Posts")
                                    .font(Font.custom("Helvetica Neue", size: 16.50).weight(.bold))
                                    .foregroundColor(viewModel.selectedTab == .posts ? Color(red: 0.82, green: 0.11, blue: 0.26) : .black)
                            }

                            Button(action: {
                                viewModel.selectedTab = .saved
                                Task {
                                    await viewModel.loadContent(for: .saved)
                                }
                            }) {
                                Text("Saved")
                                    .font(Font.custom("Helvetica Neue", size: 16.50).weight(.bold))
                                    .foregroundColor(viewModel.selectedTab == .saved ? Color(red: 0.82, green: 0.11, blue: 0.26) : .black)
                            }

                            Button(action: {
                                viewModel.selectedTab = .liked
                                Task {
                                    await viewModel.loadContent(for: .liked)
                                }
                            }) {
                                Text("Liked")
                                    .font(Font.custom("Helvetica Neue", size: 16.50).weight(.bold))
                                    .foregroundColor(viewModel.selectedTab == .liked ? Color(red: 0.82, green: 0.11, blue: 0.26) : .black)
                            }
                        }

                        Spacer()

                        Button(action: {
                            Task {
                                await viewModel.searchInProfile(query: "")
                            }
                        }) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 20))
                                .foregroundColor(.black)
                        }
                        .padding(.trailing, 20)
                    }
                    .padding(.leading, 20)
                    .padding(.vertical, -48)
                    .background(Color(red: 0.96, green: 0.96, blue: 0.96))

                    // MARK: - 图片网格
                    ScrollView {
                        VStack(spacing: 0) {
                            if viewModel.isLoading {
                                ProgressView()
                                    .padding(.top, 40)
                            } else if viewModel.hasContent {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                    ForEach(viewModel.currentTabPosts) { post in
                                        PostGridItem(post: post)
                                    }
                                }
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

                            // 👇 调整这里的高度来控制白色区域的大小
                            Color.clear
                                .frame(height: 150)
                        }
                    }
                    .background(Color(red: 0.96, green: 0.96, blue: 0.96))
                }
                .padding(.bottom, -43)

                // MARK: - 底部导航栏
                HStack(spacing: -20) {
                    // Home
                    VStack(spacing: 2) {
                        Image("home-icon-black")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 22)
                        Text("Home")
                            .font(.system(size: 9, weight: .medium))
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
                    NewPostButtonComponent(showNewPost: $showNewPost)

                    // Alice
                    VStack(spacing: -12) {
                        Image("alice-icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                        Text("")
                            .font(.system(size: 9))
                    }
                    .frame(maxWidth: .infinity)

                    // Account (高亮状态)
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .stroke(Color(red: 0.81, green: 0.13, blue: 0.25), lineWidth: 1)
                                .frame(width: 30, height: 30)

                            Image("Account-icon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                        }

                        Text("Account")
                            .font(.system(size: 9))
                            .foregroundColor(Color(red: 0.81, green: 0.13, blue: 0.25))
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 60)
                .padding(.bottom, 20)
                .background(Color.white)
                .border(Color(red: 0.74, green: 0.74, blue: 0.74), width: 0.5)
                .offset(y: 35)
            }
        }
        .onChange(of: selectedPhotoItem) { oldValue, newValue in
            Task {
                if let photoItem = newValue,
                   let data = try? await photoItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await viewModel.uploadAvatar(image: image)
                }
            }
        }
        .task {
            // TODO: Get current user ID from authentication service
            await viewModel.loadUserProfile(userId: "current_user_id")
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }
}

// MARK: - 图片网格项组件
struct PostGridItem: View {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 用户信息
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(post.creatorId)
                        .font(Font.custom("Helvetica Neue", size: 12).weight(.semibold))
                        .foregroundColor(.black)

                    Text(formattedDate)
                        .font(Font.custom("Helvetica Neue", size: 10))
                        .foregroundColor(Color(red: 0.60, green: 0.60, blue: 0.60))
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            // 图片占位符（后续可以从 media_urls 加载）
            Rectangle()
                .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                .aspectRatio(1, contentMode: .fill)
                .clipped()
                .cornerRadius(12)
                .padding(.horizontal, 12)

            // 帖子内容
            Text(post.content)
                .font(Font.custom("Helvetica Neue", size: 13).weight(.medium))
                .foregroundColor(.black)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
        }
        .background(Color.white)
        .cornerRadius(12)
    }
}

#Preview {
    ProfileView(currentPage: .constant(.account))
}
