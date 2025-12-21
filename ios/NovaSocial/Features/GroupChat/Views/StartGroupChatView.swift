import SwiftUI

// MARK: - Start Group Chat ViewModel

@MainActor
@Observable
class StartGroupChatViewModel {
    var searchQuery: String = ""
    var searchResults: [UserProfile] = []
    var friends: [UserProfile] = []
    var selectedUsers: [UserProfile] = []
    var groupName: String = ""
    var isSearching: Bool = false
    var isLoadingFriends: Bool = false
    var isCreating: Bool = false
    var errorMessage: String?
    var isPrivateGroup: Bool = false  // E2EE encrypted private group toggle

    private let friendsService = FriendsService()
    private let matrixBridge = MatrixBridgeService.shared

    var canCreateGroup: Bool {
        selectedUsers.count >= 2 && !groupName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Load friends list on view appear
    func loadFriends() async {
        isLoadingFriends = true
        errorMessage = nil

        do {
            let (friendProfiles, _) = try await friendsService.getFriendsList(limit: 100)
            friends = friendProfiles
            #if DEBUG
            print("✅ [StartGroupChat] Loaded \(friends.count) friends")
            #endif
        } catch {
            errorMessage = NSLocalizedString("group_chat.error.load_friends_failed", comment: "")
            #if DEBUG
            print("❌ [StartGroupChat] Failed to load friends: \(error)")
            #endif
        }

        isLoadingFriends = false
    }

    func searchUsers() async {
        guard !searchQuery.isEmpty else {
            searchResults = []
            return
        }

        isSearching = true
        errorMessage = nil

        do {
            searchResults = try await friendsService.searchUsers(query: searchQuery, limit: 20)
        } catch {
            errorMessage = NSLocalizedString("group_chat.error.search_failed", comment: "")
            #if DEBUG
            print("❌ [StartGroupChat] Search failed: \(error)")
            #endif
        }

        isSearching = false
    }

    func toggleUserSelection(_ user: UserProfile) {
        if let index = selectedUsers.firstIndex(where: { $0.id == user.id }) {
            selectedUsers.remove(at: index)
        } else {
            selectedUsers.append(user)
        }
    }

    func isSelected(_ user: UserProfile) -> Bool {
        selectedUsers.contains(where: { $0.id == user.id })
    }

    func removeSelectedUser(_ user: UserProfile) {
        selectedUsers.removeAll { $0.id == user.id }
    }

    func createGroupChat(retryCount: Int = 0) async -> Bool {
        guard canCreateGroup else {
            errorMessage = NSLocalizedString("group_chat.error.validation", comment: "")
            return false
        }

        isCreating = true
        errorMessage = nil

        do {
            let participantIds = selectedUsers.map { $0.id }
            if !matrixBridge.isInitialized {
                try await matrixBridge.initialize()
            }

            _ = try await matrixBridge.createGroupConversation(
                name: groupName.trimmingCharacters(in: .whitespaces),
                userIds: participantIds,
                isPrivate: isPrivateGroup
            )

            #if DEBUG
            print("✅ [StartGroupChat] \(isPrivateGroup ? "Private (E2EE)" : "Regular") group chat room created")
            #endif
            isCreating = false
            return true

        } catch MatrixBridgeError.sessionExpired {
            // Session expired - auto-retry once with fresh credentials
            if retryCount < 1 {
                #if DEBUG
                print("⚠️ [StartGroupChat] Session expired, re-initializing and retrying...")
                #endif
                isCreating = false
                return await createGroupChat(retryCount: retryCount + 1)
            } else {
                errorMessage = "Session 已過期，請重新登入後再試"
                #if DEBUG
                print("❌ [StartGroupChat] Session still expired after retry")
                #endif
                isCreating = false
                return false
            }

        } catch {
            errorMessage = NSLocalizedString("group_chat.error.create_failed", comment: "")
            #if DEBUG
            print("❌ [StartGroupChat] Failed to create group chat: \(error)")
            #endif
            isCreating = false
            return false
        }
    }
}

// MARK: - Start Group Chat View

struct StartGroupChatView: View {
    @Binding var currentPage: AppPage
    @State private var viewModel = StartGroupChatViewModel()

