import SwiftUI

// MARK: - Video URL Detection Helper

private func isVideoURL(_ url: URL?) -> Bool {
    guard let url = url else { return false }
    let lowercased = url.absoluteString.lowercased()
    return lowercased.contains(".mp4") ||
           lowercased.contains(".m4v") ||
           lowercased.contains(".mov") ||
           lowercased.contains(".webm") ||
           lowercased.contains(".avi")
}

/// A replacement for AsyncImage that uses our ImageCacheService with progressive loading
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let targetSize: CGSize?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    let enableProgressiveLoading: Bool
    let priority: ImageLoadPriority

    @State private var image: UIImage?
    @State private var thumbnailImage: UIImage?
    @State private var isLoading = true
    @State private var loadPhase: LoadPhase = .loading

    enum LoadPhase {
        case loading
        case thumbnail
        case loaded
        case failed
    }

    init(
        url: URL?,
        targetSize: CGSize? = nil,
        enableProgressiveLoading: Bool = true,
        priority: ImageLoadPriority = .normal,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.targetSize = targetSize
        self.enableProgressiveLoading = enableProgressiveLoading
        self.priority = priority
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image = image {
                content(Image(uiImage: image))
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            } else if let thumbnail = thumbnailImage, enableProgressiveLoading {
                content(Image(uiImage: thumbnail))
                    .blur(radius: 2)
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            } else if loadPhase == .failed {
                // For failed loads, show placeholder gracefully (no error UI)
                // This is especially important for avatars where we want to show
                // the default avatar view instead of an error state
                placeholder()
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url = url else {
            loadPhase = .failed
            isLoading = false
            return
        }

        // Skip loading if URL is a video - videos should use FeedVideoPlayer instead
        if isVideoURL(url) {
            #if DEBUG
            print("[CachedAsyncImage] ⚠️ Skipping video URL: \(url.absoluteString.suffix(50))")
            #endif
            loadPhase = .failed
            isLoading = false
            return
        }

        isLoading = true
        loadPhase = .loading

        if enableProgressiveLoading {
            // Try to load thumbnail first for quick preview
            let thumbnailTask = Task.detached(priority: .utility) {
                await ImageCacheService.shared.loadThumbnail(from: url.absoluteString)
            }
            if let thumbnail = await thumbnailTask.value, !Task.isCancelled {
                await MainActor.run {
                    thumbnailImage = thumbnail
                    loadPhase = .thumbnail
                }
            }
        }

        // Load full image
        let imageTask = Task.detached(priority: priority == .high ? .userInitiated : .utility) {
            await ImageCacheService.shared.loadImage(
                from: url.absoluteString,
                targetSize: targetSize,
                priority: priority
            )
        }
        let loadedImage = await imageTask.value
        
        await MainActor.run {
            if Task.isCancelled {
                // View task was cancelled (e.g., rapid re-render). Keep placeholder/thumbnail rather than showing an error.
                isLoading = false
                return
            }

            if let loadedImage = loadedImage {
                image = loadedImage
                loadPhase = .loaded
            } else {
                loadPhase = .failed
            }
            isLoading = false
        }
    }
}

// MARK: - High Performance Variant

/// Optimized image view for list cells with automatic prefetch support
struct OptimizedCachedImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let targetSize: CGSize?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    
    @State private var image: UIImage?
    @State private var hasAppeared = false
    @State private var loadFailed = false

    init(
        url: URL?,
        targetSize: CGSize? = nil,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.targetSize = targetSize
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image = image {
                content(Image(uiImage: image))
            } else {
                // Show placeholder for both loading and failed states
                // This provides a consistent, graceful fallback for avatars
                placeholder()
            }
        }
        .onAppear {
            if !hasAppeared {
                hasAppeared = true
                loadImage()
            }
        }
        .onDisappear {
            // Cancel loading if view disappears before completion
            // The task will be cancelled when the view is deallocated
        }
    }

    private func loadImage() {
        guard let url = url else {
            loadFailed = true
            return
        }

        // Skip loading if URL is a video
        if isVideoURL(url) {
            loadFailed = true
            return
        }

        Task {
            let loadedImage = await ImageCacheService.shared.loadImage(
                from: url.absoluteString,
                targetSize: targetSize,
                priority: .high
            )

            await MainActor.run {
                if let loadedImage = loadedImage {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        image = loadedImage
                    }
                } else {
                    loadFailed = true
                }
            }
        }
    }
}

// MARK: - Feed Image with Prefetch

/// Image view designed for feed cells with built-in prefetch coordination
struct FeedCachedImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let targetSize: CGSize?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    
    @State private var image: UIImage?
    @State private var loadTask: Task<Void, Never>?
    @State private var loadFailed = false
    @State private var isVisible = true
    @State private var cancelDebounceTask: Task<Void, Never>?

    init(
        url: URL?,
        targetSize: CGSize? = nil,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.targetSize = targetSize
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image = image {
                content(Image(uiImage: image))
            } else {
                // Show placeholder for both loading and failed states
                // Provides graceful fallback without error UI
                placeholder()
                    .onAppear {
                        if !loadFailed {
                            startLoading()
                        }
                    }
            }
        }
        .onAppear {
            isVisible = true
            // 🚀 取消延遲取消任務
            cancelDebounceTask?.cancel()
            cancelDebounceTask = nil
            // 如果之前載入失敗，重試
            if image == nil && loadTask == nil && !loadFailed {
                startLoading()
            }
        }
        .onDisappear {
            isVisible = false
            // 🚀 性能優化：延遲取消載入，避免快速滾動時反覆取消重試
            // 給 200ms 緩衝時間，如果用戶快速滾動回來，不需要重新載入
            cancelDebounceTask?.cancel()
            cancelDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                guard !Task.isCancelled else { return }
                // 只有圖片還沒載入完成時才取消
                if image == nil {
                    loadTask?.cancel()
                    loadTask = nil
                }
            }
        }
    }

    private func startLoading() {
        guard let url = url, image == nil, loadTask == nil else {
            if url == nil {
                loadFailed = true
            }
            return
        }

        // Skip loading if URL is a video
        if isVideoURL(url) {
            loadFailed = true
            return
        }

        loadTask = Task {
            let loadedImage = await ImageCacheService.shared.loadImage(
                from: url.absoluteString,
                targetSize: targetSize,
                priority: .high
            )

            await MainActor.run {
                // 無論是否被取消，都要清理 loadTask，否則下次無法重新載入
                defer { loadTask = nil }

                guard !Task.isCancelled else { return }

                if let loadedImage = loadedImage {
                    // 🚀 只有視圖可見時才播放動畫，否則直接設置避免 GPU 開銷
                    if isVisible {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            image = loadedImage
                        }
                    } else {
                        image = loadedImage
                    }
                } else {
                    loadFailed = true
                }
            }
        }
    }
}

// MARK: - Shimmer Loading Placeholder

/// Animated shimmer placeholder for loading states
/// 性能優化：移除 GeometryReader，使用固定漸變動畫減少 GPU 負載
struct ShimmerPlaceholder: View {
    @State private var isAnimating = false

    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .overlay(
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.clear,
                                Color.white.opacity(0.4),
                                Color.clear
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: isAnimating ? 400 : -400)
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}
