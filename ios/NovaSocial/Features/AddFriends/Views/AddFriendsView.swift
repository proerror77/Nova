import SwiftUI

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
    var toastMessage: String?

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

    func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                toastMessage = nil
            }
        }
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
                                        onAddFriend: {
                                            Task {
                                                await viewModel.addFriend(userId: user.id)
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
                                Text("推荐联系人")
                                    .font(.system(size: 17.50, weight: .bold))
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
    let onAddFriend: () -> Void
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