    var body: some View {
        ZStack {
            DesignTokens.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Navigation Bar
                HStack {
                    Button(action: {
                        currentPage = .message
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20))
                            .foregroundColor(DesignTokens.textPrimary)
                    }

                    Spacer()

                    Text(NSLocalizedString("group_chat.title", comment: ""))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(DesignTokens.textPrimary)

                    Spacer()

                    // Create button
                    Button(action: {
                        Task {
                            if await viewModel.createGroupChat() {
                                currentPage = .message
                            }
                        }
                    }) {
                        if viewModel.isCreating {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text(NSLocalizedString("group_chat.create", comment: ""))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(viewModel.canCreateGroup ? DesignTokens.accentColor : DesignTokens.textMuted)
                        }
                    }
                    .disabled(!viewModel.canCreateGroup || viewModel.isCreating)
                }
                .frame(height: 56)
                .padding(.horizontal, 16)
                .background(DesignTokens.surface)

                Divider()

                // MARK: - Group Name Input
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("group_chat.group_name", comment: ""))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DesignTokens.textSecondary)

                    HStack(spacing: 10) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 15))
                            .foregroundColor(DesignTokens.textSecondary)

                        TextField(NSLocalizedString("group_chat.group_name_placeholder", comment: ""), text: $viewModel.groupName)
                            .font(.system(size: 15))
                            .foregroundColor(DesignTokens.textPrimary)

                        Spacer()
                    }
                    .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(DesignTokens.tileBackground)
                    .cornerRadius(32)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // MARK: - Private Group Toggle
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: viewModel.isPrivateGroup ? "lock.fill" : "lock.open")
                            .font(.system(size: 16))
                            .foregroundColor(viewModel.isPrivateGroup ? DesignTokens.accentColor : DesignTokens.textSecondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Private Group")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(DesignTokens.textPrimary)

                            Text(viewModel.isPrivateGroup ? "End-to-end encrypted" : "Standard group (searchable)")
                                .font(.system(size: 12))
                                .foregroundColor(DesignTokens.textSecondary)
                        }
                    }

                    Spacer()

                    Toggle("", isOn: $viewModel.isPrivateGroup)
                        .labelsHidden()
                        .tint(DesignTokens.accentColor)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // MARK: - Search Bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundColor(DesignTokens.textSecondary)

                    TextField(NSLocalizedString("group_chat.search_placeholder", comment: ""), text: $viewModel.searchQuery)
                        .font(.system(size: 15))
                        .foregroundColor(DesignTokens.textPrimary)
                        .onChange(of: viewModel.searchQuery) { _, newValue in
                            if !newValue.isEmpty {
                                Task {
                                    try? await Task.sleep(for: .milliseconds(300))
                                    if viewModel.searchQuery == newValue {
                                        await viewModel.searchUsers()
                                    }
                                }
                            } else {
                                viewModel.searchResults = []
                            }
                        }

                    Spacer()

                    if viewModel.isSearching {
                        ProgressView().scaleEffect(0.8)
                    }
                }
                .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(DesignTokens.tileBackground)
                .cornerRadius(32)
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // MARK: - Selected Users Preview (Horizontal Scroll)
                if !viewModel.selectedUsers.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(viewModel.selectedUsers) { user in
                                GroupSelectedUserChip(user: user) {
                                    viewModel.removeSelectedUser(user)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .frame(height: 50)
                    .padding(.top, 12)

                    // Selection info
                    HStack {
                        Text(String(format: NSLocalizedString("group_chat.selected_count", comment: ""), viewModel.selectedUsers.count))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(DesignTokens.textSecondary)

                        Spacer()

                        Button(action: {
                            viewModel.selectedUsers.removeAll()
                        }) {
                            Text(NSLocalizedString("group_chat.clear", comment: ""))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(DesignTokens.accentColor)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                // MARK: - Error Message
                if let errorMessage = viewModel.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                // MARK: - User List
                ScrollView {
                    VStack(spacing: 0) {
                        if viewModel.isLoadingFriends {
                            ProgressView()
                                .padding(.top, 40)
                        } else if !viewModel.searchQuery.isEmpty {
                            // Search Results
                            if viewModel.searchResults.isEmpty && !viewModel.isSearching {
                                Text(NSLocalizedString("group_chat.no_results", comment: ""))
                                    .font(.system(size: 14))
                                    .foregroundColor(DesignTokens.textSecondary)
                                    .padding(.top, 40)
                            } else {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(NSLocalizedString("group_chat.search_results", comment: ""))
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundColor(DesignTokens.textSecondary)
                                        .padding(.horizontal, 16)

                                    ForEach(viewModel.searchResults) { user in
                                        GroupSelectableUserCardView(
                                            user: user,
                                            isSelected: viewModel.isSelected(user),
                                            onToggle: {
                                                viewModel.toggleUserSelection(user)
                                            }
                                        )
                                        .padding(.horizontal, 16)
                                    }
                                }
                                .padding(.top, 20)
                            }
                        } else {
                            // Friends List
                            if viewModel.friends.isEmpty {
                                VStack(spacing: 16) {
                                    Image(systemName: "person.2.slash")
                                        .font(.system(size: 48))
                                        .foregroundColor(DesignTokens.textMuted)

                                    Text(NSLocalizedString("group_chat.no_friends", comment: ""))
                                        .font(.system(size: 14))
                                        .foregroundColor(DesignTokens.textSecondary)
                                        .multilineTextAlignment(.center)
                                }
                                .padding(.top, 60)
                            } else {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(NSLocalizedString("group_chat.friends_section", comment: ""))
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundColor(DesignTokens.textSecondary)
                                        .padding(.horizontal, 16)

                                    ForEach(viewModel.friends) { user in
                                        GroupSelectableUserCardView(
                                            user: user,
                                            isSelected: viewModel.isSelected(user),
                                            onToggle: {
                                                viewModel.toggleUserSelection(user)
                                            }
                                        )
                                        .padding(.horizontal, 16)
                                    }
                                }
                                .padding(.top, 20)
                            }
                        }
                    }
                }
            }
        }
        .task {
            await viewModel.loadFriends()
        }
    }
}

