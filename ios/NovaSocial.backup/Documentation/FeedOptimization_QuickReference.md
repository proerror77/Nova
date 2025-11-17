# Feed 优化快速参考

## 核心文件位置

```
ios/NovaSocial/
├── Views/
│   ├── Feed/
│   │   ├── FeedView.swift              # 主 Feed 视图
│   │   └── PostCell.swift              # 帖子单元格
│   └── Common/
│       ├── LazyImageView.swift         # 图片懒加载
│       └── SkeletonLoadingView.swift   # 骨架屏
└── ViewModels/
    └── Feed/
        └── FeedViewModel.swift          # Feed 视图模型
```

## 功能清单

| 功能 | 文件 | 关键方法/属性 |
|------|------|--------------|
| 下拉刷新 | `FeedView.swift` | `.refreshable { await viewModel.refreshFeed() }` |
| 无限滚动 | `FeedViewModel.swift` | `loadMoreIfNeeded(currentPost:)` |
| 骨架屏 | `SkeletonLoadingView.swift` | `SkeletonPostList(count: 3)` |
| 乐观更新 | `PostCell.swift` | `handleLikeAction()` |
| 图片懒加载 | `LazyImageView.swift` | `LazyImageView(url:)` |
| 滚动位置恢复 | `FeedView.swift` | `scrollPosition`, `scrollProxy` |
| 快速返回顶部 | `FeedView.swift` | `showScrollToTopButton` |

## 代码片段

### 1. 下拉刷新
```swift
ScrollView {
    // 内容
}
.refreshable {
    await viewModel.refreshFeed()
}
```

### 2. 无限滚动
```swift
PostCell(post: post, onLike: { ... })
    .onAppear {
        Task {
            await viewModel.loadMoreIfNeeded(currentPost: post)
        }
    }
```

### 3. 骨架屏
```swift
if viewModel.isLoading && viewModel.posts.isEmpty {
    ScrollView {
        SkeletonPostList(count: 3)
    }
}
```

### 4. 乐观更新
```swift
// PostCell.swift
@State private var localLikeCount: Int
@State private var localIsLiked: Bool

private func handleLikeAction() {
    localIsLiked.toggle()
    localLikeCount += localIsLiked ? 1 : -1
    onLike() // 调用 API
}
```

### 5. 图片懒加载
```swift
LazyImageView(
    url: post.imageUrl,
    contentMode: .fill,
    enablePrefetch: true
)
```

### 6. 快速返回顶部
```swift
Button {
    withAnimation {
        scrollProxy?.scrollTo("top", anchor: .top)
    }
} label: {
    Text("Nova").font(.title2).fontWeight(.bold)
}
```

## 性能调优参数

| 参数 | 位置 | 默认值 | 说明 |
|------|------|--------|------|
| `prefetchThreshold` | `FeedViewModel.swift` | 5 | 预加载阈值（距底部条数） |
| `maxRetries` | `FeedViewModel.swift` | 3 | 最大重试次数 |
| `totalCostLimit` | `ImageCacheManager` | 100MB | 内存缓存大小 |
| `countLimit` | `ImageCacheManager` | 100 | 最多缓存图片数 |
| `timeout` | `LazyImageView` | 10s | 图片加载超时 |

## 动画配置

```swift
// 弹簧动画（点赞、返回顶部）
.spring(response: 0.3, dampingFraction: 0.6)

// 平滑过渡（列表刷新）
.easeInOut(duration: 0.3)

// 快速淡入（图片加载）
.easeIn(duration: 0.2)
```

## 触觉反馈

```swift
// 轻度反馈（返回顶部）
let impactFeedback = UIImpactFeedbackGenerator(style: .light)
impactFeedback.impactOccurred()

// 中度反馈（点赞、下拉刷新）
let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
impactFeedback.impactOccurred()
```

## 常用命令

### 清除图片缓存
```swift
ImageCacheManager.shared.clearCache()
```

### 查看缓存命中率
```swift
let hitRate = ImageCacheManager.shared.hitRate
print("Cache hit rate: \(hitRate * 100)%")
```

### 强制刷新 Feed
```swift
await viewModel.refreshFeed()
```

### 加载更多
```swift
await viewModel.loadMore()
```

## 调试技巧

### 1. 打印缓存统计
```swift
print("Hits: \(ImageCacheManager.shared.hitCount)")
print("Misses: \(ImageCacheManager.shared.missCount)")
print("Hit Rate: \(ImageCacheManager.shared.hitRate)")
```

### 2. 检查加载状态
```swift
print("Is Loading: \(viewModel.isLoading)")
print("Is Refreshing: \(viewModel.isRefreshing)")
print("Is Loading More: \(viewModel.isLoadingMore)")
print("Has More: \(viewModel.hasMore)")
```

### 3. 模拟慢速网络
```swift
// 在 loadImage() 中添加延迟
try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s
```

## 常见问题速查

**Q: 列表重复加载？**
```swift
// 检查 isCurrentlyLoading 标志
guard !isCurrentlyLoading else { return }
```

**Q: 图片不显示？**
```swift
// 检查 URL 是否有效
print("Image URL: \(post.imageUrl)")

// 检查缓存
if let cached = ImageCacheManager.shared.getImage(for: url) {
    print("Found in cache")
}
```

**Q: 动画卡顿？**
```swift
// 减少动画时长
.animation(.easeIn(duration: 0.1), value: state)

// 或禁用动画
withAnimation(.none) { ... }
```

**Q: 内存占用过高？**
```swift
// 降低缓存限制
memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50MB
memoryCache.countLimit = 50
```

## 关键指标

### 性能目标
- **滚动帧率**: 60 FPS
- **图片加载时间**: < 500ms (缓存命中)
- **网络请求时间**: < 2s (Feed 加载)
- **内存占用**: < 200MB (100 张图片)

### 用户体验目标
- **点赞响应**: 立即（< 50ms）
- **下拉刷新**: 平滑无卡顿
- **滚动平滑**: 无明显延迟
- **动画流畅**: 自然弹性

---

**快速链接**:
- [完整文档](./FeedOptimizationGuide.md)
- [API 文档](../API/FeedAPI.md)
- [架构设计](../Architecture/DataFlow.md)
