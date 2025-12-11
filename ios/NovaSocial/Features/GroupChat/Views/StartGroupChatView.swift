import SwiftUI

// MARK: - Start Group Chat ViewModel

@MainActor
@Observable
class StartGroupChatViewModel {
    var searchQuery: String = ""
    var searchResults: [UserProfile] = []
    var selectedUsers: Set<String> = []
    var groupName: String = ""
    var isSearching: Bool = false
    var isCreating: Bool = false
    var errorMessage: String?

    private let friendsService = FriendsService()
    private let chatService = ChatService()

    var canCreateGroup: Bool {
        selectedUsers.count >= 2 && !groupName.trimmingCharacters(in: .whitespaces).isEmpty
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
            errorMessage = "搜索失败: \(error.localizedDescription)"
            print("❌ Search failed: \(error)")
        }

        isSearching = false
    }

    func toggleUserSelection(userId: String) {
        if selectedUsers.contains(userId) {
            selectedUsers.remove(userId)
        } else {
            selectedUsers.insert(userId)
        }
    }

    func createGroupChat() async -> Conversation? {
        guard canCreateGroup else {
            errorMessage = "请至少选择2位成员并输入群组名称"
            return nil
        }

        isCreating = true
        errorMessage = nil

        do {
            let conversation = try await chatService.createConversation(
                type: ConversationType.group,
                participantIds: Array(selectedUsers),
                name: groupName.trimmingCharacters(in: .whitespaces)
            )

            print("✅ Group chat created: \(conversation.id)")
            return conversation

        } catch {
            errorMessage = "创建群聊失败: \(error.localizedDescription)"
            print("❌ Failed to create group chat: \(error)")
            isCreating = false
            return nil
        }
    }
}

// MARK: - Start Group Chat View

struct StartGroupChatView: View {
    @Binding var currentPage: AppPage
    @State private var viewModel = StartGroupChatViewModel()

    var body: some View {
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
                            .font(.system(size: 20))
                            .foregroundColor(.black)
                    }

                    Spacer()

                    Text("Start Group Chat")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.black)

                    Spacer()

                    Color.clear.frame(width: 20, height: 20)
                }
                .frame(height: 56)
                .padding(.horizontal, 16)
                .background(Color.white)

                Divider()

                // MARK: - Group Name Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("群组名称")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

                    HStack(spacing: 10) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 15))
                            .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

                        TextField("Enter group name", text: $viewModel.groupName)
                            .font(.system(size: 15))
                            .foregroundColor(.black)

                        Spacer()
                    }
                    .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(Color(red: 0.91, green: 0.91, blue: 0.91))
                    .cornerRadius(32)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // MARK: - Search Bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

                    TextField("Search friends", text: $viewModel.searchQuery)
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

                // MARK: - Selected Users Badge
                if !viewModel.selectedUsers.isEmpty {
                    HStack {
                        Text("已选择 \(viewModel.selectedUsers.count) 人")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color(red: 0.32, green: 0.32, blue: 0.32))

                        Spacer()

                        Button(action: {
                            viewModel.selectedUsers.removeAll()
                        }) {
                            Text("清除")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                }

                // MARK: - Error Message
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                ScrollView {
                    VStack(spacing: 16) {
                        // MARK: - Search Results
                        if !viewModel.searchResults.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("搜索结果")
                                    .font(.system(size: 17.50, weight: .bold))
                                    .foregroundColor(Color(red: 0.32, green: 0.32, blue: 0.32))
                                    .padding(.horizontal, 24)

                                ForEach(viewModel.searchResults) { user in
                                    SelectableUserCardView(
                                        user: user,
                                        isSelected: viewModel.selectedUsers.contains(user.id),
                                        onToggle: {
                                            viewModel.toggleUserSelection(userId: user.id)
                                        }
                                    )
                                    .padding(.horizontal, 16)
                                }
                            }
                            .padding(.top, 20)
                        }

                        // MARK: - Create Button
                        Button(action: {
                            Task {
                                if await viewModel.createGroupChat() != nil {
                                    // Navigate back to message view
                                    // The new conversation will appear in the list
                                    currentPage = .message
                                }
                            }
                        }) {
                            HStack {
                                if viewModel.isCreating {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Text("创建群聊")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(viewModel.canCreateGroup ? Color.blue : Color.gray)
                            .cornerRadius(22)
                        }
                        .disabled(!viewModel.canCreateGroup || viewModel.isCreating)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                    }
                }
            }
        }
    }
}

// MARK: - Selectable User Card Component

struct SelectableUserCardView: View {
    let user: UserProfile
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 13) {
                // Avatar
                if let avatarUrl = user.avatarUrl, let url = URL(string: avatarUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                        .frame(width: 50, height: 50)
                }

                // User Info
                VStack(alignment: .leading, spacing: 1) {
                    Text(user.displayName ?? user.username)
                        .font(.system(size: 16, weight: .bold))
                        .lineSpacing(20)
                        .foregroundColor(.black)

                    if let bio = user.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.system(size: 11.50, weight: .medium))
                            .lineSpacing(20)
                            .foregroundColor(Color(red: 0.65, green: 0.65, blue: 0.65))
                            .lineLimit(1)
                    } else {
                        Text("@\(user.username)")
                            .font(.system(size: 11.50, weight: .medium))
                            .lineSpacing(20)
                            .foregroundColor(Color(red: 0.65, green: 0.65, blue: 0.65))
                    }
                }

                Spacer()

                // Selection Indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? .blue : Color(red: 0.75, green: 0.75, blue: 0.75))
            }
            .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .frame(maxWidth: .infinity)
            .frame(height: 67)
            .background(isSelected ? Color.blue.opacity(0.05) : Color(red: 0.97, green: 0.96, blue: 0.96))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .inset(by: 0.50)
                    .stroke(isSelected ? Color.blue : Color(red: 0.75, green: 0.75, blue: 0.75), lineWidth: isSelected ? 2 : 0.50)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    StartGroupChatView(currentPage: .constant(.newChat))
}
