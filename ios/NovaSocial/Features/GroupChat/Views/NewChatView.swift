import SwiftUI

struct NewChatView: View {
    @Binding var currentPage: AppPage
    @State private var selectedContacts: Set<String> = []  // Changed to Set<String> to store user IDs
    @State private var friends: [UserProfile] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""

    private let friendsService = FriendsService()

    var body: some View {
        ZStack {
            // 背景色
            Color(red: 0.97, green: 0.97, blue: 0.97)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
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
                        if !selectedContacts.isEmpty {
                            currentPage = .groupChat
                        }
                    }) {
                        Text(selectedContacts.isEmpty ? "Save" : "Save(\(selectedContacts.count))")
                            .font(.system(size: 14))
                            .foregroundColor(selectedContacts.isEmpty ? Color(red: 0.53, green: 0.53, blue: 0.53) : Color(red: 0.87, green: 0.11, blue: 0.26))
                    }
                    .frame(width: 60, alignment: .trailing)
                    .disabled(selectedContacts.isEmpty)
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

                // MARK: - 搜索框
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundColor(Color(red: 0.69, green: 0.68, blue: 0.68))

                    TextField("Search", text: $searchText)
                        .font(.system(size: 15))
                        .foregroundColor(.black)
                }
                .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .frame(height: 32)
                .background(Color(red: 0.89, green: 0.88, blue: 0.87))
                .cornerRadius(32)
                .padding(EdgeInsets(top: 12, leading: 18, bottom: 16, trailing: 18))

                // MARK: - Select an existing group
                HStack {
                    Text("Select an existing group")
                        .font(.system(size: 16, weight: .bold))
                        .lineSpacing(20)
                        .foregroundColor(.black)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 60)
                .frame(maxWidth: .infinity)
                .overlay(
                    Rectangle()
                        .inset(by: 0.20)
                        .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.20)
                )

                // MARK: - Content
                if isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                } else if let error = errorMessage {
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
                                await loadFriends()
                            }
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                    }
                    .padding()
                    Spacer()
                } else if filteredFriends.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text(searchText.isEmpty ? "No friends yet" : "No results found")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                } else {
                    // MARK: - 联系人列表
                    ScrollView {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            ForEach(groupedFriends.keys.sorted(), id: \.self) { letter in
                                Section {
                                    ForEach(groupedFriends[letter] ?? []) { friend in
                                        ContactRow(
                                            user: friend,
                                            isSelected: selectedContacts.contains(friend.id)
                                        )
                                        .onTapGesture {
                                            toggleSelection(friend.id)
                                        }
                                    }
                                } header: {
                                    HStack {
                                        Text(letter)
                                            .font(.system(size: 16, weight: .bold))
                                            .lineSpacing(20)
                                            .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color(red: 0.97, green: 0.97, blue: 0.97))
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

    // MARK: - Filtered Friends
    private var filteredFriends: [UserProfile] {
        if searchText.isEmpty {
            return friends
        }
        return friends.filter { friend in
            let name = friend.displayName ?? friend.username
            return name.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Grouped Friends by First Letter
    private var groupedFriends: [String: [UserProfile]] {
        Dictionary(grouping: filteredFriends) { friend in
            let name = friend.displayName ?? friend.username
            let firstChar = name.first?.uppercased() ?? "#"
            return firstChar.first?.isLetter == true ? firstChar : "#"
        }
    }

    // MARK: - Load Friends
    private func loadFriends() async {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await friendsService.getFriendsList()
            await MainActor.run {
                friends = result.friends
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load friends: \(error.localizedDescription)"
                isLoading = false
            }
            #if DEBUG
            print("[NewChatView] Failed to load friends: \(error)")
            #endif
        }
    }

    private func toggleSelection(_ userId: String) {
        if selectedContacts.contains(userId) {
            selectedContacts.remove(userId)
        } else {
            selectedContacts.insert(userId)
        }
    }
}

// MARK: - 联系人行组件
struct ContactRow: View {
    let user: UserProfile
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 13) {
            // 选择圆圈
            ZStack {
                Circle()
                    .stroke(Color(red: 0.53, green: 0.53, blue: 0.53), lineWidth: 0.50)
                    .frame(width: 20, height: 20)

                if isSelected {
                    Circle()
                        .fill(Color(red: 0.82, green: 0.11, blue: 0.26))
                        .frame(width: 12, height: 12)
                }
            }

            // 头像
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

            // 名字
            VStack(alignment: .leading, spacing: 1) {
                Text(user.displayName ?? user.username)
                    .font(.system(size: 16, weight: .bold))
                    .lineSpacing(20)
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
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.97, green: 0.97, blue: 0.97))
        .overlay(
            Rectangle()
                .inset(by: 0.20)
                .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.20)
        )
    }
}

#Preview {
    NewChatView(currentPage: .constant(.newChat))
}
