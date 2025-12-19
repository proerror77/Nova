import SwiftUI

// MARK: - Comment ViewModel

/// ViewModel for managing comments on a post
@MainActor
@Observable
class CommentViewModel {
    // MARK: - Properties

    private(set) var comments: [SocialComment] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var isSendingComment = false
    private(set) var error: String?
    private(set) var totalCount = 0
    private(set) var hasMore = true

    private let socialService = SocialService()
    private var currentOffset = 0
    private let pageSize = 20

    var postId: String = ""

    // MARK: - Load Comments

    func loadComments(postId: String) async {
        guard !isLoading else { return }

        self.postId = postId
        isLoading = true
        error = nil
        currentOffset = 0

        do {
            let result = try await socialService.getComments(
                postId: postId,
                limit: pageSize,
                offset: 0
            )
            comments = result.comments
            totalCount = result.totalCount
            hasMore = result.comments.count >= pageSize
            currentOffset = result.comments.count
        } catch {
            self.error = "Failed to load comments"
            #if DEBUG
            print("[CommentViewModel] Load error: \(error)")
            #endif
        }

        isLoading = false
    }

    // MARK: - Load More Comments

    func loadMore() async {
        guard !isLoadingMore, hasMore, !postId.isEmpty else { return }

        isLoadingMore = true

        do {
            let result = try await socialService.getComments(
                postId: postId,
                limit: pageSize,
                offset: currentOffset
            )
            comments.append(contentsOf: result.comments)
            totalCount = result.totalCount
            hasMore = result.comments.count >= pageSize
            currentOffset += result.comments.count
        } catch {
            #if DEBUG
            print("[CommentViewModel] Load more error: \(error)")
            #endif
        }

        isLoadingMore = false
    }

    // MARK: - Send Comment

    func sendComment(content: String, parentCommentId: String? = nil) async -> Bool {
        guard !isSendingComment, !postId.isEmpty, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        isSendingComment = true
        error = nil

        do {
            let newComment = try await socialService.createComment(
                postId: postId,
                content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                parentCommentId: parentCommentId
            )

            // Add new comment at the beginning of the list
            if parentCommentId == nil {
                comments.insert(newComment, at: 0)
                totalCount += 1
            }

            isSendingComment = false
            return true
        } catch {
            self.error = "Failed to send comment"
            #if DEBUG
            print("[CommentViewModel] Send error: \(error)")
            #endif
            isSendingComment = false
            return false
        }
    }

    // MARK: - Delete Comment

    func deleteComment(commentId: String, userId: String) async -> Bool {
        do {
            try await socialService.deleteComment(commentId: commentId, userId: userId)
            comments.removeAll { $0.id == commentId }
            totalCount -= 1
            return true
        } catch {
            self.error = "Failed to delete comment"
            #if DEBUG
            print("[CommentViewModel] Delete error: \(error)")
            #endif
            return false
        }
    }

    // MARK: - Refresh

    func refresh() async {
        await loadComments(postId: postId)
    }
}

// MARK: - Post Detail View

struct PostDetailView: View {
    let post: FeedPost
    var onDismiss: (() -> Void)?
    var onAvatarTapped: ((String) -> Void)?  // 点击头像回调，传入 authorId
    @Environment(\.dismiss) private var dismiss
    @State private var currentImageIndex = 0
    @State private var isFollowing = false

    // MARK: - Comment State
    @State private var commentViewModel = CommentViewModel()
    @State private var newCommentText = ""
    @FocusState private var isCommentInputFocused: Bool

    // MARK: - Interaction State
    @State private var isPostLiked = false
    @State private var isPostSaved = false
    @State private var postLikeCount: Int = 0
    @State private var postSaveCount: Int = 0

    /// 当前显示的评论
    private var displayComments: [SocialComment] {
        commentViewModel.comments
    }

