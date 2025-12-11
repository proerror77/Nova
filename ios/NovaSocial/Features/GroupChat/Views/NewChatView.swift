import SwiftUI

/// NewChatView - 創建新聊天頁面
/// 架構說明：
/// - 使用 ChatService 獲取/創建對話 (realtime-chat-service)
/// - 使用 GraphService 獲取可聊天的用戶 (follow 關係)
/// - 對話創建後會同步到 Matrix (由後端處理)
struct NewChatView: View {
    @Binding var currentPage: AppPage
    @State private var selectedUserIds: Set<String> = []
    @State private var followingUsers: [UserProfile] = []
    @State private var existingConversations: [Conversation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var isCreatingChat = false

    private let chatService = ChatService()
    private let graphService = GraphService()
    private let identityService = IdentityService()

    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.97, blue: 0.97)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 頂部導航欄
                navigationBar

                // MARK: - 搜索框
                searchBar

                // MARK: - 內容
                if isLoading {
                    loadingView
                } else if let error = errorMessage {
                    errorView(error)
                } else {
                    contentView
                }
            }
        }
        .task {
            await loadData()
        }
    }

    // MARK: - Navigation Bar
    private var navigationBar: some View {
        HStack(spacing: 0) {
            Button(action: {
                currentPage = .message
            }) {
                Image(systemName: "chevron.left")
                    .frame(width: 24, height: 24)
                    .foregroundColor(.black)
            }
            .frame(width: 60, alignment: .leading)

            Spacer()

            Text("New Chat")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(.black)

            Spacer()

            Button(action: {
                Task {
                    await createNewChat()
                }
            }) {
                if isCreatingChat {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text(selectedUserIds.isEmpty ? "Create" : "Create(\(selectedUserIds.count))")
                        .font(.system(size: 14))
                        .foregroundColor(selectedUserIds.isEmpty ? Color(red: 0.53, green: 0.53, blue: 0.53) : Color(red: 0.87, green: 0.11, blue: 0.26))
                }
            }
            .frame(width: 80, alignment: .trailing)
            .disabled(selectedUserIds.isEmpty || isCreatingChat)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .padding(.horizontal, 16)
        .background(.white)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(red: 0.74, green: 0.74, blue: 0.74)),
            alignment: .bottom
        )
    }

    // MARK: - Search Bar
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundColor(Color(red: 0.69, green: 0.68, blue: 0.68))

            TextField("Search users", text: $searchText)
                .font(.system(size: 15))
                .foregroundColor(.black)
        }
        .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .frame(height: 32)
        .background(Color(red: 0.89, green: 0.88, blue: 0.87))
        .cornerRadius(32)
        .padding(EdgeInsets(top: 12, leading: 18, bottom: 16, trailing: 18))
    }

    // MARK: - Loading View
    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading...")
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .padding(.top, 8)
            Spacer()
        }
    }

    // MARK: - Error View
    private func errorView(_ error: String) -> some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundColor(.gray)
                Text(error)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task {
                        await loadData()
                    }
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
            }
            .padding()
            Spacer()
        }
    }

    // MARK: - Content View
    private var contentView: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                // MARK: - Recent Conversations Section
                if !existingConversations.isEmpty && searchText.isEmpty {
                    Section {
                        ForEach(existingConversations) { conversation in
                            ConversationRow(conversation: conversation)
                                .onTapGesture {
                                    // Navigate to existing conversation
                                    navigateToConversation(conversation)
                                }
                        }
                    } header: {
                        sectionHeader("Recent Chats")
                    }
                }

                // MARK: - Following Users Section (可發起聊天的用戶)
                if !filteredUsers.isEmpty {
                    Section {
                        ForEach(filteredUsers) { user in
                            SelectableUserRow(
                                user: user,
                                isSelected: selectedUserIds.contains(user.id)
                            )
                            .onTapGesture {
                                toggleSelection(user.id)
                            }
                        }
                    } header: {
                        sectionHeader("Start New Chat")
                    }
                }

                // MARK: - Empty State
                if filteredUsers.isEmpty && existingConversations.isEmpty {
                    emptyStateView
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(red: 0.97, green: 0.97, blue: 0.97))
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            Text(searchText.isEmpty ? "Follow users to start chatting" : "No users found")
                .font(.system(size: 14))
                .foregroundColor(.gray)
        }
        .padding(.top, 60)
    }

    // MARK: - Filtered Users
    private var filteredUsers: [UserProfile] {
        if searchText.isEmpty {
            return followingUsers
        }
        return followingUsers.filter { user in
            let name = user.displayName ?? user.username
            return name.localizedCaseInsensitiveContains(searchText) ||
                   user.username.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Load Data
    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            // Load conversations and following users in parallel
            async let conversationsTask = chatService.getConversations(limit: 10)
            async let followingTask: () = loadFollowingUsers()

            let conversations = try await conversationsTask
            try await followingTask  // Wait for following users to load (updates state internally)

            await MainActor.run {
                existingConversations = conversations
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load: \(error.localizedDescription)"
                isLoading = false
            }
            #if DEBUG
            print("[NewChatView] Failed to load data: \(error)")
            #endif
        }
    }

    private func loadFollowingUsers() async throws {
        guard let currentUserId = AuthenticationManager.shared.currentUser?.id else {
            #if DEBUG
            print("[NewChatView] No current user ID available")
            #endif
            return
        }

        do {
            // Step 1: Get user IDs from Graph Service
            let result = try await graphService.getFollowing(userId: currentUserId, limit: 50)

            // Step 2: Fetch full user profiles for each ID
            var profiles: [UserProfile] = []
            for userId in result.userIds {
                do {
                    let profile = try await identityService.getUser(userId: userId)
                    profiles.append(profile)
                } catch {
                    #if DEBUG
                    print("[NewChatView] Failed to load profile for user \(userId): \(error)")
                    #endif
                    // Continue loading other profiles
                }
            }

            await MainActor.run {
                followingUsers = profiles
            }
        } catch {
            #if DEBUG
            print("[NewChatView] Failed to load following users: \(error)")
            #endif
            // Don't throw - just show empty state for users
        }
    }

    // MARK: - Create New Chat
    private func createNewChat() async {
        guard !selectedUserIds.isEmpty else { return }

        isCreatingChat = true

        do {
            let participantIds = Array(selectedUserIds)
            let conversationType: ConversationType = participantIds.count > 1 ? .group : .direct

            let conversation = try await chatService.createConversation(
                type: conversationType,
                participantIds: participantIds,
                name: conversationType == .group ? "New Group" : nil
            )

            await MainActor.run {
                isCreatingChat = false
                // Navigate to the new conversation
                navigateToConversation(conversation)
            }
        } catch {
            await MainActor.run {
                isCreatingChat = false
                errorMessage = "Failed to create chat: \(error.localizedDescription)"
            }
            #if DEBUG
            print("[NewChatView] Failed to create conversation: \(error)")
            #endif
        }
    }

    private func navigateToConversation(_ conversation: Conversation) {
        // TODO: Navigate to ChatView with conversation
        // For now, go back to message list
        currentPage = .message
    }

    private func toggleSelection(_ userId: String) {
        if selectedUserIds.contains(userId) {
            selectedUserIds.remove(userId)
        } else {
            selectedUserIds.insert(userId)
        }
    }
}

