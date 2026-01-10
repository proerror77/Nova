import SwiftUI
import PhotosUI

// MARK: - Example 1: Feed 中显示 Live Photo（使用原生 PHLivePhotoView）

/// 在 Feed 中显示帖子的示例
/// 当帖子类型是 Live Photo 时，使用原生的 PHLivePhotoView
struct FeedPostCardWithLivePhotoExample: View {
    let post: Post

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 用户信息...

            // 媒体内容
            if post.mediaType == "live_photo" {
                displayLivePhoto()
            } else if post.mediaType == "image" {
                displayImages()
            } else if post.mediaType == "video" {
                displayVideo()
            }

            // 交互按钮...
        }
    }

    @ViewBuilder
    private func displayLivePhoto() -> some View {
        if let imageUrl = post.mediaUrls?.first,
           let videoUrl = post.mediaUrls?.dropFirst().first {

            // ✨ 使用原生 Live Photo 播放器
            FeedNativeLivePhotoPlayer(
                imageUrl: imageUrl,
                videoUrl: videoUrl,
                height: 400
            ) {
                // 点击后进入详情页
                print("Navigate to post detail")
            }
        }
    }

    @ViewBuilder
    private func displayImages() -> some View {
        // 普通图片显示...
        EmptyView()
    }

    @ViewBuilder
    private func displayVideo() -> some View {
        // 视频显示...
        EmptyView()
    }
}

// MARK: - Example 2: 帖子详情页全屏 Live Photo

/// 帖子详情页，支持全屏查看 Live Photo
struct PostDetailWithLivePhotoExample: View {
    let post: Post

    @StateObject private var loader = LivePhotoLoader()
    @State private var showFullscreen = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 用户信息头部...

                // Live Photo 内容
                if post.mediaType == "live_photo",
                   let imageUrl = post.mediaUrls?.first,
                   let videoUrl = post.mediaUrls?.dropFirst().first {

                    if let livePhoto = loader.livePhoto {
                        // 显示 Live Photo
                        NativeLivePhotoCard(
                            livePhoto: livePhoto,
                            size: CGSize(width: UIScreen.main.bounds.width, height: 500),
                            showBadge: true,
                            autoPlay: false
                        ) {
                            showFullscreen = true
                        }
                    } else if loader.isLoading {
                        // 加载中
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 500)
                            .overlay(
                                VStack {
                                    ProgressView()
                                    Text("Loading Live Photo...")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .padding(.top, 8)
                                }
                            )
                    } else if let error = loader.error {
                        // 错误状态
                        Rectangle()
                            .fill(Color.red.opacity(0.1))
                            .frame(height: 500)
                            .overlay(
                                VStack(spacing: 12) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.system(size: 40))
                                        .foregroundColor(.red)
                                    Text("Failed to load Live Photo")
                                        .font(.headline)
                                    Text(error.localizedDescription)
                                        .font(.caption)
                                        .foregroundColor(.gray)

                                    // 重试按钮
                                    Button("Retry") {
                                        Task {
                                            await loader.loadLivePhoto(
                                                imageUrl: imageUrl,
                                                videoUrl: videoUrl
                                            )
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            )
                    }

                    // 任务：加载 Live Photo
                    .task {
                        await loader.loadLivePhoto(
                            imageUrl: imageUrl,
                            videoUrl: videoUrl
                        )
                    }
                }

                // 帖子文本、评论等...
            }
        }
        .fullScreenCover(isPresented: $showFullscreen) {
            // 全屏查看 Live Photo
            if let livePhoto = loader.livePhoto {
                FullscreenLivePhotoViewer(livePhoto: livePhoto)
            }
        }
    }
}

// MARK: - Example 3: 全屏 Live Photo 查看器

struct FullscreenLivePhotoViewer: View {
    let livePhoto: PHLivePhoto

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // 黑色背景
            Color.black
                .ignoresSafeArea()