    /// 评论总数
    private var displayCommentCount: Int {
        commentViewModel.totalCount
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            DesignTokens.backgroundColor
                .ignoresSafeArea()

            // Main Content
            VStack(spacing: 0) {
                // MARK: - Top Navigation Bar
                topNavigationBar

                // MARK: - Scrollable Content
                ScrollView {
                    VStack(spacing: 0) {
                        // MARK: - Image Carousel
                        imageCarouselSection

                        // MARK: - Content Section
                        contentSection

                        // MARK: - Comments Section
                        commentsSection

                        // Bottom padding for action bar
                        Color.clear.frame(height: 100)
                    }
                }
            }

            // MARK: - Bottom Action Bar
            bottomActionBar
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // 点击空白区域退出键盘
            isCommentInputFocused = false
        }
        .navigationBarBackButtonHidden(true)
        .task {
            await commentViewModel.loadComments(postId: post.id)
        }
        .onAppear {
            // 初始化点赞和收藏数量
            postLikeCount = post.likeCount
            postSaveCount = post.shareCount
            isPostLiked = post.isLiked
            isPostSaved = post.isBookmarked
        }
    }

    // MARK: - Top Navigation Bar

    private var topNavigationBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Back Button
                Button(action: {
                    if let onDismiss = onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(DesignTokens.textPrimary)
                        .frame(width: 24, height: 24)
                }

                // User Info (点击头像或用户名跳转用户主页)
                HStack(spacing: 10) {
                    AvatarView(image: nil, url: post.authorAvatar, size: 36)
                        .onTapGesture {
                            onAvatarTapped?(post.authorId)
                        }

                    Text(post.authorName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(DesignTokens.textPrimary)
                        .onTapGesture {
                            onAvatarTapped?(post.authorId)
                        }

                    // Verified Badge
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.20, green: 0.60, blue: 1.0))
                }

                Spacer()

                // Follow Button
                Button(action: {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        isFollowing.toggle()
                    }
                }) {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.system(size: 12))
                        .foregroundColor(isFollowing ? DesignTokens.textSecondary : DesignTokens.accentColor)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 100)
                                .stroke(isFollowing ? DesignTokens.textSecondary : DesignTokens.accentColor, lineWidth: 0.5)
                        )
                }

                // Share Button
                Button(action: {}) {
                    Image("card-share-icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(DesignTokens.surface)

            // Divider
            Divider()
                .frame(height: 0.25)
                .background(Color(red: 0.77, green: 0.77, blue: 0.77))
        }
    }

    // MARK: - Image Carousel Section

    private var imageCarouselSection: some View {
        VStack(spacing: 8) {
            if !post.displayMediaUrls.isEmpty {
                // Image/Video Carousel with caching for better performance
                TabView(selection: $currentImageIndex) {
                    ForEach(Array(post.displayMediaUrls.enumerated()), id: \.element) { index, mediaUrl in
                        Group {
                            if isVideoUrl(mediaUrl) {
                                // Video content - use FeedVideoPlayer
                                FeedVideoPlayer(
                                    url: URL(string: mediaUrl)!,
                                    autoPlay: true,
                                    isMuted: true,
                                    height: UIScreen.main.bounds.width * 4 / 3 - 40
                                )
                            } else {
                                // Image content - use CachedAsyncImage
                                CachedAsyncImage(
                                    url: URL(string: mediaUrl),
                                    targetSize: CGSize(width: 750, height: 1000)  // 2x for Retina
                                ) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    Rectangle()
                                        .fill(DesignTokens.placeholderColor)
                                        .overlay(ProgressView().tint(.white))
                                }
                                .frame(maxWidth: .infinity)
                                .aspectRatio(3/4, contentMode: .fill)
                                .clipped()
                            }
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: UIScreen.main.bounds.width * 4 / 3 - 40)

                // Page Indicators
                if post.displayMediaUrls.count > 1 {
                    HStack(spacing: 11) {
                        ForEach(0..<post.displayMediaUrls.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentImageIndex ?
                                      Color(red: 0.81, green: 0.13, blue: 0.25) :
                                      Color(red: 0.85, green: 0.85, blue: 0.85))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.top, 4)
                }
            } else {
                // Placeholder for empty image
                Rectangle()
                    .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                    .frame(height: 332)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
    }

    // MARK: - Content Section

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            Text("Beautiful scenery")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(DesignTokens.textPrimary)

            // Description
            Text(post.content.isEmpty ? "The setting sun dyed the entire sea surface golden. The ship seemed to slowly sail into the light." : post.content)
                .font(.system(size: 12))
                .lineSpacing(6)
                .foregroundColor(DesignTokens.textPrimary)

            // Tags
            Text("#Fashion #Sport #Art #Beautiful")
                .font(.system(size: 12))
                .foregroundColor(DesignTokens.accentColor)

            // Time and Location
            HStack(spacing: 5) {
                Text(post.createdAt.timeAgoDisplay())
                    .font(.system(size: 10))
                    .foregroundColor(DesignTokens.textSecondary)

                Text("Beijing")
                    .font(.system(size: 10))
                    .foregroundColor(DesignTokens.textSecondary)
            }

            // Divider
            Divider()
                .frame(height: 0.2)
                .background(Color(red: 0.77, green: 0.77, blue: 0.77))
        }
        .padding(.horizontal, 17)
        .padding(.top, 16)
    }

    // MARK: - Comments Section

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Comments Count
            HStack {
                Text("\(displayCommentCount) comments")
                    .font(.system(size: 14))
                    .foregroundColor(DesignTokens.textPrimary)

                if commentViewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .padding(.horizontal, 17)
            .padding(.top, 12)

            // Comment List
            if displayComments.isEmpty && !commentViewModel.isLoading {
                Text("No comments yet. Be the first to comment!")
                    .font(.system(size: 12))
                    .foregroundColor(DesignTokens.textSecondary)
                    .padding(.horizontal, 17)
                    .padding(.vertical, 20)
            } else {
                ForEach(displayComments) { comment in
                    SocialCommentItemView(
                        comment: comment,
                        onReplyTapped: {
                            isCommentInputFocused = true
                        },
                        onAvatarTapped: onAvatarTapped
                    )
                }

                // Load More Button
                if commentViewModel.hasMore && !commentViewModel.isLoadingMore {
                    Button(action: {
                        Task {
                            await commentViewModel.loadMore()
                        }
                    }) {
                        Text("Load more comments...")
                            .font(.system(size: 12))
                            .foregroundColor(DesignTokens.accentColor)
                    }
                    .padding(.horizontal, 17)
                    .padding(.vertical, 8)
                }

                if commentViewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.8)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            Divider()
                .frame(height: 0.25)
                .background(Color(red: 0.77, green: 0.77, blue: 0.77))

            // Stats Row
            HStack(spacing: 16) {
                // Like Button
                Button(action: {
                    isPostLiked.toggle()
                    postLikeCount += isPostLiked ? 1 : -1
                }) {
                    HStack(spacing: 6) {
                        Image(isPostLiked ? "Like-on" : "Like-off")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        Text("\(postLikeCount)")
                            .font(Font.custom("Helvetica Neue", size: 14))
                            .lineSpacing(20)
                            .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
                    }
                }

                // Comment Button (点击呼出键盘)
                Button(action: {
                    isCommentInputFocused = true
                }) {
                    HStack(spacing: 6) {
                        Image("card-comment-icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        Text("\(displayCommentCount)")
                            .font(Font.custom("Helvetica Neue", size: 14))
                            .lineSpacing(20)
                            .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
                    }
                }

                // Save Button
                Button(action: {
                    isPostSaved.toggle()
                    postSaveCount += isPostSaved ? 1 : -1
                }) {
                    HStack(spacing: 6) {
                        Image(isPostSaved ? "Save-on" : "Save-off")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        Text("\(postSaveCount)")
                            .font(Font.custom("Helvetica Neue", size: 14))
                            .lineSpacing(20)
                            .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 17)
            .padding(.top, 20)
            .padding(.bottom, 16)
            .background(DesignTokens.surface)

            // 隐藏的输入框 (键盘弹出时显示)
            if isCommentInputFocused {
                HStack(spacing: 10) {
                    HStack {
                        TextField("Add a comment...", text: $newCommentText)
                            .font(.system(size: 14))
                            .foregroundColor(DesignTokens.textPrimary)
                            .focused($isCommentInputFocused)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.95, green: 0.95, blue: 0.95))
                    .cornerRadius(20)

                    // Send Button
                    Button(action: {
                        Task {
                            await sendComment()
                        }
                    }) {
                        if commentViewModel.isSendingComment {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 32, height: 32)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 16))
                                .foregroundColor(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? DesignTokens.textSecondary : DesignTokens.accentColor)
                                .frame(width: 32, height: 32)
                        }
                    }
                    .disabled(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || commentViewModel.isSendingComment)
                }
                .padding(.horizontal, 17)
                .padding(.bottom, 12)
                .background(DesignTokens.surface)
            }
        }
        .background(DesignTokens.surface)
    }

    // MARK: - Send Comment

    private func sendComment() async {
        let content = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        let success = await commentViewModel.sendComment(content: content)
        if success {
            newCommentText = ""
            isCommentInputFocused = false
        }
    }

    
    /// Check if URL points to a video file
    private func isVideoUrl(_ url: String) -> Bool {
        let lowercased = url.lowercased()
        return lowercased.contains(".mov") ||
               lowercased.contains(".mp4") ||
               lowercased.contains(".m4v") ||
               lowercased.contains(".webm")
    }
}

