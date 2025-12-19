import SwiftUI

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
                // Show error state with tap to retry
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 24))
                                .foregroundColor(.gray)
                            Text("Tap to retry")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task {
                            loadPhase = .loading
                            await loadImage()
                        }
                    }
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
                // View task was cancelled (e.g., rapid re-render). Don't leave UI stuck in loading forever.
                loadPhase = .failed
                isLoading = false
            } else if let loadedImage = loadedImage {
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
            } else if loadFailed {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 20))
                            .foregroundColor(.gray)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        loadFailed = false
                        loadImage()
                    }
            } else {
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
            } else if loadFailed {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 24))
                                .foregroundColor(.gray)
                            Text("Tap to retry")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        loadFailed = false
                        startLoading()
                    }
            } else {
                placeholder()
                    .onAppear {
                        startLoading()
                    }
            }
        }
        .onDisappear {
            // Cancel loading if view scrolls out of view
            loadTask?.cancel()
        }
    }

    private func startLoading() {
        guard let url = url, image == nil else { 
            if url == nil {
                loadFailed = true
            }
            return 
        }
        
        loadTask = Task {
            let loadedImage = await ImageCacheService.shared.loadImage(
                from: url.absoluteString,
                targetSize: targetSize,
                priority: .high
            )
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                if let loadedImage = loadedImage {
                    withAnimation(.easeInOut(duration: 0.2)) {
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
struct ShimmerPlaceholder: View {
    @State private var phase: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.gray.opacity(0.2),
                            Color.gray.opacity(0.3),
                            Color.gray.opacity(0.2)
                        ]),
                        startPoint: .init(x: phase - 0.5, y: 0.5),
                        endPoint: .init(x: phase + 0.5, y: 0.5)
                    )
                )
                .onAppear {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        phase = 1.5
                    }
                }
        }
    }
}
