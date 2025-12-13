import SwiftUI
import AVKit

// MARK: - Feed Post Card (Dynamic Data)

struct FeedPostCard: View {
    let post: FeedPost
    @Binding var showReportView: Bool
    var onLike: () -> Void = {}
    var onComment: () -> Void = {}
    var onShare: () -> Void = {}
    var onBookmark: () -> Void = {}
    var onCardTap: () -> Void = {}

    @State private var currentImageIndex = 0
    @State private var isVideoVisible: Bool = true

    var body: some View {
        VStack(spacing: 8) {
            // MARK: - User Info Header - tappable for card detail
            HStack {
                HStack(spacing: 10) {
                    // Avatar - 显示用户头像或默认头像
                    AvatarView(image: nil, url: post.authorAvatar, size: 30)

                    // User Info
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(post.authorName)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color(red: 0.02, green: 0, blue: 0))

                            // 认证标记 (可选)
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Color(red: 0.20, green: 0.60, blue: 1.0))
                        }

                        // Time ago display (location removed - backend doesn't support it yet)
                        Text(post.createdAt.timeAgoDisplay())
                            .font(.system(size: 10))
                            .lineSpacing(13)
                            .foregroundColor(Color(red: 0.32, green: 0.32, blue: 0.32))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { onCardTap() }

                Spacer()

                // Share Button
                Image("card-share-icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        #if DEBUG
                        print("[FeedPostCard] Share tapped for post: \(post.id)")
                        #endif
                        onShare()
                    }
                    .accessibilityLabel("Share")
            }
            .padding(.horizontal, 16)

            // MARK: - Post Media (Images or Video) - tappable for card detail
            if !post.displayMediaUrls.isEmpty {
                mediaContent
                    .contentShape(Rectangle())
                    .onTapGesture { onCardTap() }
            }

