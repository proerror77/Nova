import SwiftUI

// MARK: - Add Friends ViewModel

/// AddFriendsViewModel - 添加好友頁面的 ViewModel
/// 架構說明：
/// - 使用 FriendsService 搜索用戶 (可用的端點)
/// - 使用 FeedService 獲取推薦創作者 (已部署的端點)
/// - 使用 GraphService 處理 Follow 關係
/// - 使用 MatrixBridgeService 開始 E2EE 對話
@MainActor
@Observable
class AddFriendsViewModel {
    var searchQuery: String = ""
    var searchResults: [UserProfile] = []
    var recommendations: [RecommendedCreator] = []
    var isSearching: Bool = false
    var isLoadingRecommendations: Bool = false
    var errorMessage: String?
    var toastMessage: String?

    // Chat navigation state
    var showChat: Bool = false
    var chatConversationId: String = ""
    var chatUserName: String = ""
    var isCreatingChat: Bool = false

    private let friendsService = FriendsService()
    private let feedService = FeedService()
    private let graphService = GraphService()
    private let userService = UserService.shared
    private let matrixBridge = MatrixBridgeService.shared

    func loadRecommendations() async {
        isLoadingRecommendations = true
        errorMessage = nil

        do {
            // 使用 FeedService 獲取推薦創作者（已部署的端點）
            recommendations = try await feedService.getRecommendedCreators(limit: 20)
        } catch {
            // 如果端點也未部署（501），顯示空狀態而非錯誤
            if case APIError.serverError(let statusCode, _) = error, statusCode == 501 || statusCode == 503 {
                recommendations = []
                #if DEBUG
                print("[AddFriendsView] Recommendations endpoint not deployed yet")
                #endif
            } else {
                errorMessage = "加载推荐联系人失败: \(error.localizedDescription)"
                #if DEBUG
                print("❌ Failed to load recommendations: \(error)")
                #endif
            }
        }

        isLoadingRecommendations = false
    }

    func searchUsers() async {
        guard !searchQuery.isEmpty else {
            searchResults = []
            return
        }

        isSearching = true
        errorMessage = nil

        do {
            // 優先使用 FriendsService 搜索用戶 (返回 [UserProfile])
            searchResults = try await friendsService.searchUsers(query: searchQuery, limit: 20)
            #if DEBUG
            print("[AddFriendsView] Search returned \(searchResults.count) results")
            #endif
            // 如果搜索返回空結果，也嘗試直接用戶名查找
            if searchResults.isEmpty {
                #if DEBUG
                print("[AddFriendsView] Search returned empty, trying fallback...")
                #endif
                await searchUserByUsernameFallback()
            }
        } catch {
            // 如果 search-service 返回 503/502/401 錯誤，嘗試備用方案
            if case APIError.serverError(let statusCode, _) = error,
               statusCode == 503 || statusCode == 502 || statusCode == 401 {
                #if DEBUG
                print("[AddFriendsView] Search service error (\(statusCode)), trying fallback...")
                #endif
                // 備用方案：直接通過用戶名查找
                await searchUserByUsernameFallback()
            } else if case APIError.unauthorized = error {
                #if DEBUG
                print("[AddFriendsView] Search unauthorized, trying fallback...")
                #endif
                await searchUserByUsernameFallback()
            } else {
                errorMessage = "搜索失败: \(error.localizedDescription)"
                #if DEBUG
                print("❌ Search failed: \(error)")
                #endif
            }
        }

        isSearching = false
    }

    /// 備用搜索方案：當 search-service 不可用時，直接通過用戶名查找
    private func searchUserByUsernameFallback() async {
        do {
            // 嘗試通過精確用戶名查找
            let user = try await userService.getUserByUsername(searchQuery.lowercased())
            searchResults = [user]
            #if DEBUG
            print("[AddFriendsView] Fallback search found user: \(user.username)")
            #endif
        } catch {
            // 如果找不到精確匹配，顯示空結果而非錯誤
            searchResults = []
            #if DEBUG
            print("[AddFriendsView] Fallback search: no user found for '\(searchQuery)'")
            #endif
        }
    }

    func followUser(userId: String) async {
        errorMessage = nil

        do {
            // 使用 GraphService 進行 Follow
            guard let currentUserId = AuthenticationManager.shared.currentUser?.id else {
                errorMessage = "请先登录"
                return
            }
            try await graphService.followUser(followerId: currentUserId, followeeId: userId)
            showToast("已关注")
        } catch {
            errorMessage = "关注失败: \(error.localizedDescription)"
            #if DEBUG
            print("❌ Failed to follow user: \(error)")
            #endif
        }
    }

