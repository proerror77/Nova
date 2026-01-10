import SwiftUI

// MARK: - Feed Post Card (Dynamic Data)
// iOS 17+ 优化：使用 Symbol Effects 和更好的状态管理
// 手勢支援：滑動、長按、縮放

struct FeedPostCard: View {
    let post: FeedPost
    @Binding var showReportView: Bool
    var onLike: () -> Void = {}
    var onComment: () -> Void = {}
    var onShare: () -> Void = {}
    var onBookmark: () -> Void = {}
    var onDelete: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var currentPage: Int = 0
    @State private var isVisible = false

    // iOS 17+ Symbol Effect 动画状态
    @State private var likeAnimationTrigger = false
    @State private var bookmarkAnimationTrigger = false

    // MARK: - Gesture States
    /// 長按選單
    @State private var showingLongPressMenu = false
    /// 縮放預覽的圖片 URL
    @State private var zoomingImageUrl: String? = nil
    /// 雙擊點讚動畫 (Instagram 風格愛心動畫)
    @State private var showDoubleTapHeart = false
    @State private var doubleTapHeartPosition: CGPoint = .zero
    /// 文本展开/收起状态
    @State private var isTextExpanded = false
    /// 觸覺回饋生成器
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let hapticLight = UIImpactFeedbackGenerator(style: .light)

    // Target size for feed images (optimized for display)
    private let imageTargetSize = CGSize(width: 750, height: 1000)