            // MARK: - Post Content Text - tappable for card detail
            if !post.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(post.content)
                    .font(.system(size: 16, weight: .medium))
                    .lineSpacing(20)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                    .onTapGesture { onCardTap() }
            }

            // MARK: - Interaction Buttons - NO parent tap gesture here
            HStack(spacing: 0) {
                // Like button
                HStack(spacing: 6) {
                    Image(systemName: post.isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 18))
                    Text("\(post.likeCount)")
                        .font(.system(size: 10))
                }
                .foregroundColor(post.isLiked ? Color(red: 0.81, green: 0.13, blue: 0.25) : Color(red: 0.38, green: 0.37, blue: 0.37))
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
                .background(Color.white.opacity(0.001)) // Invisible but tappable
                .onTapGesture {
                    #if DEBUG
                    print("[FeedPostCard] Like tapped for post: \(post.id)")
                    #endif
                    onLike()
                }

                // Comment button
                HStack(spacing: 6) {
                    Image(systemName: "bubble.right")
                        .font(.system(size: 18))
                    Text("\(post.commentCount)")
                        .font(.system(size: 10))
                }
                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
                .background(Color.white.opacity(0.001)) // Invisible but tappable
                .onTapGesture {
                    #if DEBUG
                    print("[FeedPostCard] Comment tapped for post: \(post.id)")
                    #endif
                    onComment()
                }

                // Bookmark button (no count - like Instagram, bookmarks are private)
                Image(systemName: post.isBookmarked ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 18))
                    .foregroundColor(post.isBookmarked ? Color(red: 0.81, green: 0.13, blue: 0.25) : Color(red: 0.38, green: 0.37, blue: 0.37))
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
                    .background(Color.white.opacity(0.001)) // Invisible but tappable
                    .onTapGesture {
                        #if DEBUG
                        print("[FeedPostCard] Bookmark tapped for post: \(post.id)")
                        #endif
                        onBookmark()
                    }

                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 14)
        }
        .padding(.top, 14)
        .background(Color.white)
        // NO card-level tap gesture - each area has its own
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Post by \(post.authorName)")
    }
    
    // MARK: - Media Content View
    
    @ViewBuilder
    private var mediaContent: some View {
        switch post.mediaType {
        case .video:
            // Single video post - show video player
            if let videoUrl = post.firstVideoUrl {
                FeedVideoPlayer(
                    url: videoUrl,
                    thumbnailUrl: post.videoThumbnailUrl,
                    autoPlay: true,
                    isMuted: true,
                    height: 500,
                    isVisible: isVideoVisible
                )
                .trackVisibility(id: "\(post.id)_video", threshold: 0.5) { visible in
                    isVideoVisible = visible
                }
            }
            
        case .livePhoto:
            // Live Photo - show with press-to-play interaction
            livePhotoContent
            
        case .mixed:
            // Mixed content - show carousel with video support
            mixedMediaCarousel
            
        case .image:
            // Image only - show image carousel
            imageCarousel
        }
    }
    
    // MARK: - Live Photo Content
    
    @ViewBuilder
    private var livePhotoContent: some View {
        // Live Photo has 2 URLs: image first, video second
        if post.mediaUrls.count >= 2 {
            FeedLivePhotoPlayer(
                imageUrl: post.mediaUrls[0],
                videoUrl: post.mediaUrls[1],
                height: 500
            )
        } else if let firstUrl = post.mediaUrls.first {
            // Fallback to just showing the image if video URL is missing
            AsyncImage(url: URL(string: firstUrl)) { phase in
                switch phase {
                case .success(let image):
                    ZStack {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(height: 500)
                            .clipped()
                        
                        // Live Photo badge
                        VStack {
                            HStack {
                                LivePhotoBadge()
                                Spacer()
                            }
                            Spacer()
                        }
                        .padding(12)
                    }
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 500)
                        .overlay(ProgressView().tint(.white))
                case .failure:
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 500)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 30))
                                .foregroundColor(.white.opacity(0.5))
                        )
                @unknown default:
                    EmptyView()
                }
            }
        }
    }
    
    // MARK: - Image Carousel
    
    private var imageCarousel: some View {
        VStack(spacing: 8) {
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 500)

            // Custom page indicator
            pageIndicator
        }
    }
    
    // MARK: - Mixed Media Carousel (Images + Videos)

    @ViewBuilder
    private var mixedMediaCarousel: some View {
        VStack(spacing: 8) {
            TabView(selection: $currentImageIndex) {
                ForEach(Array(post.mediaUrls.enumerated()), id: \.offset) { index, mediaUrl in
                    mixedMediaItem(index: index, mediaUrl: mediaUrl)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 500)

            // Custom page indicator with video dots
            mixedMediaPageIndicator
        }
    }

    @ViewBuilder
    private func mixedMediaItem(index: Int, mediaUrl: String) -> some View {
        let isVideo = FeedMediaType.from(url: mediaUrl) == .video

        if isVideo, let url = URL(string: mediaUrl) {
            // Video item
            let thumbnailUrl: URL? = post.thumbnailUrls.indices.contains(index)
                ? URL(string: post.thumbnailUrls[index])
                : nil

            FeedVideoPlayer(
                url: url,
                thumbnailUrl: thumbnailUrl,
                autoPlay: currentImageIndex == index,
                isMuted: true,
                height: 500,
                isVisible: isVideoVisible
            )
            .trackVisibility(id: "\(post.id)_video_\(index)", threshold: 0.5) { visible in
                isVideoVisible = visible
            }
            .tag(index)
        } else {
            // Image item
            let displayUrl: String = post.thumbnailUrls.indices.contains(index)
                ? post.thumbnailUrls[index]
                : mediaUrl

            AsyncImage(url: URL(string: displayUrl)) { phase in
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .tag(index)
        }
    }
    
    // MARK: - Page Indicators
    
    @ViewBuilder
    private var pageIndicator: some View {
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
    
    @ViewBuilder
    private var mixedMediaPageIndicator: some View {
        if post.mediaUrls.count > 1 {
            HStack(spacing: 11) {
                ForEach(0..<post.mediaUrls.count, id: \.self) { index in
                    let isVideo = FeedMediaType.from(url: post.mediaUrls[index]) == .video
                    
                    if isVideo {
                        // Video indicator (small play icon)
                        ZStack {
                            Circle()
                                .fill(index == currentImageIndex ?
                                      Color(red: 0.81, green: 0.13, blue: 0.25) :
                                      Color(red: 0.85, green: 0.85, blue: 0.85))
                                .frame(width: 8, height: 8)
                            
                            Image(systemName: "play.fill")
                                .font(.system(size: 4))
                                .foregroundColor(index == currentImageIndex ? .white : .gray)
                        }
                    } else {
                        // Image indicator (simple dot)
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
}

// MARK: - Preview
#Preview("Image Post") {
    @Previewable @State var showReport = false

    ScrollView {
        VStack(spacing: 16) {
            FeedPostCard(
                post: FeedPost.preview,
                showReportView: $showReport
            )
        }
        .padding(.horizontal, 16)
    }
    .background(Color(red: 0.97, green: 0.97, blue: 0.97))
}

#Preview("Video Post") {
    @Previewable @State var showReport = false

    ScrollView {
        VStack(spacing: 16) {
            // Video post (short video like IG, max 60 seconds)
            FeedPostCard(
                post: FeedPost.previewVideo,
                showReportView: $showReport
            )
        }
        .padding(.horizontal, 16)
    }
    .background(Color(red: 0.97, green: 0.97, blue: 0.97))
}

#Preview("Mixed Media Post") {
    @Previewable @State var showReport = false

    ScrollView {
        VStack(spacing: 16) {
            // Mixed content (images + video)
            FeedPostCard(
                post: FeedPost.previewMixed,
                showReportView: $showReport
            )
        }
        .padding(.horizontal, 16)
    }
    .background(Color(red: 0.97, green: 0.97, blue: 0.97))
}

#Preview("Text Only Post") {
    @Previewable @State var showReport = false

    ScrollView {
        VStack(spacing: 16) {
            FeedPostCard(
                post: FeedPost.previewTextOnly,
                showReportView: $showReport
            )
        }
        .padding(.horizontal, 16)
    }
    .background(Color(red: 0.97, green: 0.97, blue: 0.97))
}

#Preview("Live Photo Post") {
    @Previewable @State var showReport = false

    ScrollView {
        VStack(spacing: 16) {
            // Live Photo post - press and hold to play
            FeedPostCard(
                post: FeedPost.previewLivePhoto,
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
            mediaType: .image,
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
            mediaType: .image,
            createdAt: Date().addingTimeInterval(-7200),
            likeCount: 56,
            commentCount: 8,
            shareCount: 3,
            isLiked: false,
            isBookmarked: true
        )
    }
    
    /// Preview with video content (short video like IG Reels, max 60 seconds)
    static var previewVideo: FeedPost {
        FeedPost(
            id: "preview-3",
            authorId: "user-789",
            authorName: "Video Creator",
            authorAvatar: "https://picsum.photos/100/101",
            content: "Check out this amazing sunset! 🌅",
            mediaUrls: [
                // Sample short video (< 60 seconds)
                "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4"
            ],
            mediaType: .video,
            createdAt: Date().addingTimeInterval(-3600),
            likeCount: 5678,
            commentCount: 432,
            shareCount: 789,
            isLiked: true,
            isBookmarked: false
        )
    }
    
    /// Preview with mixed content (images + video)
    static var previewMixed: FeedPost {
        FeedPost(
            id: "preview-4",
            authorId: "user-101",
            authorName: "Mixed Media",
            authorAvatar: "https://picsum.photos/100/102",
            content: "Some photos and a video from my trip!",
            mediaUrls: [
                "https://picsum.photos/400/533",
                "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4",
                "https://picsum.photos/401/534"
            ],
            mediaType: .mixed,
            createdAt: Date().addingTimeInterval(-1800),
            likeCount: 1234,
            commentCount: 567,
            shareCount: 234,
            isLiked: false,
            isBookmarked: true
        )
    }
    
    /// Preview with Live Photo content
    static var previewLivePhoto: FeedPost {
        FeedPost(
            id: "preview-5",
            authorId: "user-202",
            authorName: "Live Photo Fan",
            authorAvatar: "https://picsum.photos/100/103",
            content: "Check out this Live Photo! Press and hold to play ✨",
            mediaUrls: [
                // First URL is the still image
                "https://picsum.photos/400/533",
                // Second URL is the short video (~3 seconds)
                "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4"
            ],
            mediaType: .livePhoto,
            createdAt: Date().addingTimeInterval(-900),
            likeCount: 3456,
            commentCount: 234,
            shareCount: 567,
            isLiked: false,
            isBookmarked: false
        )
    }
}
