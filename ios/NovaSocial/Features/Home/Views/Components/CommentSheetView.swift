import SwiftUI

// MARK: - Comment Sheet View

struct CommentSheetView: View {
    let post: FeedPost
    @Binding var isPresented: Bool
    var onAvatarTapped: ((String) -> Void)?  // 点击头像回调
    var onCommentCountUpdated: ((String, Int) -> Void)?  // 评论数量同步回调 (postId, actualCount)
    @State private var commentText = ""
    @State private var comments: [SocialComment] = []
    @State private var isLoading = false
    @State private var isSubmitting = false
    @State private var error: String?
    @State private var totalCount = 0

    // 删除评论相关状态
    @State private var commentToDelete: SocialComment?
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false

    @EnvironmentObject private var authManager: AuthenticationManager
    private let socialService = SocialService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Comments List
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DesignTokens.spacing16) {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else if let error = error {
                            VStack(spacing: DesignTokens.spacing12) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 40))
                                    .foregroundColor(.orange)
                                Text(error)
                                    .font(.system(size: DesignTokens.fontMedium))
                                    .foregroundColor(DesignTokens.textSecondary)
                                    .multilineTextAlignment(.center)
                                Button("Retry") {
                                    Task { await loadComments() }
                                }
                                .foregroundColor(DesignTokens.accentColor)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else if comments.isEmpty {
                            VStack(spacing: DesignTokens.spacing12) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 40))
                                    .foregroundColor(DesignTokens.textMuted)
                                Text("No comments yet")
                                    .font(.system(size: DesignTokens.fontLarge))
                                    .foregroundColor(DesignTokens.textSecondary)
                                Text("Be the first to comment!")
                                    .font(.system(size: DesignTokens.fontMedium))
                                    .foregroundColor(DesignTokens.textMuted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            // Comment count header
                            Text("\(totalCount) comments")
                                .font(.system(size: DesignTokens.fontBody, weight: .medium))
                                .foregroundColor(DesignTokens.textSecondary)
                                .padding(.bottom, DesignTokens.spacing8)

                            ForEach(comments) { comment in
                                SocialCommentRow(
                                    comment: comment,
                                    canDelete: canDeleteComment(comment),
                                    onAvatarTapped: { userId in
                                        // 关闭评论弹窗，触发头像点击回调
                                        isPresented = false
                                        onAvatarTapped?(userId)
                                    },
                                    onDelete: {
                                        commentToDelete = comment
                                        showDeleteConfirmation = true
                                    }
                                )
                            }
                        }
                    }
                    .padding()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }

                Divider()

                // Comment Input
                HStack(spacing: DesignTokens.spacing12) {
                    Circle()
                        .fill(DesignTokens.avatarPlaceholder)
                        .frame(width: 36, height: 36)

                    TextField("Add a comment...", text: $commentText)
                        .font(.system(size: DesignTokens.fontMedium))
                        .textFieldStyle(.plain)
                        .disabled(isSubmitting)

                    Button(action: { Task { await submitComment() } }) {
                        if isSubmitting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: DesignTokens.fontLarge))
                                .foregroundColor(
                                    commentText.isEmpty
                                    ? DesignTokens.textMuted
                                    : DesignTokens.accentColor
                                )
                        }
                    }
                    .disabled(commentText.isEmpty || isSubmitting)
                }
                .padding(.horizontal, DesignTokens.spacing16)
                .padding(.vertical, DesignTokens.spacing12)
                .background(DesignTokens.cardBackground)
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        isPresented = false
                    }
                    .foregroundColor(DesignTokens.accentColor)
                }
            }
            .task {
                await loadComments()
            }
            .overlay {
                // 自定义删除确认弹窗
                if showDeleteConfirmation {
                    DeleteCommentConfirmation(
                        isPresented: $showDeleteConfirmation,
                        isDeleting: isDeleting,
                        onConfirm: {
                            if let comment = commentToDelete {
                                Task { await deleteComment(comment) }
                            }
                        },
                        onCancel: {
                            commentToDelete = nil
                        }
                    )
                }
            }
        }
    }

    // MARK: - Permission Check

    /// 检查当前用户是否可以删除评论（评论者本人 或 帖子拥有者）
    private func canDeleteComment(_ comment: SocialComment) -> Bool {
        guard let currentUserId = authManager.currentUser?.id else {
            #if DEBUG
            print("[CommentSheet] ❌ canDelete: currentUser is nil")
            #endif
            return false
        }
        // 评论者本人可以删除
        let isCommentAuthor = comment.userId == currentUserId
        // 帖子拥有者可以删除任何评论
        let isPostOwner = post.authorId == currentUserId
        let canDelete = isCommentAuthor || isPostOwner
        return canDelete
    }

    // MARK: - API Functions

    private func loadComments() async {
        isLoading = true
        error = nil

        do {
            let result = try await socialService.getComments(postId: post.id, limit: 50, offset: 0)
            comments = result.comments
            totalCount = result.totalCount

            // Sync actual comment count back to feed if it differs from displayed count
            if totalCount != post.commentCount {
                #if DEBUG
                print("[CommentSheet] 📝 Syncing count mismatch: \(post.commentCount) -> \(totalCount)")
                #endif
                onCommentCountUpdated?(post.id, totalCount)
            }
        } catch let apiError as APIError {
            switch apiError {
            case .unauthorized:
                error = "Please login to view comments"
            case .notFound:
                // No comments yet - not an error
                comments = []
                totalCount = 0
                // Sync the zero count back to feed
                if post.commentCount != 0 {
                    #if DEBUG
                    print("[CommentSheet] 📝 Syncing zero count - post showed \(post.commentCount)")
                    #endif
                    onCommentCountUpdated?(post.id, 0)
                }
            default:
                error = "Failed to load comments"
            }
        } catch {
            self.error = "Network error"
        }

        isLoading = false
    }

    private func submitComment() async {
        guard !commentText.isEmpty else { return }
        isSubmitting = true

        do {
            let newComment = try await socialService.createComment(postId: post.id, content: commentText)
            comments.insert(newComment, at: 0)
            totalCount += 1
            commentText = ""

            // Sync the new comment count back to feed
            onCommentCountUpdated?(post.id, totalCount)
        } catch {
            // Show error briefly
            self.error = "Failed to post comment"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.error = nil
            }
        }

        isSubmitting = false
    }

    private func deleteComment(_ comment: SocialComment) async {
        guard authManager.currentUser != nil else { return }
        isDeleting = true

        do {
            try await socialService.deleteComment(commentId: comment.id)

            // 从列表中移除评论
            if let index = comments.firstIndex(where: { $0.id == comment.id }) {
                comments.remove(at: index)
                totalCount -= 1

                // 同步评论数量到 feed
                onCommentCountUpdated?(post.id, totalCount)
            }

            // 关闭确认弹窗并清理状态
            showDeleteConfirmation = false
            commentToDelete = nil
        } catch {
            // 显示错误
            self.error = "Failed to delete comment"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.error = nil
            }
        }

        isDeleting = false
    }
}

