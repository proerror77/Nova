import SwiftUI

// MARK: - Enhanced Feed View with State Management

struct EnhancedFeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @State private var showToast: (Bool, String) = (false, "")

    var body: some View {
        NavigationStack {
            ZStack {
                // Main content based on state
                content

                // Toast overlay
                if showToast.0 {
                    VStack {
                        Spacer()
                        Text(showToast.1)
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(20)
                            .padding(.bottom, 32)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(), value: showToast.0)
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            ProgressView()
                .onAppear {
                    Task {
                        await viewModel.loadInitialFeed()
                    }
                }

        case .loading:
            loadingView

        case .loaded(let posts):
            feedView(posts: posts)

        case .error(let error):
            errorView(error: error)

        case .empty:
            emptyView
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 0) {
            headerView

            Divider()
                .background(DesignColors.borderLight)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        NovaPostCardSkeleton()
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .background(DesignColors.surfaceLight)
    }

    // MARK: - Feed View

    private func feedView(posts: [PostModel]) -> some View {
        VStack(spacing: 0) {
            headerView

            Divider()
                .background(DesignColors.borderLight)

            ScrollView(showsIndicators: false) {
                // Pull to refresh indicator
                if viewModel.isRefreshing {
                    NovaPullToRefreshIndicator(isRefreshing: true)
                }

                LazyVStack(spacing: 12) {
                    ForEach(posts) { post in
                        EnhancedPostCard(
                            post: post,
                            onLike: { viewModel.likePost(post) },
                            onSave: { viewModel.savePost(post) },
                            onDelete: {
                                Task {
                                    await viewModel.deletePost(post)
                                    showToastMessage("貼文已刪除")
                                }
                            }
                        )
                        .onAppear {
                            // Load more when reaching last item
                            if post.id == posts.last?.id {
                                Task {
                                    await viewModel.loadMore()
                                }
                            }
                        }
                    }

                    // Loading more indicator
                    if viewModel.isLoadingMore {
                        HStack(spacing: 8) {
                            NovaLoadingSpinner(size: 20)
                            Text("加載更多...")
                                .font(.system(size: 14))
                                .foregroundColor(DesignColors.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                }
                .padding(.vertical, 12)
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
        .background(DesignColors.surfaceLight)
    }

    // MARK: - Error View

    private func errorView(error: Error) -> some View {
        VStack(spacing: 0) {
            headerView

            Divider()
                .background(DesignColors.borderLight)

            NovaErrorState(error: error) {
                Task {
                    await viewModel.loadInitialFeed()
                }
            }
        }
        .background(DesignColors.surfaceLight)
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 0) {
            headerView

            Divider()
                .background(DesignColors.borderLight)

            NovaEmptyFeed {
                Task {
                    await viewModel.refresh()
                }
            }
        }
        .background(DesignColors.surfaceLight)
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack(spacing: 12) {
            Text("Nova")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(DesignColors.textPrimary)
            Spacer()
            HStack(spacing: 16) {
                NovaIconButton(icon: "heart", action: {})
                NovaIconButton(icon: "paperplane", action: {})
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Helper Methods

    private func showToastMessage(_ message: String) {
        showToast = (true, message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showToast = (false, "")
        }
    }
}

// MARK: - Enhanced Post Card

struct EnhancedPostCard: View {
    let post: PostModel
    let onLike: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false
    @State private var showShareSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text(post.avatar)
                    .font(.system(size: 24))
                    .frame(width: 44, height: 44)
                    .background(DesignColors.brandPrimary.opacity(0.1))
                    .cornerRadius(22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(post.author)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DesignColors.textPrimary)
                    Text(post.timeAgo)
                        .font(.system(size: 12))
                        .foregroundColor(DesignColors.textSecondary)
                }

                Spacer()

                Menu {
                    Button(action: { showShareSheet = true }) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                    Button(action: {}) {
                        Label("舉報", systemImage: "exclamationmark.triangle")
                    }
                    Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                        Label("刪除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(DesignColors.textSecondary)
                        .frame(width: 44, height: 44)
                }
            }
            .padding(12)

            Divider()
                .background(DesignColors.borderLight)

            // Image
            Text(post.imageEmoji)
                .font(.system(size: 80))
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .background(LinearGradient(
                    gradient: Gradient(colors: [
                        DesignColors.brandPrimary.opacity(0.1),
                        DesignColors.brandAccent.opacity(0.1)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            // Actions
            HStack(spacing: 12) {
                Button(action: onLike) {
                    Image(systemName: post.isLiked ? "heart.fill" : "heart")
                        .foregroundColor(post.isLiked ? DesignColors.brandAccent : DesignColors.textPrimary)
                }

                Button(action: {}) {
                    Image(systemName: "bubble.right")
                        .foregroundColor(DesignColors.textPrimary)
                }

                Button(action: { showShareSheet = true }) {
                    Image(systemName: "paperplane")
                        .foregroundColor(DesignColors.textPrimary)
                }

                Spacer()

                Button(action: onSave) {
                    Image(systemName: post.isSaved ? "bookmark.fill" : "bookmark")
                        .foregroundColor(post.isSaved ? DesignColors.brandPrimary : DesignColors.textPrimary)
                }
            }
            .font(.system(size: 18))
            .padding(12)

            Divider()
                .background(DesignColors.borderLight)

            // Stats & Caption
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    Text("\(post.likes) 讚")
                        .font(.system(size: 12, weight: .semibold))
                    Text("\(post.comments) 評論")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(DesignColors.textSecondary)

                Text(post.caption)
                    .font(.system(size: 13))
                    .foregroundColor(DesignColors.textPrimary)
                    .lineLimit(3)
            }
            .padding(12)
        }
        .background(DesignColors.surfaceElevated)
        .cornerRadius(8)
        .padding(.horizontal, 8)
        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1)
        .confirmationDialog("確定要刪除這篇貼文嗎？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("刪除", role: .destructive) {
                onDelete()
            }
            Button("取消", role: .cancel) {}
        }
    }
}

// MARK: - Preview

#if DEBUG
struct EnhancedFeedView_Previews: PreviewProvider {
    static var previews: some View {
        EnhancedFeedView()
    }
}
#endif