    func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                toastMessage = nil
            }
        }
    }

    // MARK: - Start Chat with User

    /// 開始與用戶的 E2EE 對話
    /// 使用 Matrix Bridge 創建加密聊天室
    /// - Parameter retryCount: Internal retry counter for session expiry handling
    func startChat(with user: UserProfile, retryCount: Int = 0) async {
        guard !isCreatingChat else { return }

        isCreatingChat = true
        errorMessage = nil

        do {
            if !matrixBridge.isInitialized {
                try await matrixBridge.initialize()
            }

            let room = try await matrixBridge.createDirectConversation(
                withUserId: user.id,
                displayName: user.displayName ?? user.username
            )

            // Navigate to chat
            chatConversationId = room.id
            chatUserName = user.displayName ?? user.username
            showChat = true

        } catch MatrixBridgeError.sessionExpired {
            // Session expired - clearSessionData() has already been called
            // Auto-retry once with fresh credentials
            if retryCount < 1 {
                #if DEBUG
                print("⚠️ [AddFriends] Session expired, forcing re-initialization and retrying...")
                #endif
                isCreatingChat = false

                // Force re-initialization to get fresh credentials from backend
                do {
                    try await matrixBridge.initialize(requireLogin: true)
                } catch {
                    #if DEBUG
                    print("❌ [AddFriends] Failed to re-initialize Matrix bridge: \(error)")
                    #endif
                    errorMessage = "無法重新連接: \(error.localizedDescription)"
                    return
                }

                await startChat(with: user, retryCount: retryCount + 1)
                return
            } else {
                errorMessage = "無法開始對話: 請重新登入後再試"
                #if DEBUG
                print("❌ Failed to start chat after retry: session still expired")
                #endif
            }

        } catch {
            errorMessage = "無法開始對話: \(error.localizedDescription)"
            #if DEBUG
            print("❌ Failed to start chat: \(error)")
            #endif
        }

        isCreatingChat = false
    }

    /// 開始與推薦創作者的對話
    func startChat(with creator: RecommendedCreator) async {
        // Convert RecommendedCreator to UserProfile for consistency
        let userProfile = UserProfile(
            id: creator.id,
            username: creator.username,
            email: nil,
            displayName: creator.displayName,
            bio: nil,
            avatarUrl: creator.avatarUrl,
            coverUrl: nil,
            website: nil,
            location: nil,
            isVerified: creator.isVerified,
            isPrivate: nil,
            isBanned: nil,
            followerCount: nil,
            followingCount: nil,
            postCount: nil,
            createdAt: nil,
            updatedAt: nil,
            deletedAt: nil,
            firstName: nil,
            lastName: nil,
            dateOfBirth: nil,
            gender: nil
        )
        await startChat(with: userProfile)
    }
}

// MARK: - Add Friends View

struct AddFriendsView: View {
    @Binding var currentPage: AppPage
    @State private var viewModel = AddFriendsViewModel()
    @State private var showQRScanner = false
    @State private var showMyQRCode = false

    var body: some View {
        ZStack {
            // Navigate to ChatView when chat is created
            if viewModel.showChat {
                ChatView(
                    showChat: $viewModel.showChat,
                    conversationId: viewModel.chatConversationId,
                    userName: viewModel.chatUserName
                )
            } else {
                mainContent
            }
        }
        .onChange(of: viewModel.showChat) { _, newValue in
            if !newValue {
                // Optionally navigate back to message list
                // currentPage = .message
            }
        }
    }

    private var mainContent: some View {
        ZStack {
            Color(red: 0.97, green: 0.97, blue: 0.97)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Navigation Bar
                HStack {
                    Button(action: {
                        currentPage = .message
                    }) {
                        Image(systemName: "chevron.left")
                            .frame(width: 24, height: 24)
                            .foregroundColor(.black)
                    }

                    Spacer()

                    Text("Add friends")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.black)

                    Spacer()

                    // QR Code button
                    Button(action: {
                        showQRScanner = true
                    }) {
                        Image(systemName: "qrcode.viewfinder")
                            .frame(width: 24, height: 24)
                            .foregroundColor(.black)
                    }
                }
                .frame(height: 56)
                .padding(.horizontal, 16)
                .background(Color.white)

                Divider()

                // MARK: - Search Bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

                    TextField("Search", text: $viewModel.searchQuery)
                        .font(.system(size: 15))
                        .foregroundColor(.black)
                        .onChange(of: viewModel.searchQuery) { _, newValue in
                            if !newValue.isEmpty {
                                Task {
                                    try? await Task.sleep(for: .milliseconds(300))
                                    if viewModel.searchQuery == newValue {
                                        await viewModel.searchUsers()
                                    }
                                }
                            }
                        }

                    Spacer()

                    if viewModel.isSearching {
                        ProgressView().scaleEffect(0.8)
                    }
                }
                .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(Color(red: 0.91, green: 0.91, blue: 0.91))
                .cornerRadius(32)
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // MARK: - Error Message
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                // MARK: - Creating Chat Indicator
                if viewModel.isCreatingChat {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Creating encrypted chat...")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 12)
                }

