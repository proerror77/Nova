import SwiftUI

// MARK: - Tab Selection
enum UserProfileFollowTab {
    case following
    case followers
}

/// UserProfile 关注页面 - 显示其他用户的关注列表
struct UserProfileFollowingView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var authManager: AuthenticationManager

    // 要查看的用户信息
    let targetUserId: String
    let targetUsername: String
    let initialTab: UserProfileFollowTab

    @State private var selectedTab: UserProfileFollowTab = .following
    @State private var searchText: String = ""
    @State private var followingUsers: [UserProfileFollowUser] = []
    @State private var followerUsers: [UserProfileFollowUser] = []
    @State private var isLoadingFollowing = false
    @State private var isLoadingFollowers = false
    @State private var followingHasMore = false
    @State private var followersHasMore = false

    // MARK: - 列表展开/收起状态
    @State private var isFollowersExpanded = false
    @State private var isFollowingExpanded = false
    private let displayLimit = 7  // 默认显示数量

    // MARK: - Services
    private let graphService = GraphService()
    private let userService = UserService.shared

    init(isPresented: Binding<Bool>, targetUserId: String, targetUsername: String, initialTab: UserProfileFollowTab = .following) {
        self._isPresented = isPresented
        self.targetUserId = targetUserId
        self.targetUsername = targetUsername
        self.initialTab = initialTab
        self._selectedTab = State(initialValue: initialTab)
    }

    // MARK: - Filtered Users
    private var filteredFollowing: [UserProfileFollowUser] {
        if searchText.isEmpty {
            return followingUsers
        }
        return followingUsers.filter { user in
            user.displayName.localizedCaseInsensitiveContains(searchText) ||
            user.username.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredFollowers: [UserProfileFollowUser] {
        if searchText.isEmpty {
            return followerUsers
        }
        return followerUsers.filter { user in
            user.displayName.localizedCaseInsensitiveContains(searchText) ||
            user.username.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - 展开/收起逻辑
    // 是否需要显示 Following 的 All 按钮
    private var shouldShowFollowingAllButton: Bool {
        filteredFollowing.count > displayLimit
    }

    // 是否需要显示 Followers 的 All 按钮
    private var shouldShowFollowersAllButton: Bool {
        filteredFollowers.count > displayLimit
    }

    // 当前显示的 Following 列表
    private var displayedFollowing: [UserProfileFollowUser] {
        if !shouldShowFollowingAllButton || isFollowingExpanded {
            return filteredFollowing
        } else {
            return Array(filteredFollowing.prefix(displayLimit))
        }
    }

    // 当前显示的 Followers 列表
    private var displayedFollowers: [UserProfileFollowUser] {
        if !shouldShowFollowersAllButton || isFollowersExpanded {
            return filteredFollowers
        } else {
            return Array(filteredFollowers.prefix(displayLimit))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Top Navigation Bar
            topNavigationBar

            // MARK: - Tab Selector
            tabSelector

            // MARK: - Search Bar
            searchBar
                .padding(EdgeInsets(top: 14.h, leading: 16.w, bottom: 14.h, trailing: 16.w))

            // MARK: - User List
            ScrollView {
                if selectedTab == .following {
                    followingContent
                } else {
                    followersContent
                }
            }

            Spacer()
        }
        .background(Color.white)
        .task {
            await loadInitialData()
        }
    }

    // MARK: - 加载初始数据
    private func loadInitialData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await loadFollowing() }
            group.addTask { await loadFollowers() }
        }
    }

    // MARK: - 加载 Following 列表（目标用户关注的人）
    private func loadFollowing() async {
        isLoadingFollowing = true

        do {
            // 1. 获取目标用户关注的用户 ID 列表
            let result = try await graphService.getFollowing(userId: targetUserId, limit: 50, offset: 0)
            followingHasMore = result.hasMore

            // 2. 批量获取用户详细信息
            let users = await fetchUserProfiles(userIds: result.userIds)

            // 3. 检查当前用户是否关注了这些用户
            var followingStatus: [String: Bool] = [:]
            if let currentUserId = authManager.currentUser?.id {
                followingStatus = (try? await graphService.batchCheckFollowing(
                    followerId: currentUserId,
                    followeeIds: result.userIds
                )) ?? [:]
            }

            // 4. 转换为 UserProfileFollowUser 模型
            await MainActor.run {
                followingUsers = users.map { user in
                    let isFollowingThem = followingStatus[user.id] ?? false
                    return UserProfileFollowUser(
                        id: user.id,
                        username: user.username,
                        displayName: user.displayName ?? user.username,
                        avatarUrl: user.avatarUrl,
                        isVerified: user.safeIsVerified,
                        isFollowedByMe: isFollowingThem
                    )
                }
                isLoadingFollowing = false
            }

            #if DEBUG
            print("[UserProfileFollowing] Loaded \(followingUsers.count) following users for: \(targetUserId)")
            #endif

        } catch {
            #if DEBUG
            print("[UserProfileFollowing] Failed to load following: \(error)")
            #endif
            await MainActor.run {
                isLoadingFollowing = false
            }
        }
    }

    // MARK: - 加载 Followers 列表（关注目标用户的人）
    private func loadFollowers() async {
        isLoadingFollowers = true

        do {
            // 1. 获取关注目标用户的用户 ID 列表
            let result = try await graphService.getFollowers(userId: targetUserId, limit: 50, offset: 0)
            followersHasMore = result.hasMore

            // 2. 批量获取用户详细信息
            let users = await fetchUserProfiles(userIds: result.userIds)

            // 3. 检查当前用户是否关注了这些用户
            var followingStatus: [String: Bool] = [:]
            if let currentUserId = authManager.currentUser?.id {
                followingStatus = (try? await graphService.batchCheckFollowing(
                    followerId: currentUserId,
                    followeeIds: result.userIds
                )) ?? [:]
            }

            // 4. 转换为 UserProfileFollowUser 模型
            await MainActor.run {
                followerUsers = users.map { user in
                    let isFollowingThem = followingStatus[user.id] ?? false
                    return UserProfileFollowUser(
                        id: user.id,
                        username: user.username,
                        displayName: user.displayName ?? user.username,
                        avatarUrl: user.avatarUrl,
                        isVerified: user.safeIsVerified,
                        isFollowedByMe: isFollowingThem
                    )
                }
                isLoadingFollowers = false
            }

            #if DEBUG
            print("[UserProfileFollowing] Loaded \(followerUsers.count) followers for: \(targetUserId)")
            #endif

        } catch {
            #if DEBUG
            print("[UserProfileFollowing] Failed to load followers: \(error)")
            #endif
            await MainActor.run {
                isLoadingFollowers = false
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
    private func toggleFollow(user: UserProfileFollowUser) async {
        guard let currentUserId = authManager.currentUser?.id else { return }

        do {
            if user.isFollowedByMe {
                try await graphService.unfollowUser(followerId: currentUserId, followeeId: user.id)
            } else {
                try await graphService.followUser(followerId: currentUserId, followeeId: user.id)
            }

            // 更新本地状态
            await MainActor.run {
                if let index = followingUsers.firstIndex(where: { $0.id == user.id }) {
                    followingUsers[index].isFollowedByMe.toggle()
                }
                if let index = followerUsers.firstIndex(where: { $0.id == user.id }) {
                    followerUsers[index].isFollowedByMe.toggle()
                }
            }

        } catch {
            #if DEBUG
            print("[UserProfileFollowing] Failed to toggle follow: \(error)")
            #endif
        }
    }

    // MARK: - Top Navigation Bar
    private var topNavigationBar: some View {
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

    // MARK: - Tab Selector
    private var tabSelector: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Following Tab
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

                // Followers Tab
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

    // MARK: - Search Bar
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

    // MARK: - Following Content
    private var followingContent: some View {
        LazyVStack(spacing: 0) {
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
                .frame(maxWidth: .infinity)
                .padding(.top, 60.h)
            } else {
                ForEach(displayedFollowing) { user in
                    UserProfileFollowUserRow(
                        user: user,
                        onFollowTap: {
                            Task {
                                await toggleFollow(user: user)
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Followers Content
    private var followersContent: some View {
        LazyVStack(spacing: 0) {
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
                .frame(maxWidth: .infinity)
                .padding(.top, 60.h)
            } else {
                ForEach(displayedFollowers) { user in
                    UserProfileFollowUserRow(
                        user: user,
                        onFollowTap: {
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

// MARK: - Follow User Model
struct UserProfileFollowUser: Identifiable {
    let id: String
    let username: String
    let displayName: String
    let avatarUrl: String?
    let isVerified: Bool
    var isFollowedByMe: Bool  // 当前登录用户是否关注了此用户

    init(id: String, username: String, displayName: String, avatarUrl: String? = nil, isVerified: Bool = false, isFollowedByMe: Bool = false) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.isVerified = isVerified
        self.isFollowedByMe = isFollowedByMe
    }
}

// MARK: - User Row View
struct UserProfileFollowUserRow: View {
    let user: UserProfileFollowUser
    var onFollowTap: () -> Void = {}

    var body: some View {
        HStack(spacing: 8.w) {
            // Avatar
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

            // Name and Verified Badge
            HStack(spacing: 4.w) {
                Text(user.displayName)
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

            // Follow Button
            actionButton
        }
        .padding(EdgeInsets(top: 10.h, leading: 16.w, bottom: 10.h, trailing: 16.w))
    }

    @ViewBuilder
    private var actionButton: some View {
        Button(action: onFollowTap) {
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

#Preview("UserProfileFollowing - Default") {
    UserProfileFollowingView(
        isPresented: .constant(true),
        targetUserId: "user-123",
        targetUsername: "Juliette"
    )
    .environmentObject(AuthenticationManager.shared)
}

#Preview("UserProfileFollowing - Followers Tab") {
    UserProfileFollowingView(
        isPresented: .constant(true),
        targetUserId: "user-123",
        targetUsername: "Juliette",
        initialTab: .followers
    )
    .environmentObject(AuthenticationManager.shared)
}
