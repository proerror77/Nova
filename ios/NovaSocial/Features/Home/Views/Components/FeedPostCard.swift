import SwiftUI

// MARK: - Feed Post Card (Dynamic Data)

struct FeedPostCard: View {
    let post: FeedPost
    @Binding var showReportView: Bool
    var onLike: () -> Void = {}
    var onComment: () -> Void = {}
    var onShare: () -> Void = {}
    var onBookmark: () -> Void = {}

    @State private var currentImageIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: - User Info Header
            HStack {
                HStack(spacing: 10) {
                    // Avatar - 显示用户头像或默认头像
                    AvatarView(image: nil, url: post.authorAvatar, size: 32)

                    // User Info
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(post.authorName)
                                .font(Font.custom("Helvetica Neue", size: 14).weight(.medium))
                                .foregroundColor(DesignTokens.textPrimary)

                            // 认证标记 (可选)
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Color(red: 0.20, green: 0.60, blue: 1.0))
                        }

                        HStack(spacing: 9) {
                            Text(post.createdAt.timeAgoDisplay())
                                .font(Font.custom("Helvetica Neue", size: 10))
                                .lineSpacing(13)
                                .foregroundColor(DesignTokens.textTertiary)

                            Text("Location")
                                .font(Font.custom("Helvetica Neue", size: 10))
                                .lineSpacing(13)
                                .foregroundColor(DesignTokens.textTertiary)
                        }
                    }
                }

                Spacer()

                // Share Button
                Button(action: onShare) {
                    Image("card-share-icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                }
                .accessibilityLabel("Share")
            }
            .padding(.horizontal, 17)
            .padding(.top, 14)

            // MARK: - Post Images (3:4 比例)
            if !post.displayMediaUrls.isEmpty {
                VStack(spacing: 7) {
                    TabView(selection: $currentImageIndex) {
                        ForEach(Array(post.displayMediaUrls.enumerated()), id: \.offset) { index, imageUrl in
                            AsyncImage(url: URL(string: imageUrl)) { phase in
                                switch phase {
                                case .empty:
                                    Rectangle()
                                        .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                                        .overlay(
                                            ProgressView()
                                                .tint(.white)
                                        )
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                case .failure:
                                    Rectangle()
                                        .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                                        .overlay(
                                            Image(systemName: "photo")
                                                .font(.system(size: 30))
                                                .foregroundColor(.white.opacity(0.5))
                                        )
                                @unknown default:
                                    EmptyView()
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .aspectRatio(3/4, contentMode: .fill)
                            .clipped()
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: UIScreen.main.bounds.width * 4 / 3 - 68) // 3:4 比例
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .padding(.horizontal, 17)

                    // 自定义页面指示器
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
                    }
                }
            }

            // MARK: - Interaction Buttons
            HStack(spacing: 20) {
                // Like button
                Button(action: onLike) {
                    HStack(spacing: 6) {
                        Image("card-heart-icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        Text("\(post.likeCount)")
                            .font(Font.custom("Helvetica Neue", size: 10))
                            .lineSpacing(20)
                            .foregroundColor(DesignTokens.textSecondary)
                    }
                }
                .accessibilityLabel("Like, \(post.likeCount) likes")

                // Comment button
                Button(action: onComment) {
                    HStack(spacing: 6) {
                        Image("card-comment-icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        Text("\(post.commentCount)")
                            .font(Font.custom("Helvetica Neue", size: 10))
                            .lineSpacing(20)
                            .foregroundColor(DesignTokens.textSecondary)
                    }
                }
                .accessibilityLabel("Comments, \(post.commentCount)")

                // Bookmark/Star button
                Button(action: onBookmark) {
                    HStack(spacing: 6) {
                        Image("card-star-icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        Text("\(post.shareCount)")
                            .font(Font.custom("Helvetica Neue", size: 10))
                            .lineSpacing(20)
                            .foregroundColor(DesignTokens.textSecondary)
                    }
                }
                .accessibilityLabel("Bookmark")

                Spacer()
            }
            .padding(.horizontal, 17)
            .padding(.bottom, 14)
        }
        .background(DesignTokens.surface)
        .cornerRadius(5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Post by \(post.authorName)")
    }
}

// MARK: - Preview
#Preview {
    @Previewable @State var showReport = false

    ScrollView {
        VStack(spacing: 16) {
            // 带图片的帖子
            FeedPostCard(
                post: FeedPost.preview,
                showReportView: $showReport
            )

            // 纯文字帖子
            FeedPostCard(
                post: FeedPost.previewTextOnly,
                showReportView: $showReport
            )
        }
        .padding(.horizontal, 16)
    }
    .background(Color(red: 0.97, green: 0.97, blue: 0.97))
}

// MARK: - Preview Data
extension FeedPost {
    static var preview: FeedPost {
        FeedPost(
            id: "preview-1",
            authorId: "user-123",
            authorName: "Simone Carter",
            authorAvatar: "https://picsum.photos/100/100",
            content: "This is a sample post with images.",
            mediaUrls: [
                "https://picsum.photos/400/533",
                "https://picsum.photos/401/534",
                "https://picsum.photos/402/535",
                "https://picsum.photos/403/536",
                "https://picsum.photos/404/537"
            ],
            createdAt: Date().addingTimeInterval(-5400), // 1d30m ago
            likeCount: 2234,
            commentCount: 1232,
            shareCount: 1232,
            isLiked: false,
            isBookmarked: false
        )
    }

    static var previewTextOnly: FeedPost {
        FeedPost(
            id: "preview-2",
            authorId: "user-456",
            authorName: "Jane Smith",
            authorAvatar: nil,
            content: "Just finished reading an amazing book!",
            mediaUrls: [],
            createdAt: Date().addingTimeInterval(-7200),
            likeCount: 56,
            commentCount: 8,
            shareCount: 3,
            isLiked: false,
            isBookmarked: true
        )
    }
}