// MARK: - Previews

#Preview("CommentSheet - Default") {
    CommentSheetView(
        post: FeedPost.preview,
        isPresented: .constant(true)
    )
}

#Preview("CommentSheet - Dark Mode") {
    CommentSheetView(
        post: FeedPost.preview,
        isPresented: .constant(true)
    )
    .preferredColorScheme(.dark)
}

// MARK: - Social Comment Row

struct SocialCommentRow: View {
    let comment: SocialComment
    var canDelete: Bool = false  // 是否可以删除（评论者本人或帖子拥有者）
    var onAvatarTapped: ((String) -> Void)?  // 点击头像回调
    var onDelete: (() -> Void)?  // 删除评论回调

    @State private var showDeleteMenu = false

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.spacing12) {
            // Avatar (点击跳转用户主页)
            if let avatarUrl = comment.authorAvatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(DesignTokens.avatarPlaceholder)
                }
                .frame(width: DesignTokens.avatarSmall, height: DesignTokens.avatarSmall)
                .clipShape(Circle())
                .onTapGesture {
                    onAvatarTapped?(comment.userId)
                }
            } else {
                Circle()
                    .fill(DesignTokens.avatarPlaceholder)
                    .frame(width: DesignTokens.avatarSmall, height: DesignTokens.avatarSmall)
                    .onTapGesture {
                        onAvatarTapped?(comment.userId)
                    }
            }

            VStack(alignment: .leading, spacing: DesignTokens.spacing4) {
                HStack {
                    // 用户名 (点击跳转用户主页)
                    Text(comment.displayAuthorName)
                        .font(.system(size: DesignTokens.fontMedium, weight: .semibold))
                        .foregroundColor(.black)
                        .onTapGesture {
                            onAvatarTapped?(comment.userId)
                        }

                    Text(comment.createdDate.timeAgoDisplay())
                        .font(.system(size: DesignTokens.fontSmall))
                        .foregroundColor(DesignTokens.textSecondary)
                }

                Text(comment.content)
                    .font(.system(size: DesignTokens.fontMedium))
                    .foregroundColor(DesignTokens.textPrimary)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    if canDelete {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                        onDelete?()
                    }
                }
        )
    }
}

// MARK: - Delete Comment Confirmation

struct DeleteCommentConfirmation: View {
    @Binding var isPresented: Bool
    let isDeleting: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            // 半透明背景
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isDeleting {
                        isPresented = false
                        onCancel()
                    }
                }

            // 弹窗内容
            VStack(spacing: 0) {
                // 图标
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white, .red)
                    .padding(.top, 24)

                // 标题
                Text("Delete Comment?")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.top, 16)

                // 描述
                Text("This comment will be permanently deleted and cannot be recovered.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                // 按钮
                HStack(spacing: 12) {
                    // 取消按钮
                    Button {
                        isPresented = false
                        onCancel()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color(.systemGray5))
                            .cornerRadius(10)
                    }
                    .disabled(isDeleting)

                    // 删除按钮
                    Button {
                        onConfirm()
                    } label: {
                        HStack(spacing: 8) {
                            if isDeleting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text(isDeleting ? "Deleting..." : "Delete")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.red)
                        .cornerRadius(10)
                    }
                    .disabled(isDeleting)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 20)
            }
            .frame(width: 300)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPresented)
    }
}
