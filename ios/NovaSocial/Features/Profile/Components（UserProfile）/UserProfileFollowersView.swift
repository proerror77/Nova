import SwiftUI

/// UserProfile 关注者页面 - 显示其他用户的关注者列表
struct UserProfileFollowersView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var authManager: AuthenticationManager

    // 要查看的用户信息
    let targetUserId: String
    let targetUsername: String

    // 当前选中的标签
    @State private var selectedTab: Tab = .followers
    @State private var searchText: String = ""

    // MARK: - 数据状态
    @State private var followers: [UserProfileFollowerUser] = []
    @State private var following: [UserProfileFollowerUser] = []
    @State private var isLoadingFollowers = false
    @State private var isLoadingFollowing = false
    @State private var followersHasMore = false
    @State private var followingHasMore = false

    // MARK: - Services
    private let graphService = GraphService()
    private let userService = UserService.shared

    enum Tab {
        case following
        case followers
    }

    // 过滤后的关注者列表
    private var filteredFollowers: [UserProfileFollowerUser] {
        if searchText.isEmpty {
            return followers
        }
        return followers.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // 过滤后的关注列表
    private var filteredFollowing: [UserProfileFollowerUser] {
        if searchText.isEmpty {
            return following
        }
        return following.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - 顶部导航栏
            navigationBar

            // MARK: - 标签栏
            tabBar

            // MARK: - 内容区域
            ScrollView {
                VStack(spacing: 0) {
                    // 搜索框
                    searchBar
                        .padding(.horizontal, 13)
                        .padding(.top, 12)

                    if selectedTab == .followers {
                        followersContent
                    } else {
                        followingContent
                    }
                }
            }
        }
        .background(Color.white)
        .task {
            await loadInitialData()
        }
    }

    // MARK: - 加载初始数据
    private func loadInitialData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await loadFollowers() }
            group.addTask { await loadFollowing() }
        }
    }

    // MARK: - 加载 Followers 列表（关注目标用户的人）
    private func loadFollowers() async {
        isLoadingFollowers = true

        do {
            // 1. 获取关注目标用户的用户 ID 列表（包含关系状态）
            let result = try await graphService.getFollowers(userId: targetUserId, limit: 50, offset: 0)
            followersHasMore = result.hasMore

            // 2. 批量获取用户详细信息
            let users = await fetchUserProfiles(userIds: result.userIds)

            // 3. 使用后端返回的关系状态（无需额外 API 调用）
            await MainActor.run {
                followers = users.map { user in
                    // 从后端返回的 users 数组中获取关系状态
                    let status = result.relationshipStatus(for: user.id)
                    return UserProfileFollowerUser(
                        id: user.id,
                        name: user.displayName ?? user.username,
                        avatarUrl: user.avatarUrl,
                        isVerified: user.safeIsVerified,
                        isFollowedByMe: status?.youAreFollowing ?? false
                    )
                }
                isLoadingFollowers = false
            }

            #if DEBUG
            print("[UserProfileFollowers] Loaded \(followers.count) followers for user: \(targetUserId) (enriched: \(result.users?.count ?? 0))")
            #endif

        } catch {
            #if DEBUG
            print("[UserProfileFollowers] Failed to load followers: \(error)")
            #endif
            await MainActor.run {
                isLoadingFollowers = false
            }
        }
    }

    // MARK: - 加载 Following 列表（目标用户关注的人）
    private func loadFollowing() async {
        isLoadingFollowing = true

        do {
            // 1. 获取目标用户关注的用户 ID 列表（包含关系状态）
            let result = try await graphService.getFollowing(userId: targetUserId, limit: 50, offset: 0)
            followingHasMore = result.hasMore

            // 2. 批量获取用户详细信息
            let users = await fetchUserProfiles(userIds: result.userIds)

            // 3. 使用后端返回的关系状态（无需额外 API 调用）
            await MainActor.run {
                following = users.map { user in
                    // 从后端返回的 users 数组中获取关系状态
                    let status = result.relationshipStatus(for: user.id)
                    return UserProfileFollowerUser(
                        id: user.id,
                        name: user.displayName ?? user.username,
                        avatarUrl: user.avatarUrl,
                        isVerified: user.safeIsVerified,
                        isFollowedByMe: status?.youAreFollowing ?? false
                    )
                }
                isLoadingFollowing = false
            }

            #if DEBUG
            print("[UserProfileFollowers] Loaded \(following.count) following for user: \(targetUserId) (enriched: \(result.users?.count ?? 0))")
            #endif

        } catch {
            #if DEBUG
            print("[UserProfileFollowers] Failed to load following: \(error)")
            #endif
            await MainActor.run {
                isLoadingFollowing = false
            }
        }
    }

    // MARK: - 批量获取用户资料
    private func fetchUserProfiles(userIds: [String]) async -> [UserProfile] {
        var profiles: [UserProfile] = []

        await withTaskGroup(of: UserProfile?.self) { group in
            for userId in userIds {
                group.addTask {
                    try? await self.userService.getUser(userId: userId)
                }
            }

            for await profile in group {
                if let profile = profile {
                    profiles.append(profile)
                }
            }
        }

        return profiles
    }

    // MARK: - 关注/取消关注用户
    private func toggleFollow(user: UserProfileFollowerUser) async {
        guard let currentUserId = authManager.currentUser?.id else { return }

        do {
            if user.isFollowedByMe {
                try await graphService.unfollowUser(followerId: currentUserId, followeeId: user.id)
            } else {
                try await graphService.followUser(followerId: currentUserId, followeeId: user.id)
            }

            // 更新本地状态
            await MainActor.run {
                if let index = followers.firstIndex(where: { $0.id == user.id }) {
                    followers[index].isFollowedByMe.toggle()
                }
                if let index = following.firstIndex(where: { $0.id == user.id }) {
                    following[index].isFollowedByMe.toggle()
                }
            }
        } catch {
            #if DEBUG
            print("[UserProfileFollowers] Failed to toggle follow: \(error)")
            #endif
        }
    }

    // MARK: - 导航栏
    private var navigationBar: some View {
        ZStack {
            // 标题
            Text(targetUsername)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(.black)

            // 返回按钮
            HStack {
                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.black)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 56)
        .background(Color.white)
    }

    // MARK: - 标签栏
    private var tabBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 100) {
                // Following 标签
                Button(action: {
                    selectedTab = .following
                }) {
                    Text("Following")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(selectedTab == .following ? .black : Color(red: 0.51, green: 0.51, blue: 0.51))
                }

                // Followers 标签
                Button(action: {
                    selectedTab = .followers
                }) {
                    Text("Followers")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(selectedTab == .followers ? .black : Color(red: 0.51, green: 0.51, blue: 0.51))
                }
            }
            .frame(height: 44)

            // 底部指示线
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color(red: 0.81, green: 0.13, blue: 0.25))
                    .frame(width: geometry.size.width / 2, height: 2)
                    .offset(x: selectedTab == .followers ? geometry.size.width / 2 : 0)
                    .animation(.easeInOut(duration: 0.2), value: selectedTab)
            }
            .frame(height: 2)

            // 分隔线
            Rectangle()
                .fill(DesignTokens.borderColor)
                .frame(height: 0.5)
        }
    }

    // MARK: - 搜索框
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

            TextField("Search", text: $searchText)
                .font(.system(size: 14))
                .foregroundColor(.black)
        }
        .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .frame(height: 32)
        .background(Color(red: 0.91, green: 0.91, blue: 0.91))
        .cornerRadius(32)
    }

    // MARK: - Followers 内容
    private var followersContent: some View {
        VStack(spacing: 0) {
            if isLoadingFollowers {
                SkeletonListLoader(itemCount: 5) {
                    AnyView(UserRowSkeleton())
                }
            } else if filteredFollowers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.2")
                        .font(.system(size: 48))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("No followers yet")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                }
                .padding(.top, 60)
            } else {
                ForEach(filteredFollowers) { user in
                    UserProfileFollowerRow(
                        user: user,
                        onFollowTapped: {
                            Task {
                                await toggleFollow(user: user)
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Following 内容
    private var followingContent: some View {
        VStack(spacing: 0) {
            if isLoadingFollowing {
                SkeletonListLoader(itemCount: 5) {
                    AnyView(UserRowSkeleton())
                }
            } else if filteredFollowing.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("Not following anyone yet")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                }
                .padding(.top, 60)
            } else {
                ForEach(filteredFollowing) { user in
                    UserProfileFollowerRow(
                        user: user,
                        onFollowTapped: {
                            Task {
                                await toggleFollow(user: user)
                            }
                        }
                    )
                }
            }
        }
    }
}

// MARK: - 用户数据模型
struct UserProfileFollowerUser: Identifiable {
    let id: String
    let name: String
    let avatarUrl: String?
    let isVerified: Bool
    var isFollowedByMe: Bool  // 当前登录用户是否关注了此用户

    init(id: String = UUID().uuidString, name: String, avatarUrl: String? = nil, isVerified: Bool = false, isFollowedByMe: Bool = false) {
        self.id = id
        self.name = name
        self.avatarUrl = avatarUrl
        self.isVerified = isVerified
        self.isFollowedByMe = isFollowedByMe
    }
}

// MARK: - 用户行组件
struct UserProfileFollowerRow: View {
    let user: UserProfileFollowerUser
    var onFollowTapped: () -> Void = {}

    var body: some View {
        HStack(spacing: 13) {
            // 头像
            if let avatarUrl = user.avatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                    .frame(width: 50, height: 50)
            }

            // 用户名和认证标记
            HStack(spacing: 6) {
                Text(user.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)

                if user.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 0.20, green: 0.60, blue: 0.86))
                }
            }

            Spacer()

            // 关注按钮
            Button(action: onFollowTapped) {
                if user.isFollowedByMe {
                    Text("Following")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white)
                        .cornerRadius(100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 100)
                                .stroke(Color(red: 0.53, green: 0.53, blue: 0.53), lineWidth: 0.5)
                        )
                } else {
                    Text("Follow")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.87, green: 0.11, blue: 0.26))
                        .cornerRadius(46)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Previews

#Preview("UserProfileFollowers") {
    UserProfileFollowersView(
        isPresented: .constant(true),
        targetUserId: "user-123",
        targetUsername: "Juliette"
    )
    .environmentObject(AuthenticationManager.shared)
}