    var body: some View {
        // MARK: - Main Content (Instagram Style - No Swipe Gestures)
        mainContent
        // MARK: - Long Press Menu
        .confirmationDialog("Post Options", isPresented: $showingLongPressMenu, titleVisibility: .visible) {
            Button("Share", action: onShare)
            Button("Bookmark") {
                bookmarkAnimationTrigger.toggle()
                onBookmark()
            }
            Button("Copy Link") {
                UIPasteboard.general.string = "https://nova.social/post/\(post.id)"
                hapticLight.impactOccurred()
            }
            Button("Report", role: .destructive) {
                showReportView = true
            }
            if onDelete != nil {
                Button("Delete", role: .destructive) {
                    onDelete?()
                }
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    // MARK: - Main Content View
    private var mainContent: some View {
        VStack(spacing: 0) {
            // MARK: - User Info Header
            HStack(spacing: 8.w) {
                // Avatar - 显示用户头像或默认头像
                AvatarView(
                    image: nil,
                    url: post.authorAvatar,
                    size: 30,
                    name: post.authorName,
                    accountType: post.authorAccountType
                )

                // User Info
                VStack(alignment: .leading, spacing: 1.h) {
                    HStack(spacing: 3.w) {
                        Text(post.authorName)
                            .font(Font.custom("SFProDisplay-Semibold", size: 14.f))
                            .tracking(0.28)
                            .foregroundColor(DesignTokens.textPrimary)

                        // TODO: 认证标记 - 用户通过认证后显示
                        // if post.isVerified {
                        //     Image("Blue-v")
                        //         .resizable()
                        //         .scaledToFit()
                        //         .frame(width: 12.s, height: 12.s)
                        // }
                    }

                    HStack(spacing: 5.w) {
                        Text(post.createdAt.timeAgoDisplay())
                            .font(Font.custom("SFProDisplay-Regular", size: 10.f))
                            .foregroundColor(DesignTokens.textSecondary)

                        if let location = post.location {
                            Text(location)
                                .font(Font.custom("SFProDisplay-Regular", size: 10.f))
                                .foregroundColor(DesignTokens.textSecondary)
                        }
                    }
                }

                Spacer()

                // TODO: 分享按钮 - 后续添加认证功能后启用
                // Button(action: onShare) {
                //     Image("Share-black")
                //         .resizable()
                //         .scaledToFit()
                //         .frame(width: 24.s, height: 24.s)
                // }
                // .accessibilityLabel("Share")
            }
            .padding(EdgeInsets(top: 10.h, leading: 10.w, bottom: 10.h, trailing: 10.w))

            // MARK: - Post Media (Images/Video/Live Photo) - Instagram Style
            if !post.displayMediaUrls.isEmpty {
                mediaContent
            }

            // MARK: - Post Content & Interaction
            VStack(alignment: .leading, spacing: 10.h) {
                // Post Content Text with expandable "more/less"
                if !post.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ExpandableTextView(
                        text: post.content,
                        isExpanded: $isTextExpanded,
                        lineLimit: 1
                    )
                }

                // Channel Tags
                if let formattedTags = post.formattedTags {
                    Text(formattedTags)
                        .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                        .tracking(0.28)
                        .foregroundColor(Color(red: 0.91, green: 0.20, blue: 0.34))
                }

                // Interaction Buttons
                HStack(spacing: 8.w) {
                    // Left side: Like, Comment, Collect buttons
                    HStack(spacing: 12.w) {
                        // Like button
                        Button {
                            likeAnimationTrigger.toggle()
                            onLike()
                        } label: {
                            HStack(spacing: 4.w) {
                                Image(post.isLiked ? "card-heart-icon-filled" : "card-heart-icon")
                                    .resizable()
                                    .renderingMode(post.isLiked ? .original : .template)
                                    .foregroundColor(post.isLiked ? nil : DesignTokens.textPrimary)
                                    .scaledToFit()
                                    .frame(width: 22.s, height: 22.s)
                                Text(post.likeCount.abbreviated)
                                    .font(Font.custom("SFProDisplay-Semibold", size: 12.f))
                                    .tracking(0.24)
                                    .foregroundColor(DesignTokens.textPrimary)
                                    .contentTransition(.numericText())
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Like, \(post.likeCount) likes")

                        // Comment button
                        Button(action: onComment) {
                            HStack(spacing: 4.w) {
                                Image("card-comment-icon")
                                    .resizable()
                                    .renderingMode(.template)
                                    .foregroundColor(DesignTokens.textPrimary)
                                    .scaledToFit()
                                    .frame(width: 24.s, height: 24.s)
                                Text(post.commentCount.abbreviated)
                                    .font(Font.custom("SFProDisplay-Semibold", size: 12.f))
                                    .tracking(0.24)
                                    .foregroundColor(DesignTokens.textPrimary)
                                    .contentTransition(.numericText())
                            }
                        }
                        .accessibilityLabel("Comments, \(post.commentCount)")

                        // Collect/Star button
                        Button {
                            bookmarkAnimationTrigger.toggle()
                            onBookmark()
                        } label: {
                            HStack(spacing: 4.w) {
                                Image(post.isBookmarked ? "collect-fill" : "collect")
                                    .resizable()
                                    .renderingMode(post.isBookmarked ? .original : .template)
                                    .foregroundColor(post.isBookmarked ? nil : DesignTokens.textPrimary)
                                    .scaledToFit()
                                    .frame(width: 22.s, height: 22.s)
                                Text(post.bookmarkCount.abbreviated)
                                    .font(Font.custom("SFProDisplay-Semibold", size: 12.f))
                                    .tracking(0.24)
                                    .foregroundColor(DesignTokens.textPrimary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Collect, \(post.bookmarkCount)")
                    }

                    Spacer()

                    // Right side: Share button
                    Button(action: onShare) {
                        Image("Share-black")
                            .resizable()
                            .renderingMode(.template)
                            .foregroundColor(DesignTokens.textPrimary)
                            .scaledToFit()
                            .frame(width: 24.s, height: 24.s)
                    }
                    .accessibilityLabel("Share")
                }
            }
            .padding(EdgeInsets(top: 10.h, leading: 14.w, bottom: 26.h, trailing: 14.w))
        }
        .frame(width: 375.w)
        .background(DesignTokens.surface)
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


    // MARK: - Media Content View (Instagram Style - Native Scroll)

    @ViewBuilder
    private var mediaContent: some View {
        ZStack {
            VStack(spacing: 10.h) {
                switch post.mediaType {
                case .video:
                    // Video post - show video player
                    videoContent

                case .livePhoto:
                    // Live Photo - show with indicator
                    livePhotoContent

                case .image, .mixed, .none:
                    // Image carousel (default) - Native SwiftUI scroll, no gesture interference
                    imageCarousel
                }

                // Page indicator for multiple media items
                if mediaItemCount > 1 {
                    pageIndicator
                }
            }

            // Instagram style double-tap heart animation
            if showDoubleTapHeart {
                Image(systemName: "heart.fill")
                    .font(.system(size: 80.f))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 10)
                    .scaleEffect(showDoubleTapHeart ? 1.0 : 0.5)
                    .opacity(showDoubleTapHeart ? 1.0 : 0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showDoubleTapHeart)
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
                height: 500.h
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
                .frame(width: 375.w, height: 500.h)
                .clipped()

                // Live Photo badge
                HStack(spacing: 4.w) {
                    Image(systemName: "livephoto")
                        .font(.system(size: 12.f))
                    Text("LIVE")
                        .font(Font.custom("SFProDisplay-Semibold", size: 10.f))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8.w)
                .padding(.vertical, 4.h)
                .background(Color.black.opacity(0.6))
                .cornerRadius(4)
                .padding(12.s)
            }
        }
    }

    // MARK: - Image Carousel (TabView for smooth paging)
    // 🚀 使用 TabView 替代 ScrollView 解決手勢衝突問題
    // TabView 的 page style 專門為分頁設計，手勢處理更流暢
    @ViewBuilder
    private var imageCarousel: some View {
        TabView(selection: $currentPage) {
            ForEach(Array(post.displayMediaUrls.enumerated()), id: \.offset) { index, imageUrl in
                mediaItemView(for: imageUrl, at: index)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(width: 375.w, height: 500.h)
        .clipped()
        .onChange(of: currentPage) { _, newPage in
            // Prefetch adjacent images when page changes
            prefetchAdjacentImages(around: newPage)
        }
        .onAppear {
            // Prefetch first page's adjacent images
            prefetchAdjacentImages(around: 0)
        }
    }
    
    /// Current visible image index
    private var currentImageIndex: Int {
        currentPage
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

    // MARK: - Single Media Item View (Instagram Style)
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
                height: 500.h
            )
            // Instagram style: double-tap to like on video
            .onTapGesture(count: 2) {
                triggerDoubleTapLike()
            }
        } else {
            // Image - Instagram style: double-tap to like
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
            .contentShape(Rectangle())
            // Instagram style: double-tap to like
            .onTapGesture(count: 2) {
                triggerDoubleTapLike()
            }
            // Single tap to view full screen (optional, like Instagram)
            .onTapGesture(count: 1) {
                // Single tap does nothing for now (Instagram behavior)
                // Can be used to pause/play video or show/hide UI
            }
            // Long press for menu
            .onLongPressGesture(minimumDuration: 0.5) {
                hapticFeedback.impactOccurred()
                showingLongPressMenu = true
            }
        }
    }

    // MARK: - Instagram Style Double-Tap Like
    /// 觸發 Instagram 風格的雙擊點讚動畫
    private func triggerDoubleTapLike() {
        hapticFeedback.impactOccurred()

        // 顯示愛心動畫
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            showDoubleTapHeart = true
        }

        // 如果還沒點讚，執行點讚
        if !post.isLiked {
            likeAnimationTrigger.toggle()
            onLike()
        }

        // 延遲隱藏愛心
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 0.2)) {
                showDoubleTapHeart = false
            }
        }
    }

    // MARK: - Page Indicator

    private var pageIndicator: some View {
        HStack(spacing: 4.w) {
            ForEach(0..<mediaItemCount, id: \.self) { index in
                Circle()
                    .fill(index == currentImageIndex ?
                          Color(red: 0.87, green: 0.11, blue: 0.26) :
                          Color(red: 0.90, green: 0.90, blue: 0.90))
                    .frame(width: 6.s, height: 6.s)
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
        }
        .padding(.horizontal, 16)
    }
    .background(Color(red: 0.24, green: 0.24, blue: 0.24))
}

// MARK: - Preview Data
extension FeedPost {
    static var preview: FeedPost {
        FeedPost(
            id: "preview-1",
            authorId: "user-123",
            authorName: "yuumeiart",
            authorAvatar: "https://picsum.photos/100/100",
            content: "I will come again next time to visit and experience the beautiful scenery that this place has to offer. The mountains were breathtaking and the local food was amazing!",
            mediaUrls: [
                "https://picsum.photos/400/533",
                "https://picsum.photos/401/534",
                "https://picsum.photos/402/535",
                "https://picsum.photos/403/536",
                "https://picsum.photos/404/537"
            ],
            createdAt: Date().addingTimeInterval(-5400), // 1d30m ago
            likeCount: 8049,
            commentCount: 54,
            shareCount: 1232,
            bookmarkCount: 227,
            isLiked: false,
            isBookmarked: false,
            location: "English",
            tags: ["Fashion", "Sport", "Art", "Beautiful", "Draw", "Visual Storytelling", "Experimental Design", "Youth Culture", "City Culture"]
        )
    }

    static var previewTextOnly: FeedPost {
        FeedPost(
            id: "preview-2",
            authorId: "user-456",
            authorName: "Jane Smith",
            authorAvatar: nil,
            content: "Just finished reading an amazing book! It really changed my perspective on life and inspired me to pursue my dreams.",
            mediaUrls: [],
            createdAt: Date().addingTimeInterval(-7200),
            likeCount: 56,
            commentCount: 8,
            shareCount: 3,
            bookmarkCount: 12,
            isLiked: false,
            isBookmarked: true,
            tags: ["Books", "Inspiration", "Life"]
        )
    }
}

// MARK: - Expandable Text View
/// 可展开/收起的文本视图，文本超过指定行数时显示 "more"，展开后显示 "less"
struct ExpandableTextView: View {
    let text: String
    @Binding var isExpanded: Bool
    let lineLimit: Int
    
    @State private var isTruncated: Bool = false
    
    var body: some View {
        if isExpanded {
            // 展开状态：显示完整文本 + " less"
            VStack(alignment: .leading, spacing: 0) {
                Text(text)
                    .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                    .tracking(0.28)
                    .foregroundColor(DesignTokens.textPrimary)
                + Text(" less")
                    .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                    .tracking(0.28)
                    .foregroundColor(DesignTokens.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = false
                }
            }
        } else {
            // 收起状态
            HStack(alignment: .bottom, spacing: 0) {
                // 文本区域
                Text(text)
                    .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                    .tracking(0.28)
                    .foregroundColor(DesignTokens.textPrimary)
                    .lineLimit(lineLimit)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                
                // more 按钮（仅在截断时显示）
                if isTruncated {
                    Text(" more")
                        .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                        .tracking(0.28)
                        .foregroundColor(DesignTokens.textSecondary)
                        .fixedSize()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded = true
                            }
                        }
                }
            }
            .background(
                // 使用 ViewThatFits 方式检测截断（更可靠）
                Text(text)
                    .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                    .tracking(0.28)
                    .lineLimit(lineLimit)
                    .hidden()
                    .background(
                        GeometryReader { limitedGeo in
                            Text(text)
                                .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                                .tracking(0.28)
                                .fixedSize(horizontal: false, vertical: true)
                                .hidden()
                                .background(
                                    GeometryReader { fullGeo in
                                        Color.clear
                                            .onAppear {
                                                // 延迟检测，确保布局完成
                                                DispatchQueue.main.async {
                                                    isTruncated = fullGeo.size.height > limitedGeo.size.height + 1
                                                }
                                            }
                                    }
                                )
                        }
                    )
            )
            .onAppear {
                // 备用检测：基于字符数的简单判断
                // 假设每行约 40 个字符（根据字体和宽度）
                let estimatedCharsPerLine = 45
                let estimatedLines = text.count / estimatedCharsPerLine
                if estimatedLines >= lineLimit && text.count > estimatedCharsPerLine * lineLimit {
                    // 延迟设置，让 GeometryReader 有机会先执行
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if !isTruncated {
                            isTruncated = true
                        }
                    }
                }
            }
        }
    }
}

// Preference Keys for size measurement
private struct IntrinsicSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

// MARK: - String Identifiable Extension (for fullScreenCover)
extension String: @retroactive Identifiable {
    public var id: String { self }
}

// MARK: - Zoomable Image View (Pinch to Zoom)
/// 全螢幕可縮放圖片檢視器
struct ZoomableImageView: View {
    let imageUrl: String
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景
                Color.black.ignoresSafeArea()

