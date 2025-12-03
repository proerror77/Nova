import SwiftUI

struct PostCell: View {
    let post: Post
    var onLike: () -> Void
    var onTap: () -> Void

    @State private var isLikeAnimating = false
    @State private var localLikeCount: Int
    @State private var localIsLiked: Bool

    init(post: Post, onLike: @escaping () -> Void, onTap: @escaping () -> Void) {
        self.post = post
        self.onLike = onLike
        self.onTap = onTap
        self._localLikeCount = State(initialValue: post.likeCount)
        self._localIsLiked = State(initialValue: post.isLiked)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            PostHeaderView(user: post.user ?? placeholderUser)
                .padding(.horizontal)
                .padding(.vertical, 12)

            // Image - 使用优化的懒加载
            Button {
                onTap()
            } label: {
                PostImageView(
                    imageUrl: post.imageUrl,
                    thumbnailUrl: post.thumbnailUrl
                )
            }
            .voiceOverSupport(
                label: "帖子图片",
                hint: "双击查看帖子详情",
                traits: .isImage
            )

            // Action Buttons
            HStack(spacing: 16) {
                // Like Button - 乐观更新动画
                AccessibleButton(
                    localIsLiked ? "已点赞" : "点赞",
                    hint: localIsLiked ? "双击取消点赞" : "双击点赞这条帖子"
                ) {
                    handleLikeAction()
                } buttonLabel: {
                    ZStack {
                        // 心形图标
                        Image(systemName: localIsLiked ? "heart.fill" : "heart")
                            .font(.title3)
                            .foregroundColor(localIsLiked ? .red : .primary)
                            .scaleEffect(isLikeAnimating ? 1.3 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: localIsLiked)

                        // 点赞爆炸效果（粒子动画）
                        if isLikeAnimating && localIsLiked {
                            ForEach(0..<8) { index in
                                Circle()
                                    .fill(Color.red.opacity(0.8))
                                    .frame(width: 4, height: 4)
                                    .offset(
                                        x: cos(Double(index) * .pi / 4) * (isLikeAnimating ? 20 : 0),
                                        y: sin(Double(index) * .pi / 4) * (isLikeAnimating ? 20 : 0)
                                    )
                                    .opacity(isLikeAnimating ? 0 : 1)
                                    .animation(
                                        .easeOut(duration: 0.4),
                                        value: isLikeAnimating
                                    )
                            }
                        }
                    }
                }

                // Comment Button
                AccessibleButton(
                    "评论",
                    hint: "双击查看和添加评论"
                ) {
                    onTap()
                } buttonLabel: {
                    Image(systemName: "bubble.right")
                        .font(.title3)
                }

                // Share Button
                AccessibleButton(
                    "分享",
                    hint: "双击分享这条帖子"
                ) {
                    // TODO: Share functionality
                } buttonLabel: {
                    Image(systemName: "paperplane")
                        .font(.title3)
                }

                Spacer()

                // Bookmark Button
                AccessibleButton(
                    "收藏",
                    hint: "双击收藏这条帖子"
                ) {
                    // TODO: Bookmark functionality
                } buttonLabel: {
                    Image(systemName: "bookmark")
                        .font(.title3)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)

            // Like Count - 动画过渡
            if localLikeCount > 0 {
                Text("\(localLikeCount) likes")
                    .accessibleBody()
                    .fontWeight(.semibold)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                    .voiceOverSupport(
                        label: "\(localLikeCount) 个赞",
                        traits: .staticText
                    )
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .opacity
                    ))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: localLikeCount)
            }

            // Caption
            if let caption = post.caption, !caption.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Text(post.user?.username ?? "unknown")
                        .fontWeight(.semibold)

                    Text(caption)
                }
                .accessibleBody()
                .padding(.horizontal)
                .padding(.bottom, 4)
                .voiceOverSupport(
                    label: "\(post.user?.username ?? "unknown") 说: \(caption)",
                    traits: .staticText
                )
            }

            // Comment Count
            if post.commentCount > 0 {
                Button {
                    onTap()
                } label: {
                    Text("View all \(post.commentCount) comments")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            }

            // Timestamp
            Text(post.createdAt.timeAgoDisplay)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 12)
        }
        .onChange(of: post.likeCount) { _, newValue in
            localLikeCount = newValue
        }
        .onChange(of: post.isLiked) { _, newValue in
            localIsLiked = newValue
        }
    }

    // MARK: - Private Methods

    private func handleLikeAction() {
        // 触发动画
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            isLikeAnimating = true
        }

        // 乐观更新本地状态
        let wasLiked = localIsLiked
        localIsLiked.toggle()
        localLikeCount += wasLiked ? -1 : 1

        // 执行点赞操作（会调用 ViewModel）
        onLike()

        // 重置动画状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isLikeAnimating = false
        }

        // 触觉反馈
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }

    private var placeholderUser: User {
        User(
            id: UUID(),
            username: "unknown",
            email: "",
            displayName: nil,
            bio: nil,
            avatarUrl: nil,
            isVerified: false,
            createdAt: Date()
        )
    }
}

struct PostHeaderView: View {
    let user: User

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            AsyncImageView(url: user.avatarUrl)
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .voiceOverSupport(
                    label: "\(user.username) 的头像",
                    hint: "双击查看用户资料",
                    traits: .isImage
                )

            // Username
            HStack(spacing: 4) {
                Text(user.username)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if user.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            Spacer()

            // More Button
            Button {
                // TODO: Show action sheet
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundColor(.primary)
            }
        }
    }
}

// MARK: - Date Extension

extension Date {
    var timeAgoDisplay: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

#Preview {
    let samplePost = Post(
        id: UUID(),
        userId: UUID(),
        imageUrl: "https://picsum.photos/400/400",
        thumbnailUrl: nil,
        caption: "This is a sample post caption",
        likeCount: 42,
        commentCount: 5,
        isLiked: false,
        createdAt: Date().addingTimeInterval(-3600),
        user: User(
            id: UUID(),
            username: "johndoe",
            email: "john@example.com",
            displayName: "John Doe",
            bio: nil,
            avatarUrl: "https://picsum.photos/200/200",
            isVerified: true,
            createdAt: Date()
        )
    )

    PostCell(post: samplePost, onLike: {}, onTap: {})
}
