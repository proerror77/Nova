import SwiftUI

// MARK: - Hashtag Feed View
// Displays posts containing a specific hashtag

struct HashtagFeedView: View {
    @Binding var isPresented: Bool
    let hashtag: String
    let postCount: Int

    @StateObject private var viewModel = HashtagFeedViewModel()
    @State private var showUserProfile = false
    @State private var selectedUserId: String?

    var body: some View {
        NavigationView {
            ZStack {
                DesignTokens.backgroundColor
                    .ignoresSafeArea()

                if viewModel.isLoading && viewModel.posts.isEmpty {
                    loadingView
                } else if viewModel.posts.isEmpty && !viewModel.isLoading {
                    emptyView
                } else {
                    postsList
                }
            }
            .navigationTitle("#\(hashtag)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(DesignTokens.textPrimary)
                    }
                }
            }
        }
        .task {
            await viewModel.loadPosts(hashtag: hashtag)
        }
        .fullScreenCover(isPresented: $showUserProfile) {
            if let userId = selectedUserId {
                UserProfileView(showUserProfile: $showUserProfile, userId: userId)
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading posts...")
                .font(Font.custom("SFProDisplay-Regular", size: 14))
                .foregroundColor(DesignTokens.textSecondary)
        }
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "number")
                .font(.system(size: 48))
                .foregroundColor(DesignTokens.textMuted)

            Text("No posts found")
                .font(Font.custom("SFProDisplay-Semibold", size: 18))
                .foregroundColor(DesignTokens.textPrimary)

            Text("There are no posts with #\(hashtag) yet")
                .font(Font.custom("SFProDisplay-Regular", size: 14))
                .foregroundColor(DesignTokens.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Posts List

    private var postsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Header with post count
                headerView

                // Posts
                ForEach(Array(viewModel.posts), id: \.id) { (post: PostSearchResult) in
                    HashtagPostRow(
                        post: post,
                        onAuthorTap: {
                            self.selectedUserId = post.authorId
                            self.showUserProfile = true
                        }
                    )

                    Divider()
                        .background(DesignTokens.dividerColor)
                }

                // Load more indicator
                if viewModel.hasMore {
                    ProgressView()
                        .padding()
                        .onAppear {
                            Task {
                                await viewModel.loadMore(hashtag: hashtag)
                            }
                        }
                }
            }
        }
        .refreshable {
            await viewModel.refresh(hashtag: hashtag)
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("#\(hashtag)")
                    .font(Font.custom("SFProDisplay-Bold", size: 24))
                    .foregroundColor(DesignTokens.textPrimary)

                Text("\(postCount) posts")
                    .font(Font.custom("SFProDisplay-Regular", size: 14))
                    .foregroundColor(DesignTokens.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
        .background(DesignTokens.surface)
    }
}

// MARK: - Hashtag Post Row

struct HashtagPostRow: View {
    let post: PostSearchResult
    var onAuthorTap: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Author row
            HStack {
                Button(action: onAuthorTap) {
                    HStack(spacing: 8) {
                        // Avatar placeholder
                        Circle()
                            .fill(DesignTokens.inputBackground)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(DesignTokens.textMuted)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(post.authorName ?? "User")
                                .font(Font.custom("SFProDisplay-Semibold", size: 15))
                                .foregroundColor(DesignTokens.textPrimary)

                            Text(relativeTime)
                                .font(Font.custom("SFProDisplay-Regular", size: 12))
                                .foregroundColor(DesignTokens.textSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()
            }

            // Content
            Text(post.content)
                .font(Font.custom("SFProDisplay-Regular", size: 15))
                .foregroundColor(DesignTokens.textPrimary)
                .lineLimit(6)

            // Stats row
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "heart")
                        .font(.system(size: 14))
                    Text("\(post.likeCount ?? 0)")
                        .font(Font.custom("SFProDisplay-Regular", size: 13))
                }
                .foregroundColor(DesignTokens.textSecondary)

                if let commentCount = post.commentCount, commentCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 14))
                        Text("\(commentCount)")
                            .font(Font.custom("SFProDisplay-Regular", size: 13))
                    }
                    .foregroundColor(DesignTokens.textSecondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(DesignTokens.surface)
        .contentShape(Rectangle())
    }

    private var relativeTime: String {
        let interval = Date().timeIntervalSince(post.createdDate)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)

        if hours < 1 {
            return "Just now"
        } else if hours < 24 {
            return "\(hours)h ago"
        } else {
            return "\(days)d ago"
        }
    }
}

// MARK: - View Model

@MainActor
class HashtagFeedViewModel: ObservableObject {
    @Published var posts: [PostSearchResult] = []
    @Published var isLoading = false
    @Published var hasMore = true
    @Published var error: String?

    private let searchService = SearchService()
    private var currentOffset = 0
    private let pageSize = 20

    func loadPosts(hashtag: String) async {
        guard !isLoading else { return }

        isLoading = true
        error = nil

        do {
            let results = try await searchService.searchPostsByHashtag(hashtag, limit: pageSize, offset: 0)
            posts = results
            currentOffset = results.count
            hasMore = results.count >= pageSize
        } catch {
            self.error = error.localizedDescription
            print("[HashtagFeed] Error loading posts: \(error)")
        }

        isLoading = false
    }

    func loadMore(hashtag: String) async {
        guard !isLoading && hasMore else { return }

        isLoading = true

        do {
            let results = try await searchService.searchPostsByHashtag(hashtag, limit: pageSize, offset: currentOffset)
            posts.append(contentsOf: results)
            currentOffset += results.count
            hasMore = results.count >= pageSize
        } catch {
            print("[HashtagFeed] Error loading more posts: \(error)")
        }

        isLoading = false
    }

    func refresh(hashtag: String) async {
        currentOffset = 0
        hasMore = true
        await loadPosts(hashtag: hashtag)
    }
}

#Preview {
    HashtagFeedView(
        isPresented: .constant(true),
        hashtag: "photography",
        postCount: 1234
    )
}