// MARK: - Selected User Chip Component

struct GroupSelectedUserChip: View {
    let user: UserProfile
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            // Small avatar
            if let avatarUrl = user.avatarUrl, !avatarUrl.isEmpty, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
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

            Text(user.displayName ?? user.username)
                .font(.system(size: 14))
                .foregroundColor(DesignTokens.textPrimary)
                .lineLimit(1)

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

// MARK: - Selectable User Card Component

struct GroupSelectableUserCardView: View {
    let user: UserProfile
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
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
                if let avatarUrl = user.avatarUrl, let url = URL(string: avatarUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        DefaultAvatarView(size: 50)
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                } else {
                    DefaultAvatarView(size: 50)
                }

                // User Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayName ?? user.username)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DesignTokens.textPrimary)

                    Text("@\(user.username)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignTokens.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Checkmark for selected state
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(DesignTokens.accentColor)
                }
            }
            .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .frame(maxWidth: .infinity)
            .frame(height: 67)
            .background(isSelected ? DesignTokens.accentColor.opacity(0.05) : DesignTokens.tileBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .inset(by: 0.50)
                    .stroke(isSelected ? DesignTokens.accentColor : DesignTokens.borderColor, lineWidth: isSelected ? 2 : 0.50)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    StartGroupChatView(currentPage: .constant(.newChat))
}
