import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = UserProfileViewModel()
    @State private var selectedPost: Post?
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.isLoading && viewModel.user == nil {
                    LoadingView(message: "Loading profile...")
                        .frame(height: 400)
                } else if let user = viewModel.user {
                    VStack(spacing: 0) {
                        // Profile Header
                        ProfileHeaderView(
                            user: user,
                            stats: viewModel.stats,
                            isOwnProfile: viewModel.isOwnProfile,
                            onFollowTap: {
                                Task {
                                    await viewModel.toggleFollow()
                                }
                            },
                            onEditProfile: {
                                // TODO: Navigate to edit profile
                            }
                        )
                        .padding()

                        Divider()

                        // Posts Grid
                        if viewModel.isLoadingPosts {
                            ProgressView()
                                .padding()
                        } else if viewModel.posts.isEmpty {
                            EmptyStateView(
                                icon: "photo.on.rectangle.angled",
                                title: "No Posts Yet",
                                message: "Posts you create will appear here"
                            )
                            .frame(height: 300)
                        } else {
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
            .navigationTitle(viewModel.user?.username ?? "Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.isOwnProfile {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "line.3.horizontal")
                        }
                    }
                }
            }
            .navigationDestination(item: $selectedPost) { post in
                PostDetailView(post: post)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .task {
                if viewModel.user == nil {
                    await viewModel.loadProfile()
                }
            }
            .refreshable {
                await viewModel.loadProfile()
            }
            .errorAlert(
                isPresented: $viewModel.showError,
                message: viewModel.errorMessage
            )
        }
    }
}

struct ProfileHeaderView: View {
    let user: User
    let stats: UserStats?
    let isOwnProfile: Bool
    let onFollowTap: () -> Void
    let onEditProfile: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 20) {
                // Avatar
                AsyncImageView(url: user.avatarUrl)
                    .frame(width: 86, height: 86)
                    .clipShape(Circle())

                // Stats
                HStack(spacing: 24) {
                    StatView(
                        count: stats?.postCount ?? 0,
                        label: "Posts"
                    )

                    StatView(
                        count: stats?.followerCount ?? 0,
                        label: "Followers"
                    )

                    StatView(
                        count: stats?.followingCount ?? 0,
                        label: "Following"
                    )
                }
            }

            // User Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(user.displayName ?? user.username)
                        .font(.headline)

                    if user.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.blue)
                    }
                }

                if let bio = user.bio {
                    Text(bio)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Action Button
            if isOwnProfile {
                Button {
                    onEditProfile()
                } label: {
                    Text("Edit Profile")
                }
                .buttonStyle(SecondaryButtonStyle())
            } else {
                Button {
                    onFollowTap()
                } label: {
                    Text(stats?.isFollowing == true ? "Unfollow" : "Follow")
                }
                .buttonStyle(
                    stats?.isFollowing == true ?
                    SecondaryButtonStyle() as any ButtonStyle :
                    PrimaryButtonStyle() as any ButtonStyle
                )
            }
        }
    }
}

struct StatView: View {
    let count: Int
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.headline)
                .fontWeight(.semibold)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct PostsGridView: View {
    let posts: [Post]
    let onPostTap: (Post) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(posts) { post in
                Button {
                    onPostTap(post)
                } label: {
                    AsyncImageView(url: post.thumbnailUrl ?? post.imageUrl)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                }
            }
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(AppState())
}
