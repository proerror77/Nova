# Live Photo 完整实现指南

## 📋 概述

Nova iOS 现在支持完整的 Live Photo 生命周期：
1. **选择和导出** - 使用 PhotosPicker 选择，PHAssetResourceManager 导出原始资源
2. **上传** - 分别上传静态图（WebP压缩）和配对视频（MOV）
3. **下载和重建** - 从服务器下载后使用 `PHLivePhoto.request` 重建原生 Live Photo
4. **显示** - 使用原生 `PHLivePhotoView` 或自定义播放器

---

## 🎯 方案对比

### 方案 A: 原生 PHLivePhotoView（新增）✨

**优势：**
- ✅ iOS 原生 Live Photo 体验
- ✅ 完整的过渡动画和特效
- ✅ 自动处理长按播放
- ✅ 系统级性能优化

**使用场景：**
- Feed 中显示从服务器下载的 Live Photo
- 详情页全屏预览
- 需要原生体验的场景

### 方案 B: 自定义视频播放器（现有）

**优势：**
- ✅ 完全自定义 UI
- ✅ 更灵活的播放控制
- ✅ 降级兼容

**使用场景：**
- 发帖预览（本地 Live Photo）
- 需要自定义播放逻辑

---

## 🚀 快速开始

### 1. 选择 Live Photo（现有功能）

⚠️ **重要：照片和视频应该分开选择**

```swift
import SwiftUI
import PhotosUI

struct PostCreationView: View {
    // 照片选择（包括 Live Photo）
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var photoMediaItems: [PostMediaItem] = []

    // 视频选择（独立）
    @State private var selectedVideoItems: [PhotosPickerItem] = []
    @State private var videoMediaItems: [PostMediaItem] = []

    @StateObject private var livePhotoManager = LivePhotoManager.shared

    var body: some View {
        VStack {
            // 📸 照片选择器（支持静态照片 + Live Photo）
            PhotosPicker(
                selection: $selectedPhotoItems,
                maxSelectionCount: 5,
                matching: .any(of: [.images, .livePhotos])  // ← 只选照片
            ) {
                HStack {
                    Image(systemName: "photo.on.rectangle.angled")
                    Text("添加照片")
                }
            }
            .disabled(!videoMediaItems.isEmpty)  // 如果选了视频，禁用
            .onChange(of: selectedPhotoItems) { newItems in
                Task {
                    let items = try await livePhotoManager.loadMedia(
                        from: newItems,
                        maxCount: 5
                    )
                    photoMediaItems = items
                }
            }

            // 🎥 视频选择器（独立）
            PhotosPicker(
                selection: $selectedVideoItems,
                maxSelectionCount: 1,
                matching: .videos  // ← 只选视频
            ) {
                HStack {
                    Image(systemName: "video.fill")
                    Text("添加视频")
                }
            }
            .disabled(!photoMediaItems.isEmpty)  // 如果选了照片，禁用
            .onChange(of: selectedVideoItems) { newItems in
                Task {
                    let items = try await livePhotoManager.loadMedia(
                        from: newItems,
                        maxCount: 1
                    )
                    videoMediaItems = items
                }
            }

            // 显示选中的照片（Live Photo + 静态照片）
            ForEach(photoMediaItems) { item in
                switch item {
                case .livePhoto(let data, let metadata):
                    LivePhotoPreviewCard(
                        livePhotoData: data,
                        onDelete: { /* 删除逻辑 */ }
                    )
                    if let location = metadata.locationName {
                        Text("📍 \(location)")
                    }

                case .image(let image, let metadata):
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()

                case .video:
                    EmptyView()  // 不会出现
                }
            }

            // 显示选中的视频
            ForEach(videoMediaItems) { item in
                if case .video(let videoData, let metadata) = item {
                    // 视频预览
                    Image(uiImage: videoData.thumbnail)
                        .resizable()
                        .scaledToFit()
                }
            }
        }
    }
}
```

**为什么要分开？**

| 原因 | 说明 |
|------|------|
| 📱 产品设计 | 用户习惯：发照片 OR 发视频，很少混合 |
| 🎨 UI 布局 | 照片可以多图排列，视频需要独立展示 |
| ⚙️ 处理逻辑 | 视频需要特殊处理（转码、时长限制） |
| 📊 服务端 | 不同的存储策略和CDN配置 |

**详细示例见：** `SeparateMediaPickerExample.swift`

### 2. 上传 Live Photo（现有功能）

上传在 `BackgroundUploadManager` 中自动处理：

```swift
// 内部实现（已完成）
private func compressAndUploadMedia(items: [PostMediaItem]) async throws -> [String] {
    for item in items {
        switch item {
        case .livePhoto(let data, _):
            // 1. 压缩静态图为 WebP
            let compressionResult = await imageCompressor.compressImage(
                data.stillImage,
                quality: .low,
                format: .webp
            )

            // 2. 上传两个资源
            let result = try await mediaService.uploadLivePhoto(
                imageData: compressionResult.data,
                videoURL: data.videoURL,
                imageFilename: compressionResult.filename
            )

            // 返回 [imageUrl, videoUrl]
            return [result.imageUrl, result.videoUrl]
        }
    }
}
```