                // 可縮放圖片
                FeedCachedImage(
                    url: URL(string: imageUrl),
                    targetSize: CGSize(width: 1500, height: 2000)
                ) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    ProgressView()
                        .tint(.white)
                }
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    // 縮放手勢
                    MagnifyGesture()
                        .onChanged { value in
                            let delta = value.magnification / lastScale
                            lastScale = value.magnification
                            scale = min(max(scale * delta, minScale), maxScale)
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                            // 如果縮放小於 1，重置
                            if scale < minScale {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    scale = minScale
                                    offset = .zero
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    // 拖曳手勢 (縮放時移動)
                    DragGesture()
                        .onChanged { value in
                            if scale > 1 {
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                        }
                        .onEnded { _ in
                            lastOffset = offset
                            // 如果縮放回到 1，重置位置
                            if scale <= 1 {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    offset = .zero
                                    lastOffset = .zero
                                }
                            }
                        }
                )
                .onTapGesture(count: 2) {
                    // 雙擊切換縮放
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if scale > 1 {
                            scale = 1
                            offset = .zero
                            lastOffset = .zero
                        } else {
                            scale = 2.5
                        }
                    }
                }

                // 關閉按鈕
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            onDismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 30.f))
                                .foregroundStyle(.white.opacity(0.8), .black.opacity(0.3))
                        }
                        .padding()
                    }
                    Spacer()
                }
            }
        }
        .gesture(
            // 下滑關閉
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    if value.translation.height > 100 && scale <= 1 {
                        onDismiss()
                    }
                }
        )
    }
}
