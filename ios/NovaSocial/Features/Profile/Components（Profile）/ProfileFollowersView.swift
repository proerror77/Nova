import SwiftUI

/// 关注者/正在关注页面
struct ProfileFollowersView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var authManager: AuthenticationManager

    // 当前选中的标签
    @State private var selectedTab: Tab = .followers
    @State private var searchText: String = ""

    // MARK: - 数据状态
    @State private var followers: [FollowerUser] = []
    @State private var following: [FollowerUser] = []
    @State private var suggestions: [FollowerUser] = []
    @State private var isLoadingFollowers = false
    @State private var isLoadingFollowing = false
    @State private var followersHasMore = false
    @State private var followingHasMore = false
    @State private var followersError: String? = nil
    @State private var followingError: String? = nil

    // MARK: - 取消关注确认
    @State private var showUnfollowConfirmation = false
    @State private var userToUnfollow: FollowerUser? = nil

    // MARK: - Services
    private let graphService = GraphService()
    private let userService = UserService.shared

    enum Tab {
        case following
        case followers
    }

    // 过滤后的关注者列表
    private var filteredFollowers: [FollowerUser] {
        if searchText.isEmpty {
            return followers
        }
        return followers.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // 过滤后的关注列表
    private var filteredFollowing: [FollowerUser] {
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
            .refreshable {
                await loadInitialData()
            }
        }
        .background(Color.white)
        .task {
            await loadInitialData()
        }
        .alert("Unfollow", isPresented: $showUnfollowConfirmation) {
            Button("Cancel", role: .cancel) {
                userToUnfollow = nil
            }
            Button("Unfollow", role: .destructive) {
                if let user = userToUnfollow {
                    Task {
                        await performUnfollow(user: user)
                    }
                }
                userToUnfollow = nil
            }
        } message: {
            if let user = userToUnfollow {
                Text("Are you sure you want to unfollow \(user.name)?")
            }
        }
    }

    // MARK: - 加载初始数据
    private func loadInitialData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await loadFollowers() }
            group.addTask { await loadFollowing() }
        }
    }

    // MARK: - 加载 Followers 列表
    private func loadFollowers() async {
        guard let currentUserId = authManager.currentUser?.id else {
            await MainActor.run {
                followersError = "請先登入"
            }
            return
        }

        await MainActor.run {
            isLoadingFollowers = true
            followersError = nil
        }

        do {
            // 1. 获取关注当前用户的用户 ID 列表（包含关系状态）
            let result = try await graphService.getFollowers(userId: currentUserId, limit: 50, offset: 0)
            followersHasMore = result.hasMore

            // 2. 批量获取用户详细信息（並行處理提升速度）
            let users = await fetchUserProfiles(userIds: result.userIds)

            // 3. 使用后端返回的关系状态（无需额外 API 调用）
            await MainActor.run {
                followers = users.map { user in
                    // 从后端返回的 users 数组中获取关系状态
                    let status = result.relationshipStatus(for: user.id)
                    return FollowerUser(
                        id: user.id,
                        name: user.displayName ?? user.username,
                        avatarUrl: user.avatarUrl,
                        isVerified: user.safeIsVerified,
                        isFollowingYou: true, // 他们关注了你（这是 followers 列表）
                        youAreFollowing: status?.youAreFollowing ?? false // 你是否关注了他们
                    )
                }
                isLoadingFollowers = false
            }

            #if DEBUG
            print("[ProfileFollowers] Loaded \(followers.count) followers (enriched: \(result.users?.count ?? 0))")
            #endif

        } catch {
            #if DEBUG
            print("[ProfileFollowers] Failed to load followers: \(error)")
            #endif
            await MainActor.run {
                isLoadingFollowers = false
                followersError = "載入失敗，請下拉重試"
            }
        }
    }

    // MARK: - 加载 Following 列表
    private func loadFollowing() async {
        guard let currentUserId = authManager.currentUser?.id else {
            await MainActor.run {
                followingError = "請先登入"
            }
            return
        }

        await MainActor.run {
            isLoadingFollowing = true
            followingError = nil
        }

        do {
            // 1. 获取当前用户关注的用户 ID 列表（包含关系状态）
            let result = try await graphService.getFollowing(userId: currentUserId, limit: 50, offset: 0)
            followingHasMore = result.hasMore

            // 2. 批量获取用户详细信息（並行處理提升速度）
            let users = await fetchUserProfiles(userIds: result.userIds)

            // 3. 使用后端返回的关系状态（无需额外 API 调用）
            await MainActor.run {
                following = users.map { user in
                    // 从后端返回的 users 数组中获取关系状态
                    let status = result.relationshipStatus(for: user.id)
                    return FollowerUser(
                        id: user.id,
                        name: user.displayName ?? user.username,
                        avatarUrl: user.avatarUrl,
                        isVerified: user.safeIsVerified,
                        isFollowingYou: status?.followsYou ?? false, // 他们是否关注你
                        youAreFollowing: true // 你关注了他们（这是 following 列表）
                    )
                }
                isLoadingFollowing = false
            }

            #if DEBUG
            print("[ProfileFollowers] Loaded \(following.count) following (enriched: \(result.users?.count ?? 0))")
            #endif

        } catch {
            #if DEBUG
            print("[ProfileFollowers] Failed to load following: \(error)")
            #endif
            await MainActor.run {
                isLoadingFollowing = false
                followingError = "載入失敗，請下拉重試"
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
    private func toggleFollow(user: FollowerUser) async {
        guard let currentUserId = authManager.currentUser?.id else { return }

        do {
            if user.youAreFollowing {
                // 取消关注
                try await graphService.unfollowUser(followerId: currentUserId, followeeId: user.id)
            } else {
                // 关注
                try await graphService.followUser(followerId: currentUserId, followeeId: user.id)
            }

            // 更新本地状态
            await MainActor.run {
                if let index = followers.firstIndex(where: { $0.id == user.id }) {
                    followers[index].youAreFollowing.toggle()
                }
                if let index = following.firstIndex(where: { $0.id == user.id }) {
                    following[index].youAreFollowing.toggle()
                }
            }
        } catch {
            #if DEBUG
            print("[ProfileFollowers] Failed to toggle follow: \(error)")
            #endif
        }
    }

    // MARK: - 处理关注/取消关注按钮点击
    private func handleFollowButtonTap(user: FollowerUser) {
        if user.youAreFollowing {
            // 如果已关注，显示确认弹窗
            userToUnfollow = user
            showUnfollowConfirmation = true
        } else {
            // 如果未关注，直接关注
            Task {
                await toggleFollow(user: user)
            }
        }
    }

    // MARK: - 执行取消关注
    private func performUnfollow(user: FollowerUser) async {
        guard let currentUserId = authManager.currentUser?.id else { return }

        do {
            try await graphService.unfollowUser(followerId: currentUserId, followeeId: user.id)

            // 更新本地状态
            await MainActor.run {
                if let index = followers.firstIndex(where: { $0.id == user.id }) {
                    followers[index].youAreFollowing = false
                }
                if let index = following.firstIndex(where: { $0.id == user.id }) {
                    following[index].youAreFollowing = false
                }
            }

            #if DEBUG
            print("[ProfileFollowers] Successfully unfollowed user: \(user.id)")
            #endif
        } catch {
            #if DEBUG
            print("[ProfileFollowers] Failed to unfollow: \(error)")
            #endif
        }
    }

    // MARK: - 用戶顯示名稱
    private var displayUsername: String {
        authManager.currentUser?.displayName
            ?? authManager.currentUser?.username
            ?? "User"
    }

    // MARK: - 导航栏
    private var navigationBar: some View {
        ZStack {
            // 标题
            Text(displayUsername)
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
            } else if let error = followersError {
                // 錯誤狀態
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                    Button(action: {
                        Task { await loadFollowers() }
                    }) {
                        Text("重試")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                            .background(Color(red: 0.87, green: 0.11, blue: 0.26))
                            .cornerRadius(20)
                    }
                }
                .padding(.top, 60)
            } else if filteredFollowers.isEmpty {
                // 空状态
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
                // 关注者列表
                ForEach(filteredFollowers) { user in
                    FollowerRow(
                        user: user,
                        // 互相关注显示 Friend，否则显示 Follow back
                        buttonType: user.youAreFollowing ? .friend : .followBack,
                        onFollowTapped: {
                            handleFollowButtonTap(user: user)
                        }
                    )
                }

                // All 下拉
                HStack {
                    Spacer()
                    Button(action: {
                        // TODO: 显示筛选选项
                    }) {
                        HStack(spacing: 4) {
                            Text("All")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10))
                                .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 12)

                // 分隔线
                Rectangle()
                    .fill(Color(red: 0.93, green: 0.93, blue: 0.93))
                    .frame(height: 3)

                // 你可能认识的人
                VStack(alignment: .leading, spacing: 0) {
                    Text("People You May Know")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                    ForEach(suggestions) { user in
                        FollowerRow(
                            user: user,
                            buttonType: .follow,
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

    // MARK: - Following 内容
    private var followingContent: some View {
        VStack(spacing: 0) {
            if isLoadingFollowing {
                SkeletonListLoader(itemCount: 5) {
                    AnyView(UserRowSkeleton())
                }
            } else if let error = followingError {
                // 錯誤狀態
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                    Button(action: {
                        Task { await loadFollowing() }
                    }) {
                        Text("重試")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                            .background(Color(red: 0.87, green: 0.11, blue: 0.26))
                            .cornerRadius(20)
                    }
                }
                .padding(.top, 60)
            } else if filteredFollowing.isEmpty {
                // 空状态
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
                // 正在关注的用户列表
                ForEach(filteredFollowing) { user in
                    FollowerRow(
                        user: user,
                        // 互相关注显示 Friend，否则显示 Following
                        buttonType: user.isFollowingYou ? .friend : .following,
                        onFollowTapped: {
                            handleFollowButtonTap(user: user)
                        }
                    )
                }
            }
        }
    }
}

// MARK: - 关注者数据模型
struct FollowerUser: Identifiable {
    let id: String
    let name: String
    let avatarUrl: String?
    let isVerified: Bool
    let isFollowingYou: Bool  // 对方是否关注了你
    var youAreFollowing: Bool // 你是否关注了对方

    init(id: String = UUID().uuidString, name: String, avatarUrl: String? = nil, isVerified: Bool = false, isFollowingYou: Bool = false, youAreFollowing: Bool = false) {
        self.id = id
        self.name = name
        self.avatarUrl = avatarUrl
        self.isVerified = isVerified
        self.isFollowingYou = isFollowingYou
        self.youAreFollowing = youAreFollowing
    }
}

// MARK: - 关注者行组件
struct FollowerRow: View {
    let user: FollowerUser
    let buttonType: ButtonType
    var onFollowTapped: () -> Void = {}

    enum ButtonType {
        case follow      // 关注（红色描边）- 陌生人
        case followBack  // 回关（红色实心）- 对方关注你，你未关注对方
        case following   // 已关注（灰色描边）- 你关注对方，对方未关注你
        case friend      // 互关/好友（灰色描边）- 双向关注
    }

    var body: some View {
        HStack(spacing: 13) {
            // 头像 - 使用 CachedAsyncImage 优化性能
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

            // 按钮
            Button(action: onFollowTapped) {
                switch buttonType {
                case .followBack:
                    Text("Follow back")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.87, green: 0.11, blue: 0.26))
                        .cornerRadius(46)

                case .following:
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

                case .follow:
                    Text("Follow")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                        .frame(width: 85, height: 24)
                        .background(Color.white)
                        .cornerRadius(100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 100)
                                .stroke(Color(red: 0.87, green: 0.11, blue: 0.26), lineWidth: 0.5)
                        )

                case .friend:
                    Text("Friend")
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
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Previews

#Preview("ProfileFollowers - Default") {
    ProfileFollowersView(isPresented: .constant(true))
        .environmentObject(AuthenticationManager.shared)
}

#Preview("ProfileFollowers - Dark Mode") {
    ProfileFollowersView(isPresented: .constant(true))
        .environmentObject(AuthenticationManager.shared)
        .preferredColorScheme(.dark)
}