            // Live Photo
            NativeLivePhotoView(
                livePhoto: livePhoto,
                isMuted: true,
                autoPlay: false,
                contentMode: .scaleAspectFit
            )
            .scaleEffect(scale)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let delta = value / lastScale
                        lastScale = value
                        scale = min(max(scale * delta, 1), 4)
                    }
                    .onEnded { _ in
                        lastScale = 1.0
                        if scale < 1 {
                            withAnimation(.spring()) {
                                scale = 1
                            }
                        }
                    }
            )

            // 关闭按钮
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .padding()

                    Spacer()
                }
                Spacer()
            }
        }
        .statusBar(hidden: true)
    }
}

// MARK: - Example 4: 创建帖子时使用现有的 Live Photo 预览

/// 创建帖子时的 Live Photo 预览（使用现有的自定义播放器）
struct CreatePostWithLivePhotoExample: View {
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var mediaItems: [PostMediaItem] = []
    @StateObject private var livePhotoManager = LivePhotoManager.shared

    var body: some View {
        VStack(spacing: 16) {
            // 选择按钮
            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: 5,
                matching: .any(of: [.images, .livePhotos, .videos])
            ) {
                HStack {
                    Image(systemName: "photo.on.rectangle.angled")
                    Text("Select Media")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
            }
            .onChange(of: selectedItems) { newItems in
                Task {
                    do {
                        // 并行加载所有媒体（包括 Live Photo）
                        let items = try await livePhotoManager.loadMedia(
                            from: newItems,
                            maxCount: 5
                        )
                        mediaItems = items
                    } catch {
                        print("Failed to load media: \(error)")
                    }
                }
            }

            // 显示选中的媒体
            if !mediaItems.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(mediaItems) { item in
                            mediaPreview(for: item)
                        }
                    }
                    .padding(.horizontal)
                }
            }

            // 发帖按钮...
        }
        .padding()
    }

    @ViewBuilder
    private func mediaPreview(for item: PostMediaItem) -> some View {
        switch item {
        case .livePhoto(let data, let metadata):
            // ✨ Live Photo 预览卡片（使用现有的自定义播放器）
            LivePhotoPreviewCard(
                livePhotoData: data,
                onDelete: {
                    mediaItems.removeAll { $0.id == item.id }
                }
            )
            .overlay(alignment: .bottom) {
                if let location = metadata.locationName {
                    Text("📍 \(location)")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(6)
                        .padding(8)
                }
            }

        case .image(let image, let metadata):
            // 普通图片预览
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 239, height: 290)
                .clipped()
                .cornerRadius(10)
                .overlay(alignment: .topTrailing) {
                    deleteButton {
                        mediaItems.removeAll { $0.id == item.id }
                    }
                }

        case .video(let videoData, _):
            // 视频预览...
            EmptyView()
        }
    }

    @ViewBuilder
    private func deleteButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 20, height: 20)
                )
        }
        .padding(4)
    }
}

// MARK: - Example 5: 手动控制 Live Photo 加载

/// 展示如何手动控制 Live Photo 的加载过程
struct ManualLivePhotoLoadingExample: View {
    let imageUrl: String
    let videoUrl: String

    @State private var livePhoto: PHLivePhoto?
    @State private var isLoading = false
    @State private var error: Error?

    var body: some View {
        VStack(spacing: 20) {
            if let livePhoto = livePhoto {
                // 显示 Live Photo
                NativeLivePhotoView(
                    livePhoto: livePhoto,
                    isMuted: true,
                    autoPlay: false
                )
                .frame(width: 320, height: 400)
                .cornerRadius(12)

                Text("Long press to play")
                    .font(.caption)
                    .foregroundColor(.gray)

            } else if isLoading {
                // 加载状态
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading Live Photo...")
                        .font(.headline)
                }
                .frame(width: 320, height: 400)

            } else if let error = error {
                // 错误状态
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.red)
                    Text("Failed to load")
                        .font(.headline)
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)