**服务端存储要求：**
- ✅ 存储两个独立文件：photo (WebP/HEIC) + video (MOV)
- ✅ 返回两个 URL 给客户端
- ❌ 不要在服务端合并或转码（会破坏配对元数据）

### 3. 显示 Live Photo - 原生方式（新增）✨

#### 方式 A: 自动加载的 Feed 播放器

```swift
import SwiftUI

struct FeedPostCard: View {
    let post: Post

    var body: some View {
        VStack {
            if post.mediaType == "live_photo",
               let imageUrl = post.mediaUrls?.first,
               let videoUrl = post.mediaUrls?.dropFirst().first {

                // 使用原生 PHLivePhotoView
                FeedNativeLivePhotoPlayer(
                    imageUrl: imageUrl,
                    videoUrl: videoUrl,
                    height: 400
                ) {
                    // 点击后跳转到详情页
                    navigateToDetail(post)
                }
            }
        }
    }
}
```

**特性：**
- ✅ 自动下载和缓存 photo + video
- ✅ 自动重建 PHLivePhoto
- ✅ 显示加载指示器
- ✅ 降级到静态图（如果重建失败）
- ✅ 内存和磁盘缓存

#### 方式 B: 手动控制加载

```swift
struct DetailView: View {
    let imageUrl: String
    let videoUrl: String

    @StateObject private var loader = LivePhotoLoader()

    var body: some View {
        VStack {
            if let livePhoto = loader.livePhoto {
                // 原生 Live Photo 卡片
                NativeLivePhotoCard(
                    livePhoto: livePhoto,
                    size: CGSize(width: 375, height: 500),
                    showBadge: true,
                    autoPlay: false
                )
            } else if loader.isLoading {
                ProgressView("Loading Live Photo...")
            } else if let error = loader.error {
                Text("Error: \(error.localizedDescription)")
            }
        }
        .task {
            await loader.loadLivePhoto(
                imageUrl: imageUrl,
                videoUrl: videoUrl
            )
        }
    }
}
```

#### 方式 C: 直接使用 PHLivePhotoView 包装器

```swift
struct CustomLivePhotoView: View {
    @State private var livePhoto: PHLivePhoto?

    var body: some View {
        NativeLivePhotoView(
            livePhoto: livePhoto,
            isMuted: true,
            autoPlay: false,
            contentMode: .scaleAspectFit
        )
        .frame(width: 320, height: 400)
        .onAppear {
            loadLivePhoto()
        }
    }

    private func loadLivePhoto() {
        Task {
            let result = try await LivePhotoRebuilder.shared.rebuildLivePhoto(
                imageUrl: "https://cdn.example.com/photo.heic",
                videoUrl: "https://cdn.example.com/video.mov"
            )
            livePhoto = result.livePhoto
        }
    }
}
```

### 4. 显示 Live Photo - 自定义方式（现有）

用于发帖预览等本地场景：

```swift
struct NewPostPreview: View {
    let livePhotoData: LivePhotoData

    var body: some View {
        LivePhotoPreviewCard(
            livePhotoData: livePhotoData,
            onDelete: { /* 删除 */ }
        )
    }
}
```

---

## 🔧 核心 API 参考

### LivePhotoRebuilder

```swift
@MainActor
class LivePhotoRebuilder {
    static let shared: LivePhotoRebuilder

    /// 从服务器 URL 重建 Live Photo
    func rebuildLivePhoto(
        imageUrl: String,
        videoUrl: String,
        targetSize: CGSize = CGSize(width: 1920, height: 1920)
    ) async throws -> LivePhotoRebuildResult

    /// 清除内存缓存
    func clearMemoryCache()

    /// 清除磁盘缓存
    func clearDiskCache() throws
}

struct LivePhotoRebuildResult {
    let livePhoto: PHLivePhoto       // 重建的 Live Photo
    let stillImage: UIImage?         // 静态图（用于预加载）
    let photoURL: URL                // 本地缓存的 photo 路径
    let videoURL: URL                // 本地缓存的 video 路径
}
```

### LivePhotoLoader

```swift
@MainActor
class LivePhotoLoader: ObservableObject {
    @Published var livePhoto: PHLivePhoto?
    @Published var isLoading: Bool
    @Published var error: Error?

    /// 异步加载 Live Photo
    func loadLivePhoto(imageUrl: String, videoUrl: String) async

    /// 取消加载
    func cancel()
}
```

### SwiftUI 组件