// MARK: - Comment Item View

struct SocialCommentItemView: View {
    let comment: SocialComment
    var onReplyTapped: (() -> Void)? = nil
    var onAvatarTapped: ((String) -> Void)? = nil  // 点击头像回调
    @State private var isLiked = false
    @State private var isSaved = false
    @State private var likeCount = 0
    @State private var saveCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main Comment
            HStack(alignment: .top, spacing: 10) {
                // Avatar (点击跳转用户主页)
                AvatarView(image: nil, url: comment.authorAvatarUrl, size: 30)
                    .onTapGesture {
                        onAvatarTapped?(comment.userId)
                    }

                // Comment Content
                VStack(alignment: .leading, spacing: 5) {
                    // Author Name (点击跳转用户主页)
                    Text(comment.displayAuthorName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignTokens.textSecondary)
                        .onTapGesture {
                            onAvatarTapped?(comment.userId)
                        }

                    // Comment Text
                    Text(comment.content)
                        .font(.system(size: 12))
                        .foregroundColor(DesignTokens.textPrimary)

                    // Time, Location, Reply + Like & Save (same row)
                    HStack(spacing: 14) {
                        HStack(spacing: 5) {
                            Text(comment.createdDate.timeAgoDisplay())
                                .font(.system(size: 12))
                                .foregroundColor(DesignTokens.textSecondary)
                        }

                        Button(action: {
                            onReplyTapped?()
                        }) {
                            Text("Reply")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
                        }

                        Spacer()

                        // Like & Save Buttons (Horizontal)
                        HStack(spacing: 5) {
                            // Like Button
                            Button(action: {
                                isLiked.toggle()
                                likeCount += isLiked ? 1 : -1
                            }) {
                                HStack(spacing: 2) {
                                    Image(isLiked ? "Like-on" : "Like-off")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 12, height: 12)
                                    Text("\(likeCount)")
                                        .font(Font.custom("Helvetica Neue", size: 12))
                                        .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
                                }
                            }

                            // Save Button
                            Button(action: {
                                isSaved.toggle()
                                saveCount += isSaved ? 1 : -1
                            }) {
                                HStack(spacing: 2) {
                                    Image(isSaved ? "Save-on" : "Save-off")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 12, height: 12)
                                    Text("\(saveCount)")
                                        .font(Font.custom("Helvetica Neue", size: 12))
                                        .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Previews

#Preview("PostDetail - Default") {
    NavigationStack {
        PostDetailView(post: FeedPost.preview)
    }
    .environmentObject(AuthenticationManager.shared)
}

#Preview("PostDetail - Dark Mode") {
    NavigationStack {
        PostDetailView(post: FeedPost.preview)
    }
    .environmentObject(AuthenticationManager.shared)
    .preferredColorScheme(.dark)
}
