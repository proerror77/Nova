import SwiftUI

/// Reusable post card for feed/profile grids
struct PostCard: View {
    let post: Post
    let onTap: () -> Void
    let onLike: () -> Void
    let onComment: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Header
            HStack(spacing: Theme.Spacing.xs) {
                Avatar(
                    imageURL: post.author.avatarURL,
                    initials: post.author.initials,
                    size: Theme.AvatarSize.sm
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.author.displayName)
                        .font(Theme.Typography.bodyBold)
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text(post.createdAt.timeAgo)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)

            // Image (使用高性能缓存)
            Button(action: onTap) {
                CachedAsyncImage(url: post.imageURL, size: .medium) { uiImage in
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .clipped()
                }
            }

            // Actions
            HStack(spacing: Theme.Spacing.md) {
                Button(action: onLike) {
                    HStack(spacing: 4) {
                        Image(systemName: post.isLiked ? "heart.fill" : "heart")
                            .foregroundColor(post.isLiked ? .red : Theme.Colors.textPrimary)
                        if post.likeCount > 0 {
                            Text("\(post.likeCount)")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }
                }

                Button(action: onComment) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.right")
                            .foregroundColor(Theme.Colors.textPrimary)
                        if post.commentCount > 0 {
                            Text("\(post.commentCount)")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.xs)

            // Caption
            if let caption = post.caption, !caption.isEmpty {
                Text(caption)
                    .font(Theme.Typography.bodySmall)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(2)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.sm)
            }
        }
        .background(Theme.Colors.surface)
        .cornerRadius(Theme.CornerRadius.md)
        .themeShadow(Theme.Shadows.small)
    }
}

// MARK: - Skeleton Loader
struct SkeletonView: View {
    @State private var isAnimating = false

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Theme.Colors.skeletonBase, Theme.Colors.skeletonHighlight, Theme.Colors.skeletonBase],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Preview
#Preview {
    PostCard(
        post: Post(
            id: "1",
            author: User(
                id: "1",
                username: "johndoe",
                displayName: "John Doe",
                avatarURL: nil,
                bio: "Photography enthusiast",
                followersCount: 1000,
                followingCount: 500,
                postsCount: 42
            ),
            imageURL: URL(string: "https://picsum.photos/400"),
            caption: "Beautiful sunset 🌅",
            likeCount: 42,
            commentCount: 5,
            isLiked: false,
            createdAt: Date()
        ),
        onTap: {},
        onLike: {},
        onComment: {}
    )
    .padding()
}
