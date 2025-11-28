import SwiftUI

// MARK: - Feed Post Card (Dynamic Data)

struct FeedPostCard: View {
    let post: FeedPost
    @Binding var showReportView: Bool
    var onLike: () -> Void = {}
    var onComment: () -> Void = {}
    var onShare: () -> Void = {}
    var onBookmark: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - User Info Header
            HStack(spacing: DesignTokens.spacing10) {
                // Avatar
                Circle()
                    .fill(DesignTokens.avatarPlaceholder)
                    .frame(width: DesignTokens.avatarMedium, height: DesignTokens.avatarMedium)

                // User Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.authorName)
                        .font(.system(size: DesignTokens.fontMedium, weight: .semibold))
                        .foregroundColor(.black)

                    Text(post.createdAt.timeAgoDisplay())
                        .font(.system(size: DesignTokens.fontSmall))
                        .foregroundColor(DesignTokens.textTertiary)
                }

                Spacer()

                // Menu Button
                Button(action: { showReportView = true }) {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.black)
                        .font(.system(size: DesignTokens.fontMedium))
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More options")
            }
            .padding(.horizontal, DesignTokens.spacing12)
            .padding(.vertical, DesignTokens.spacing10)

            // MARK: - Post Images with Horizontal Swipe
            if !post.mediaUrls.isEmpty {
                TabView {
                    ForEach(post.mediaUrls, id: \.self) { imageUrl in
                        AsyncImage(url: URL(string: imageUrl)) { phase in
                            switch phase {
                            case .empty:
                                Rectangle()
                                    .fill(DesignTokens.loadingBackground)
                                    .overlay(
                                        ProgressView()
                                            .tint(DesignTokens.accentColor)
                                    )
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                Rectangle()
                                    .fill(DesignTokens.loadingBackground)
                                    .overlay(
                                        Image(systemName: "photo")
                                            .font(.system(size: DesignTokens.iconXL))
                                            .foregroundColor(DesignTokens.textMuted)
                                    )
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                        .clipped()
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: post.mediaUrls.count > 1 ? .automatic : .never))
                .frame(height: 280)
                .cornerRadius(DesignTokens.cardCornerRadius)
                .padding(.horizontal, DesignTokens.spacing12)
                .padding(.vertical, DesignTokens.spacing8)
            }

            // MARK: - Post Content
            HStack(spacing: DesignTokens.spacing4) {
                Text(post.content)
                    .font(.system(size: DesignTokens.fontBody))
                    .foregroundColor(.black)
                    .lineLimit(3)

                Spacer()
            }
            .padding(.horizontal, DesignTokens.spacing12)
            .padding(.vertical, DesignTokens.spacing8)

            // MARK: - Interaction Buttons
            HStack(spacing: DesignTokens.spacing16) {
                // Like button
                Button(action: onLike) {
                    HStack(spacing: DesignTokens.spacing6) {
                        Image(systemName: post.isLiked ? "arrowtriangle.up.fill" : "arrowtriangle.up")
                            .font(.system(size: DesignTokens.iconSmall))
                            .foregroundColor(post.isLiked ? DesignTokens.accentColor : .black)
                        Text("\(post.likeCount)")
                            .font(.system(size: DesignTokens.spacing12, weight: .bold))
                            .foregroundColor(post.isLiked ? DesignTokens.accentColor : .black)
                    }
                }
                .accessibilityLabel(post.isLiked ? "Unlike, \(post.likeCount) likes" : "Like, \(post.likeCount) likes")

                // Downvote placeholder (not implemented)
                HStack(spacing: DesignTokens.spacing6) {
                    Image(systemName: "arrowtriangle.down")
                        .font(.system(size: DesignTokens.iconSmall))
                        .foregroundColor(.black)
                    Text("0")
                        .font(.system(size: DesignTokens.spacing12, weight: .bold))
                        .foregroundColor(.black)
                }

                // Comment button
                Button(action: onComment) {
                    HStack(spacing: DesignTokens.spacing6) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: DesignTokens.iconSmall))
                            .foregroundColor(.black)
                        Text("\(post.commentCount)")
                            .font(.system(size: DesignTokens.spacing12, weight: .bold))
                            .foregroundColor(.black)
                    }
                }
                .accessibilityLabel("Comments, \(post.commentCount)")

                // Share button
                Button(action: onShare) {
                    HStack(spacing: DesignTokens.spacing6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: DesignTokens.iconSmall))
                            .foregroundColor(.black)
                        Text("\(post.shareCount)")
                            .font(.system(size: DesignTokens.spacing12, weight: .bold))
                            .foregroundColor(.black)
                    }
                }
                .accessibilityLabel("Share, \(post.shareCount) shares")

                Spacer()

                // Bookmark button
                Button(action: onBookmark) {
                    Image(systemName: post.isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: DesignTokens.spacing12))
                        .foregroundColor(post.isBookmarked ? DesignTokens.accentColor : .black)
                }
                .accessibilityLabel(post.isBookmarked ? "Remove bookmark" : "Bookmark")
            }
            .padding(.horizontal, DesignTokens.spacing12)
            .padding(.vertical, DesignTokens.spacing8)
        }
        .background(DesignTokens.cardBackground)
        .cornerRadius(DesignTokens.cardCornerRadius)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Post by \(post.authorName)")
    }
}
