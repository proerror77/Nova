import SwiftUI

struct UserProfileView: View {
    @Binding var showUserProfile: Bool
    let userId: String

    @State private var profileData = ProfileData()
    @State private var selectedTab: ProfileTab = .posts
    @State private var isFollowing = false
    @State private var isCheckingFollowStatus = true

    private let graphService = GraphService()

    private var currentUserId: String? {
        KeychainService.shared.get(.userId)
    }

    enum ProfileTab {
        case posts, saved, liked
    }

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            if profileData.isLoading && profileData.userProfile == nil {
                // Loading state
                VStack {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading profile...")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .padding(.top, 12)
                }
            } else if let error = profileData.errorMessage, profileData.userProfile == nil {
                // Error state
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        Task {
                            await profileData.loadUserProfile(userId: userId)
                        }
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.87, green: 0.11, blue: 0.26))
                    .cornerRadius(20)
                }
                .padding()
            } else {
                // Profile content
                profileContent
            }
        }
        .ignoresSafeArea()
        .task {
            await profileData.loadUserProfile(userId: userId)
            await checkFollowStatus()
        }
    }

    private var profileContent: some View {
        VStack(spacing: 0) {
            // MARK: - 顶部背景区域
            ZStack(alignment: .top) {
                // 背景图片
                if let coverUrl = profileData.userProfile?.coverUrl,
                   let url = URL(string: coverUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        defaultBackground
                    }
                    .frame(height: 500)
                    .clipped()
                    .blur(radius: 20)
                    .overlay(Color.black.opacity(0.3))
                    .ignoresSafeArea(edges: .top)
                } else {
                    defaultBackground
                }

                VStack(spacing: 0) {
                    // MARK: - 顶部导航栏
                    HStack {
                        // 返回按钮
                        Button(action: {
                            showUserProfile = false
                        }) {
                            Image(systemName: "chevron.left")
                                .frame(width: 24, height: 24)
                                .foregroundColor(.white)
                        }

                        Spacer()

                        // 分享按钮
                        Button(action: {
                            profileData.shareProfile()
                        }) {
                            Image(systemName: "square.and.arrow.up")
                                .frame(width: 24, height: 24)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 60)
                    .padding(.bottom, 20)

                    // MARK: - 认证徽章
                    if profileData.userProfile?.safeIsVerified == true {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.blue)

                            Text("Verified Icered Partner")
                                .font(.system(size: 13))
                                .foregroundColor(.white)
                        }
                        .padding(.bottom, 16)
                    }

                    // MARK: - 用户信息区域
                    VStack(spacing: 12) {
                        // 头像
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 110, height: 110)

                            if let avatarUrl = profileData.userProfile?.avatarUrl,
                               let url = URL(string: avatarUrl) {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
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
                        }

                        // 用户名
                        Text(profileData.userProfile?.displayName ?? profileData.userProfile?.username ?? "Unknown")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)

                        // 位置
                        if let location = profileData.userProfile?.location, !location.isEmpty {
                            Text(location)
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                        }

                        // Bio
                        if let bio = profileData.userProfile?.bio, !bio.isEmpty {
                            Text(bio)
                                .font(.system(size: 12, weight: .light))
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .padding(.horizontal, 40)
                        }

                        // MARK: - 统计数据
                        HStack(spacing: 0) {
                            // Following
                            VStack(spacing: 4) {
                                Text("Following")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                                Text("\(profileData.userProfile?.safeFollowingCount ?? 0)")
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
                                Text("\(profileData.userProfile?.safeFollowerCount ?? 0)")
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
                                Text("\(profileData.userProfile?.safePostCount ?? 0)")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 40)
                        .padding(.top, 10)

                        // MARK: - 操作按钮
                        if currentUserId != userId {
                            HStack(spacing: 10) {
                                // Follow/Following 按钮
                                Button(action: {
                                    Task {
                                        if isFollowing {
                                            await profileData.unfollowUser()
                                        } else {
                                            await profileData.followUser()
                                        }
                                        isFollowing.toggle()
                                    }
                                }) {
                                    if isCheckingFollowStatus {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .frame(width: 105, height: 34)
                                    } else {
                                        Text(isFollowing ? "Following" : "Follow")
                                            .font(.system(size: 12))
                                            .foregroundColor(.white)
                                            .frame(width: 105, height: 34)
                                            .background(isFollowing ? Color.gray.opacity(0.5) : Color(red: 0.87, green: 0.11, blue: 0.26))
                                            .cornerRadius(57)
                                    }
                                }
                                .disabled(isCheckingFollowStatus)

                                // Message 按钮
                                Button(action: {
                                    // Message 操作
                                }) {
                                    Text("Message")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white)
                                        .frame(width: 105, height: 34)
                                        .cornerRadius(57)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 57)
                                                .stroke(Color(red: 0.91, green: 0.91, blue: 0.91), lineWidth: 0.5)
                                        )
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(.bottom, 30)
                }
            }
            .frame(height: 500)

            // MARK: - 标签栏
            VStack(spacing: 0) {
                HStack {
                    Spacer()

                    HStack(spacing: 40) {
                        Button(action: {
                            selectedTab = .posts
                            Task {
                                await profileData.loadContent(for: .posts)
                            }
                        }) {
                            Text("Posts")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(selectedTab == .posts ? Color(red: 0.82, green: 0.11, blue: 0.26) : .black)
                        }

                        Button(action: {
                            selectedTab = .saved
                            Task {
                                await profileData.loadContent(for: .saved)
                            }
                        }) {
                            Text("Saved")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(selectedTab == .saved ? Color(red: 0.82, green: 0.11, blue: 0.26) : .black)
                        }

                        Button(action: {
                            selectedTab = .liked
                            Task {
                                await profileData.loadContent(for: .liked)
                            }
                        }) {
                            Text("Liked")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(selectedTab == .liked ? Color(red: 0.82, green: 0.11, blue: 0.26) : .black)
                        }
                    }

                    Spacer()
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
                } else if profileData.currentTabPosts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: emptyStateIcon)
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text(emptyStateText)
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 60)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(profileData.currentTabPosts) { post in
                            UserPostGridCard(post: post)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                }

                Color.clear
                    .frame(height: 20)
            }
            .background(Color(red: 0.96, green: 0.96, blue: 0.96))
        }
    }

    private var defaultBackground: some View {
        Rectangle()
            .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
            .frame(height: 500)
            .clipped()
            .blur(radius: 20)
            .overlay(Color.black.opacity(0.3))
            .ignoresSafeArea(edges: .top)
    }

    private var emptyStateIcon: String {
        switch selectedTab {
        case .posts: return "doc.text"
        case .saved: return "bookmark"
        case .liked: return "heart"
        }
    }

    private var emptyStateText: String {
        switch selectedTab {
        case .posts: return "No posts yet"
        case .saved: return "No saved posts"
        case .liked: return "No liked posts"
        }
    }

    private func checkFollowStatus() async {
        guard let currentId = currentUserId, currentId != userId else {
            isCheckingFollowStatus = false
            return
        }

        do {
            isFollowing = try await graphService.isFollowing(followerId: currentId, followeeId: userId)
        } catch {
            print("Failed to check follow status: \(error)")
            isFollowing = false
        }
        isCheckingFollowStatus = false
    }
}

// MARK: - 用户帖子卡片组件
struct UserPostGridCard: View {
    let post: Post

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部时间信息
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                    .frame(width: 24, height: 24)

                Text(formatTimeAgo(post.createdAt))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            // 图片或内容占位符
            if let mediaUrls = post.mediaUrls, let firstUrl = mediaUrls.first,
               let url = URL(string: firstUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                }
                .frame(height: 200)
                .cornerRadius(8)
                .clipped()
                .padding(.horizontal, 12)
                .padding(.top, 8)
            } else {
                Rectangle()
                    .fill(Color(red: 0.91, green: 0.91, blue: 0.91))
                    .frame(height: 200)
                    .cornerRadius(8)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            // 文字描述
            if !post.content.isEmpty {
                Text(post.content)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.black)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            } else {
                Spacer()
                    .frame(height: 12)
            }
        }
        .background(.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }

    private func formatTimeAgo(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    UserProfileView(showUserProfile: .constant(true), userId: "preview-user-id")
}
