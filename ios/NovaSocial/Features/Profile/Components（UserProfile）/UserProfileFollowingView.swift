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

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Top Navigation Bar
            topNavigationBar

            // MARK: - Tab Selector
            tabSelector

            // MARK: - Separator Line
            Rectangle()
                .fill(Color(red: 0.74, green: 0.74, blue: 0.74))
                .frame(height: 0.5)

            // MARK: - Search Bar
            searchBar
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

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
        HStack {
            Button(action: {
                isPresented = false
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.black)
            }
            .frame(width: 24, height: 24)

            Spacer()

            Text(targetUsername)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(.black)

            Spacer()

            // Placeholder for symmetry
            Color.clear
                .frame(width: 24, height: 24)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Color.white)
    }

    // MARK: - Tab Selector
    private var tabSelector: some View {
        HStack(spacing: 0) {
            // Following Tab
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTab = .following
                }
            }) {
                VStack(spacing: 8) {
                    Text("Following")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(selectedTab == .following ? .black : Color(red: 0.51, green: 0.51, blue: 0.51))

                    Rectangle()
                        .fill(selectedTab == .following ? Color(red: 0.81, green: 0.13, blue: 0.25) : Color.clear)
                        .frame(height: 2)
                }
            }
            .frame(maxWidth: .infinity)

            // Followers Tab
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTab = .followers
                }
            }) {
                VStack(spacing: 8) {
                    Text("Followers")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(selectedTab == .followers ? .black : Color(red: 0.51, green: 0.51, blue: 0.51))

                    Rectangle()
                        .fill(selectedTab == .followers ? Color(red: 0.81, green: 0.13, blue: 0.25) : Color.clear)
                        .frame(height: 2)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Search Bar
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

            TextField("Search", text: $searchText)
                .font(.system(size: 14))
                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(red: 0.91, green: 0.91, blue: 0.91))
        .cornerRadius(32)
    }

    // MARK: - Following Content
    private var followingContent: some View {
        LazyVStack(spacing: 0) {
            if isLoadingFollowing {
                ProgressView()
                    .padding(.top, 40)
            } else if filteredFollowing.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("Not following anyone yet")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else {
                ForEach(filteredFollowing) { user in
                    UserProfileFollowUserRow(
                        user: user,
                        onFollowTap: {
                            Task {
                                await toggleFollow(user: user)
                            }
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    // MARK: - Followers Content
    private var followersContent: some View {
        LazyVStack(spacing: 0) {
            if isLoadingFollowers {
                ProgressView()
                    .padding(.top, 40)
            } else if filteredFollowers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.2")
                        .font(.system(size: 48))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("No followers yet")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else {
                ForEach(filteredFollowers) { user in
                    UserProfileFollowUserRow(
                        user: user,
                        onFollowTap: {
                            Task {
                                await toggleFollow(user: user)
                            }
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
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
        HStack(spacing: 12) {
            // Avatar
            if let avatarUrl = user.avatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    defaultAvatar
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                defaultAvatar
            }

            // Name and Verified Badge
            HStack(spacing: 6) {
                Text(user.displayName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)

                if user.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 0.2, green: 0.6, blue: 1.0))
                }
            }

            Spacer()

            // Follow Button
            Button(action: onFollowTap) {
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
    }

    private var defaultAvatar: some View {
        Circle()
            .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.5))
            .frame(width: 50, height: 50)
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
