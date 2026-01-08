
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

    // MARK: - Recommended Users (People You May Know)
    @State private var recommendedUsers: [FollowUser] = []
    @State private var isLoadingRecommended = false

    // MARK: - Followers List Expand/Collapse
    @State private var isFollowersExpanded = false
    private let followersThreshold = 7  // 超过此数量才显示 All 按钮
    private let collapsedFollowersCount = 7  // 收起时显示的粉丝数量

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

    private var filteredRecommended: [FollowUser] {
        if searchText.isEmpty {
            return recommendedUsers
        }
        return recommendedUsers.filter { user in
            user.displayName.localizedCaseInsensitiveContains(searchText) ||
            user.username.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Followers Display Logic
    /// 是否显示 All 按钮（粉丝数量 > 7 时显示）
    private var shouldShowAllButton: Bool {
        filteredFollowers.count > followersThreshold
    }

    /// 当前显示的粉丝列表（根据展开/收起状态）
    private var displayedFollowers: [FollowUser] {
        if !shouldShowAllButton || isFollowersExpanded {
            // 不需要 All 按钮，或者已展开 → 显示全部
            return filteredFollowers
        } else {
            // 需要 All 按钮且收起状态 → 只显示前几个
            return Array(filteredFollowers.prefix(collapsedFollowersCount))
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
                .padding(EdgeInsets(top: 14.h, leading: 16.w, bottom: 14.h, trailing: 16.w))

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
            group.addTask { await loadRecommendedUsers() }
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

    // MARK: - 加载推荐用户 (People You May Know)
    private func loadRecommendedUsers() async {
        await MainActor.run {
            isLoadingRecommended = true
        }

        // TODO: 替换为真实的推荐用户 API
        // 目前使用 mock 数据用于展示 UI
        do {
            // 模拟网络延迟
            try await Task.sleep(nanoseconds: 500_000_000)

            // Mock 推荐用户数据
            let mockRecommended = [
                FollowUser(id: "rec-1", username: "oliver", displayName: "Oliver", avatarUrl: nil, isVerified: true, isFollowedByMe: false, isFollowingMe: false),
                FollowUser(id: "rec-2", username: "ava", displayName: "Ava", avatarUrl: nil, isVerified: true, isFollowedByMe: false, isFollowingMe: false),
                FollowUser(id: "rec-3", username: "sophia", displayName: "Sophia", avatarUrl: nil, isVerified: true, isFollowedByMe: false, isFollowingMe: false),
                FollowUser(id: "rec-4", username: "noah", displayName: "Noah", avatarUrl: nil, isVerified: true, isFollowedByMe: false, isFollowingMe: false),
                FollowUser(id: "rec-5", username: "mua", displayName: "Mua", avatarUrl: nil, isVerified: true, isFollowedByMe: false, isFollowingMe: false),
                FollowUser(id: "rec-6", username: "god", displayName: "God", avatarUrl: nil, isVerified: true, isFollowedByMe: false, isFollowingMe: false)
            ]

            await MainActor.run {
                recommendedUsers = mockRecommended
                isLoadingRecommended = false
            }

            #if DEBUG
            print("[ProfileFollowing] Loaded \(recommendedUsers.count) recommended users")
            #endif
        } catch {
            await MainActor.run {
                isLoadingRecommended = false
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
        ZStack {
            // 标题居中
            Text(displayUsername)
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
                        buttonType: .message,
                        onAvatarTap: {
                            // Invalidate cache for fresh profile data (Issue #166)
                            userService.invalidateCache(userId: user.id)
                            selectedUserId = user.id
                            showUserProfile = true
                        },
                        onButtonTap: {
                            // TODO: Navigate to chat/message screen
                            print("[ProfileFollowing] Message tapped for user: \(user.username)")
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
                        .font(Font.custom("SF Pro Display", size: 16.f))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                    Button(action: {
                        Task { await loadFollowers() }
                    }) {
                        Text("Retry")
                            .font(Font.custom("SF Pro Display", size: 14.f).weight(.medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24.w)
                            .padding(.vertical, 8.h)
                            .background(Color(red: 0.87, green: 0.11, blue: 0.26))
                            .cornerRadius(20.s)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60.h)
            } else if filteredFollowers.isEmpty && filteredRecommended.isEmpty {
                // 空状态
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
                // MARK: - 真正的粉丝列表 (Follow back)
                ForEach(displayedFollowers) { user in
                    UserRowView(
                        user: user,
                        buttonType: user.isFollowedByMe ? .message : .followBack,
                        onAvatarTap: {
                            userService.invalidateCache(userId: user.id)
                            selectedUserId = user.id
                            showUserProfile = true
                        },
                        onButtonTap: {
                            if user.isFollowedByMe {
                                // 已关注，点击发送消息
                                print("[ProfileFollowing] Message tapped for user: \(user.username)")
                            } else {
                                // 未关注，点击回关
                                Task { await toggleFollow(user: user) }
                            }
                        }
                    )
                    .padding(.horizontal, 16.w)
                    .padding(.vertical, 10.h)
                }

                // MARK: - All 展开/收起按钮（仅当粉丝 > 7 时显示）
                if shouldShowAllButton {
                    allToggleButton
                } else if !filteredFollowers.isEmpty && !filteredRecommended.isEmpty {
                    // 粉丝 ≤ 7 时，用简单分隔线
                    Rectangle()
                        .fill(Color(red: 0.75, green: 0.75, blue: 0.75))
                        .frame(height: 2)
                        .padding(.vertical, 10.h)
                }

                // MARK: - People You May Know 标题
                if !filteredRecommended.isEmpty {
                    peopleYouMayKnowHeader
                }

                // MARK: - 推荐用户列表 (Follow)
                ForEach(filteredRecommended) { user in
                    UserRowView(
                        user: user,
                        buttonType: user.isFollowedByMe ? .message : .follow,
                        onAvatarTap: {
                            userService.invalidateCache(userId: user.id)
                            selectedUserId = user.id
                            showUserProfile = true
                        },
                        onButtonTap: {
                            if user.isFollowedByMe {
                                print("[ProfileFollowing] Message tapped for user: \(user.username)")
                            } else {
                                Task { await followRecommendedUser(user: user) }
                            }
                        }
                    )
                    .padding(.horizontal, 16.w)
                    .padding(.vertical, 10.h)
                }
            }
        }
    }

    // MARK: - All 展开/收起按钮
    private var allToggleButton: some View {
        VStack(spacing: 16.h) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isFollowersExpanded.toggle()
                }
            }) {
                HStack(spacing: 4.w) {
                    Text("All")
                        .font(Font.custom("SF Pro Display", size: 14.f).weight(.semibold))
                        .tracking(0.28)
                        .foregroundColor(Color(red: 0.51, green: 0.51, blue: 0.51))
                    Image(systemName: isFollowersExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10.f, weight: .semibold))
                        .foregroundColor(Color(red: 0.51, green: 0.51, blue: 0.51))
                }
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color(red: 0.75, green: 0.75, blue: 0.75))
                .frame(height: 2)
        }
        .padding(.vertical, 10.h)
    }

    // MARK: - People You May Know 标题
    private var peopleYouMayKnowHeader: some View {
        HStack {
            Text("People You May Know")
                .font(Font.custom("SF Pro Display", size: 14.f).weight(.semibold))
                .tracking(0.28)
                .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
            Spacer()
        }
        .padding(.horizontal, 16.w)
        .padding(.vertical, 8.h)
    }

    // MARK: - 关注推荐用户
    private func followRecommendedUser(user: FollowUser) async {
        guard let currentUserId = authManager.currentUser?.id else {
            await MainActor.run {
                errorAlertMessage = "Please login first"
                showErrorAlert = true
            }
            return
        }

        do {
            try await graphService.followUser(followerId: currentUserId, followeeId: user.id)

            // 更新本地状态
            await MainActor.run {
                if let index = recommendedUsers.firstIndex(where: { $0.id == user.id }) {
                    recommendedUsers[index].isFollowedByMe = true
                }
            }

            #if DEBUG
            print("[ProfileFollowing] Followed recommended user: \(user.username)")
            #endif
        } catch {
            #if DEBUG
            print("[ProfileFollowing] Failed to follow recommended user: \(error)")
            #endif
            await MainActor.run {
                errorAlertMessage = "Failed to follow. Please try again."
                showErrorAlert = true
            }
        }
    }
}

// MARK: - Button Type
enum UserRowButtonType {
    case message      // 黑色描边 - Following tab
    case followBack   // 红色填充 - Followers tab (粉丝)
    case follow       // 红色描边 - People You May Know
}

// MARK: - User Row View
struct UserRowView: View {
    let user: FollowUser
    var buttonType: UserRowButtonType = .message
    var onAvatarTap: () -> Void = {}
    var onButtonTap: () -> Void = {}

    var body: some View {
        HStack(spacing: 8.w) {
            // Left: Avatar + Name
            HStack(spacing: 8.w) {
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
                .buttonStyle(.plain)

                // Name and Verified Badge - 點擊可跳轉到用戶 profile
                Button(action: onAvatarTap) {
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
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Action Button - 根據類型顯示不同樣式
            actionButton
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch buttonType {
        case .message:
            // Message Button - 黑色描边 (Figma: 105x34)
            Button(action: onButtonTap) {
                Text("Message")
                    .font(Font.custom("SF Pro Display", size: 12.f))
                    .tracking(0.24)
                    .foregroundColor(.black)
            }
            .buttonStyle(.plain)
            .frame(width: 105.w, height: 34.h)
            .cornerRadius(57.s)
            .overlay(
                RoundedRectangle(cornerRadius: 57.s)
                    .inset(by: 0.75)
                    .stroke(.black, lineWidth: 0.5)
            )

        case .followBack:
            // Follow back Button - 红色填充 (Figma: 105x34)
            Button(action: onButtonTap) {
                Text("Follow back")
                    .font(Font.custom("SF Pro Display", size: 12.f))
                    .tracking(0.24)
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .frame(width: 105.w, height: 34.h)
            .background(Color(red: 0.87, green: 0.11, blue: 0.26))
            .cornerRadius(57.s)

        case .follow:
            // Follow Button - 红色描边 (Figma: 105x34)
            Button(action: onButtonTap) {
                Text("Follow")
                    .font(Font.custom("SF Pro Display", size: 12.f))
                    .tracking(0.24)
                    .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
            }
            .buttonStyle(.plain)
            .frame(width: 105.w, height: 34.h)
            .cornerRadius(57.s)
            .overlay(
                RoundedRectangle(cornerRadius: 57.s)
                    .inset(by: 0.5)
                    .stroke(Color(red: 0.87, green: 0.11, blue: 0.26), lineWidth: 0.5)
            )
        }
    }

    private var defaultAvatar: some View {
        Ellipse()
            .foregroundColor(.clear)
            .frame(width: 50.s, height: 50.s)
            .background(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.5))
            .clipShape(Circle())
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
