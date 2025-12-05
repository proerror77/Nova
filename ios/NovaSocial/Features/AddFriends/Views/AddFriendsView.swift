import SwiftUI

// MARK: - Friends Service (Inline)

/// Manages friend relationships and user connections
class FriendsService {
    private let client = APIClient.shared

    func searchUsers(query: String, limit: Int = 20, offset: Int = 0) async throws -> [UserProfile] {
        struct Response: Codable {
            let users: [UserProfile]
            let total: Int?
        }

        let response: Response = try await client.get(
            endpoint: APIConfig.Friends.searchUsers,
            queryParams: [
                "q": query,
                "limit": String(limit),
                "offset": String(offset)
            ]
        )

        return response.users
    }

    func getRecommendations(limit: Int = 20) async throws -> [UserProfile] {
        struct Response: Codable {
            let recommendations: [UserProfile]
            let total: Int?
        }

        let response: Response = try await client.get(
            endpoint: APIConfig.Friends.getRecommendations,
            queryParams: ["limit": String(limit)]
        )

        return response.recommendations
    }

    func addFriend(userId: String) async throws {
        struct Request: Codable {
            let user_id: String
        }

        struct Response: Codable {
            let success: Bool
            let message: String?
        }

        let request = Request(user_id: userId)
        let response: Response = try await client.request(
            endpoint: APIConfig.Friends.addFriend,
            method: "POST",
            body: request
        )

        guard response.success else {
            throw APIError.serverError(
                statusCode: 400,
                message: response.message ?? "Failed to add friend"
            )
        }
    }

    func getFriendsList(userId: String? = nil, limit: Int = 50, offset: Int = 0) async throws -> (friends: [UserProfile], total: Int) {
        struct Response: Codable {
            let friends: [UserProfile]
            let total: Int
        }

        var queryParams = [
            "limit": String(limit),
            "offset": String(offset)
        ]

        if let userId = userId {
            queryParams["user_id"] = userId
        }

        let response: Response = try await client.get(
            endpoint: APIConfig.Friends.getFriendsList,
            queryParams: queryParams
        )

        return (response.friends, response.total)
    }
}

// MARK: - Add Friends ViewModel

@MainActor
@Observable
class AddFriendsViewModel {
    var searchQuery: String = ""
    var searchResults: [UserProfile] = []
    var recommendations: [UserProfile] = []
    var isSearching: Bool = false
    var isLoadingRecommendations: Bool = false
    var errorMessage: String?

    private let friendsService = FriendsService()

    func loadRecommendations() async {
        isLoadingRecommendations = true
        errorMessage = nil

        do {
            recommendations = try await friendsService.getRecommendations(limit: 20)
        } catch {
            errorMessage = "加载推荐联系人失败: \(error.localizedDescription)"
            print("❌ Failed to load recommendations: \(error)")
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
            searchResults = try await friendsService.searchUsers(query: searchQuery, limit: 20)
        } catch {
            errorMessage = "搜索失败: \(error.localizedDescription)"
            print("❌ Search failed: \(error)")
        }

        isSearching = false
    }

    func addFriend(userId: String) async {
        errorMessage = nil

        do {
            try await friendsService.addFriend(userId: userId)
            await loadRecommendations()
        } catch {
            errorMessage = "添加好友失败: \(error.localizedDescription)"
            print("❌ Failed to add friend: \(error)")
        }
    }
}

// MARK: - Add Friends View

struct AddFriendsView: View {
    @Binding var currentPage: AppPage
    @State private var viewModel = AddFriendsViewModel()

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

                    Text("Add friends")
                        .font(Font.custom("Helvetica Neue", size: 20).weight(.bold))
                        .foregroundColor(.black)

                    Spacer()

                    Color.clear.frame(width: 20, height: 20)
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
                        .font(Font.custom("Helvetica Neue", size: 15))
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

                ScrollView {
                    VStack(spacing: 16) {
                        // MARK: - Search Results
                        if !viewModel.searchResults.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("搜索结果")
                                    .font(Font.custom("Helvetica Neue", size: 17.50).weight(.bold))
                                    .foregroundColor(Color(red: 0.32, green: 0.32, blue: 0.32))
                                    .padding(.horizontal, 24)

                                ForEach(viewModel.searchResults) { user in
                                    UserCardView(
                                        user: user,
                                        onAddFriend: {
                                            Task {
                                                await viewModel.addFriend(userId: user.id)
                                            }
                                        }
                                    )
                                    .padding(.horizontal, 16)
                                }
                            }
                            .padding(.top, 20)
                        }

                        // MARK: - Recommendations
                        if !viewModel.recommendations.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("推荐联系人")
                                    .font(Font.custom("Helvetica Neue", size: 17.50).weight(.bold))
                                    .foregroundColor(Color(red: 0.32, green: 0.32, blue: 0.32))
                                    .padding(.horizontal, 24)

                                ForEach(viewModel.recommendations) { user in
                                    UserCardView(
                                        user: user,
                                        onAddFriend: {
                                            Task {
                                                await viewModel.addFriend(userId: user.id)
                                            }
                                        }
                                    )
                                    .padding(.horizontal, 16)
                                }
                            }
                            .padding(.top, viewModel.searchResults.isEmpty ? 20 : 0)
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
                                    .font(Font.custom("Helvetica Neue", size: 15))
                                    .lineSpacing(20)
                                    .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

                                Spacer()
                            }
                            .padding(EdgeInsets(top: 7, leading: 37, bottom: 7, trailing: 37))
                            .frame(width: 351, height: 35)
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
        }
        .task {
            await viewModel.loadRecommendations()
        }
    }
}

// MARK: - User Card Component

struct UserCardView: View {
    let user: UserProfile
    let onAddFriend: () -> Void
    @State private var isAdding: Bool = false
    @State private var isAdded: Bool = false

    var body: some View {
        HStack(spacing: 13) {
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

            VStack(alignment: .leading, spacing: 1) {
                Text(user.displayName ?? user.username)
                    .font(Font.custom("Helvetica Neue", size: 16).weight(.bold))
                    .lineSpacing(20)
                    .foregroundColor(.black)

                if let bio = user.bio, !bio.isEmpty {
                    Text(bio)
                        .font(Font.custom("Helvetica Neue", size: 11.50).weight(.medium))
                        .lineSpacing(20)
                        .foregroundColor(Color(red: 0.65, green: 0.65, blue: 0.65))
                        .lineLimit(1)
                } else {
                    Text("@\(user.username)")
                        .font(Font.custom("Helvetica Neue", size: 11.50).weight(.medium))
                        .lineSpacing(20)
                        .foregroundColor(Color(red: 0.65, green: 0.65, blue: 0.65))
                }
            }

            Spacer()

            Button(action: {
                guard !isAdding && !isAdded else { return }
                isAdding = true
                onAddFriend()
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

#Preview {
    AddFriendsView(currentPage: .constant(.addFriends))
}
