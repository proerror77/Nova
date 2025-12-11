import SwiftUI

struct NewChatView: View {
    @Binding var currentPage: AppPage

    // MARK: - State
    @State private var searchText = ""
    @State private var selectedUsers: [SearchedUser] = []
    @State private var searchResults: [SearchedUser] = []
    @State private var friends: [SearchedUser] = []
    @State private var isLoading = false
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showChat = false
    @State private var createdConversationId: String = ""
    @State private var createdConversationName: String = ""

    // MARK: - Services
    private let chatService = ChatService()
    private let friendsService = FriendsService()

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
                            // Show Friends List
                            if friends.isEmpty {
                                Text("Search for users to start a chat")
                                    .font(Font.custom("Helvetica Neue", size: 14))
                                    .foregroundColor(DesignTokens.textSecondary)
                                    .padding(.top, 40)
                            } else {
                                HStack {
                                    Text("Friends")
                                        .font(Font.custom("Helvetica Neue", size: 16).weight(.bold))
                                        .foregroundColor(DesignTokens.textSecondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)

                                ForEach(friends) { user in
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
        isLoading = true
        errorMessage = nil

        do {
            let (friendProfiles, _) = try await friendsService.getFriendsList(limit: 50)
            friends = friendProfiles.map { SearchedUser(from: $0) }

            #if DEBUG
            print("[NewChatView] Loaded \(friends.count) friends")
            #endif
        } catch {
            // Friends loading failed is non-critical, just log
            #if DEBUG
            print("[NewChatView] Failed to load friends: \(error)")
            #endif
        }

        isLoading = false
    }

    private func createConversation() async {
        guard !selectedUsers.isEmpty else { return }

        isCreating = true
        errorMessage = nil

        do {
            let participantIds = selectedUsers.map { $0.id }
            let conversationType: ConversationType = selectedUsers.count == 1 ? .direct : .group
            let groupName: String? = selectedUsers.count > 1
                ? selectedUsers.map { $0.displayName }.joined(separator: ", ")
                : nil

            let conversation = try await chatService.createConversation(
                type: conversationType,
                participantIds: participantIds,
                name: groupName
            )

            createdConversationId = conversation.id
            createdConversationName = selectedUsers.count == 1
                ? selectedUsers[0].displayName
                : (groupName ?? "Group Chat")

            #if DEBUG
            print("[NewChatView] Created conversation: \(conversation.id)")
            #endif

            // Navigate to the chat
            showChat = true

        } catch {
            errorMessage = "Failed to create conversation"
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

#Preview {
    NewChatView(currentPage: .constant(.newChat))
}