```swift
// 原生 PHLivePhotoView 包装器
NativeLivePhotoView(
    livePhoto: PHLivePhoto?,
    isMuted: Bool = true,
    autoPlay: Bool = false,
    contentMode: UIView.ContentMode = .scaleAspectFill
)

// 带徽章的 Live Photo 卡片
NativeLivePhotoCard(
    livePhoto: PHLivePhoto?,
    size: CGSize = CGSize(width: 320, height: 400),
    showBadge: Bool = true,
    autoPlay: Bool = false,
    onTap: (() -> Void)? = nil
)

// Feed 播放器（自动下载和重建）
FeedNativeLivePhotoPlayer(
    imageUrl: String,
    videoUrl: String,
    height: CGFloat,
    onTap: (() -> Void)? = nil
)
```

---

## ⚠️ 重要注意事项

### 1. 服务端要求

**必须：**
- ✅ 分别存储 photo 和 video 两个文件
- ✅ 保持原始格式（WebP/HEIC + MOV）
- ✅ 返回两个独立的下载 URL

**禁止：**
- ❌ 合并成单一文件
- ❌ 转码视频格式（如 MOV → MP4）
- ❌ 修改视频元数据

### 2. 性能优化

**缓存策略：**
- 内存缓存：已重建的 PHLivePhoto 对象
- 磁盘缓存：下载的 photo + video 文件
- 自动清理：系统内存压力时清理

**下载优化：**
- 并行下载 photo 和 video
- 使用 URLSession 的缓存策略
- 支持断点续传

### 3. 降级策略

如果 Live Photo 重建失败：
1. Feed 中显示静态图（AsyncImage）
2. 提供重试按钮
3. 日志记录失败原因

### 4. 文件清理

```swift
// 发帖完成后清理临时文件
livePhotoManager.cleanupTemporaryFiles(for: mediaItems)

// 定期清理缓存
try? LivePhotoRebuilder.shared.clearDiskCache()
```

---

## 📊 数据流图

```
用户选择 Live Photo
     ↓
PhotosPicker (PhotosPickerItem)
     ↓
LivePhotoManager.loadMedia()
     ↓
PHAssetResourceManager 导出
  ├─→ photo.heic (stillImage)
  └─→ video.mov (pairedVideo)
     ↓
BackgroundUploadManager
  ├─→ 压缩 photo → WebP
  └─→ 读取 video → Data
     ↓
MediaService.uploadLivePhoto()
  ├─→ POST /upload photo.webp → imageUrl
  └─→ POST /upload video.mov → videoUrl
     ↓
服务器存储 [imageUrl, videoUrl]
     ↓
     ↓
Feed 显示
     ↓
FeedNativeLivePhotoPlayer
     ↓
LivePhotoRebuilder.rebuildLivePhoto()
  ├─→ 下载 imageUrl → 缓存/photo.heic
  └─→ 下载 videoUrl → 缓存/video.mov
     ↓
PHLivePhoto.request(withResourceFileURLs: [photo, video])
     ↓
PHLivePhoto 对象
     ↓
NativeLivePhotoView (PHLivePhotoView)
     ↓
用户长按播放 Live Photo ✨
```

---

## 🧪 测试检查清单

- [ ] 选择 Live Photo 并上传
- [ ] 检查服务器返回两个 URL
- [ ] Feed 中加载并显示 Live Photo
- [ ] 长按播放动画流畅
- [ ] 测试网络中断时的重试
- [ ] 测试缓存命中率
- [ ] 测试内存使用（大量 Live Photo）
- [ ] 测试降级到静态图
- [ ] 清理临时文件验证

---

## 🐛 常见问题

### Q1: Live Photo 无法重建，报错 "rebuildFailed"

**可能原因：**
- 服务端转码了 MOV 文件
- photo 和 video 丢失了配对元数据
- 文件损坏

**解决方案：**
1. 检查服务端是否原样存储
2. 验证下载的文件完整性
3. 查看详细错误日志

### Q2: Feed 中 Live Photo 加载很慢

**优化方案：**
- 使用 CDN 加速
- 预加载静态图
- 调整 targetSize（默认 1920x1920）
- 检查网络质量

### Q3: 内存占用过高

**解决方案：**
```swift
// 定期清理缓存
LivePhotoRebuilder.shared.clearMemoryCache()

// 或在收到内存警告时
NotificationCenter.default.addObserver(
    forName: UIApplication.didReceiveMemoryWarningNotification,
    object: nil,
    queue: .main
) { _ in
    LivePhotoRebuilder.shared.clearMemoryCache()
}
```

---

## 📚 相关文件

- `LivePhotoManager.swift` - Live Photo 选择和导出
- `LivePhotoRebuilder.swift` - 下载和重建服务
- `NativeLivePhotoView.swift` - SwiftUI 包装器
- `LivePhotoView.swift` - 自定义播放器（现有）
- `BackgroundUploadManager.swift` - 上传管理
- `MediaService.swift` - 网络上传

---

## 🎉 完成！

现在你已经拥有完整的 Live Photo 支持：从选择、上传到下载、重建、显示的全流程。

**推荐使用：**
- 发帖时：现有的 `LivePhotoPreviewCard`（自定义播放器）
- Feed 显示：新的 `FeedNativeLivePhotoPlayer`（原生体验）✨
