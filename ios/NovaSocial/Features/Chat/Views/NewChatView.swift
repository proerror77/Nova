import SwiftUI

struct NewChatView: View {
    @Binding var currentPage: AppPage

    // MARK: - State
    @State private var searchText = ""
    @State private var selectedUsers: [SearchedUser] = []
    @State private var searchResults: [SearchedUser] = []
    @State private var friends: [SearchedUser] = []
    @State private var starredFriends: [SearchedUser] = []
    @State private var isLoading = false
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showChat = false
    @State private var createdConversationId: String = ""
    @State private var createdConversationName: String = ""
    @State private var isPrivateChat = false  // E2EE encrypted private chat toggle

    // Group selection
    @State private var showGroupSelection = false
    @State private var showGroupChat = false
    @State private var selectedGroupId = ""
    @State private var selectedGroupName = ""
    @State private var selectedGroupMemberCount = 0

    @State private var isPreviewMode = false  // 追踪预览模式状态

    // MARK: - 预览模式配置 (开发调试用)
    // 🎨 在模拟器上运行时启用预览模式，方便调试UI
    #if DEBUG
    private static var usePreviewMode: Bool {
        #if targetEnvironment(simulator)
        return false  // 关闭模拟器预览模式，使用真实API
        #else
        return false
        #endif
    }
    #else
    private static let usePreviewMode = false
    #endif

    // MARK: - Computed Properties

    /// Group friends by first letter of display name
    private var groupedFriends: [Character: [SearchedUser]] {
        Dictionary(grouping: friends) { user in
            user.displayName.first?.uppercased().first ?? "#"
        }
    }

    // MARK: - Services
    private let friendsService = FriendsService()
    private let matrixBridge = MatrixBridgeService.shared

    // Simple user model for search results
    struct SearchedUser: Identifiable, Equatable {
        let id: String
        let username: String
        let displayName: String
        let avatarUrl: String?

        static func == (lhs: SearchedUser, rhs: SearchedUser) -> Bool {
            lhs.id == rhs.id
        }

        // Convert from UserProfile
        init(from profile: UserProfile) {
            self.id = profile.id
            self.username = profile.username
            self.displayName = profile.displayName ?? profile.username
            self.avatarUrl = profile.avatarUrl
        }

        init(id: String, username: String, displayName: String, avatarUrl: String?) {
            self.id = id
            self.username = username
            self.displayName = displayName
            self.avatarUrl = avatarUrl
        }
    }

    var body: some View {
        ZStack {
            if showChat {
                ChatView(
                    showChat: $showChat,
                    conversationId: createdConversationId,
                    userName: createdConversationName
                )
            } else if showGroupChat {
                GroupChatView(
                    showGroupChat: $showGroupChat,
                    conversationId: selectedGroupId,
                    groupName: selectedGroupName,
                    memberCount: selectedGroupMemberCount
                )
            } else {
                mainContent
            }
        }
        .onChange(of: showChat) { _, newValue in
            if !newValue {
                // Return to message list when chat is closed
                currentPage = .message
            }
        }
        .onChange(of: showGroupChat) { _, newValue in
            if !newValue {
                // Return to message list when group chat is closed
                currentPage = .message
            }
        }
        .sheet(isPresented: $showGroupSelection) {
            GroupSelectionView(isPresented: $showGroupSelection) { groupId, groupName, memberCount in
                selectedGroupId = groupId
                selectedGroupName = groupName
                selectedGroupMemberCount = memberCount
                showGroupChat = true
            }
        }
    }

