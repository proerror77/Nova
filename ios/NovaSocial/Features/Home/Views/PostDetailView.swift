import SwiftUI
import Photos

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

    func deleteComment(commentId: String) async -> Bool {
        do {
            try await socialService.deleteComment(commentId: commentId)
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

    // MARK: - Update Total Count (从 CommentSheetView 回调)

    func updateTotalCount(_ count: Int) {
        totalCount = count
    }
}

// MARK: - Post Detail View

struct PostDetailView: View {
    let post: FeedPost
    var onDismiss: (() -> Void)?
    var onAvatarTapped: ((String) -> Void)?  // 点击头像回调，传入 authorId
    var onPostDeleted: (() -> Void)?  // 帖子删除后回调
    var onLikeChanged: ((Bool, Int) -> Void)?  // 点赞状态变化回调 (isLiked, likeCount)
    var onBookmarkChanged: ((Bool, Int) -> Void)?  // 收藏状态变化回调 (isBookmarked, bookmarkCount)
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var currentImageIndex = 0
    @State private var isFollowing = false
    @State private var isFollowLoading = false

    private let graphService = GraphService()
    private let contentService = ContentService()
    private let socialService = SocialService()

    // MARK: - Comment State
    @State private var commentViewModel = CommentViewModel()
    @State private var showComments = false  // 使用 CommentSheetView 弹窗（与 Home 统一）

    // MARK: - Interaction State
    @State private var isPostLiked = false
    @State private var isPostSaved = false
    @State private var postLikeCount: Int = 0
    @State private var postSaveCount: Int = 0
    @State private var isLikeLoading = false
    @State private var isBookmarkLoading = false

    // MARK: - Post Actions State (作者操作)
    @State private var showingActionSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var showingSaveSuccess = false
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""
    @State private var showingDeleteError = false
    @State private var deleteErrorMessage = ""

    /// 是否是自己的帖子
    private var isOwnPost: Bool {
        guard let currentUserId = authManager.currentUser?.id else { return false }
        return post.authorId == currentUserId
    }

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
        .navigationBarBackButtonHidden(true)
        .task {
            await commentViewModel.loadComments(postId: post.id)
            await checkFollowStatus()
        }
        .onAppear {
            // 初始化点赞和收藏数量
            postLikeCount = post.likeCount
            postSaveCount = post.bookmarkCount  // 修复: 应该使用 bookmarkCount 而非 shareCount
            isPostLiked = post.isLiked
            isPostSaved = post.isBookmarked
        }
        // MARK: - Action Sheet (作者操作菜单)
        .confirmationDialog("Post Options", isPresented: $showingActionSheet, titleVisibility: .visible) {
            if !post.displayMediaUrls.isEmpty {
                Button("Save Image") {
                    Task {
                        await saveCurrentImageToPhotos()
                    }
                }
            }
            Button("Delete Post", role: .destructive) {
                showingDeleteConfirmation = true
            }
            Button("Cancel", role: .cancel) { }
        }
        // MARK: - Delete Confirmation
        .alert("Delete Post", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await deletePost()
                }
            }
        } message: {
            Text("Are you sure you want to delete this post? This action cannot be undone.")
        }
        // MARK: - Save Success Alert
        .alert("Saved", isPresented: $showingSaveSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Image saved to Photos")
        }
        // MARK: - Save Error Alert
        .alert("Save Failed", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
        // MARK: - Delete Error Alert
        .alert("Delete Failed", isPresented: $showingDeleteError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deleteErrorMessage)
        }
        // MARK: - Deleting Overlay
        .overlay {
            if isDeleting {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("Deleting...")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                    }
                    .padding(24)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(12)
                }
            }
        }
        // MARK: - Comment Sheet (与 Home 统一)
        .sheet(isPresented: $showComments) {
            CommentSheetView(
                post: post,
                isPresented: $showComments,
                onAvatarTapped: { userId in
                    onAvatarTapped?(userId)
                },
                onCommentCountUpdated: { postId, actualCount in
                    // 更新本地评论数量
                    commentViewModel.updateTotalCount(actualCount)
                }
            )
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

                // 根据是否是自己的帖子显示不同按钮
                if isOwnPost {
                    // 作者视角: 显示 "..." 按钮
                    Button(action: {
                        showingActionSheet = true
                    }) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(DesignTokens.textPrimary)
                            .frame(width: 24, height: 24)
                    }
                } else {
                    // 其他用户视角: 显示 Follow + Share 按钮
                    // Follow Button
                    Button(action: {
                        Task {
                            await toggleFollow()
                        }
                    }) {
                        if isFollowLoading {
                            ProgressView()
                                .frame(width: 60, height: 24)
                        } else {
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
                    }
                    .disabled(isFollowLoading)

                    // Share Button
                    Button(action: {}) {
                        Image("card-share-icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                    }
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
                GeometryReader { geometry in
                    // Image/Video Carousel with caching for better performance
                    TabView(selection: $currentImageIndex) {
                        ForEach(Array(post.displayMediaUrls.enumerated()), id: \.element) { index, mediaUrl in
                            Group {
                                if isVideoUrl(mediaUrl), let videoUrl = URL(string: mediaUrl) {
                                    // Video content - use FeedVideoPlayer
                                    FeedVideoPlayer(
                                        url: videoUrl,
                                        autoPlay: true,
                                        isMuted: true,
                                        height: geometry.size.width * 4 / 3 - 40
                                    )
                                } else if isVideoUrl(mediaUrl) {
                                    // Invalid video URL - show placeholder
                                    Rectangle()
                                        .fill(DesignTokens.placeholderColor)
                                        .frame(height: geometry.size.width * 4 / 3 - 40)
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
                }
                .aspectRatio(3/4, contentMode: .fit)  // Provide aspect ratio instead of fixed height

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
            // Title (from backend or VLM analysis)
            if let title = post.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(DesignTokens.textPrimary)
            }

            // Description
            if !post.content.isEmpty {
                Text(post.content)
                    .font(.system(size: 12))
                    .lineSpacing(6)
                    .foregroundColor(DesignTokens.textPrimary)
            }

            // Tags (from AI analysis or user input)
            if let formattedTags = post.formattedTags {
                Text(formattedTags)
                    .font(.system(size: 12))
                    .foregroundColor(DesignTokens.accentColor)
            }

            // Time and Location
            HStack(spacing: 5) {
                Text(post.createdAt.timeAgoDisplay())
                    .font(.system(size: 10))
                    .foregroundColor(DesignTokens.textSecondary)

                if let location = post.location {
                    Text(location)
                        .font(.system(size: 10))
                        .foregroundColor(DesignTokens.textSecondary)
                }
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
                            showComments = true
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
                    Task { await toggleLike() }
                }) {
                    HStack(spacing: 6) {
                        if isLikeLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 20, height: 20)
                        } else {
                            Image(isPostLiked ? "card-heart-icon-filled" : "card-heart-icon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                        }
                        Text("\(postLikeCount)")
                            .font(.system(size: 14))
                            .lineSpacing(20)
                            .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
                    }
                }
                .disabled(isLikeLoading)

                // Comment Button (打开评论弹窗，与 Home 统一)
                Button(action: {
                    showComments = true
                }) {
                    HStack(spacing: 6) {
                        Image("card-comment-icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        Text("\(displayCommentCount)")
                            .font(.system(size: 14))
                            .lineSpacing(20)
                            .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
                    }
                }

                // Bookmark Button (与 Home 一致的图标)
                Button(action: {
                    Task { await toggleBookmark() }
                }) {
                    HStack(spacing: 6) {
                        if isBookmarkLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 20, height: 20)
                        } else {
                            Image(isPostSaved ? "collect-fill" : "collect")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                        }
                        Text("\(postSaveCount)")
                            .font(.system(size: 14))
                            .lineSpacing(20)
                            .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
                    }
                }
                .disabled(isBookmarkLoading)

                Spacer()
            }
            .padding(.horizontal, 17)
            .padding(.top, 20)
            .padding(.bottom, 16)
            .background(DesignTokens.surface)

        }
        .background(DesignTokens.surface)
    }

    // MARK: - Follow Actions

    private func toggleFollow() async {
        guard let currentUserId = authManager.currentUser?.id else { return }
        guard !isFollowLoading else { return }

        isFollowLoading = true

        do {
            if isFollowing {
                try await graphService.unfollowUser(followerId: currentUserId, followeeId: post.authorId)
            } else {
                try await graphService.followUser(followerId: currentUserId, followeeId: post.authorId)
            }
            isFollowing.toggle()
        } catch {
            #if DEBUG
            print("[PostDetailView] Failed to toggle follow: \(error)")
            #endif
        }

        isFollowLoading = false
    }

    private func checkFollowStatus() async {
        guard let currentUserId = authManager.currentUser?.id else { return }

        do {
            isFollowing = try await graphService.isFollowing(followerId: currentUserId, followeeId: post.authorId)
        } catch {
            #if DEBUG
            print("[PostDetailView] Failed to check follow status: \(error)")
            #endif
        }
    }

    // MARK: - Like Actions

    private func toggleLike() async {
        guard let userId = authManager.currentUser?.id else { return }
        guard !isLikeLoading else { return }

        isLikeLoading = true
        let wasLiked = isPostLiked

        // Optimistic update
        isPostLiked.toggle()
        postLikeCount = max(0, postLikeCount + (isPostLiked ? 1 : -1))

        do {
            let response: SocialService.LikeResponse
            if wasLiked {
                response = try await socialService.deleteLike(postId: post.id, userId: userId)
            } else {
                response = try await socialService.createLike(postId: post.id, userId: userId)
            }

            // Sync with server's accurate count
            postLikeCount = Int(response.likeCount)

            // Notify parent to sync state
            onLikeChanged?(isPostLiked, postLikeCount)

            // Invalidate feed cache
            await FeedCacheService.shared.invalidateCache()
        } catch {
            // Revert on failure
            isPostLiked = wasLiked
            postLikeCount = max(0, postLikeCount + (wasLiked ? 1 : -1))
            #if DEBUG
            print("[PostDetailView] Toggle like error: \(error)")
            #endif
        }

        isLikeLoading = false
    }

    // MARK: - Bookmark Actions

    private func toggleBookmark() async {
        guard let userId = authManager.currentUser?.id else { return }
        guard !isBookmarkLoading else { return }

        isBookmarkLoading = true
        let wasBookmarked = isPostSaved

        // Optimistic update
        isPostSaved.toggle()
        postSaveCount = max(0, postSaveCount + (isPostSaved ? 1 : -1))

        do {
            if wasBookmarked {
                try await socialService.deleteBookmark(postId: post.id)
            } else {
                try await socialService.createBookmark(postId: post.id, userId: userId)
            }

            // Notify parent to sync state
            onBookmarkChanged?(isPostSaved, postSaveCount)

            // Invalidate feed cache
            await FeedCacheService.shared.invalidateCache()
        } catch {
            // Revert on failure
            isPostSaved = wasBookmarked
            postSaveCount = max(0, postSaveCount + (wasBookmarked ? 1 : -1))
            #if DEBUG
            print("[PostDetailView] Toggle bookmark error: \(error)")
            #endif
        }

        isBookmarkLoading = false
    }

    /// Check if URL points to a video file
    private func isVideoUrl(_ url: String) -> Bool {
        let lowercased = url.lowercased()
        return lowercased.contains(".mov") ||
               lowercased.contains(".mp4") ||
               lowercased.contains(".m4v") ||
               lowercased.contains(".webm")
    }

    // MARK: - Delete Post

    private func deletePost() async {
        isDeleting = true

        do {
            try await contentService.deletePost(postId: post.id)

            #if DEBUG
            print("✅ Post deleted successfully: \(post.id)")
            #endif

            await MainActor.run {
                isDeleting = false
                onPostDeleted?()
                if let onDismiss = onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            }
        } catch {
            #if DEBUG
            print("❌ Failed to delete post: \(error)")
            #endif

            await MainActor.run {
                isDeleting = false
                deleteErrorMessage = "Failed to delete. Please try again."
                showingDeleteError = true
            }
        }
    }

    // MARK: - Save Image to Photos

    private func saveCurrentImageToPhotos() async {
        // 获取当前显示的图片 URL
        guard currentImageIndex < post.displayMediaUrls.count else {
            saveErrorMessage = "No image to save"
            showingSaveError = true
            return
        }

        let imageUrlString = post.displayMediaUrls[currentImageIndex]

        // Skip videos
        guard !isVideoUrl(imageUrlString) else {
            saveErrorMessage = "Video saving is not supported"
            showingSaveError = true
            return
        }

        guard let imageUrl = URL(string: imageUrlString) else {
            saveErrorMessage = "Invalid image URL"
            showingSaveError = true
            return
        }

        // Request photo library permission
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveErrorMessage = "Please allow photo library access in Settings"
            showingSaveError = true
            return
        }

        do {
            // Download image
            let (data, _) = try await URLSession.shared.data(from: imageUrl)
            guard let image = UIImage(data: data) else {
                saveErrorMessage = "Failed to load image"
                showingSaveError = true
                return
            }

            // Save to photo library
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }

            showingSaveSuccess = true
        } catch {
            #if DEBUG
            print("❌ Failed to save image: \(error)")
            #endif
            saveErrorMessage = "Save failed: \(error.localizedDescription)"
            showingSaveError = true
        }
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
                                    Text(likeCount.abbreviated)
                                        .font(.system(size: 12))
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
                                    Text(saveCount.abbreviated)
                                        .font(.system(size: 12))
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
