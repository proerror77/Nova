import SwiftUI

// MARK: - Comment Sheet View

struct CommentSheetView: View {
    let post: FeedPost
    @Binding var isPresented: Bool
    var onAvatarTapped: ((String) -> Void)?  // 点击头像回调
    @State private var commentText = ""
    @State private var comments: [SocialComment] = []
    @State private var isLoading = false
    @State private var isSubmitting = false
    @State private var error: String?
    @State private var totalCount = 0

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
                                    onAvatarTapped: { userId in
                                        // 关闭评论弹窗，触发头像点击回调
                                        isPresented = false
                                        onAvatarTapped?(userId)
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
        }
    }

    private func loadComments() async {
        isLoading = true
        error = nil

        do {
            let result = try await socialService.getComments(postId: post.id, limit: 50, offset: 0)
            comments = result.comments
            totalCount = result.totalCount
        } catch let apiError as APIError {
            switch apiError {
            case .unauthorized:
                error = "Please login to view comments"
            case .notFound:
                // No comments yet - not an error
                comments = []
                totalCount = 0
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
        } catch {
            // Show error briefly
            self.error = "Failed to post comment"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.error = nil
            }
        }

        isSubmitting = false
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
    var onAvatarTapped: ((String) -> Void)?  // 点击头像回调

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.spacing12) {
            // Avatar (点击跳转用户主页)
            Circle()
                .fill(DesignTokens.avatarPlaceholder)
                .frame(width: DesignTokens.avatarSmall, height: DesignTokens.avatarSmall)
                .onTapGesture {
                    onAvatarTapped?(comment.userId)
                }

            VStack(alignment: .leading, spacing: DesignTokens.spacing4) {
                HStack {
                    // 用户名 (点击跳转用户主页)
                    Text("User \(comment.userId.prefix(8))")
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
    }
}
