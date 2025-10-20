# iOS 媒体上传功能实现总结

## 概述

已成功实现 iOS 应用的**图片和视频上传功能**，用户现在可以在 "Create" tab 中上传图片或视频创建帖子。

---

## 📁 文件变更

### 新增文件

#### 1. `MediaKit/Core/MediaUploadManager.swift`
通用媒体上传管理器，统一处理图片和视频上传。

**核心功能：**
- 支持图片和视频混合上传
- 并发上传控制（最多 3 个并发）
- 自动压缩和重试逻辑（最多 3 次重试）
- 进度追踪和状态管理
- 统计信息（总上传数、成功率等）

**主要 API：**
```swift
// 上传单个媒体
func uploadMedia(_ media: MediaData, to uploadURL: URL, metadata: [String: String]) -> String

// 批量上传
func uploadBatch(_ medias: [MediaData], getUploadURL: @escaping () async throws -> URL) async throws -> [String]

// 暂停/恢复/取消
func pauseUpload(taskId: String)
func resumeUpload(taskId: String)
func cancelUpload(taskId: String)
```

**数据结构：**
```swift
enum MediaData {
    case image(UIImage)
    case video(URL)
}
```

---

### 修改文件

#### 2. `ViewModels/Post/CreatePostViewModel.swift`
完全重构以支持媒体（图片和视频）。

**关键变更：**
- ✅ 添加了 `selectedVideoURL` 和 `selectedMediaType`
- ✅ 添加了视频元数据支持（`videoThumbnail`, `videoDuration`, `videoFileSize`）
- ✅ 使用 `MediaUploadManager` 进行上传
- ✅ 动态确定 `contentType`（image/jpeg 或 video/mp4）
- ✅ 新方法：`selectVideo()`, `removeMedia()`, `loadVideoMetadata()`

**发布属性：**
```swift
@Published var selectedImage: UIImage?
@Published var selectedVideoURL: URL?
@Published var selectedMediaType: MediaType?
@Published var videoThumbnail: UIImage?
@Published var videoDuration: String
@Published var videoFileSize: String
```

**验证规则：**
- 需要选择图片或视频
- 需要写入标题（caption 不能为空）

#### 3. `Views/Post/CreatePostView.swift`
UI 完全重设计，现在支持图片和视频上传。

**UI 改进：**

1. **媒体选择按钮**（没有媒体时显示）
   - "Add Photo" 按钮（蓝色，图标 photo.on.rectangle.angled）
   - "Add Video" 按钮（红色，图标 video.fill）
   - 两个按钮都打开同一个统一的 `MediaPickerView`

2. **图片预览**
   - 全宽预览（1:1 比例）
   - 删除按钮（右上角）
   - "PHOTO" 标签（蓝色）

3. **视频预览**
   - 缩略图 + 播放按钮叠加（16:9 比例）
   - 显示视频时长和文件大小
   - 删除按钮（右上角）
   - "VIDEO" 标签（红色）
   - 支持加载中状态

4. **新的 MediaPickerView**
   - 替代旧的 ImagePicker
   - 支持 `UIImagePickerController` 模式
   - 自动检测选择的是图片还是视频
   - `mediaTypes = ["public.image", "public.movie"]`

---

## 🎯 用户流程

1. **打开应用** → 点击底部 "Create" tab（加号图标）
2. **选择媒体**：
   - 点击 "Add Photo" 或 "Add Video"
   - 从相册选择
3. **输入标题**：在 caption 文本框中输入
4. **上传**：
   - 点击 "Share Post" 按钮
   - 看到进度条（0-100%）
   - 成功后弹出确认提示
5. **表单重置**：自动清空图片/视频和标题

---

## 🛠 技术细节

### 视频处理流程

```
选择视频
  ↓
生成缩略图 (VideoManager.generateThumbnail)
  ↓
获取视频信息 (duration, size, resolution)
  ↓
用户输入标题
  ↓
点击上传
  ↓
压缩视频 (VideoManager.compressVideo - 中等质量)
  ↓
上传到 S3/后端
  ↓
创建帖子数据库记录
  ↓
完成
```

