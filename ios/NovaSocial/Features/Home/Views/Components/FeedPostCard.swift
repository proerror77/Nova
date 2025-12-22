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

    @State private var scrollPosition = ScrollPosition(idType: Int.self)
    @State private var isVisible = false

    // iOS 17+ Symbol Effect 动画状态
    @State private var likeAnimationTrigger = false
    @State private var bookmarkAnimationTrigger = false

    // MARK: - Gesture States
    /// 滑動偏移量
    @State private var swipeOffset: CGFloat = 0
    /// 是否顯示操作選單
    @State private var showingActions = false
    /// 長按選單
    @State private var showingLongPressMenu = false
    /// 圖片縮放比例
    @State private var imageScale: CGFloat = 1.0
    /// 縮放時的錨點
    @State private var imageAnchor: UnitPoint = .center
    /// 是否正在縮放
    @State private var isZooming = false
    /// 縮放預覽的圖片 URL
    @State private var zoomingImageUrl: String? = nil
    /// 是否在進行水平滑動 (圖片輪播)
    @State private var isHorizontalScrolling = false
    /// 圖片輪播的初始滑動位置
    @State private var carouselDragStart: CGFloat = 0
    /// 觸覺回饋生成器
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let hapticLight = UIImpactFeedbackGenerator(style: .light)

    // Target size for feed images (optimized for display)
    private let imageTargetSize = CGSize(width: 750, height: 1000)

    // 滑動閾值
    private let swipeThreshold: CGFloat = 80
    private let maxSwipeOffset: CGFloat = 120

    var body: some View {
        ZStack {
            // MARK: - Swipe Action Background
            swipeActionBackground

            // MARK: - Main Content with Swipe Gesture
            mainContent
                .offset(x: swipeOffset)
                .gesture(swipeGesture)
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: swipeOffset)
        }
        .clipped()
        // MARK: - Long Press Menu
        .confirmationDialog("貼文選項", isPresented: $showingLongPressMenu, titleVisibility: .visible) {
            Button("分享", action: onShare)
            Button("收藏") {
                bookmarkAnimationTrigger.toggle()
                onBookmark()
            }
            Button("複製連結") {
                UIPasteboard.general.string = "https://nova.social/post/\(post.id)"
                hapticLight.impactOccurred()
            }
            Button("舉報", role: .destructive) {
                showReportView = true
            }
            if onDelete != nil {
                Button("刪除", role: .destructive) {
                    onDelete?()
                }
            }
            Button("取消", role: .cancel) { }
        }
        // MARK: - Fullscreen Image Zoom Overlay
        .fullScreenCover(item: $zoomingImageUrl) { imageUrl in
            ZoomableImageView(
                imageUrl: imageUrl,
                onDismiss: { zoomingImageUrl = nil }
            )
        }
    }

    // MARK: - Main Content View
    private var mainContent: some View {
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

            // MARK: - Post Media (Images/Video/Live Photo) with Long Press & Pinch
            if !post.displayMediaUrls.isEmpty {
                mediaContent
                    .gesture(longPressGesture)
            }

            // MARK: - Post Content & Interaction
            VStack(alignment: .leading, spacing: 10) {
                // Post Content Text
                if !post.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(post.content)
                        .font(Typography.semibold16)
                        .lineSpacing(20)
                        .foregroundColor(.black)
                        .gesture(longPressGesture)
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
                            Text("\(post.bookmarkCount)")
                                .font(Typography.regular10)
                                .lineSpacing(20)
                                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
                        }
                    }
                    .accessibilityLabel("Bookmark, \(post.bookmarkCount)")

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

    // MARK: - Swipe Action Background View
    private var swipeActionBackground: some View {
        HStack(spacing: 0) {
            // 右滑顯示：快速點讚 (綠色背景)
            if swipeOffset > 0 {
                HStack {
                    Image(systemName: post.isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.leading, 24)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(post.isLiked ? Color.gray : Color.red.opacity(0.9))
            }

            Spacer()

            // 左滑顯示：舉報/更多選項 (紅色背景)
            if swipeOffset < 0 {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Button {
                            resetSwipe()
                            showReportView = true
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "flag.fill")
                                    .font(.system(size: 20))
                                Text("舉報")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.white)
                        }

                        if onDelete != nil {
                            Button {
                                resetSwipe()
                                onDelete?()
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 20))
                                    Text("刪除")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(.white)
                            }
                        }
                    }
                    .padding(.trailing, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.red.opacity(0.9))
            }
        }
    }

    // MARK: - Swipe Gesture
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onChanged { value in
                // 只處理水平滑動
                guard abs(value.translation.width) > abs(value.translation.height) else { return }

                let translation = value.translation.width

                // 限制最大滑動距離
                if translation > 0 {
                    swipeOffset = min(translation, maxSwipeOffset)
                } else {
                    swipeOffset = max(translation, -maxSwipeOffset)
                }

                // 達到閾值時觸發觸覺回饋
                if abs(swipeOffset) >= swipeThreshold && !showingActions {
                    hapticLight.impactOccurred()
                    showingActions = true
                } else if abs(swipeOffset) < swipeThreshold {
                    showingActions = false
                }
            }
            .onEnded { value in
                let translation = value.translation.width

                if translation > swipeThreshold {
                    // 右滑完成 - 點讚
                    hapticFeedback.impactOccurred()
                    likeAnimationTrigger.toggle()
                    onLike()
                    resetSwipe()
                } else if translation < -swipeThreshold {
                    // 左滑完成 - 保持顯示操作按鈕
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        swipeOffset = -maxSwipeOffset
                    }
                } else {
                    // 未達閾值 - 重置
                    resetSwipe()
                }
            }
    }

    // MARK: - Long Press Gesture
    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .onEnded { _ in
                hapticFeedback.impactOccurred()
                showingLongPressMenu = true
            }
    }

    /// 重置滑動狀態
    private func resetSwipe() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            swipeOffset = 0
            showingActions = false
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
        // 快速反應的方向檢測：在拖曳開始時立即判斷方向
        // 使用簡單的DragGesture（不使用highPriorityGesture）
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .local)
                .onChanged { value in
                    let horizontalDistance = abs(value.translation.width)
                    let verticalDistance = abs(value.translation.height)
                    
                    // 快速判斷：竪直優先
                    if verticalDistance > horizontalDistance {
                        isHorizontalScrolling = false
                    }
                    // 明確的水平滑動
                    else if horizontalDistance > verticalDistance * 1.3 && horizontalDistance > 15 {
                        isHorizontalScrolling = true
                    }
                }
        )
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
    // 性能優化：移除 GeometryReader，使用 containerRelativeFrame 替代
    // 手勢優化：禁用圖片輪播ScrollView，只有明確水平滑動時才啟用
    // 這樣Feed的ScrollView永遠獲得最高優先級，滾動最流暢
    @ViewBuilder
    private var imageCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(post.displayMediaUrls.enumerated()), id: \.offset) { index, imageUrl in
                    mediaItemView(for: imageUrl, at: index)
                        .containerRelativeFrame(.horizontal)
                        .frame(height: 500)
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
        .frame(height: 500)
        // 關鍵優化：禁用ScrollView滾動，除非明確檢測到水平滑動
        // 這樣Feed的ScrollView永遠不會被干擾，獲得絕對優先級
        .scrollDisabled(!isHorizontalScrolling)
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
            // Image - use cached image loading with tap to zoom
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
            // 輕量級方向檢測：快速判斷是否是水平滑動
            // 這個手勢不會阻止任何東西，只是用來檢測方向
            .gesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .local)
                    .onChanged { value in
                        let horizontalDistance = abs(value.translation.width)
                        let verticalDistance = abs(value.translation.height)
                        
                        // 快速檢測方向：如果水平 > 竪直 1.3 倍 && > 20pt，啟用圖片輪播
                        if horizontalDistance > verticalDistance * 1.3 && horizontalDistance > 20 {
                            isHorizontalScrolling = true
                        }
                        // 竪直滑動優先，禁用圖片輪播
                        else if verticalDistance > horizontalDistance && verticalDistance > 8 {
                            isHorizontalScrolling = false
                        }
                    }
                    .onEnded { _ in
                        // 重置狀態（延遲100ms以確保ScrollView已接管）
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isHorizontalScrolling = false
                            carouselDragStart = 0
                        }
                    }
            )
            .onTapGesture(count: 2) {
                // 雙擊放大圖片
                hapticLight.impactOccurred()
                zoomingImageUrl = urlString
            }
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
                                .font(.system(size: 30))
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
