# Nova Social - iOS App

完整的 SwiftUI + MVVM 架构的 Instagram 风格社交应用。

## 📁 项目结构

```
NovaSocial/
├── App/                          # 应用入口
│   ├── NovaSocialApp.swift      # App 主入口
│   ├── ContentView.swift        # 根视图（认证/主应用切换）
│   └── AppState.swift           # 全局应用状态（在 NovaSocialApp.swift 中定义）
│
├── ViewModels/                   # MVVM 视图模型层
│   ├── Auth/
│   │   └── AuthViewModel.swift           # 登录/注册状态管理
│   ├── Feed/
│   │   ├── FeedViewModel.swift           # Feed 流状态管理
│   │   └── PostDetailViewModel.swift     # 帖子详情状态管理
│   ├── Post/
│   │   └── CreatePostViewModel.swift     # 创建帖子状态管理
│   ├── User/
│   │   └── UserProfileViewModel.swift    # 用户资料状态管理
│   └── Common/
│       ├── ExploreViewModel.swift        # 探索页状态管理
│       └── NotificationViewModel.swift   # 通知状态管理
│
├── Views/                        # SwiftUI 视图层
│   ├── Auth/                     # 认证相关视图
│   │   ├── AuthenticationView.swift      # 认证容器（登录/注册切换）
│   │   ├── LoginView.swift               # 登录页面
│   │   └── RegisterView.swift            # 注册页面
│   │
│   ├── Feed/                     # Feed 相关视图
│   │   ├── FeedView.swift                # Feed 主页面
│   │   ├── PostCell.swift                # 帖子卡片组件
│   │   └── PostDetailView.swift          # 帖子详情页面
│   │
│   ├── Post/                     # 帖子创建
│   │   └── CreatePostView.swift          # 创建帖子页面
│   │
│   ├── User/                     # 用户相关视图
│   │   ├── ProfileView.swift             # 用户资料页面
│   │   └── SettingsView.swift            # 设置页面
│   │
│   ├── Explore/                  # 探索和通知
│   │   ├── ExploreView.swift             # 探索页面
│   │   └── NotificationView.swift        # 通知页面
│   │
│   └── Common/                   # 可复用组件
│       ├── Styles.swift                  # 按钮和文本框样式
│       ├── LoadingView.swift             # 加载指示器
│       ├── ErrorMessageView.swift        # 错误和空状态组件
│       └── AsyncImageView.swift          # 异步图片加载组件
│
├── Network/                      # 网络层（已存在）
│   ├── Models/                   # 数据模型
│   ├── Core/                     # 核心网络组件
│   ├── Repositories/             # Repository 模式
│   └── Utils/                    # 工具类
│
├── Tests/                        # 测试
└── Examples/                     # 示例代码
```

## 🎯 核心功能

### 1. 认证系统
- ✅ 登录/注册切换
- ✅ 表单验证
- ✅ 错误处理
- ✅ 自动登录状态检查

### 2. Feed 流
- ✅ 无限滚动加载
- ✅ 下拉刷新
- ✅ 帖子点赞（乐观更新）
- ✅ 评论预览
- ✅ 离线缓存支持

### 3. 帖子详情
- ✅ 完整帖子信息
- ✅ 评论列表
- ✅ 添加评论
- ✅ 点赞/取消点赞

### 4. 创建帖子
- ✅ 图片选择器
- ✅ 图片预览
- ✅ 添加标题
- ✅ 上传进度显示
- ✅ 错误处理

### 5. 用户资料
- ✅ 用户信息展示
- ✅ 关注/取消关注
- ✅ 帖子网格
- ✅ 统计数据

### 6. 探索和搜索
- ✅ 探索帖子网格
- ✅ 用户搜索
- ✅ 搜索防抖
- ✅ 搜索结果展示

### 7. 通知
- ✅ 通知列表
- ✅ 未读标记
- ✅ 点击跳转
- ✅ 标记已读

## 🏗 架构特点

### MVVM 模式
- **View**: 纯 SwiftUI，只负责 UI 渲染
- **ViewModel**: 使用 `@MainActor` 确保线程安全，通过 `@Published` 属性发布状态变化
- **Model**: Repository 模式处理数据获取和业务逻辑