// MARK: - Conversation Row Component
struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 13) {
            // Avatar
            if let avatarUrl = conversation.avatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
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

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(conversationDisplayName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)
                    .lineLimit(1)

                if let lastMessage = conversation.lastMessage {
                    Text(lastMessage.content.isEmpty ? "Encrypted message" : lastMessage.content)
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Unread count
            if conversation.unreadCount > 0 {
                Text("\(conversation.unreadCount)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Color(red: 0.87, green: 0.11, blue: 0.26))
                    .clipShape(Circle())
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
        .background(Color(red: 0.97, green: 0.97, blue: 0.97))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(red: 0.77, green: 0.77, blue: 0.77)),
            alignment: .bottom
        )
    }

    private var conversationDisplayName: String {
        if let name = conversation.name, !name.isEmpty {
            return name
        }
        // For direct chats, show the other person's username
        let memberNames = conversation.members.map { $0.username }
        return memberNames.joined(separator: ", ")
    }
}

// MARK: - Selectable User Row Component
struct SelectableUserRow: View {
    let user: UserProfile
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 13) {
            // Selection indicator
            ZStack {
                Circle()
                    .stroke(Color(red: 0.53, green: 0.53, blue: 0.53), lineWidth: 0.5)
                    .frame(width: 20, height: 20)

                if isSelected {
                    Circle()
                        .fill(Color(red: 0.82, green: 0.11, blue: 0.26))
                        .frame(width: 12, height: 12)
                }
            }

            // Avatar
            if let avatarUrl = user.avatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
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
            VStack(alignment: .leading, spacing: 1) {
                Text(user.displayName ?? user.username)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)

                if let displayName = user.displayName, !displayName.isEmpty {
                    Text("@\(user.username)")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
        .background(Color(red: 0.97, green: 0.97, blue: 0.97))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(red: 0.77, green: 0.77, blue: 0.77)),
            alignment: .bottom
        )
    }
}

#Preview {
    NewChatView(currentPage: .constant(.newChat))
}
