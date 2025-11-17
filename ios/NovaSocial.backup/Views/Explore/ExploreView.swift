import SwiftUI

struct ExploreView: View {
    @StateObject private var viewModel = ExploreViewModel()
    @State private var selectedPost: Post?
    @State private var selectedUser: User?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                SearchBar(text: $viewModel.searchText) {
                    viewModel.searchUsers()
                }
                .padding()

                if !viewModel.searchText.isEmpty {
                    // Search Results
                    if viewModel.isSearching {
                        LoadingView(message: "Searching...")
                    } else if viewModel.searchResults.isEmpty {
                        EmptyStateView(
                            icon: "magnifyingglass",
                            title: "No Results",
                            message: "Try searching for different users"
                        )
                    } else {
                        List(viewModel.searchResults) { user in
                            Button {
                                selectedUser = user
                            } label: {
                                UserRowView(user: user)
                            }
                        }
                        .listStyle(.plain)
                    }
                } else {
                    // Explore Grid
                    if viewModel.isLoading && viewModel.posts.isEmpty {
                        LoadingView(message: "Loading posts...")
                    } else if viewModel.posts.isEmpty {
                        EmptyStateView(
                            icon: "photo.on.rectangle.angled",
                            title: "No Posts",
                            message: "Explore posts will appear here"
                        )
                    } else {
                        ScrollView {
                            PostsGridView(
                                posts: viewModel.posts,
                                onPostTap: { post in
                                    selectedPost = post
                                }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedPost) { post in
                PostDetailView(post: post)
            }
            .navigationDestination(item: $selectedUser) { user in
                UserProfileView(userId: user.id)
            }
            .task {
                if viewModel.posts.isEmpty {
                    await viewModel.loadExplorePosts()
                }
            }
            .errorAlert(
                isPresented: $viewModel.showError,
                message: viewModel.errorMessage
            )
        }
    }
}

struct SearchBar: View {
    @Binding var text: String
    let onSearch: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)

            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .onChange(of: text) { _, _ in
                    onSearch()
                }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

struct UserRowView: View {
    let user: User

    var body: some View {
        HStack(spacing: 12) {
            AsyncImageView(url: user.avatarUrl)
                .frame(width: 50, height: 50)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(user.username)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if user.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }

                if let displayName = user.displayName {
                    Text(displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct UserProfileView: View {
    let userId: UUID
    @StateObject private var viewModel: UserProfileViewModel

    init(userId: UUID) {
        self.userId = userId
        _viewModel = StateObject(wrappedValue: UserProfileViewModel(userId: userId))
    }

    var body: some View {
        ProfileView()
            .environmentObject(AppState()) // TODO: Pass actual app state
    }
}

#Preview {
    ExploreView()
}