### 状态管理
- `@StateObject`: 视图拥有的 ViewModel
- `@EnvironmentObject`: 全局状态（AppState）
- `@Published`: 响应式数据绑定
- Combine: 异步数据流处理

### 导航
- `NavigationStack`: iOS 16+ 新导航系统
- `navigationDestination`: 声明式导航
- `@Environment(\.dismiss)`: 返回导航

### 数据加载策略
1. **离线优先**: 先返回缓存，后台刷新
2. **乐观更新**: 点赞等操作立即更新 UI
3. **错误回滚**: 失败时自动恢复原状态
4. **分页加载**: 触底自动加载更多

## 🎨 UI 组件

### 可复用样式
- `PrimaryButtonStyle`: 主要按钮样式
- `SecondaryButtonStyle`: 次要按钮样式
- `RoundedTextFieldStyle`: 圆角输入框样式

### 通用组件
- `LoadingView`: 加载指示器
- `LoadingOverlay`: 全屏加载遮罩
- `ErrorMessageView`: 错误消息提示
- `EmptyStateView`: 空状态占位
- `AsyncImageView`: 异步图片加载
- `CachedAsyncImage`: 带缓存的图片加载

## 📱 使用方式

### 1. 启动应用

```swift
// 应用会自动检查登录状态
// - 已登录：显示主应用（TabView）
// - 未登录：显示认证界面

@main
struct NovaSocialApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}
```

### 2. ViewModel 使用示例

```swift
// 在 View 中使用 ViewModel
struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()

    var body: some View {
        List(viewModel.posts) { post in
            PostCell(post: post)
        }
        .task {
            await viewModel.loadInitialFeed()
        }
    }
}
```

### 3. 异步操作

```swift
// ViewModel 中的异步方法
@MainActor
func loadFeed() async {
    isLoading = true

    do {
        posts = try await feedRepository.loadFeed()
    } catch {
        errorMessage = error.localizedDescription
    }

    isLoading = false
}
```

### 4. 乐观更新示例

```swift
// 立即更新 UI，后台同步
func toggleLike(for post: Post) {
    // 1. 立即更新本地状态
    updateLocalPost(post, isLiked: !post.isLiked)

    // 2. 后台同步到服务器
    Task {
        do {
            try await postRepository.toggleLike(postId: post.id)
        } catch {
            // 失败时回滚
            updateLocalPost(post, isLiked: post.isLiked)
        }
    }
}
```

## 🔧 自定义配置

### 修改 API 端点

编辑 `Network/Utils/AppConfig.swift`:

```swift
enum AppConfig {
    static let baseURL = "https://your-api.com/api/v1"
}
```

### 修改缓存策略

编辑 `Network/Repositories/FeedRepository.swift`:

```swift
final class FeedCache {
    private let maxCacheSize = 50 // 调整缓存大小
}
```

## 🎯 下一步开发建议

1. **图片缓存优化**
   - 集成 Kingfisher 或 SDWebImage
   - 实现图片压缩和懒加载

2. **离线支持增强**
   - 使用 Core Data 或 Realm
   - 实现完整的离线同步

3. **性能优化**
   - 列表虚拟化
   - 图片预加载
   - 内存管理优化

4. **功能扩展**
   - 故事（Stories）功能
   - 私信系统
   - 视频支持
   - AR 滤镜

5. **测试覆盖**
   - 单元测试（ViewModel 层）
   - UI 测试（SwiftUI 测试）
   - 集成测试

## 📝 注意事项

### 线程安全
所有 ViewModel 都使用 `@MainActor` 标记，确保 UI 更新在主线程执行。

### 内存管理
- 使用 `weak self` 避免循环引用
- 取消不需要的 Task
- 及时释放大对象（图片等）

### 错误处理
每个 ViewModel 都有统一的错误处理机制：
- `errorMessage`: 错误消息
- `showError`: 控制 Alert 显示
- `clearError()`: 清除错误状态

## 🤝 贡献指南

1. 新增功能请遵循现有的 MVVM 结构
2. ViewModel 必须使用 `@MainActor`
3. 异步方法使用 `async/await`，避免回调地狱
4. 所有可复用组件放在 `Views/Common`
5. 遵循 SwiftUI 最佳实践

## 📄 License

MIT License
