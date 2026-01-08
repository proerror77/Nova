import SwiftUI

// MARK: - Follow User Model
struct FollowUser: Identifiable {
    let id: String
    let username: String
    let displayName: String
    let avatarUrl: String?
    let isVerified: Bool
    var isFollowedByMe: Bool  // 当前用户是否关注了此用户
    var isFollowingMe: Bool   // 此用户是否关注了当前用户

    init(id: String, username: String, displayName: String, avatarUrl: String? = nil, isVerified: Bool = false, isFollowedByMe: Bool = false, isFollowingMe: Bool = false) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.isVerified = isVerified
        self.isFollowedByMe = isFollowedByMe
        self.isFollowingMe = isFollowingMe
    }
}

// MARK: - Tab Selection
enum FollowTab {
    case following
    case followers
}

struct ProfileFollowingView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var authManager: AuthenticationManager

    let userId: String
    let username: String
    let initialTab: FollowTab

    @State private var selectedTab: FollowTab = .following
    @State private var searchText: String = ""
    @State private var followingUsers: [FollowUser] = []
    @State private var followerUsers: [FollowUser] = []
    @State private var isLoadingFollowing = false
    @State private var isLoadingFollowers = false
    @State private var followingHasMore = false
    @State private var followersHasMore = false
    @State private var followingError: String? = nil
    @State private var followersError: String? = nil

    // MARK: - Navigation State
    @State private var showUserProfile = false
    @State private var selectedUserId: String? = nil

    // MARK: - Error Feedback
    @State private var showErrorAlert = false
    @State private var errorAlertMessage = ""

    // MARK: - Services
    private let graphService = GraphService()
    private let userService = UserService.shared

    init(isPresented: Binding<Bool>, userId: String, username: String, initialTab: FollowTab = .following) {
        self._isPresented = isPresented
        self.userId = userId
        self.username = username
        self.initialTab = initialTab
        self._selectedTab = State(initialValue: initialTab)
    }

    // MARK: - Filtered Users
    private var filteredFollowing: [FollowUser] {
        if searchText.isEmpty {
            return followingUsers
        }
        return followingUsers.filter { user in
            user.displayName.localizedCaseInsensitiveContains(searchText) ||
            user.username.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredFollowers: [FollowUser] {
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
                .fill(DesignTokens.borderColor)
                .frame(height: 0.5)

            // MARK: - Search Bar
            searchBar
                .padding(.horizontal, 16.w)
                .padding(.vertical, 12.h)

            // MARK: - User List
            ScrollView {
                if selectedTab == .following {
                    followingContent
                } else {
                    followersContent
                }
            }
            .refreshable {
                await loadInitialData()
            }

            Spacer()
        }
        .background(Color.white)
        .task {
            await loadInitialData()
        }
        .fullScreenCover(isPresented: $showUserProfile) {
            if let userId = selectedUserId {
                UserProfileView(showUserProfile: $showUserProfile, userId: userId)
            } else {
                // Fallback: auto-dismiss if userId is nil to prevent blank screen
                Color.clear
                    .onAppear {
                        showUserProfile = false
                    }
            }
        }
        .alert("Operation Failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorAlertMessage)
        }
    }

    // MARK: - 用戶顯示名稱
    private var displayUsername: String {
        if !username.isEmpty && username != "User" {
            return username
        }
        return authManager.currentUser?.displayName
            ?? authManager.currentUser?.username
            ?? "User"
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
        let currentUserId = authManager.currentUser?.id

        await MainActor.run {
            isLoadingFollowing = true
            followingError = nil
        }

        do {
            // 1. 获取目标用户关注的用户 ID 列表（使用传入的 userId，而非 currentUserId）
            let result = try await graphService.getFollowing(userId: userId, limit: 50, offset: 0)
            followingHasMore = result.hasMore

            // 2. 批量获取用户详细信息（並行處理提升速度）
            let users = await fetchUserProfiles(userIds: result.userIds)

            // 3. 检查当前登录用户是否关注了这些用户
            var followingStatus: [String: Bool] = [:]
            if let currentUserId = currentUserId {
                followingStatus = (try? await graphService.batchCheckFollowing(
                    followerId: currentUserId,
                    followeeIds: result.userIds
                )) ?? [:]
            }

            // 4. 转换为 FollowUser 模型
            await MainActor.run {
                followingUsers = users.map { user in
                    let isFollowingThem = followingStatus[user.id] ?? false
                    return FollowUser(
                        id: user.id,
                        username: user.username,
                        displayName: user.displayName ?? user.username,
                        avatarUrl: user.avatarUrl,
                        isVerified: user.safeIsVerified,
                        isFollowedByMe: isFollowingThem,  // 当前登录用户是否关注了他们
                        isFollowingMe: false              // 需要额外查询
                    )
                }
                isLoadingFollowing = false
            }

            #if DEBUG
            print("[ProfileFollowing] Loaded \(followingUsers.count) following users")
            #endif

        } catch {
            #if DEBUG
            print("[ProfileFollowing] Failed to load following: \(error)")
            #endif
            await MainActor.run {
                isLoadingFollowing = false
                followingError = "Failed to load. Pull down to retry."
            }
        }
    }

    // MARK: - 加载 Followers 列表（关注目标用户的人）
    private func loadFollowers() async {
        let currentUserId = authManager.currentUser?.id

        await MainActor.run {
            isLoadingFollowers = true
            followersError = nil
        }

        do {
            // 1. 获取关注目标用户的用户 ID 列表（使用传入的 userId，而非 currentUserId）
            let result = try await graphService.getFollowers(userId: userId, limit: 50, offset: 0)
            followersHasMore = result.hasMore

            // 2. 批量获取用户详细信息（並行處理提升速度）
            let users = await fetchUserProfiles(userIds: result.userIds)

            // 3. 检查当前登录用户是否关注了这些用户
            var followingStatus: [String: Bool] = [:]
            if let currentUserId = currentUserId {
                followingStatus = (try? await graphService.batchCheckFollowing(
                    followerId: currentUserId,
                    followeeIds: result.userIds
                )) ?? [:]
            }

            // 4. 转换为 FollowUser 模型
            await MainActor.run {
                followerUsers = users.map { user in
                    let isFollowingThem = followingStatus[user.id] ?? false
                    return FollowUser(
                        id: user.id,
                        username: user.username,
                        displayName: user.displayName ?? user.username,
                        avatarUrl: user.avatarUrl,
                        isVerified: user.safeIsVerified,
                        isFollowedByMe: isFollowingThem,  // 当前登录用户是否关注了他们
                        isFollowingMe: true               // 他们关注了目标用户
                    )
                }
                isLoadingFollowers = false
            }

            #if DEBUG
            print("[ProfileFollowing] Loaded \(followerUsers.count) followers")
            #endif

        } catch {
            #if DEBUG
            print("[ProfileFollowing] Failed to load followers: \(error)")
            #endif
            await MainActor.run {
                isLoadingFollowers = false
                followersError = "Failed to load. Pull down to retry."
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
    private func toggleFollow(user: FollowUser) async {
        #if DEBUG
        print("[ProfileFollowing] toggleFollow called for user: \(user.username), isFollowedByMe: \(user.isFollowedByMe)")
        #endif

        guard let currentUserId = authManager.currentUser?.id else {
            #if DEBUG
            print("[ProfileFollowing] No current user ID found")
            #endif
            await MainActor.run {
                errorAlertMessage = "Please login first"
                showErrorAlert = true
            }
            return
        }

        do {
            if user.isFollowedByMe {
                // 取消关注
                try await graphService.unfollowUser(followerId: currentUserId, followeeId: user.id)
            } else {
                // 关注
                try await graphService.followUser(followerId: currentUserId, followeeId: user.id)
            }

            // 更新本地状态（不從列表移除，只切換按鈕狀態）
            await MainActor.run {
                if let index = followingUsers.firstIndex(where: { $0.id == user.id }) {
                    followingUsers[index].isFollowedByMe.toggle()
                }
                if let index = followerUsers.firstIndex(where: { $0.id == user.id }) {
                    followerUsers[index].isFollowedByMe.toggle()
                }
            }

            #if DEBUG
            print("[ProfileFollowing] Toggle follow succeeded for user: \(user.id)")
            #endif
        } catch {
            #if DEBUG
            print("[ProfileFollowing] Failed to toggle follow: \(error)")
            #endif
            await MainActor.run {
                errorAlertMessage = "Operation failed. Please try again later."
                showErrorAlert = true
            }
        }
    }

    // MARK: - Top Navigation Bar
    private var topNavigationBar: some View {
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

            Text(displayUsername)
                .font(Font.custom("SFProDisplay-Medium", size: 24.f))
                .foregroundColor(.black)

            Spacer()

            // Placeholder for symmetry
            Color.clear
                .frame(width: 24.s, height: 24.s)
        }
        .padding(.horizontal, 16.w)
        .frame(height: 56.h)
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
                VStack(spacing: 8.h) {
                    Text("Following")
                        .font(Font.custom("SFProDisplay-Medium", size: 18.f))
                        .foregroundColor(selectedTab == .following ? .black : Color(red: 0.51, green: 0.51, blue: 0.51))

                    Rectangle()
                        .fill(selectedTab == .following ? Color(red: 0.81, green: 0.13, blue: 0.25) : Color.clear)
                        .frame(height: 2.h)
                }
            }
            .frame(maxWidth: .infinity)

            // Followers Tab
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTab = .followers
                }
            }) {
                VStack(spacing: 8.h) {
                    Text("Followers")
                        .font(Font.custom("SFProDisplay-Medium", size: 18.f))
                        .foregroundColor(selectedTab == .followers ? .black : Color(red: 0.51, green: 0.51, blue: 0.51))

                    Rectangle()
                        .fill(selectedTab == .followers ? Color(red: 0.81, green: 0.13, blue: 0.25) : Color.clear)
                        .frame(height: 2.h)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16.w)
    }

    // MARK: - Search Bar
    private var searchBar: some View {
        HStack(spacing: 10.w) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14.f))
                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

            TextField("Search", text: $searchText)
                .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
        }
        .padding(.horizontal, 12.w)
        .padding(.vertical, 6.h)
        .background(Color(red: 0.91, green: 0.91, blue: 0.91))
        .cornerRadius(32.s)
    }

    // MARK: - Following Content
    private var followingContent: some View {
        LazyVStack(spacing: 0) {
            if isLoadingFollowing {
                SkeletonListLoader(itemCount: 5) {
                    UserRowSkeleton()
                }
            } else if let error = followingError {
                // 錯誤狀態
                VStack(spacing: 16.h) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48.f))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(Font.custom("SFProDisplay-Regular", size: 16.f))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                    Button(action: {
                        Task { await loadFollowing() }
                    }) {
                        Text("Retry")
                            .font(Font.custom("SFProDisplay-Medium", size: 14.f))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24.w)
                            .padding(.vertical, 8.h)
                            .background(Color(red: 0.87, green: 0.11, blue: 0.26))
                            .cornerRadius(20.s)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60.h)
            } else if filteredFollowing.isEmpty {
                // 空状态
                VStack(spacing: 12.h) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 48.f))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("Not following anyone yet")
                        .font(Font.custom("SFProDisplay-Regular", size: 16.f))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60.h)
            } else {
                ForEach(filteredFollowing) { user in
                    UserRowView(
                        user: user,
                        showFollowButton: false,
                        onAvatarTap: {
                            // Invalidate cache for fresh profile data (Issue #166)
                            userService.invalidateCache(userId: user.id)
                            selectedUserId = user.id
                            showUserProfile = true
                        },
                        onFollowTap: {
                            Task {
                                await toggleFollow(user: user)
                            }
                        }
                    )
                    .padding(.horizontal, 16.w)
                    .padding(.vertical, 10.h)
                }
            }
        }
    }

    // MARK: - Followers Content
    private var followersContent: some View {
        LazyVStack(spacing: 0) {
            if isLoadingFollowers {
                SkeletonListLoader(itemCount: 5) {
                    UserRowSkeleton()
                }
            } else if let error = followersError {
                // 錯誤狀態
                VStack(spacing: 16.h) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48.f))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(Font.custom("SFProDisplay-Regular", size: 16.f))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                    Button(action: {
                        Task { await loadFollowers() }
                    }) {
                        Text("Retry")
                            .font(Font.custom("SFProDisplay-Medium", size: 14.f))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24.w)
                            .padding(.vertical, 8.h)
                            .background(Color(red: 0.87, green: 0.11, blue: 0.26))
                            .cornerRadius(20.s)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60.h)
            } else if filteredFollowers.isEmpty {
                // 空状态
                VStack(spacing: 12.h) {
                    Image(systemName: "person.2")
                        .font(.system(size: 48.f))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("No followers yet")
                        .font(Font.custom("SFProDisplay-Regular", size: 16.f))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60.h)
            } else {
                ForEach(filteredFollowers) { user in
                    UserRowView(
                        user: user,
                        showFollowButton: true,
                        onAvatarTap: {
                            // Invalidate cache for fresh profile data (Issue #166)
                            userService.invalidateCache(userId: user.id)
                            selectedUserId = user.id
                            showUserProfile = true
                        },
                        onFollowTap: {
                            Task {
                                await toggleFollow(user: user)
                            }
                        }
                    )
                    .padding(.horizontal, 16.w)
                    .padding(.vertical, 10.h)
                }
            }
        }
    }
}

