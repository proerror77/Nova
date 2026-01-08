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

    // MARK: - 強制刷新觸發器
    @State private var refreshID = UUID()

    // MARK: - 粉丝列表展开/收起
    @State private var isFollowersExpanded = false
    private let followersDisplayLimit = 7  // 默认显示数量

    // MARK: - Error Feedback
    @State private var showErrorAlert = false
    @State private var errorAlertMessage = ""

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

    // 是否需要显示 All 按钮（粉丝数量 > 7）
    private var shouldShowAllButton: Bool {
        filteredFollowers.count > followersDisplayLimit
    }

    // 当前显示的粉丝列表（根据展开/收起状态）
    private var displayedFollowers: [FollowerUser] {
        if !shouldShowAllButton || isFollowersExpanded {
            // 不需要 All 按钮，或已展开 → 显示全部
            return filteredFollowers
        } else {
            // 需要 All 按钮且收起状态 → 只显示前7个
            return Array(filteredFollowers.prefix(followersDisplayLimit))
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
        .alert("Operation Failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorAlertMessage)
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
                followersError = "Please login first"
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
                followersError = "Failed to load. Pull down to retry."
            }
        }
    }

    // MARK: - 加载 Following 列表
    private func loadFollowing() async {
        guard let currentUserId = authManager.currentUser?.id else {
            await MainActor.run {
                followingError = "Please login first"
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
                followingError = "Failed to load. Pull down to retry."
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

            // 更新本地状态 - 創建新數組強制 SwiftUI 重新渲染
            await MainActor.run {
                if let index = followers.firstIndex(where: { $0.id == user.id }) {
                    var updatedFollowers = followers
                    updatedFollowers[index].youAreFollowing.toggle()
                    followers = updatedFollowers
                }
                if let index = following.firstIndex(where: { $0.id == user.id }) {
                    var updatedFollowing = following
                    updatedFollowing[index].youAreFollowing.toggle()
                    following = updatedFollowing
                }
            }
        } catch {
            #if DEBUG
            print("[ProfileFollowers] Failed to toggle follow: \(error)")
            #endif
            await MainActor.run {
                errorAlertMessage = "Operation failed. Please try again later."
                showErrorAlert = true
            }
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
        #if DEBUG
        print("[ProfileFollowers] performUnfollow called for user: \(user.name) (id: \(user.id))")
        #endif

        guard let currentUserId = authManager.currentUser?.id else {
            #if DEBUG
            print("[ProfileFollowers] ERROR: No current user ID")
            #endif
            await MainActor.run {
                errorAlertMessage = "Please login first"
                showErrorAlert = true
            }
            return
        }

        do {
            try await graphService.unfollowUser(followerId: currentUserId, followeeId: user.id)

            // 更新本地状态 - 創建新數組強制 SwiftUI 重新渲染
            await MainActor.run {
                // 更新 followers 數組
                if let index = followers.firstIndex(where: { $0.id == user.id }) {
                    var updatedFollowers = followers
                    updatedFollowers[index].youAreFollowing = false
                    followers = updatedFollowers
                }

                // 更新 following 數組 - 創建新數組以強制 SwiftUI 重新渲染
                if let index = following.firstIndex(where: { $0.id == user.id }) {
                    var updatedFollowing = following
                    updatedFollowing[index].youAreFollowing = false
                    following = updatedFollowing

                    // 強制刷新視圖
                    refreshID = UUID()
                }
            }

            #if DEBUG
            print("[ProfileFollowers] Successfully unfollowed user: \(user.id)")
            #endif
        } catch {
            #if DEBUG
            print("[ProfileFollowers] Failed to unfollow: \(error)")
            #endif
            await MainActor.run {
                errorAlertMessage = "Failed to unfollow. Please try again later."
                showErrorAlert = true
            }
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
                .padding(.top, 60.h)
            } else if filteredFollowers.isEmpty {
                // 空状态
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
                // 关注者列表 - 根据展开状态显示
                ForEach(displayedFollowers) { user in
                    FollowerRow(
                        user: user,
                        // 互相关注显示 Friend，否则显示 Follow back
                        buttonType: user.youAreFollowing ? .friend : .followBack,
                        onFollowTapped: {
                            handleFollowButtonTap(user: user)
                        }
                    )
                }

                // All 下拉 - 仅在粉丝数量大于7时显示
                if shouldShowAllButton {
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
                                    .font(.system(size: 10.f))
                                    .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12.h)
                }

                // 分隔线
                Rectangle()
                    .fill(Color(red: 0.93, green: 0.93, blue: 0.93))
                    .frame(height: 3.h)

                // 你可能认识的人
                VStack(alignment: .leading, spacing: 0) {
                    Text("People You May Know")
                        .font(Font.custom("SF Pro Display", size: 14.f).weight(.bold))
                        .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
                        .padding(.horizontal, 16.w)
                        .padding(.top, 16.h)
                        .padding(.bottom, 8.h)

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
                    UserRowSkeleton()
                }
            } else if let error = followingError {
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
                        Task { await loadFollowing() }
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
                .padding(.top, 60.h)
            } else if filteredFollowing.isEmpty {
                // 空状态
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
                // 正在关注的用户列表
                ForEach(filteredFollowing) { user in
                    let computedButtonType: FollowerRow.ButtonType = user.youAreFollowing
                        ? (user.isFollowingYou ? .friend : .following)
                        : .follow
                    FollowerRow(
                        user: user,
                        // 根據關注狀態顯示按鈕：
                        // - youAreFollowing=true + isFollowingYou=true → Friend（互相關注）
                        // - youAreFollowing=true + isFollowingYou=false → Following（單向關注）
                        // - youAreFollowing=false → Follow（取消關注後）
                        buttonType: computedButtonType,
                        onFollowTapped: {
                            handleFollowButtonTap(user: user)
                        }
                    )
                    .id("\(user.id)-\(user.youAreFollowing)")  // 強制根據關注狀態重新渲染
                }
                .id(refreshID)  // 強制刷新整個列表
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
        HStack(spacing: 8.w) {
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
                .frame(width: 50.s, height: 50.s)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                    .frame(width: 50.s, height: 50.s)
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

            // 按钮
            actionButton
        }
        .padding(EdgeInsets(top: 10.h, leading: 16.w, bottom: 10.h, trailing: 16.w))
    }

    @ViewBuilder
    private var actionButton: some View {
        Button(action: onFollowTapped) {
            switch buttonType {
            case .followBack:
                Text("Follow back")
                    .font(Font.custom("SF Pro Display", size: 12.f))
                    .tracking(0.24)
                    .foregroundColor(.white)
            case .following:
                Text("Following")
                    .font(Font.custom("SF Pro Display", size: 12.f))
                    .tracking(0.24)
                    .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
            case .follow:
                Text("Follow")
                    .font(Font.custom("SF Pro Display", size: 12.f))
                    .tracking(0.24)
                    .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
            case .friend:
                Text("Friend")
                    .font(Font.custom("SF Pro Display", size: 12.f))
                    .tracking(0.24)
                    .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
            }
        }
        .buttonStyle(.plain)
        .frame(width: 105.w, height: 34.h)
        .background(buttonType == .followBack ? Color(red: 0.87, green: 0.11, blue: 0.26) : Color.white)
        .cornerRadius(57.s)
        .overlay(
            RoundedRectangle(cornerRadius: 57.s)
                .inset(by: 0.75)
                .stroke(buttonStrokeColor, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
    }

    private var buttonStrokeColor: Color {
        switch buttonType {
        case .followBack:
            return Color.clear
        case .follow:
            return Color(red: 0.87, green: 0.11, blue: 0.26)
        case .following, .friend:
            return Color(red: 0.53, green: 0.53, blue: 0.53)
        }
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
