import SwiftUI

// MARK: - Feed Post Card (Dynamic Data)
// iOS 17+ 优化：使用 Symbol Effects 和更好的状态管理

struct FeedPostCard: View {
    let post: FeedPost
    @Binding var showReportView: Bool
    var onLike: () -> Void = {}
    var onComment: () -> Void = {}
    var onShare: () -> Void = {}
    var onBookmark: () -> Void = {}

    @State private var scrollPosition = ScrollPosition(idType: Int.self)
    @State private var isVisible = false
    
    // iOS 17+ Symbol Effect 动画状态
    @State private var likeAnimationTrigger = false
    @State private var bookmarkAnimationTrigger = false

    // Target size for feed images (optimized for display)
    private let imageTargetSize = CGSize(width: 750, height: 1000)

    var body: some View {
        VStack(spacing: 8) {
            // MARK: - User Info Header
            HStack {
                HStack(spacing: 10) {
                    // Avatar - 显示用户头像或默认头像
                    AvatarView(image: nil, url: post.authorAvatar, size: 30)

                    // User Info
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(post.authorName)
                                .font(Typography.semibold14)
                                .foregroundColor(Color(red: 0.02, green: 0, blue: 0))

                            // 认证标记 (可选)
                            Image(systemName: "checkmark.seal.fill")
                                .font(Typography.regular10)
                                .foregroundColor(Color(red: 0.20, green: 0.60, blue: 1.0))
                        }

                        HStack(spacing: 9) {
                            Text(post.createdAt.timeAgoDisplay())
                                .font(Typography.regular10)
                                .lineSpacing(13)
                                .foregroundColor(Color(red: 0.32, green: 0.32, blue: 0.32))

                            Text("Location")
                                .font(Typography.regular10)
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
                        .frame(width: 24, height: 24)
                }
                .accessibilityLabel("Share")
            }
            .padding(.horizontal, 16)

            // MARK: - Post Media (Images/Video/Live Photo)
            if !post.displayMediaUrls.isEmpty {
                mediaContent
            }

            // MARK: - Post Content & Interaction
            VStack(alignment: .leading, spacing: 10) {
                // Post Content Text
                if !post.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(post.content)
                        .font(Typography.semibold16)
                        .lineSpacing(20)
                        .foregroundColor(.black)
                }

                // Interaction Buttons with iOS 17+ Symbol Effects
                HStack(spacing: 20) {
                    // Like button - 使用 SF Symbol 和 bounce 动画
                    Button {
                        likeAnimationTrigger.toggle()
                        onLike()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: post.isLiked ? "heart.fill" : "heart")
                                .font(.system(size: 18))
                                .foregroundColor(post.isLiked ? .red : Color(red: 0.38, green: 0.37, blue: 0.37))
                                .symbolEffect(.bounce, value: likeAnimationTrigger)
                            Text("\(post.likeCount)")
                                .font(Typography.regular10)
                                .lineSpacing(20)
                                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
                                .contentTransition(.numericText())
                        }
                    }
                    .accessibilityLabel("Like, \(post.likeCount) likes")

                    // Comment button
                    Button(action: onComment) {
                        HStack(spacing: 6) {
                            Image(systemName: "bubble.right")
                                .font(.system(size: 18))
                                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
                            Text("\(post.commentCount)")
                                .font(Typography.regular10)
                                .lineSpacing(20)
                                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
                                .contentTransition(.numericText())
                        }
                    }
                    .accessibilityLabel("Comments, \(post.commentCount)")

                    // Bookmark/Star button - 使用 SF Symbol 和 bounce 动画
                    Button {
                        bookmarkAnimationTrigger.toggle()
                        onBookmark()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: post.isBookmarked ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 18))
                                .foregroundColor(post.isBookmarked ? .orange : Color(red: 0.38, green: 0.37, blue: 0.37))
                                .symbolEffect(.bounce, value: bookmarkAnimationTrigger)
                            Text("\(post.shareCount)")
                                .font(Typography.regular10)
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
        .onAppear {
            isVisible = true
        }
        .onDisappear {
            isVisible = false
            // Clean up off-screen resources
            cleanupOffScreenResources()
        }
    }

    // MARK: - Media Content View

    @ViewBuilder
    private var mediaContent: some View {
        VStack(spacing: 8) {
            switch post.mediaType {
            case .video:
                // Video post - show video player
                videoContent

            case .livePhoto:
                // Live Photo - show with indicator
                livePhotoContent

            case .image, .mixed, .none:
                // Image carousel (default)
                imageCarousel
            }

            // Page indicator for multiple media items
            if mediaItemCount > 1 {
                pageIndicator
            }
        }
    }

    // MARK: - Video Content

    @ViewBuilder
    private var videoContent: some View {
        if let videoUrl = post.mediaUrls.first,
           let url = URL(string: videoUrl) {
            // Get thumbnail URL (second URL or from thumbnailUrls)
            let thumbnailUrl: URL? = {
                if let thumb = post.thumbnailUrls.first {
                    return URL(string: thumb)
                } else if post.mediaUrls.count > 1 {
                    return URL(string: post.mediaUrls[1])
                }
                return nil
            }()

            FeedVideoPlayer(
                url: url,
                thumbnailUrl: thumbnailUrl,
                autoPlay: true,
                isMuted: true,
                height: 500
            )
        }
    }

    // MARK: - Live Photo Content

    @ViewBuilder
    private var livePhotoContent: some View {
        // For Live Photo, show the still image with a Live Photo badge
        // The first URL is the still image
        if let imageUrl = post.displayMediaUrls.first {
            ZStack(alignment: .topLeading) {
                FeedCachedImage(
                    url: URL(string: imageUrl),
                    targetSize: imageTargetSize
                ) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Rectangle()
                        .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                        .overlay(
                            ProgressView()
                                .tint(.white)
                        )
                }
                .frame(maxWidth: .infinity)
                .frame(height: 500)
                .clipped()

                // Live Photo badge
                HStack(spacing: 4) {
                    Image(systemName: "livephoto")
                        .font(.system(size: 12, weight: .medium))
                    Text("LIVE")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.6))
                .cornerRadius(4)
                .padding(12)
            }
        }
    }

    // MARK: - Image Carousel

    @ViewBuilder
    private var imageCarousel: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(post.displayMediaUrls.enumerated()), id: \.offset) { index, imageUrl in
                        mediaItemView(for: imageUrl, at: index)
                            .frame(width: geometry.size.width, height: 500)
                            .clipped()
                            .id(index)
                            .onAppear {
                                prefetchAdjacentImages(around: index)
                            }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition($scrollPosition)
            .scrollClipDisabled(false)
        }
        .frame(height: 500)
    }
    
    /// Current visible image index based on scroll position
    private var currentImageIndex: Int {
        scrollPosition.viewID(type: Int.self) ?? 0
    }

    /// Prefetch images adjacent to the given index
    private func prefetchAdjacentImages(around index: Int) {
        // Prefetch next image if exists
        if index + 1 < post.displayMediaUrls.count {
            let nextUrl = post.displayMediaUrls[index + 1]
            if !isVideoUrl(nextUrl) {
                Task.detached(priority: .low) { [imageTargetSize] in
                    _ = await ImageCacheService.shared.loadImage(
                        from: nextUrl,
                        targetSize: imageTargetSize,
                        priority: .low
                    )
                }
            }
        }

        // Prefetch previous image if exists
        if index > 0 {
            let prevUrl = post.displayMediaUrls[index - 1]
            if !isVideoUrl(prevUrl) {
                Task.detached(priority: .low) { [imageTargetSize] in
                    _ = await ImageCacheService.shared.loadImage(
                        from: prevUrl,
                        targetSize: imageTargetSize,
                        priority: .low
                    )
                }
            }
        }
    }

    // MARK: - Single Media Item View

    @ViewBuilder
    private func mediaItemView(for urlString: String, at index: Int) -> some View {
        // Check if this URL is a video (for mixed content posts)
        if isVideoUrl(urlString), let url = URL(string: urlString) {
            // Get thumbnail for this video
            let thumbnailUrl: URL? = {
                // For mixed content, thumbnail might be the next URL
                if index + 1 < post.mediaUrls.count {
                    let nextUrl = post.mediaUrls[index + 1]
                    if !isVideoUrl(nextUrl) {
                        return URL(string: nextUrl)
                    }
                }
                // Or from thumbnailUrls
                if index < post.thumbnailUrls.count {
                    return URL(string: post.thumbnailUrls[index])
                }
                return nil
            }()

            FeedVideoPlayer(
                url: url,
                thumbnailUrl: thumbnailUrl,
                autoPlay: true,
                isMuted: true,
                height: 500
            )
        } else {
            // Image - use cached image loading
            FeedCachedImage(
                url: URL(string: urlString),
                targetSize: imageTargetSize
            ) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Rectangle()
                    .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                    .overlay(
                        ProgressView()
                            .tint(.white)
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
    }

    // MARK: - Page Indicator

    private var pageIndicator: some View {
        HStack(spacing: 11) {
            ForEach(0..<mediaItemCount, id: \.self) { index in
                Circle()
                    .fill(index == currentImageIndex ?
                          Color(red: 0.81, green: 0.13, blue: 0.25) :
                          Color(red: 0.85, green: 0.85, blue: 0.85))
                    .frame(width: 6, height: 6)
            }
        }
    }

    // MARK: - Helper Properties

    /// Number of media items to display (excluding thumbnail URLs for videos)
    private var mediaItemCount: Int {
        switch post.mediaType {
        case .video, .livePhoto:
            return 1 // Video and Live Photo show as single item
        default:
            return post.displayMediaUrls.count
        }
    }

    /// Check if a URL points to a video file
    private func isVideoUrl(_ urlString: String) -> Bool {
        let lowercased = urlString.lowercased()
        return lowercased.contains(".mp4") ||
               lowercased.contains(".m4v") ||
               lowercased.contains(".mov") ||
               lowercased.contains(".webm")
    }

    // MARK: - Resource Cleanup

    /// Clean up resources when card goes off-screen to reduce memory usage
    private func cleanupOffScreenResources() {
        // Cancel any ongoing image prefetch operations for this post
        // The ImageCacheService maintains its own cache, so images will be quickly
        // reloaded if user scrolls back to this post
        Task.detached(priority: .utility) { [displayUrls = post.displayMediaUrls] in
            // Evict off-screen images from memory cache (but keep on disk)
            await ImageCacheService.shared.evictFromMemory(urls: displayUrls)
        }
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
