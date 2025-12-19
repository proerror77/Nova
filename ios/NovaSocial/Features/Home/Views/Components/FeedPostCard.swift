import SwiftUI

// MARK: - Feed Post Card (Dynamic Data)

struct FeedPostCard: View {
    let post: FeedPost
    @Binding var showReportView: Bool
    var onLike: () -> Void = {}
    var onComment: () -> Void = {}
    var onShare: () -> Void = {}
    var onBookmark: () -> Void = {}
    var onAvatarTapped: ((String) -> Void)?  // 点击头像回调，传入 authorId

    @State private var currentImageIndex = 0
    
    /// Check if URL points to a video file
    private func isVideoUrl(_ url: String) -> Bool {
        let lowercased = url.lowercased()
        return lowercased.contains(".mov") ||
               lowercased.contains(".mp4") ||
               lowercased.contains(".m4v") ||
               lowercased.contains(".webm")
    }

    var body: some View {
        VStack(spacing: 8) {
            // MARK: - User Info Header
            HStack {
                HStack(spacing: 10) {
                    // Avatar - 显示用户头像或默认头像（可点击跳转用户主页）
                    AvatarView(image: nil, url: post.authorAvatar, size: 30)
                        .onTapGesture {
                            onAvatarTapped?(post.authorId)
                        }

                    // User Info（用户名也可点击）
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(post.authorName)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color(red: 0.02, green: 0, blue: 0))
                                .onTapGesture {
                                    onAvatarTapped?(post.authorId)
                                }

                            // 认证标记 (可选)
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Color(red: 0.20, green: 0.60, blue: 1.0))
                        }

                        HStack(spacing: 9) {
                            Text(post.createdAt.timeAgoDisplay())
                                .font(.system(size: 10))
                                .lineSpacing(13)
                                .foregroundColor(Color(red: 0.32, green: 0.32, blue: 0.32))

                            Text("Location")
                                .font(.system(size: 10))
                                .lineSpacing(13)
                                .foregroundColor(Color(red: 0.32, green: 0.32, blue: 0.32))
                        }
                    }
                }

                Spacer()

                // Share Button
                Button(action: onShare) {
                    Image("card-share-icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                }
                .accessibilityLabel("Share")
            }
            .padding(.horizontal, 16)

            // MARK: - Post Media (Images & Videos)
            let _ = print("[DEBUG] Post \(post.id.prefix(8)) displayMediaUrls=\(post.displayMediaUrls), mediaUrls=\(post.mediaUrls), thumbnailUrls=\(post.thumbnailUrls)")
            if !post.displayMediaUrls.isEmpty {
                VStack(spacing: 8) {
                    TabView(selection: $currentImageIndex) {
                        ForEach(Array(post.displayMediaUrls.enumerated()), id: \.offset) { index, mediaUrl in
                            Group {
                                if isVideoUrl(mediaUrl) {
                                    // Video content - use FeedVideoPlayer (autoplay when visible)
                                    FeedVideoPlayer(
                                        url: URL(string: mediaUrl)!,
                                        autoPlay: true,
                                        isMuted: true
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
                                            .overlay(
                                                ProgressView()
                                                    .tint(.white)
                                            )
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 500)

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

            // MARK: - Post Content & Interaction
            VStack(alignment: .leading, spacing: 10) {
                // Post Content Text
                if !post.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(post.content)
                        .font(.system(size: 16, weight: .medium))
                        .lineSpacing(20)
                        .foregroundColor(.black)
                }

                // Interaction Buttons
                HStack(spacing: 20) {
                    // Like button
                    Button(action: onLike) {
                        HStack(spacing: 6) {
                            Image(post.isLiked ? "Like-on" : "Like-off")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: post.isLiked)
                            Text("\(post.likeCount)")
                                .font(.system(size: 10))
                                .lineSpacing(20)
                                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
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
                                .font(.system(size: 10))
                                .lineSpacing(20)
                                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
                        }
                    }
                    .accessibilityLabel("Comments, \(post.commentCount)")

                    // Bookmark/Star button
                    Button(action: onBookmark) {
                        HStack(spacing: 6) {
                            Image(post.isBookmarked ? "Save-on" : "Save-off")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: post.isBookmarked)
                            Text("\(post.shareCount)")
                                .font(.system(size: 10))
                                .lineSpacing(20)
                                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
                        }
                    }
                    .accessibilityLabel("Bookmark")

            Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .padding(.top, 14)
        .background(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Post by \(post.authorName)")
    }
}

// MARK: - Previews

#Preview("FeedPostCard - Default") {
    @Previewable @State var showReport = false

    ScrollView {
        VStack(spacing: 16) {
            FeedPostCard(
                post: FeedPost.preview,
                showReportView: $showReport
            )
            .padding(.horizontal, -DesignTokens.spacing16)
            .ignoresSafeArea(.container, edges: .horizontal)
        }
        .padding(.horizontal, 16)
    }
    .background(Color(red: 0.97, green: 0.97, blue: 0.97))
}

#Preview("FeedPostCard - Dark Mode") {
    @Previewable @State var showReport = false

    ScrollView {
        VStack(spacing: 16) {
            FeedPostCard(
                post: FeedPost.preview,
                showReportView: $showReport
            )
            .padding(.horizontal, -DesignTokens.spacing16)
            .ignoresSafeArea(.container, edges: .horizontal)
        }
        .padding(.horizontal, 16)
    }
    .background(Color(red: 0.97, green: 0.97, blue: 0.97))
    .preferredColorScheme(.dark)
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