// MARK: - User Row View
struct UserRowView: View {
    let user: FollowUser
    var showFollowButton: Bool = false
    var onAvatarTap: () -> Void = {}
    var onFollowTap: () -> Void = {}

    var body: some View {
        HStack(spacing: 12.w) {
            // Avatar - 使用 CachedAsyncImage 优化性能，點擊可跳轉到用戶 profile
            Button(action: onAvatarTap) {
                if let avatarUrl = user.avatarUrl, let url = URL(string: avatarUrl) {
                    CachedAsyncImage(
                        url: url,
                        targetSize: CGSize(width: 100, height: 100),  // 2x for retina
                        enableProgressiveLoading: false,
                        priority: .normal
                    ) { image in
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
            }

            // Name and Verified Badge - 點擊可跳轉到用戶 profile
            Button(action: onAvatarTap) {
                HStack(spacing: 6.w) {
                    Text(user.displayName)
                        .font(Font.custom("SFProDisplay-Bold", size: 16.f))
                        .foregroundColor(.black)
                        .lineLimit(1)

                    if user.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14.f))
                            .foregroundColor(Color(red: 0.2, green: 0.6, blue: 1.0))
                    }
                }
            }

            Spacer()

            // 按钮区域 - 根據關注狀態顯示不同按鈕
            if user.isFollowedByMe {
                // Following Button (已關注狀態) - 點擊可取消關注
                Button(action: onFollowTap) {
                    Text("Following")
                        .font(Font.custom("SFProDisplay-Medium", size: 12.f))
                        .foregroundColor(.black)
                        .padding(.horizontal, 16.w)
                        .padding(.vertical, 8.h)
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 66.s)
                                .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.66)
                        )
                        .cornerRadius(66.s)
                }
                .buttonStyle(.plain)
            } else {
                // Follow Button (未關注狀態) - 點擊可關注
                Button(action: onFollowTap) {
                    Text("Follow")
                        .font(Font.custom("SFProDisplay-Medium", size: 12.f))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16.w)
                        .padding(.vertical, 8.h)
                        .background(Color(red: 0.87, green: 0.11, blue: 0.26))
                        .cornerRadius(46.s)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var defaultAvatar: some View {
        Circle()
            .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.5))
            .frame(width: 50.s, height: 50.s)
    }
}

// MARK: - Previews

#Preview("ProfileFollowing - Default") {
    ProfileFollowingView(
        isPresented: .constant(true),
        userId: "user-123",
        username: "User"
    )
    .environmentObject(AuthenticationManager.shared)
}

#Preview("ProfileFollowing - Dark Mode") {
    ProfileFollowingView(
        isPresented: .constant(true),
        userId: "user-123",
        username: "User"
    )
    .environmentObject(AuthenticationManager.shared)
    .preferredColorScheme(.dark)
}
