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

    // MARK: - 列表展开/收起状态
    @State private var isFollowersExpanded = false
    @State private var isFollowingExpanded = false
    private let displayLimit = 7  // 默认显示数量

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

    // MARK: - 展开/收起逻辑
    // 是否需要显示 Followers 的 All 按钮
    private var shouldShowFollowersAllButton: Bool {
        filteredFollowers.count > displayLimit
    }

    // 是否需要显示 Following 的 All 按钮
    private var shouldShowFollowingAllButton: Bool {
        filteredFollowing.count > displayLimit
    }

    // 当前显示的 Followers 列表
    private var displayedFollowers: [UserProfileFollowerUser] {
        if !shouldShowFollowersAllButton || isFollowersExpanded {
            return filteredFollowers
        } else {
            return Array(filteredFollowers.prefix(displayLimit))
        }
    }

    // 当前显示的 Following 列表
    private var displayedFollowing: [UserProfileFollowerUser] {
        if !shouldShowFollowingAllButton || isFollowingExpanded {
            return filteredFollowing
        } else {
            return Array(filteredFollowing.prefix(displayLimit))
        }
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
                        .padding(EdgeInsets(top: 14.h, leading: 16.w, bottom: 14.h, trailing: 16.w))

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
                        name: user.fullName,
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
                        name: user.fullName,
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
            // 标题居中
            Text(targetUsername)
                .font(Font.custom("SF Pro Display", size: 18.f).weight(.semibold))
                .foregroundColor(.black)

            // 返回按钮靠左
            HStack {
                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18.f))
                        .foregroundColor(.black)
                }
                .frame(width: 24.s, height: 24.s)

                Spacer()
            }
        }
        .padding(.horizontal, 16.w)
        .frame(height: 54.h)
        .background(Color.white)
    }

    // MARK: - 标签栏
    private var tabBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Following 标签
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = .following
                    }
                }) {
                    VStack(spacing: 14.h) {
                        Text("Following")
                            .font(Font.custom("SF Pro Display", size: 18.f).weight(.semibold))
                            .lineSpacing(20.h)
                            .foregroundColor(selectedTab == .following ? Color(red: 0.87, green: 0.11, blue: 0.26) : Color(red: 0.75, green: 0.75, blue: 0.75))

                        Rectangle()
                            .foregroundColor(.clear)
                            .frame(height: 0)
                            .overlay(
                                Rectangle()
                                    .stroke(selectedTab == .following ? Color(red: 0.87, green: 0.11, blue: 0.26) : Color(red: 0.75, green: 0.75, blue: 0.75), lineWidth: 0.5)
                            )
                    }
                }
                .frame(width: 188.w)

                // Followers 标签
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = .followers
                    }
                }) {
                    VStack(spacing: 14.h) {
                        Text("Followers")
                            .font(Font.custom("SF Pro Display", size: 18.f).weight(.semibold))
                            .lineSpacing(20.h)
                            .foregroundColor(selectedTab == .followers ? Color(red: 0.87, green: 0.11, blue: 0.26) : Color(red: 0.75, green: 0.75, blue: 0.75))

                        Rectangle()
                            .foregroundColor(.clear)
                            .frame(height: 0)
                            .overlay(
                                Rectangle()
                                    .stroke(selectedTab == .followers ? Color(red: 0.87, green: 0.11, blue: 0.26) : Color(red: 0.75, green: 0.75, blue: 0.75), lineWidth: 0.5)
                            )
                    }
                }
                .frame(width: 187.w)
            }

            // 分隔线
            Rectangle()
                .fill(DesignTokens.borderColor)
                .frame(height: 0.5)
        }
    }

    // MARK: - 搜索框
    private var searchBar: some View {
        HStack(spacing: 10.w) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14.f))
                .foregroundColor(Color(red: 0.41, green: 0.41, blue: 0.41))

            TextField("Search", text: $searchText)
                .font(Font.custom("SF Pro Display", size: 14.f))
                .tracking(0.28)
                .foregroundColor(Color(red: 0.41, green: 0.41, blue: 0.41))
        }
        .padding(EdgeInsets(top: 6.h, leading: 12.w, bottom: 6.h, trailing: 12.w))
        .frame(width: 343.w, height: 32.h)
        .background(Color(red: 0.90, green: 0.90, blue: 0.90))
        .cornerRadius(32.s)
    }

    // MARK: - Followers 内容
    private var followersContent: some View {
        VStack(spacing: 0) {
            // All 按钮（仅当粉丝数 > 7 时显示）
            if shouldShowFollowersAllButton {
                HStack {
                    Spacer()
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isFollowersExpanded.toggle()
                        }
                    }) {
                        HStack(spacing: 4.w) {
                            Text("All")
                                .font(Font.custom("SF Pro Display", size: 14.f).weight(.medium))
                                .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                            Image(systemName: isFollowersExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12.f))
                                .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                        }
                    }
                }
                .padding(.horizontal, 16.w)
                .padding(.bottom, 8.h)
            }

            if isLoadingFollowers {
                SkeletonListLoader(itemCount: 5) {
                    UserRowSkeleton()
                }
            } else if filteredFollowers.isEmpty {
                VStack(spacing: 12.h) {
                    Image(systemName: "person.2")
                        .font(.system(size: 48.f))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("No followers yet")
                        .font(Font.custom("SF Pro Display", size: 16.f))
                        .foregroundColor(.gray)
                }
                .padding(.top, 60.h)
            } else {
                ForEach(displayedFollowers) { user in
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
            // All 按钮（仅当关注数 > 7 时显示）
            if shouldShowFollowingAllButton {
                HStack {
                    Spacer()
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isFollowingExpanded.toggle()
                        }
                    }) {
                        HStack(spacing: 4.w) {
                            Text("All")
                                .font(Font.custom("SF Pro Display", size: 14.f).weight(.medium))
                                .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                            Image(systemName: isFollowingExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12.f))
                                .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                        }
                    }
                }
                .padding(.horizontal, 16.w)
                .padding(.bottom, 8.h)
            }

            if isLoadingFollowing {
                SkeletonListLoader(itemCount: 5) {
                    UserRowSkeleton()
                }
            } else if filteredFollowing.isEmpty {
                VStack(spacing: 12.h) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 48.f))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("Not following anyone yet")
                        .font(Font.custom("SF Pro Display", size: 16.f))
                        .foregroundColor(.gray)
                }
                .padding(.top, 60.h)
            } else {
                ForEach(displayedFollowing) { user in
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
        HStack(spacing: 8.w) {
            // 头像
            if let avatarUrl = user.avatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    defaultAvatar
                }
                .frame(width: 50.s, height: 50.s)
                .clipShape(Circle())
            } else {
                defaultAvatar
            }

            // 用户名和认证标记
            HStack(spacing: 4.w) {
                Text(user.name)
                    .font(Font.custom("SF Pro Display", size: 16.f).weight(.heavy))
                    .tracking(0.32)
                    .foregroundColor(.black)

                if user.isVerified {
                    ZStack {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14.f))
                            .foregroundColor(Color(red: 0.2, green: 0.6, blue: 1.0))
                    }
                    .frame(width: 14.s, height: 14.s)
                }
            }

            Spacer()

            // 关注按钮
            actionButton
        }
        .padding(EdgeInsets(top: 10.h, leading: 16.w, bottom: 10.h, trailing: 16.w))
    }

    @ViewBuilder
    private var actionButton: some View {
        Button(action: onFollowTapped) {
            if user.isFollowedByMe {
                Text("Following")
                    .font(Font.custom("SF Pro Display", size: 12.f))
                    .tracking(0.24)
                    .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
            } else {
                Text("Follow")
                    .font(Font.custom("SF Pro Display", size: 12.f))
                    .tracking(0.24)
                    .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
            }
        }
        .buttonStyle(.plain)
        .frame(width: 105.w, height: 34.h)
        .background(Color.white)
        .cornerRadius(57.s)
        .overlay(
            RoundedRectangle(cornerRadius: 57.s)
                .inset(by: 0.5)
                .stroke(user.isFollowedByMe ? Color(red: 0.53, green: 0.53, blue: 0.53) : Color(red: 0.87, green: 0.11, blue: 0.26), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
    }

    private var defaultAvatar: some View {
        Circle()
            .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.5))
            .frame(width: 50.s, height: 50.s)
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