### 图片处理流程

```
选择图片
  ↓
用户输入标题
  ↓
点击上传
  ↓
压缩图片 (ImageCompressor - 80% 质量)
  ↓
上传到 S3/后端
  ↓
创建帖子数据库记录
  ↓
完成
```

### 并发控制

- **最大并发上传数**：3
- **重试机制**：失败时延迟 2 秒后自动重试（最多 3 次）
- **任务队列**：pending → uploading → completed/failed

---

## 📊 数据流

```
CreatePostView (UI)
     ↓
CreatePostViewModel (业务逻辑)
     ↓
MediaUploadManager (上传管理)
     ↓
VideoManager (视频处理)
     ↓
ImageCompressor (图片压缩)
     ↓
PostRepository (API 调用)
     ↓
后端服务
```

---

## ✅ 检查清单

- [x] 支持图片上传
- [x] 支持视频上传
- [x] UI 清晰的上传按钮
- [x] 进度显示
- [x] 错误处理
- [x] 视频预览
- [x] 视频元数据显示
- [x] 标题验证
- [x] 自动压缩
- [x] 并发控制
- [x] 重试机制

---

## 🚀 使用示例

### 在 SwiftUI 中使用 MediaUploadManager

```swift
let manager = MediaUploadManager.shared

// 上传图片
let imageUploadId = manager.uploadMedia(
    .image(uiImage),
    to: uploadURL,
    metadata: ["type": "photo"]
)

// 上传视频
let videoUploadId = manager.uploadMedia(
    .video(videoURL),
    to: uploadURL
)

// 获取状态
if let status = manager.getTaskStatus(taskId: uploadId) {
    // 处理状态
}

// 监听上传队列变化
@Published var uploadQueue = manager.uploadQueue
```

---

## 📝 Linus 风格设计原则

> "好代码没有特殊情况"

**实现中的应用：**

1. **统一的媒体处理**
   - `MediaData` 枚举统一图片和视频
   - 消除了 if-else 分支
   - 通用的 `MediaUploadManager`

2. **简化的数据结构**
   - 一个 `selectedMediaType` 替代多个图片/视频字段
   - 清晰的任务状态机制

3. **最小化的复杂性**
   - 没有深度嵌套的条件
   - 明确的职责分工
   - 可读性高的 UI 代码

---

## 🔧 配置要求

**Info.plist 权限：**
```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>We need access to your photo library to upload photos and videos</string>

<key>NSCameraUsageDescription</key>
<string>We need camera access to record videos</string>
```

**最小 iOS 版本**：iOS 16+

---

## 📚 相关文件树

```
ios/NovaSocialApp/
├── MediaKit/
│   └── Core/
│       └── MediaUploadManager.swift (NEW)
├── ViewModels/
│   └── Post/
│       └── CreatePostViewModel.swift (MODIFIED)
└── Views/
    └── Post/
        └── CreatePostView.swift (MODIFIED)
```

---

## 🎬 截图/演示

创建帖子的工作流：

1. **初始状态** - 两个按钮可选
2. **图片选择** - 显示图片预览
3. **视频选择** - 显示视频缩略图、时长、大小
4. **输入标题** - 标题字段
5. **上传中** - 进度条（0-100%）
6. **完成** - 成功提示

---

## 🐛 已知限制

1. **视频大小**：当前压缩为中等质量，大文件可能仍需时间
2. **并发数**：固定为 3，可根据网络条件调整
3. **超时设置**：上传最多等待 5 分钟

---

## 🚀 未来改进方向

- [ ] 支持图片和视频混合发布
- [ ] 添加视频编辑工具（剪裁、滤镜）
- [ ] 支持直播功能
- [ ] 添加上传历史记录
- [ ] 离线上传队列

---

## 🎓 代码质量

**遵循原则：**
- ✅ 单一职责原则（每个类一个目的）
- ✅ 开放-闭合原则（易于扩展，难以修改）
- ✅ 无深层嵌套（最多 2-3 层缩进）
- ✅ 明确的错误处理
- ✅ 文档完善的公开 API
