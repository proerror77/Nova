import SwiftUI

// MARK: - Comment Sheet View

// MARK: - Text Parsing Helper
/// Parse comment text and highlight @mentions with accent color
private func parseCommentText(_ text: String) -> Text {
    let pattern = try? NSRegularExpression(pattern: "@[\\w\\u4e00-\\u9fff]+", options: [])
    guard let regex = pattern else {
        return Text(text)
    }

    let nsString = text as NSString
    let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

    if matches.isEmpty {
        return Text(text)
    }

    var result = Text("")
    var lastEnd = 0

    for match in matches {
        if match.range.location > lastEnd {
            let beforeRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
            let beforeText = nsString.substring(with: beforeRange)
            result = result + Text(beforeText)
        }
        let mentionText = nsString.substring(with: match.range)
        result = result + Text(mentionText)
            .foregroundColor(DesignTokens.accentColor)
            .fontWeight(.medium)
        lastEnd = match.range.location + match.range.length
    }

    if lastEnd < nsString.length {
        let afterText = nsString.substring(from: lastEnd)
        result = result + Text(afterText)
    }

    return result
}

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

    // 批次加載的評論按讚狀態 (修復 N+1 問題)
    @State private var commentLikeStatus: [String: Bool] = [:]
    @State private var commentLikeCounts: [String: Int] = [:]

    @EnvironmentObject private var authManager: AuthenticationManager
    private let socialService = SocialService()

    /// 将评论按照父子关系分组 (IG/小红书风格嵌套回复)
    private var groupedComments: [(parent: SocialComment, replies: [SocialComment])] {
        // 获取所有顶级评论 (没有 parentCommentId 或是空字串)
        let topLevelComments = comments.filter { $0.parentCommentId == nil || $0.parentCommentId?.isEmpty == true }

        // 为每个顶级评论找到其回复
        return topLevelComments.map { parent in
            let replies = comments.filter { $0.parentCommentId == parent.id }
            return (parent: parent, replies: replies)
        }
    }

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
                                    .font(.system(size: 40.f))
                                    .foregroundColor(.orange)
                                Text(error)
                                    .font(Font.custom("SFProDisplay-Regular", size: DesignTokens.fontMedium))
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
                                    .font(.system(size: 40.f))
                                    .foregroundColor(DesignTokens.textMuted)
                                Text("No comments yet")
                                    .font(Font.custom("SFProDisplay-Regular", size: DesignTokens.fontLarge))
                                    .foregroundColor(DesignTokens.textSecondary)
                                Text("Be the first to comment!")
                                    .font(Font.custom("SFProDisplay-Regular", size: DesignTokens.fontMedium))
                                    .foregroundColor(DesignTokens.textMuted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            // Comment count header
                            Text("\(totalCount) comments")
                                .font(Font.custom("SFProDisplay-Medium", size: DesignTokens.fontBody))
                                .foregroundColor(DesignTokens.textSecondary)
                                .padding(.bottom, DesignTokens.spacing8)

                            // 使用分组评论显示嵌套回复 (IG/小红书风格)
                            ForEach(Array(groupedComments.enumerated()), id: \.offset) { _, group in
                                VStack(alignment: .leading, spacing: 0) {
                                    // 父评论
                                    SocialCommentRow(
                                        comment: group.parent,
                                        canDelete: canDeleteComment(group.parent),
                                        initialLikedStatus: commentLikeStatus[group.parent.id],
                                        onAvatarTapped: { userId in
                                            isPresented = false
                                            onAvatarTapped?(userId)
                                        },
                                        onDelete: {
                                            commentToDelete = group.parent
                                            showDeleteConfirmation = true
                                        },
                                        onLikeStatusChanged: { commentId, isLiked, count in
                                            updateCommentLikeStatus(commentId: commentId, isLiked: isLiked, count: count)
                                        }
                                    )

                                    // 嵌套回复 (有缩进)
                                    if !group.replies.isEmpty {
                                        NestedRepliesView(
                                            replies: group.replies,
                                            canDeleteComment: canDeleteComment,
                                            commentLikeStatus: commentLikeStatus,
                                            onAvatarTapped: { userId in
                                                isPresented = false
                                                onAvatarTapped?(userId)
                                            },
                                            onDelete: { comment in
                                                commentToDelete = comment
                                                showDeleteConfirmation = true
                                            },
                                            onLikeStatusChanged: { commentId, isLiked, count in
                                                updateCommentLikeStatus(commentId: commentId, isLiked: isLiked, count: count)
                                            }
                                        )
                                    }
                                }
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
                    // 显示当前用户真实头像 (IG/小红书风格)
                    if let avatarUrl = authManager.currentUser?.avatarUrl, let url = URL(string: avatarUrl) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            Circle()
                                .fill(DesignTokens.avatarPlaceholder)
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(DesignTokens.avatarPlaceholder)
                            .frame(width: 36, height: 36)
                    }

                    TextField("Add a comment...", text: $commentText)
                        .font(Font.custom("SFProDisplay-Regular", size: DesignTokens.fontMedium))
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
            // 傳遞 viewerUserId 以在回應中直接包含 likeCount 和 isLikedByViewer
            // 這樣就不需要額外的 API 呼叫來獲取按讚資訊
            let result = try await socialService.getComments(
                postId: post.id,
                limit: 50,
                offset: 0,
                viewerUserId: authManager.currentUser?.id
            )
            comments = result.comments
            totalCount = result.totalCount

            // Sync actual comment count back to feed if it differs from displayed count
            if totalCount != post.commentCount {
                #if DEBUG
                print("[CommentSheet] 📝 Syncing count mismatch: \(post.commentCount) -> \(totalCount)")
                #endif
                onCommentCountUpdated?(post.id, totalCount)
            }

            // 從評論回應中提取按讚狀態 (不需要額外 API 呼叫)
            for comment in comments {
                if let isLiked = comment.isLikedByViewer {
                    commentLikeStatus[comment.id] = isLiked
                }
            }

            #if DEBUG
            print("[CommentSheet] ✅ Loaded \(comments.count) comments with embedded like info (0 extra API calls)")
            #endif
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

    /// 更新單個評論的按讚狀態（供子元件回調使用）
    func updateCommentLikeStatus(commentId: String, isLiked: Bool, count: Int) {
        commentLikeStatus[commentId] = isLiked
        commentLikeCounts[commentId] = count
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
    var initialLikedStatus: Bool? = nil  // 從批次 API 預載的按讚狀態
    var onAvatarTapped: ((String) -> Void)?  // 点击头像回调
    var onDelete: (() -> Void)?  // 删除评论回调
    var onLikeStatusChanged: ((String, Bool, Int) -> Void)?  // 按讚狀態變更回調

    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var showDeleteMenu = false
    @State private var isLiked = false  // 评论点赞状态
    @State private var likeCount = 0    // 点赞数量
    @State private var isLikeLoading = false
    @State private var hasLoadedStatus = false  // 追蹤是否已載入狀態

    private let socialService = SocialService()

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
                .accessibilityLabel("View \(comment.displayAuthorName)'s profile")
                .accessibilityHint("Double tap to view profile")
            } else {
                Circle()
                    .fill(DesignTokens.avatarPlaceholder)
                    .frame(width: DesignTokens.avatarSmall, height: DesignTokens.avatarSmall)
                    .onTapGesture {
                        onAvatarTapped?(comment.userId)
                    }
                    .accessibilityLabel("View \(comment.displayAuthorName)'s profile")
                    .accessibilityHint("Double tap to view profile")
            }

            VStack(alignment: .leading, spacing: DesignTokens.spacing4) {
                // 内联格式: 用户名 + 评论内容在同一行 (IG/小红书风格)
                // 使用 Text 连接以支持 @mention 高亮
                (
                    Text(comment.displayAuthorName)
                        .font(Font.custom("SFProDisplay-Semibold", size: DesignTokens.fontMedium))
                        .foregroundColor(DesignTokens.textSecondary)
                    + Text(" ")
                    + parseCommentText(comment.content)
                        .font(Font.custom("SFProDisplay-Regular", size: DesignTokens.fontMedium))
                        .foregroundColor(DesignTokens.textPrimary)
                )
                .fixedSize(horizontal: false, vertical: true)
                .onTapGesture {
                    onAvatarTapped?(comment.userId)
                }
                .accessibilityLabel("\(comment.displayAuthorName) commented: \(comment.content)")

                // 时间戳和回复按钮
                HStack(spacing: 12) {
                    Text(comment.createdDate.timeAgoDisplay())
                        .font(Font.custom("SFProDisplay-Regular", size: DesignTokens.fontSmall))
                        .foregroundColor(DesignTokens.textSecondary)
                        .accessibilityLabel("Posted \(comment.createdDate.timeAgoDisplay())")

                    Text("Reply")
                        .font(Font.custom("SFProDisplay-Medium", size: DesignTokens.fontSmall))
                        .foregroundColor(DesignTokens.textSecondary)
                        .accessibilityLabel("Reply to comment")
                        .accessibilityHint("Double tap to reply")
                }
            }

            Spacer()

            // 点赞按钮 + 数量 (IG 风格 - 右侧爱心)
            Button(action: {
                Task { await toggleCommentLike() }
            }) {
                VStack(spacing: 2) {
                    if isLikeLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                            .foregroundColor(isLiked ? .red : DesignTokens.textSecondary)
                            .scaleEffect(isLiked ? 1.1 : 1.0)
                    }

                    if likeCount > 0 {
                        Text("\(likeCount)")
                            .font(Font.custom("SFProDisplay-Regular", size: 10.f))
                            .foregroundColor(DesignTokens.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isLikeLoading)
            .accessibilityLabel(isLiked ? "Unlike comment, \(likeCount) likes" : "Like comment, \(likeCount) likes")
            .accessibilityHint(isLiked ? "Double tap to unlike" : "Double tap to like")
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
        .task {
            await loadCommentLikeStatus()
        }
    }

    // MARK: - Comment Like API

    private func loadCommentLikeStatus() async {
        guard !hasLoadedStatus else { return }
        hasLoadedStatus = true

        // 優先使用嵌入在評論中的按讚資訊 (來自 GetComments API)
        // 這樣完全不需要額外的 API 呼叫
        if let embeddedLikeCount = comment.likeCount {
            likeCount = Int(embeddedLikeCount)
        }

        if let embeddedIsLiked = comment.isLikedByViewer {
            isLiked = embeddedIsLiked
            return  // 有嵌入資料，不需要任何 API 呼叫
        }

        // 向後兼容：如果有從父元件傳入的預載狀態，使用它
        if let preloadedStatus = initialLikedStatus {
            isLiked = preloadedStatus
            // 如果沒有嵌入的 likeCount，需要載入
            if comment.likeCount == nil {
                do {
                    likeCount = try await socialService.getCommentLikes(commentId: comment.id)
                } catch {
                    #if DEBUG
                    print("[SocialCommentRow] Failed to load like count: \(error)")
                    #endif
                }
            }
            return
        }

        // 最後的 Fallback：沒有任何預載資料時，個別載入
        guard let userId = authManager.currentUser?.id else { return }

        do {
            async let likedCheck = socialService.checkCommentLiked(commentId: comment.id, userId: userId)
            async let countCheck = socialService.getCommentLikes(commentId: comment.id)

            let (liked, count) = try await (likedCheck, countCheck)
            isLiked = liked
            likeCount = count
        } catch {
            #if DEBUG
            print("[SocialCommentRow] Failed to load like status: \(error)")
            #endif
        }
    }

    private func toggleCommentLike() async {
        guard let userId = authManager.currentUser?.id else { return }
        guard !isLikeLoading else { return }

        isLikeLoading = true
        let wasLiked = isLiked

        // 乐观更新 UI
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            isLiked.toggle()
            likeCount = max(0, likeCount + (isLiked ? 1 : -1))
        }

        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

        do {
            let response: SocialService.CommentLikeResponse
            if wasLiked {
                response = try await socialService.deleteCommentLike(commentId: comment.id, userId: userId)
            } else {
                response = try await socialService.createCommentLike(commentId: comment.id, userId: userId)
            }

            // 使用服务器返回的准确数量
            likeCount = Int(response.likeCount)

            // 通知父元件狀態變更
            onLikeStatusChanged?(comment.id, isLiked, likeCount)
        } catch {
            // API 失败时回滚
            withAnimation {
                isLiked = wasLiked
                likeCount = max(0, likeCount + (wasLiked ? 1 : -1))
            }
            #if DEBUG
            print("[SocialCommentRow] Toggle like error: \(error)")
            #endif
        }

        isLikeLoading = false
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
                    .font(.system(size: 48.f))
                    .foregroundStyle(.white, .red)
                    .padding(.top, 24)

                // 标题
                Text("Delete Comment?")
                    .font(Font.custom("SFProDisplay-Semibold", size: 18.f))
                    .foregroundColor(.primary)
                    .padding(.top, 16)

                // 描述
                Text("This comment will be permanently deleted and cannot be recovered.")
                    .font(Font.custom("SFProDisplay-Regular", size: 14.f))
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
                            .font(Font.custom("SFProDisplay-Medium", size: 16.f))
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
                                .font(Font.custom("SFProDisplay-Semibold", size: 16.f))
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

// MARK: - Nested Replies View (IG/小红书风格嵌套回复)

struct NestedRepliesView: View {
    let replies: [SocialComment]
    let canDeleteComment: (SocialComment) -> Bool
    var commentLikeStatus: [String: Bool] = [:]  // 從批次 API 預載的按讚狀態
    var onAvatarTapped: ((String) -> Void)?
    var onDelete: ((SocialComment) -> Void)?
    var onLikeStatusChanged: ((String, Bool, Int) -> Void)?  // 按讚狀態變更回調

    @State private var isExpanded = false
    private let maxCollapsedReplies = 1  // 收起时显示的回复数量

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 显示的回复 (展开时显示全部，收起时只显示第一条)
            let visibleReplies = isExpanded ? replies : Array(replies.prefix(maxCollapsedReplies))

            ForEach(visibleReplies) { reply in
                HStack(alignment: .top, spacing: DesignTokens.spacing12) {
                    // 缩进线条 (IG 风格)
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: DesignTokens.avatarSmall)

                    // 回复内容
                    SocialCommentRow(
                        comment: reply,
                        canDelete: canDeleteComment(reply),
                        initialLikedStatus: commentLikeStatus[reply.id],
                        onAvatarTapped: onAvatarTapped,
                        onDelete: {
                            onDelete?(reply)
                        },
                        onLikeStatusChanged: onLikeStatusChanged
                    )
                }
            }

            // "查看更多回复" 按钮
            if replies.count > maxCollapsedReplies {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        // 缩进对齐
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: DesignTokens.avatarSmall)

                        // 展开/收起线条
                        Rectangle()
                            .fill(DesignTokens.textSecondary)
                            .frame(width: 20, height: 1)

                        Text(isExpanded ? "Hide replies" : "View \(replies.count - maxCollapsedReplies) more \(replies.count - maxCollapsedReplies == 1 ? "reply" : "replies")")
                            .font(Font.custom("SFProDisplay-Medium", size: DesignTokens.fontSmall))
                            .foregroundColor(DesignTokens.textSecondary)
                    }
                }
                .padding(.leading, DesignTokens.spacing12)
            }
        }
        .padding(.leading, DesignTokens.spacing12)
    }
}