                    Button("Retry") {
                        loadLivePhoto()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(width: 320, height: 400)
            }

            // 控制按钮
            HStack(spacing: 16) {
                Button("Load") {
                    loadLivePhoto()
                }
                .buttonStyle(.bordered)
                .disabled(isLoading || livePhoto != nil)

                Button("Clear Cache") {
                    LivePhotoRebuilder.shared.clearMemoryCache()
                    livePhoto = nil
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    private func loadLivePhoto() {
        isLoading = true
        error = nil
        livePhoto = nil

        Task {
            do {
                let result = try await LivePhotoRebuilder.shared.rebuildLivePhoto(
                    imageUrl: imageUrl,
                    videoUrl: videoUrl,
                    targetSize: CGSize(width: 1920, height: 1920)
                )

                await MainActor.run {
                    self.livePhoto = result.livePhoto
                    self.isLoading = false
                }

                #if DEBUG
                print("Live Photo loaded successfully")
                print("Photo: \(result.photoURL.path)")
                print("Video: \(result.videoURL.path)")
                #endif

            } catch {
                await MainActor.run {
                    self.error = error
                    self.isLoading = false
                }

                #if DEBUG
                print("Failed to load Live Photo: \(error)")
                #endif
            }
        }
    }
}

// MARK: - Example 6: 缓存管理

/// 展示如何管理 Live Photo 缓存
struct LivePhotoCacheManagementExample: View {
    @State private var cacheSize: String = "Calculating..."

    var body: some View {
        List {
            Section("Cache Information") {
                HStack {
                    Text("Disk Cache Size")
                    Spacer()
                    Text(cacheSize)
                        .foregroundColor(.gray)
                }
            }

            Section("Cache Actions") {
                Button("Clear Memory Cache") {
                    LivePhotoRebuilder.shared.clearMemoryCache()
                }

                Button("Clear Disk Cache", role: .destructive) {
                    do {
                        try LivePhotoRebuilder.shared.clearDiskCache()
                        calculateCacheSize()
                    } catch {
                        print("Failed to clear disk cache: \(error)")
                    }
                }
            }

            Section {
                Button("Refresh Cache Size") {
                    calculateCacheSize()
                }
            }
        }
        .onAppear {
            calculateCacheSize()
        }
    }

    private func calculateCacheSize() {
        // 计算缓存大小的示例实现
        cacheSize = "Calculating..."

        Task {
            let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            let livePhotosDir = cachesDir.appendingPathComponent("LivePhotos", isDirectory: true)

            var totalSize: UInt64 = 0

            if let enumerator = FileManager.default.enumerator(at: livePhotosDir, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                       let fileSize = resourceValues.fileSize {
                        totalSize += UInt64(fileSize)
                    }
                }
            }

            let formatter = ByteCountFormatter()
            formatter.countStyle = .file

            await MainActor.run {
                cacheSize = formatter.string(fromByteCount: Int64(totalSize))
            }
        }
    }
}

// MARK: - Previews

#Preview("Feed Post with Live Photo") {
    FeedPostCardWithLivePhotoExample(
        post: Post(
            id: "1",
            creatorId: "user1",
            username: "john_doe",
            displayName: "John Doe",
            content: "Check out this Live Photo!",
            mediaUrls: [
                "https://example.com/photo.heic",
                "https://example.com/video.mov"
            ],
            mediaType: "live_photo",
            createdAt: Date(),
            likesCount: 42,
            commentsCount: 5,
            isLiked: false
        )
    )
}

#Preview("Create Post with Live Photo") {
    CreatePostWithLivePhotoExample()
}

#Preview("Manual Loading Example") {
    ManualLivePhotoLoadingExample(
        imageUrl: "https://example.com/photo.heic",
        videoUrl: "https://example.com/video.mov"
    )
}

#Preview("Cache Management") {
    LivePhotoCacheManagementExample()
}
