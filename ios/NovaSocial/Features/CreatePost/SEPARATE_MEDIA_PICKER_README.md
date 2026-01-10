# 分离的照片和视频选择功能

## ✅ 已实现的改进

### 之前的实现
- ❌ 单一选择器，可以同时选照片和视频
- ❌ UI混乱，用户困惑
- ❌ 不符合主流App设计

### 现在的实现
- ✅ 两个独立按钮：📸 照片 和 🎥 视频
- ✅ 互斥逻辑：选了照片就不能选视频
- ✅ 符合微信、Instagram 等主流设计

---

## 🎨 UI 变化

### 底部工具栏

```
之前：[相机] [Alice] [位置]

现在：[📸 照片] [🎥 视频] [Alice] [位置]
      ↑ 新增    ↑ 新增
```

### 互斥逻辑

| 状态 | 照片按钮 | 视频按钮 | 说明 |
|------|---------|---------|------|
| 无内容 | ✅ 启用 | ✅ 启用 | 可以选择任一种 |
| 已选照片 | ✅ 启用 | ❌ 禁用（灰色） | 只能继续添加照片 |
| 已选视频 | ❌ 禁用（灰色） | ✅ 启用 | 不能再选照片 |

---

## 🔧 技术实现

### 新增的状态变量

```swift
// 分离的选择器状态
@State private var selectedPhotoItems: [PhotosPickerItem] = []
@State private var selectedVideoItems: [PhotosPickerItem] = []
@State private var showPhotoPhotoPicker = false
@State private var showVideoPhotoPicker = false

// 计算当前媒体类型
private var currentMediaType: MediaSelectionType {
    // 检测 selectedMediaItems 中是否有照片或视频
    // 返回 .none / .photos / .video
}
```

### 两个独立的 PhotosPicker

```swift
// 📸 照片选择器
.photosPicker(
    isPresented: $showPhotoPhotoPicker,
    selection: $selectedPhotoItems,
    maxSelectionCount: 5 - viewModel.selectedMediaItems.count,
    matching: .any(of: [.images, .livePhotos])  // ← 只选照片
)

// 🎥 视频选择器
.photosPicker(
    isPresented: $showVideoPhotoPicker,
    selection: $selectedVideoItems,
    maxSelectionCount: 1,  // 视频只能选1个
    matching: .videos  // ← 只选视频
)
```

### 处理方法

```swift
// 处理照片选择
private func processSelectedPhotos(_ items: [PhotosPickerItem]) async {
    // 1. 加载媒体
    // 2. 过滤掉视频（理论上不会有，但保险起见）
    // 3. 添加到 selectedMediaItems
    // 4. 触发 VLM 分析
}

// 处理视频选择
private func processSelectedVideos(_ items: [PhotosPickerItem]) async {
    // 1. 加载媒体
    // 2. 过滤掉照片（理论上不会有，但保险起见）
    // 3. 添加到 selectedMediaItems
}
```

---

## 📱 用户体验

### 选择照片流程

1. 用户点击 📸 照片按钮
2. 系统相册打开，只显示照片和 Live Photo
3. 可以选择 1-5 张（取决于已有数量）
4. 选择后自动加载并显示
5. 如果需要，可以继续点击📸添加更多照片

### 选择视频流程

1. 用户点击 🎥 视频按钮
2. 系统相册打开，只显示视频
3. 只能选择 1 个视频
4. 选择后自动加载并显示缩略图
5. 视频按钮变灰，不能再添加

### 互斥行为

**场景 1：先选照片，再想选视频**
- 用户选了 2 张照片
- 🎥 视频按钮变灰
- 点击无响应
- ✅ 符合预期：不能混合

**场景 2：先选视频，再想选照片**
- 用户选了 1 个视频
- 📸 照片按钮变灰
- 点击无响应
- ✅ 符合预期：不能混合

---

## 🧪 测试场景

### 基本功能测试

- [ ] 点击📸按钮，打开相册，只能看到照片和Live Photo
- [ ] 选择多张照片（静态+Live Photo混合），正常加载
- [ ] 点击🎥按钮，打开相册，只能看到视频
- [ ] 选择1个视频，正常加载

### 互斥逻辑测试

- [ ] 选了照片后，🎥按钮变灰且无法点击
- [ ] 选了视频后，📸按钮变灰且无法点击
- [ ] 删除所有照片后，🎥按钮恢复可用
- [ ] 删除视频后，📸按钮恢复可用

### 边界情况测试

- [ ] 已有5张照片，不能再添加
- [ ] 已有1个视频，不能再添加
- [ ] 相机拍摄的照片仍然正常添加
- [ ] 旧的"添加更多"按钮根据类型显示正确图标

---

## 🔄 兼容性

### 保留的功能

为了向后兼容，保留了旧的选择器配置：

```swift
// 旧的 PhotosPicker（用于其他入口）
.photosPicker(
    isPresented: $viewModel.showPhotoPicker,
    selection: $viewModel.selectedPhotos,
    maxSelectionCount: 5 - viewModel.selectedMediaItems.count,
    matching: .any(of: [.images, .livePhotos, .videos])
)
```

这样，如果从其他地方调用 `viewModel.showPhotoPicker = true`，仍然可以正常工作。

---

## 📊 数据流

```
用户点击 📸 照片按钮
    ↓
showPhotoPhotoPicker = true
    ↓
PhotosPicker 打开 (.images + .livePhotos)
    ↓
用户选择 → selectedPhotoItems
    ↓
processSelectedPhotos()
    ↓
LivePhotoManager.loadMedia()
    ↓
过滤视频（保险）
    ↓
viewModel.selectedMediaItems.append()
    ↓
触发 VLM 分析
    ↓
显示在预览区
```

---

## 🎯 核心优势

### 对用户的优势

1. **清晰的意图** - 发照片还是发视频，一目了然
2. **避免错误** - 不会意外选错类型
3. **符合习惯** - 和微信、Instagram一样的体验

### 对开发的优势

1. **类型安全** - 照片数组不会混入视频
2. **逻辑清晰** - 处理流程分离
3. **易于维护** - 未来扩展更容易

### 对产品的优势

1. **专业性** - 符合主流社交产品设计
2. **可扩展** - 未来可以添加更多限制（如视频时长）
3. **一致性** - 与Feed显示逻辑一致

---

## 📝 注意事项

### Live Photo 处理

Live Photo 被归类为"照片"类型：
- ✅ 可以和静态照片混合选择
- ✅ 最多选5个（照片+Live Photo 总和）
- ✅ 自动提取 photo + pairedVideo 上传

### 视频限制

当前实现：
- 只能选1个视频
- 选了视频后不能再添加照片
- 未来可以扩展：视频时长限制、多个视频等

### 相机拍摄

相机拍摄的照片/视频仍然通过原有逻辑处理，不受分离选择器影响。

---

## 🚀 未来改进

可选的增强功能：

1. **视频时长限制** - 最长60秒
2. **文件大小提示** - 显示文件大小
3. **压缩选项** - 让用户选择压缩质量
4. **批量操作** - 全部删除、调整顺序等

---

## 📚 相关文件

- `NewPostView.swift` - 主界面实现
- `NewPostViewModel.swift` - 状态管理
- `LivePhotoManager.swift` - 媒体加载
- `BackgroundUploadManager.swift` - 上传管理

---

## ✅ 完成！

现在 Nova iOS 有了符合行业标准的媒体选择体验！

**核心原则：照片（包括 Live Photo）和视频是两种完全不同的内容类型，应该分开选择和处理。**