                ScrollView {
                    VStack(spacing: 16) {
                        // MARK: - QR Code Actions
                        VStack(spacing: 12) {
                            // Scan QR Code Button
                            Button(action: {
                                showQRScanner = true
                            }) {
                                HStack(spacing: 16) {
                                    Image(systemName: "qrcode.viewfinder")
                                        .font(.system(size: 20))
                                        .foregroundColor(.blue)
                                        .frame(width: 40, height: 40)
                                        .background(Color.blue.opacity(0.1))
                                        .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(String(localized: "scan_qr_code", defaultValue: "Scan QR Code"))
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.black)

                                        Text(String(localized: "scan_qr_hint", defaultValue: "Scan a friend's QR code to add them"))
                                            .font(.system(size: 12))
                                            .foregroundColor(.gray)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.gray)
                                }
                                .padding(16)
                                .background(Color.white)
                                .cornerRadius(12)
                            }

                            // My QR Code Button
                            Button(action: {
                                showMyQRCode = true
                            }) {
                                HStack(spacing: 16) {
                                    Image(systemName: "qrcode")
                                        .font(.system(size: 20))
                                        .foregroundColor(.green)
                                        .frame(width: 40, height: 40)
                                        .background(Color.green.opacity(0.1))
                                        .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(String(localized: "my_qr_code", defaultValue: "My QR Code"))
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.black)

                                        Text(String(localized: "my_qr_hint", defaultValue: "Let others scan to add you"))
                                            .font(.system(size: 12))
                                            .foregroundColor(.gray)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.gray)
                                }
                                .padding(16)
                                .background(Color.white)
                                .cornerRadius(12)
                            }

                            // Friend Requests Button
                            Button(action: {
                                currentPage = .friendRequests
                            }) {
                                HStack(spacing: 16) {
                                    Image(systemName: "person.badge.clock")
                                        .font(.system(size: 20))
                                        .foregroundColor(.orange)
                                        .frame(width: 40, height: 40)
                                        .background(Color.orange.opacity(0.1))
                                        .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(String(localized: "friend_requests", defaultValue: "Friend Requests"))
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.black)

                                        Text(String(localized: "friend_requests_hint", defaultValue: "View and manage friend requests"))
                                            .font(.system(size: 12))
                                            .foregroundColor(.gray)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.gray)
                                }
                                .padding(16)
                                .background(Color.white)
                                .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                        // MARK: - Search Results
                        if !viewModel.searchResults.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("搜索结果")
                                    .font(.system(size: 17.50, weight: .bold))
                                    .foregroundColor(Color(red: 0.32, green: 0.32, blue: 0.32))
                                    .padding(.horizontal, 24)

                                ForEach(viewModel.searchResults) { user in
                                    UserCardView(
                                        user: user,
                                        onFollow: {
                                            Task {
                                                await viewModel.followUser(userId: user.id)
                                            }
                                        },
                                        onChat: {
                                            Task {
                                                await viewModel.startChat(with: user)
                                            }
                                        }
                                    )
                                    .padding(.horizontal, 16)
                                }
                            }
                            .padding(.top, 8)
                        }

                        // MARK: - Recommendations
                        if !viewModel.recommendations.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("推荐关注")
                                    .font(.system(size: 17.50, weight: .bold))
                                    .foregroundColor(Color(red: 0.32, green: 0.32, blue: 0.32))
                                    .padding(.horizontal, 24)

                                ForEach(viewModel.recommendations) { creator in
                                    RecommendedCreatorCard(
                                        creator: creator,
                                        onFollow: {
                                            Task {
                                                await viewModel.followUser(userId: creator.id)
                                            }
                                        },
                                        onChat: {
                                            Task {
                                                await viewModel.startChat(with: creator)
                                            }
                                        }
                                    )
                                    .padding(.horizontal, 16)
                                }
                            }
                            .padding(.top, viewModel.searchResults.isEmpty ? 8 : 0)
                        }

                        // MARK: - Loading
                        if viewModel.isLoadingRecommendations {
                            ProgressView("加载推荐联系人...").padding()
                        }

                        // MARK: - Share Button
                        Button(action: {}) {
                            HStack(spacing: 24) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

                                Text("Share invitation link")
                                    .font(.system(size: 15))
                                    .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

                                Spacer()
                            }
                            .padding(EdgeInsets(top: 7, leading: 37, bottom: 7, trailing: 37))
                            .frame(maxWidth: .infinity, minHeight: 35.h)
                        }
                        .background(Color.white)
                        .cornerRadius(23)
                        .overlay(
                            RoundedRectangle(cornerRadius: 23)
                                .inset(by: 0.50)
                                .stroke(Color(red: 0.75, green: 0.75, blue: 0.75), lineWidth: 0.50)
                        )
                        .padding(.top, 16)
                    }
                }
            }

            // MARK: - Toast Message
            if let toast = viewModel.toastMessage {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(20)
                        .padding(.bottom, 100)
                }
                .transition(.opacity)
                .animation(.easeInOut, value: viewModel.toastMessage)
            }
        }
        .task {
            await viewModel.loadRecommendations()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .fullScreenCover(isPresented: $showQRScanner) {
            QRCodeScannerView(
                isPresented: $showQRScanner,
                onFriendAdded: { userId in
                    viewModel.showToast(String(localized: "friend_added_toast", defaultValue: "Friend added successfully!"))
                    Task {
                        await viewModel.loadRecommendations()
                    }
                }
            )
        }
        .sheet(isPresented: $showMyQRCode) {
            MyQRCodeView()
        }
    }
}

