# MediaKit 完整使用指南

## Linus Torvalds 代码审查

> **品味评分**: 🟢 好品味
>
> **核心判断**: 简洁的数据结构，清晰的职责分离，零特殊情况
>
> **关键洞察**:
> - **数据流**: 内存缓存 → 磁盘缓存 → 网络下载（三层清晰）
> - **状态管理**: 待上传 → 上传中 → 完成/失败（无分支）
> - **网络优化**: WiFi/蜂窝/低速模式（策略模式）

---

## 目录

1. [快速开始](#快速开始)
2. [核心组件](#核心组件)
3. [图片加载](#图片加载)
4. [图片上传](#图片上传)
5. [视频处理](#视频处理)
6. [性能优化](#性能优化)
7. [高级用法](#高级用法)
8. [最佳实践](#最佳实践)

---

## 快速开始

### 1. 安装 Kingfisher（可选）

MediaKit 支持两种模式：
- **不安装 Kingfisher**: 使用内置的 `ImageManager`，零依赖
- **安装 Kingfisher**: 自动启用生产级图片加载

安装方法：
```
File > Add Package Dependencies > https://github.com/onevcat/Kingfisher.git
```

### 2. 应用启动配置

在 `App.swift` 中初始化 MediaKit：

```swift
import SwiftUI

@main
struct NovaSocialApp: App {
    init() {
        // 配置 MediaKit
        MediaKit.configure(with: MediaKitConfig())

        // 如果安装了 Kingfisher，配置缓存
        #if canImport(Kingfisher)
        KFImageView.setupKingfisher()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .mediaKit() // 注入 MediaKit 环境
        }
    }
}
```

### 3. 基础使用

```swift
import SwiftUI

struct MyView: View {
    var body: some View {
        VStack {
            // 1. 加载网络图片（自动缓存）
            KFImageView(url: "https://example.com/image.jpg")
                .frame(width: 200, height: 200)
                .roundedCorners(12)

            // 2. 头像样式
            KFImageView.avatar(
                url: user.avatarURL,
                size: 60
            )

            // 3. 封面样式
            KFImageView.cover(
                url: post.coverImageURL,
                aspectRatio: 16/9
            )
                .frame(height: 200)
        }
    }
}
```

---

## 核心组件

### 1. ImageManager - 图片缓存管理

**职责**: 三层缓存系统（内存 → 磁盘 → 网络）

```swift
let imageManager = ImageManager.shared

// 加载图片
let image = try await imageManager.loadImage(url: "https://example.com/photo.jpg")

// 预加载图片（用于下一页内容）
imageManager.prefetchImages(urls: nextPageImageURLs)

// 取消下载
imageManager.cancelDownload(url: imageURL)

// 清空缓存
await imageManager.clearCache()

// 获取缓存大小
let (memory, disk) = await imageManager.getCacheSize()
print("Memory: \(memory) bytes, Disk: \(disk) bytes")
```

### 2. ImageUploadManager - 智能上传

**职责**: 压缩、批量上传、进度追踪、失败重试

```swift
let uploadManager = ImageUploadManager.shared

// 单张上传
let taskId = uploadManager.uploadImage(
    selectedImage,
    to: uploadURL
)

// 批量上传
let taskIds = try await uploadManager.uploadBatch(
    selectedImages,
    getUploadURL: {
        // 从服务器获取上传 URL
        try await apiClient.getUploadURL()
    }
)

// 监控进度
ForEach(uploadManager.uploadQueue) { task in
    ProgressView(value: task.progress)
    Text("\(Int(task.progress * 100))%")
}

// 暂停/恢复/取消
uploadManager.pauseUpload(taskId: taskId)
uploadManager.resumeUpload(taskId: taskId)
uploadManager.cancelUpload(taskId: taskId)
```

### 3. VideoManager - 视频处理

**职责**: 缩略图生成、视频压缩、视频信息提取

```swift
let videoManager = VideoManager.shared

// 生成缩略图
let thumbnail = try await videoManager.generateThumbnail(
    from: videoURL,
    at: 5.0  // 5 秒处
)

// 批量生成（用于预览条）
let thumbnails = try await videoManager.generateThumbnails(
    from: videoURL,
    count: 10
)

// 获取视频信息
let info = try await videoManager.getVideoInfo(from: videoURL)
print("Duration: \(info.durationFormatted)")
print("Size: \(info.fileSizeFormatted)")

// 压缩视频
let compressedURL = try await videoManager.compressVideo(
    from: videoURL,
    quality: .medium
)
```

### 4. MediaNetworkOptimizer - 网络自适应

**职责**: 根据网络状态自动调整质量

```swift
let optimizer = MediaNetworkOptimizer.shared

// 获取优化后的图片 URL
let optimizedURL = optimizer.optimizedImageURL(for: originalURL)

// 检查是否应该预加载
if optimizer.shouldPrefetch {
    imageManager.prefetchImages(urls: nextPageURLs)
}

// 检查是否自动播放视频
if optimizer.shouldAutoPlayVideo {
    videoPlayer.play()
}

// 获取推荐压缩质量
let quality = optimizer.recommendedCompressionQuality
```

### 5. MediaMetrics - 性能监控

**职责**: 图片加载耗时、缓存命中率、内存使用

```swift
let metrics = MediaMetrics.shared

// 启动监控
metrics.startMonitoring()

// 获取性能报告
let report = metrics.getPerformanceReport()
print(report.summary)

// 显示调试视图
MediaPerformanceDebugView()
```

---

## 图片加载

### 基础加载

```swift
// 方式 1: 使用 KFImageView（推荐）
KFImageView(url: imageURL)
    .frame(width: 200, height: 200)

// 方式 2: 使用 CachedAsyncImage
CachedAsyncImage(url: imageURL)
    .frame(width: 200, height: 200)

// 方式 3: 直接使用 ImageManager
Task {
    let image = try await ImageManager.shared.loadImage(url: imageURL)
    self.displayImage = image
}
```

### 占位符和错误处理

```swift
KFImageView(
    url: imageURL,
    placeholder: Image("placeholder"),
    contentMode: .fill
)
```

### 重试策略

```swift
// 默认重试（3 次，间隔 2 秒）
KFImageView(url: imageURL)

// 自定义重试策略
KFImageView(
    url: imageURL,
    retryStrategy: .aggressive  // 5 次，间隔 1 秒
)

// 不重试
KFImageView(
    url: imageURL,
    retryStrategy: .noRetry
)
```

### 图片处理

```swift
#if !canImport(Kingfisher)
// 自定义处理器（未安装 Kingfisher）
KFImageView(url: imageURL)
    .roundedCorners(20)
    .resize(to: CGSize(width: 300, height: 300))
    .blur(radius: 5)
#else
// Kingfisher 自动处理
KFImageView(url: imageURL)
    .roundedCorners(20)  // 使用 clipShape
#endif
```

### 预加载优化

```swift
// Feed 场景：预加载下一页
func loadNextPage() {
    let nextPageURLs = posts.map { $0.imageURL }
    ImageManager.shared.prefetchImages(urls: nextPageURLs)
}

// 详情页场景：预加载全部图片
func openPostDetail(post: Post) {
    ImageManager.shared.prefetchImages(urls: post.allImageURLs)
}
```

---

## 图片上传

### 单张上传

```swift
struct PostCreationView: View {
    @State private var selectedImage: UIImage?
    @State private var uploadProgress: Double = 0

    var body: some View {
        VStack {
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)

                ProgressView(value: uploadProgress)

                Button("Upload") {
                    uploadImage()
                }
            }
        }
    }

    func uploadImage() {
        guard let image = selectedImage else { return }

        Task {
            // 1. 获取上传 URL
            let uploadURL = try await apiClient.getUploadURL()

            // 2. 开始上传
            let taskId = ImageUploadManager.shared.uploadImage(
                image,
                to: uploadURL
            )

            // 3. 监控进度
            // UploadTask 自动更新 progress 属性
        }
    }
}
```

### 批量上传

```swift
struct MultiImageUploadView: View {
    @State private var selectedImages: [UIImage] = []
    @StateObject private var uploadManager = ImageUploadManager.shared

    var body: some View {
        VStack {
            // 显示上传队列
            List(uploadManager.uploadQueue) { task in
                HStack {
                    Image(uiImage: task.image)
                        .resizable()
                        .frame(width: 50, height: 50)

                    VStack(alignment: .leading) {
                        ProgressView(value: task.progress)
                        Text(task.state.description)
                    }

                    // 控制按钮
                    if task.state == .uploading {
                        Button("Pause") {
                            uploadManager.pauseUpload(taskId: task.id)
                        }
                    } else if task.state == .paused {
                        Button("Resume") {
                            uploadManager.resumeUpload(taskId: task.id)
                        }
                    }
                }
            }

            Button("Upload All") {
                uploadAll()
            }
        }
    }

    func uploadAll() {
        Task {
            do {
                let taskIds = try await uploadManager.uploadBatch(
                    selectedImages,
                    getUploadURL: {
                        try await apiClient.getUploadURL()
                    }
                )
                print("Started \(taskIds.count) uploads")
            } catch {
                print("Upload failed: \(error)")
            }
        }
    }
}
```

### 压缩配置

```swift
// 自定义压缩配置
let config = ImageCompressor.CompressionConfig(
    maxFileSize: 500 * 1024,    // 500KB
    maxDimension: 2048,          // 最大边长
    initialQuality: 0.8,         // 初始质量
    minQuality: 0.3,             // 最低质量
    qualityStep: 0.1             // 递减步长
)

let compressor = ImageCompressor(config: config)
let compressedData = compressor.compress(originalImage)
```

---

## 视频处理

### 视频播放器

```swift
// 简单播放器
VideoPlayerView(
    url: videoURL,
    autoPlay: false
)

// 带控制条的播放器
CustomVideoPlayerView(
    url: videoURL,
    autoPlay: true
)
```

### 缩略图展示

```swift
struct VideoThumbnailView: View {
    let videoURL: URL
    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }

    func loadThumbnail() {
        Task {
            thumbnail = try? await VideoManager.shared.generateThumbnail(
                from: videoURL,
                at: 0
            )
        }
    }
}
```

### 视频预览条

```swift
struct VideoPreviewBar: View {
    let videoURL: URL
    @State private var thumbnails: [UIImage] = []

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(Array(thumbnails.enumerated()), id: \.offset) { index, thumb in
                    Image(uiImage: thumb)
                        .resizable()
                        .frame(width: 60, height: 40)
                }
            }
        }
        .onAppear {
            loadThumbnails()
        }
    }

    func loadThumbnails() {
        Task {
            thumbnails = try await VideoManager.shared.generateThumbnails(
                from: videoURL,
                count: 10
            )
        }
    }
}
```

---

## 性能优化

### 1. 网络自适应

```swift
// 自动根据网络状态调整
let optimizer = MediaNetworkOptimizer.shared

// WiFi: 加载高清
// 蜂窝: 加载标清
// 低速: 加载缩略图
let imageURL = optimizer.optimizedImageURL(for: baseURL)

KFImageView(url: imageURL)
```

### 2. 预加载策略

```swift
// Feed 滚动预加载
struct FeedView: View {
    @State private var posts: [Post] = []

    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(posts) { post in
                    PostCell(post: post)
                        .onAppear {
                            prefetchNextIfNeeded(post: post)
                        }
                }
            }
        }
    }

    func prefetchNextIfNeeded(post: Post) {
        // 距离底部还有 3 个时预加载
        guard let index = posts.firstIndex(where: { $0.id == post.id }),
              index >= posts.count - 3 else { return }

        let nextURLs = posts[index...].map { $0.imageURL }
        ImageManager.shared.prefetchImages(urls: nextURLs)
    }
}
```

### 3. 内存管理

```swift
// 定期清理缓存
Task {
    // 获取缓存大小
    let (memory, disk) = await ImageManager.shared.getCacheSize()

    // 如果超过限制，清理
    if disk > 500 * 1024 * 1024 {  // 500MB
        await ImageManager.shared.clearCache(
            includeMemory: false,
            includeDisk: true
        )
    }
}
```

### 4. 性能监控

```swift
// 在开发模式下启用监控
#if DEBUG
struct ContentView: View {
    var body: some View {
        TabView {
            FeedView()
                .tabItem { Label("Feed", systemImage: "house") }

            MediaPerformanceDebugView()
                .tabItem { Label("Performance", systemImage: "chart.bar") }
        }
        .onAppear {
            MediaMetrics.shared.startMonitoring()
        }
    }
}
#endif
```

---

## 高级用法

### 1. 图片选择器

```swift
struct ImagePickerDemo: View {
    @State private var images: [UIImage] = []
    @State private var showPicker = false

    var body: some View {
        VStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) {
                    ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                    }
                }
            }

            Button("Select Images") {
                showPicker = true
            }
        }
        .imagePicker(
            isPresented: $showPicker,
            selectedImages: $images,
            maxSelection: 9,
            allowCamera: true
        )
    }
}
```

### 2. 图片浏览器

```swift
struct PostDetailView: View {
    let post: Post
    @State private var showImageViewer = false
    @State private var selectedIndex = 0

    var body: some View {
        ScrollView {
            ForEach(Array(post.images.enumerated()), id: \.offset) { index, imageURL in
                KFImageView(url: imageURL)
                    .frame(height: 300)
                    .onTapGesture {
                        selectedIndex = index
                        showImageViewer = true
                    }
            }
        }
        .fullScreenCover(isPresented: $showImageViewer) {
            ImageViewerView(
                images: post.images,
                initialIndex: selectedIndex
            )
        }
    }
}
```

### 3. 自定义图片处理

```swift
// 创建自定义处理器
struct WatermarkProcessor: ImageProcessor {
    let watermarkText: String

    func process(_ image: UIImage) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { context in
            // 绘制原图
            image.draw(in: CGRect(origin: .zero, size: image.size))

            // 添加水印
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20),
                .foregroundColor: UIColor.white.withAlphaComponent(0.5)
            ]
            watermarkText.draw(
                at: CGPoint(x: 10, y: image.size.height - 30),
                withAttributes: attrs
            )
        }
    }
}

// 使用
KFImageView(url: imageURL)
    .processors([WatermarkProcessor(watermarkText: "@nova")])
```

---

## 最佳实践

### 1. 错误处理

```swift
// 始终处理加载失败
KFImageView(url: imageURL)
    .onFailure { error in
        // 记录错误
        logger.error("Image load failed: \(error)")

        // 显示错误提示
        showErrorToast("Failed to load image")
    }
```

### 2. 内存优化

```swift
// 大图列表使用 LazyVStack
ScrollView {
    LazyVStack {  // ✅ 懒加载
        ForEach(posts) { post in
            PostCell(post: post)
        }
    }
}

// 避免使用 VStack（会一次性加载所有）
ScrollView {
    VStack {  // ❌ 性能问题
        ForEach(posts) { post in
            PostCell(post: post)
        }
    }
}
```

### 3. 缓存策略

```swift
// 定期清理过期缓存（应用启动时）
Task {
    await ImageManager.shared.clearCache(
        includeMemory: true,
        includeDisk: false  // 保留磁盘缓存
    )
}

// 低内存警告时清理
NotificationCenter.default.addObserver(
    forName: UIApplication.didReceiveMemoryWarningNotification,
    object: nil,
    queue: .main
) { _ in
    Task {
        await ImageManager.shared.clearCache(
            includeMemory: true,
            includeDisk: false
        )
    }
}
```

### 4. 网络优化

```swift
// WiFi 环境：预加载
if MediaNetworkOptimizer.shared.shouldPrefetch {
    ImageManager.shared.prefetchImages(urls: allImageURLs)
}

// 蜂窝环境：按需加载
// 不预加载，等用户滚动到时再加载
```

### 5. 测试和调试

```swift
// 开发环境显示性能指标
#if DEBUG
.onAppear {
    MediaMetrics.shared.startMonitoring()

    // 5 秒后打印报告
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
        let report = MediaMetrics.shared.getPerformanceReport()
        print(report.summary)
    }
}
#endif
```

---

## 总结

MediaKit 提供了完整的图片和视频处理解决方案：

✅ **零配置**: 开箱即用，无需复杂设置
✅ **高性能**: 三层缓存，预加载，网络自适应
✅ **易扩展**: 支持自定义处理器和策略
✅ **好品味**: 简洁的 API，清晰的职责分离

开始使用 MediaKit，让你的应用图片加载飞起来！