    private var mainContent: some View {
        ZStack {
            DesignTokens.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Navigation Bar
                HStack(spacing: 0) {
                    Button(action: {
                        currentPage = .message
                    }) {
                        Image(systemName: "chevron.left")
                            .frame(width: 24, height: 24)
                            .foregroundColor(DesignTokens.textPrimary)
                    }
                    .frame(width: 60, alignment: .leading)

                    Spacer()

                    Text(selectedUsers.count > 1 ? "New Group Chat" : "New Chat")
                        .font(Font.custom("Helvetica Neue", size: 24).weight(.medium))
                        .foregroundColor(DesignTokens.textPrimary)

                    Spacer()

                    Button(action: {
                        Task { await createConversation() }
                    }) {
                        if isCreating {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text(selectedUsers.isEmpty ? "Start" : "Start(\(selectedUsers.count))")
                                .font(Font.custom("Helvetica Neue", size: 14))
                                .foregroundColor(selectedUsers.isEmpty ? DesignTokens.textMuted : DesignTokens.accentColor)
                        }
                    }
                    .frame(width: 70, alignment: .trailing)
                    .disabled(selectedUsers.isEmpty || isCreating)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .padding(.horizontal, 16)
                .background(DesignTokens.surface)
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(DesignTokens.borderColor),
                    alignment: .bottom
                )

                // MARK: - Search Box
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundColor(DesignTokens.textSecondary)

                    TextField("Search users...", text: $searchText)
                        .font(Font.custom("Helvetica Neue", size: 15))
                        .foregroundColor(DesignTokens.textPrimary)
                        .onChange(of: searchText) { _, newValue in
                            Task { await searchUsers(query: newValue) }
                        }
                }
                .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .frame(height: 32)
                .background(DesignTokens.tileBackground)
                .cornerRadius(32)
                .padding(EdgeInsets(top: 12, leading: 18, bottom: 16, trailing: 18))

                // MARK: - Private Chat Toggle
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: isPrivateChat ? "lock.fill" : "lock.open")
                            .font(.system(size: 16))
                            .foregroundColor(isPrivateChat ? DesignTokens.accentColor : DesignTokens.textSecondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Private Chat")
                                .font(Font.custom("Helvetica Neue", size: 15).weight(.medium))
                                .foregroundColor(DesignTokens.textPrimary)

                            Text(isPrivateChat ? "End-to-end encrypted" : "Standard chat (searchable)")
                                .font(Font.custom("Helvetica Neue", size: 12))
                                .foregroundColor(DesignTokens.textSecondary)
                        }
                    }

                    Spacer()

                    Toggle("", isOn: $isPrivateChat)
                        .labelsHidden()
                        .tint(DesignTokens.accentColor)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 12)

                // MARK: - Selected Users (horizontal scroll)
                if !selectedUsers.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(selectedUsers) { user in
                                SelectedUserChip(user: user) {
                                    selectedUsers.removeAll { $0.id == user.id }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .frame(height: 50)
                    .padding(.bottom, 8)
                }

                // MARK: - Error Message
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }

                // MARK: - User List
                ScrollView {
                    VStack(spacing: 0) {
                        if isLoading {
                            ProgressView()
                                .padding(.top, 40)
                        } else if !searchText.isEmpty {
                            // Search Results
                            if searchResults.isEmpty {
                                Text("No users found")
                                    .font(Font.custom("Helvetica Neue", size: 14))
                                    .foregroundColor(DesignTokens.textSecondary)
                                    .padding(.top, 40)
                            } else {
                                ForEach(searchResults) { user in
                                    UserRow(
                                        user: user,
                                        isSelected: selectedUsers.contains(user)
                                    )
                                    .onTapGesture {
                                        toggleUserSelection(user)
                                    }
                                }
                            }
                        } else {
                            // MARK: - Select an existing group
                            Button(action: {
                                showGroupSelection = true
                            }) {
                                HStack {
                                    Text("Select an existing group")
                                        .font(Font.custom("Helvetica Neue", size: 16).weight(.bold))
                                        .foregroundColor(DesignTokens.textPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14))
                                        .foregroundColor(DesignTokens.textMuted)
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 60)
                                .frame(maxWidth: .infinity)
                                .background(DesignTokens.backgroundColor)
                                .overlay(
                                    Rectangle()
                                        .frame(height: 0.2)
                                        .foregroundColor(DesignTokens.borderColor),
                                    alignment: .bottom
                                )
                            }

                            // MARK: - Starred Friends Section
                            if !starredFriends.isEmpty {
                                SectionHeader(title: "Starred Friends")

                                ForEach(starredFriends) { user in
                                    UserRow(
                                        user: user,
                                        isSelected: selectedUsers.contains(user)
                                    )
                                    .onTapGesture {
                                        toggleUserSelection(user)
                                    }
                                }
                            }

                            // MARK: - Friends List (grouped by letter)
                            if friends.isEmpty && starredFriends.isEmpty {
                                Text("Search for users to start a chat")
                                    .font(Font.custom("Helvetica Neue", size: 14))
                                    .foregroundColor(DesignTokens.textSecondary)
                                    .padding(.top, 40)
                            } else {
                                ForEach(groupedFriends.keys.sorted(), id: \.self) { letter in
                                    SectionHeader(title: String(letter))

                                    ForEach(groupedFriends[letter] ?? []) { user in
                                        UserRow(
                                            user: user,
                                            isSelected: selectedUsers.contains(user)
                                        )
                                        .onTapGesture {
                                            toggleUserSelection(user)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .task {
            await loadFriends()
        }
    }

    // MARK: - Actions

    private func toggleUserSelection(_ user: SearchedUser) {
        if selectedUsers.contains(user) {
            selectedUsers.removeAll { $0.id == user.id }
        } else {
            selectedUsers.append(user)
        }
    }

    private func searchUsers(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        // Debounce - only search if query hasn't changed
        try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
        guard searchText == query else { return }

        isLoading = true
        errorMessage = nil

        do {
            let profiles = try await friendsService.searchUsers(query: query, limit: 20)
            searchResults = profiles.map { SearchedUser(from: $0) }

            #if DEBUG
            print("[NewChatView] Found \(searchResults.count) users for query: \(query)")
            #endif
        } catch {
            errorMessage = "Search failed"
            #if DEBUG
            print("[NewChatView] Search error: \(error)")
            #endif
        }

        isLoading = false
    }

    private func loadFriends() async {
        // 🎨 预览模式：使用模拟数据进行UI调试
        if Self.usePreviewMode {
            print("🎨 [NewChatView] Preview Mode enabled - using mock data")
            await MainActor.run {
                loadMockData()
                isLoading = false
                errorMessage = nil
                isPreviewMode = true
            }
            return
        }

        await MainActor.run {
            isPreviewMode = false
        }

        isLoading = true
        errorMessage = nil

        do {
            let (friendProfiles, _) = try await friendsService.getFriendsList(limit: 50)
            friends = friendProfiles.map { SearchedUser(from: $0) }

            #if DEBUG
            print("[NewChatView] Loaded \(friends.count) friends")
            #endif
        } catch {
            errorMessage = "Failed to load friends: \(error.localizedDescription)"
            #if DEBUG
            print("[NewChatView] Failed to load friends: \(error)")
            #endif
        }

        isLoading = false
    }

    private func loadMockData() {
        // Mock starred friends
        starredFriends = [
            SearchedUser(id: "1", username: "bruce_li", displayName: "Bruce Li", avatarUrl: nil),
            SearchedUser(id: "2", username: "alice_wang", displayName: "Alice Wang", avatarUrl: nil),
        ]

        // Mock friends list (grouped by letter)
        friends = [
            SearchedUser(id: "3", username: "adam_chen", displayName: "Adam Chen", avatarUrl: nil),
            SearchedUser(id: "4", username: "amy_liu", displayName: "Amy Liu", avatarUrl: nil),
            SearchedUser(id: "5", username: "bob_zhang", displayName: "Bob Zhang", avatarUrl: nil),
            SearchedUser(id: "6", username: "bella_wu", displayName: "Bella Wu", avatarUrl: nil),
            SearchedUser(id: "7", username: "charlie_lee", displayName: "Charlie Lee", avatarUrl: nil),
            SearchedUser(id: "8", username: "david_huang", displayName: "David Huang", avatarUrl: nil),
            SearchedUser(id: "9", username: "emma_lin", displayName: "Emma Lin", avatarUrl: nil),
        ]
    }

    private func createConversation(retryCount: Int = 0) async {
        guard !selectedUsers.isEmpty else { return }

        isCreating = true
        errorMessage = nil

        do {
            if !matrixBridge.isInitialized {
                try await matrixBridge.initialize()
            }

            // Use user IDs (UUIDs) for Matrix user ID construction
            // This is critical for findExistingDirectRoom to detect existing DMs
            let participantIds = selectedUsers.map { $0.id }
            let groupName: String? = selectedUsers.count > 1
                ? selectedUsers.map { $0.displayName }.joined(separator: ", ")
                : nil

            #if DEBUG
            print("[NewChatView] Creating Matrix room with user IDs: \(participantIds)")
            #endif

            let room: MatrixBridgeService.MatrixConversationInfo
            if selectedUsers.count == 1 {
                room = try await matrixBridge.createDirectConversation(
                    withUserId: participantIds[0],
                    displayName: selectedUsers[0].displayName,
                    isPrivate: isPrivateChat
                )
            } else {
                room = try await matrixBridge.createGroupConversation(
                    name: groupName ?? "Group Chat",
                    userIds: participantIds,
                    isPrivate: isPrivateChat
                )
            }

            #if DEBUG
            print("[NewChatView] Created \(isPrivateChat ? "private (E2EE)" : "regular") conversation: \(room.id)")
            #endif

            createdConversationId = room.id
            createdConversationName = selectedUsers.count == 1
                ? selectedUsers[0].displayName
                : (groupName ?? "Group Chat")

            // Navigate to the chat
            showChat = true

        } catch MatrixBridgeError.sessionExpired {
            // Session expired - clearSessionData() has already been called
            // Auto-retry once with fresh credentials
            if retryCount < 1 {
                #if DEBUG
                print("⚠️ [NewChatView] Session expired, forcing re-initialization and retrying...")
                #endif
                isCreating = false

                // Force re-initialization to get fresh credentials from backend
                do {
                    try await matrixBridge.initialize(requireLogin: true)
                } catch {
                    #if DEBUG
                    print("❌ [NewChatView] Failed to re-initialize Matrix bridge: \(error)")
                    #endif
                    errorMessage = "無法重新連接: \(error.localizedDescription)"
                    return
                }

                await createConversation(retryCount: retryCount + 1)
                return
            } else {
                errorMessage = "Session 已過期，請重新登入後再試"
                #if DEBUG
                print("❌ [NewChatView] Session still expired after retry")
                #endif
            }

        } catch {
            errorMessage = "Failed to create conversation: \(error.localizedDescription)"
            #if DEBUG
            print("[NewChatView] Create conversation error: \(error)")
            #endif
        }

        isCreating = false
    }
}

// MARK: - User Row Component
struct UserRow: View {
    let user: NewChatView.SearchedUser
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 13) {
            // Selection circle
            ZStack {
                Circle()
                    .stroke(DesignTokens.textMuted, lineWidth: 0.50)
                    .frame(width: 20, height: 20)

                if isSelected {
                    Circle()
                        .fill(DesignTokens.accentColor)
                        .frame(width: 12, height: 12)
                }
            }

            // Avatar
            if let avatarUrl = user.avatarUrl, !avatarUrl.isEmpty {
                AsyncImage(url: URL(string: avatarUrl)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    DefaultAvatarView(size: 42)
                }
                .frame(width: 42, height: 42)
                .clipShape(Circle())
            } else {
                DefaultAvatarView(size: 42)
            }

            // User info
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(Font.custom("Helvetica Neue", size: 16).weight(.bold))
                    .foregroundColor(DesignTokens.textPrimary)

                Text("@\(user.username)")
                    .font(Font.custom("Helvetica Neue", size: 13))
                    .foregroundColor(DesignTokens.textSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
        .frame(maxWidth: .infinity)
        .background(DesignTokens.backgroundColor)
        .overlay(
            Rectangle()
                .inset(by: 0.20)
                .stroke(DesignTokens.borderColor, lineWidth: 0.20)
        )
    }
}

// MARK: - Selected User Chip
struct SelectedUserChip: View {
    let user: NewChatView.SearchedUser
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            // Small avatar
            if let avatarUrl = user.avatarUrl, !avatarUrl.isEmpty {
                AsyncImage(url: URL(string: avatarUrl)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    DefaultAvatarView(size: 24)
                }
                .frame(width: 24, height: 24)
                .clipShape(Circle())
            } else {
                DefaultAvatarView(size: 24)
            }

            Text(user.displayName)
                .font(Font.custom("Helvetica Neue", size: 14))
                .foregroundColor(DesignTokens.textPrimary)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(DesignTokens.textMuted)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DesignTokens.tileBackground)
        .cornerRadius(20)
    }
}

// MARK: - Section Header
struct SectionHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(Font.custom("Helvetica Neue", size: 16).weight(.bold))
                .foregroundColor(DesignTokens.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(DesignTokens.backgroundColor)
    }
}

// MARK: - Previews

#Preview("NewChat - Default") {
    NewChatView(currentPage: .constant(.newChat))
        .environmentObject(AuthenticationManager.shared)
}

#Preview("NewChat - Dark Mode") {
    NewChatView(currentPage: .constant(.newChat))
        .environmentObject(AuthenticationManager.shared)
        .preferredColorScheme(.dark)
}