// MARK: - User Card Component

struct UserCardView: View {
    let user: UserProfile
    let onFollow: () -> Void
    let onChat: () -> Void
    @State private var isAdding: Bool = false
    @State private var isAdded: Bool = false

    var body: some View {
        HStack(spacing: 13) {
            // 头像 - 使用统一的默认头像组件
            AvatarView(image: nil, url: user.avatarUrl, size: 50)

            VStack(alignment: .leading, spacing: 1) {
                Text(user.displayName ?? user.username)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)

                if let bio = user.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.system(size: 11.50, weight: .medium))
                        .foregroundColor(Color(red: 0.65, green: 0.65, blue: 0.65))
                        .lineLimit(1)
                } else {
                    Text("@\(user.username)")
                        .font(.system(size: 11.50, weight: .medium))
                        .foregroundColor(Color(red: 0.65, green: 0.65, blue: 0.65))
                }
            }

            Spacer()

            // Chat button - Start E2EE conversation
            Button(action: onChat) {
                Image(systemName: "message.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color(red: 0.87, green: 0.11, blue: 0.26))
                    .clipShape(Circle())
            }

            // Follow button
            Button(action: {
                guard !isAdding && !isAdded else { return }
                isAdding = true
                onFollow()
                isAdded = true
                isAdding = false
            }) {
                if isAdding {
                    ProgressView().scaleEffect(0.8)
                } else if isAdded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                }
            }
            .disabled(isAdding || isAdded)
        }
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        .frame(maxWidth: .infinity)
        .frame(height: 67)
        .background(Color(red: 0.97, green: 0.96, blue: 0.96))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .inset(by: 0.50)
                .stroke(Color(red: 0.75, green: 0.75, blue: 0.75), lineWidth: 0.50)
        )
    }
}

// MARK: - Recommended Creator Card Component

struct RecommendedCreatorCard: View {
    let creator: RecommendedCreator
    let onFollow: () -> Void
    let onChat: () -> Void
    @State private var isFollowing: Bool = false
    @State private var isFollowed: Bool = false

    var body: some View {
        HStack(spacing: 13) {
            // 头像
            AvatarView(image: nil, url: creator.avatarUrl, size: 50)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(creator.displayName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)

                    if creator.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                    }
                }

                Text("@\(creator.username)")
                    .font(.system(size: 11.50, weight: .medium))
                    .foregroundColor(Color(red: 0.65, green: 0.65, blue: 0.65))

                if let reason = creator.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.system(size: 10))
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Chat button - Start E2EE conversation
            Button(action: onChat) {
                Image(systemName: "message.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color(red: 0.87, green: 0.11, blue: 0.26))
                    .clipShape(Circle())
            }

            // Follow button
            Button(action: {
                guard !isFollowing && !isFollowed else { return }
                isFollowing = true
                onFollow()
                isFollowed = true
                isFollowing = false
            }) {
                if isFollowing {
                    ProgressView().scaleEffect(0.8)
                } else if isFollowed {
                    Text("已关注")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.9, green: 0.9, blue: 0.9))
                        .cornerRadius(14)
                } else {
                    Text("关注")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.87, green: 0.11, blue: 0.26))
                        .cornerRadius(14)
                }
            }
            .disabled(isFollowing || isFollowed)
        }
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        .frame(maxWidth: .infinity)
        .frame(minHeight: 67)
        .background(Color(red: 0.97, green: 0.96, blue: 0.96))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .inset(by: 0.50)
                .stroke(Color(red: 0.75, green: 0.75, blue: 0.75), lineWidth: 0.50)
        )
    }
}

// MARK: - Previews

#Preview("AddFriends - Default") {
    AddFriendsView(currentPage: .constant(.addFriends))
        .environmentObject(AuthenticationManager.shared)
}

#Preview("AddFriends - Dark Mode") {
    AddFriendsView(currentPage: .constant(.addFriends))
        .environmentObject(AuthenticationManager.shared)
        .preferredColorScheme(.dark)
}
