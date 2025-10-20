# Nova Social iOS - 快速启动指南

## 🚀 5 分钟快速集成

### 1. 创建 Xcode 项目

```bash
# 在 Xcode 中创建新项目
# 1. File → New → Project
# 2. 选择 iOS → App
# 3. Interface: SwiftUI
# 4. 保存到: /Users/proerror/Documents/nova/ios/NovaSocial
```

### 2. 添加源代码到项目

将以下文件夹拖入 Xcode 项目：

```
✅ App/
✅ ViewModels/
✅ Views/
✅ Network/
```

### 3. 配置 Info.plist

添加相机和相册权限：

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>We need access to your photo library to upload images</string>

<key>NSCameraUsageDescription</key>
<string>We need access to your camera to take photos</string>
```

### 4. 配置 API 端点

编辑 `Network/Utils/AppConfig.swift`:

```swift
enum AppConfig {
    static let baseURL = "http://localhost:8080/api/v1"  // 修改为你的后端地址
}
```

### 5. 运行应用

```bash
# 在 Xcode 中
# 1. 选择模拟器或真机
# 2. Command + R 运行
```

## 📱 应用导航结构

```
App 启动
  ↓
检查登录状态
  ├─ 未登录 → AuthenticationView
  │            ├─ LoginView
  │            └─ RegisterView
  │
  └─ 已登录 → MainTabView
               ├─ FeedView (首页)
               ├─ ExploreView (探索)
               ├─ CreatePostView (创建)
               ├─ NotificationView (通知)
               └─ ProfileView (个人)
```

## 🎯 核心 View 说明

### AuthenticationView
- **位置**: `Views/Auth/AuthenticationView.swift`
- **功能**: 登录/注册切换容器
- **依赖**: `LoginView`, `RegisterView`

### FeedView
- **位置**: `Views/Feed/FeedView.swift`
- **功能**: 首页 Feed 流
- **特性**: 无限滚动、下拉刷新、点赞
- **ViewModel**: `FeedViewModel`

### CreatePostView
- **位置**: `Views/Post/CreatePostView.swift`
- **功能**: 创建新帖子
- **特性**: 图片选择、上传进度、标题
- **ViewModel**: `CreatePostViewModel`

### ProfileView
- **位置**: `Views/User/ProfileView.swift`
- **功能**: 用户资料页
- **特性**: 关注、帖子网格、统计
- **ViewModel**: `UserProfileViewModel`

## 🔌 ViewModel 集成示例

### 方式 1: 简单集成

```swift
import SwiftUI

struct MyView: View {
    @StateObject private var viewModel = MyViewModel()

    var body: some View {
        List(viewModel.items) { item in
            Text(item.name)
        }
        .task {
            await viewModel.loadData()
        }
    }
}
```

### 方式 2: 依赖注入

```swift
import SwiftUI

struct MyView: View {
    @StateObject private var viewModel: MyViewModel

    init(repository: MyRepository = MyRepository()) {
        _viewModel = StateObject(wrappedValue: MyViewModel(repository: repository))
    }

    var body: some View {
        // ...
    }
}
```

### 方式 3: 环境对象

```swift
import SwiftUI

struct ParentView: View {
    @StateObject private var appState = AppState()

    var body: some View {
        ChildView()
            .environmentObject(appState)
    }
}

struct ChildView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        // 可以直接访问 appState
    }
}
```

## 🎨 UI 组件使用

### 1. 按钮样式

```swift
Button("登录") {
    // 动作
}
.buttonStyle(PrimaryButtonStyle())  // 蓝色主按钮

Button("取消") {
    // 动作
}
.buttonStyle(SecondaryButtonStyle())  // 灰色次要按钮
```

### 2. 输入框样式

```swift
TextField("Email", text: $email)
    .textFieldStyle(RoundedTextFieldStyle())  // 圆角背景
```

### 3. 加载状态

```swift
// 全屏加载
if isLoading {
    LoadingView(message: "Loading...")
}

// 遮罩加载
if isUploading {
    LoadingOverlay()
}
```

### 4. 错误提示

```swift
// 内联错误消息
if let error = errorMessage {
    ErrorMessageView(message: error)
}

// Alert 弹窗
.errorAlert(
    isPresented: $viewModel.showError,
    message: viewModel.errorMessage
)
```

### 5. 空状态

```swift
if items.isEmpty {
    EmptyStateView(
        icon: "photo.on.rectangle.angled",
        title: "No Posts Yet",
        message: "Start following people to see their posts"
    )
}
```

### 6. 异步图片

```swift
// 基础异步加载
AsyncImageView(url: imageURL)
    .frame(width: 200, height: 200)
    .cornerRadius(12)

// 带缓存
CachedAsyncImage(url: imageURL)
    .frame(width: 200, height: 200)
    .clipShape(Circle())
```

## 🔄 常见操作模式

### 1. 数据加载

```swift
@MainActor
final class MyViewModel: ObservableObject {
    @Published var items: [Item] = []
    @Published var isLoading = false

    func loadData() async {
        isLoading = true

        do {
            items = try await repository.fetchItems()
        } catch {
            // 错误处理
        }

        isLoading = false
    }
}
```

### 2. 下拉刷新

```swift
ScrollView {
    // 内容
}
.refreshable {
    await viewModel.refreshData()
}
```

### 3. 无限滚动

```swift
LazyVStack {
    ForEach(items) { item in
        ItemView(item: item)
            .onAppear {
                await viewModel.loadMoreIfNeeded(item)
            }
    }
}
```

### 4. 乐观更新

```swift
func toggleLike() {
    // 1. 立即更新 UI
    isLiked.toggle()
    likeCount += isLiked ? 1 : -1

    // 2. 后台同步
    Task {
        do {
            try await repository.updateLike()
        } catch {
            // 失败时回滚
            isLiked.toggle()
            likeCount -= isLiked ? 1 : -1
        }
    }
}
```

### 5. 搜索防抖

```swift
@Published var searchText = "" {
    didSet {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await performSearch()
        }
    }
}
```

## 🐛 调试技巧

### 1. 打印网络请求

```swift
// 在 Network/Utils/Logger.swift 中已实现
Logger.log("API Request: \(url)", level: .debug)
```

### 2. SwiftUI 视图调试

```swift
// 添加到任何 View
.onAppear {
    print("View appeared")
}

.onChange(of: value) { old, new in
    print("Value changed from \(old) to \(new)")
}
```

### 3. ViewModel 状态监控

```swift
@Published var state = State.idle {
    didSet {
        print("State changed: \(oldValue) → \(state)")
    }
}
```

## 📊 性能优化建议

### 1. 列表优化

```swift
// ✅ 使用 LazyVStack/LazyHStack
LazyVStack {
    ForEach(items) { item in
        ItemView(item: item)
    }
}

// ❌ 避免使用 VStack（加载所有内容）
VStack {
    ForEach(items) { item in
        ItemView(item: item)
    }
}
```

### 2. 图片优化

```swift
// 使用缩略图
AsyncImageView(url: post.thumbnailUrl ?? post.imageUrl)

// 限制图片尺寸
image.jpegData(compressionQuality: 0.8)
```

### 3. 避免过度渲染

```swift
// ✅ 使用 Identifiable
ForEach(items) { item in ... }

// ❌ 避免使用索引
ForEach(0..<items.count, id: \.self) { index in ... }
```

## 🔐 安全注意事项

### 1. 敏感信息

```swift
// ❌ 不要硬编码
let apiKey = "sk-1234567890"

// ✅ 使用环境变量或 Keychain
let apiKey = ProcessInfo.processInfo.environment["API_KEY"]
```

### 2. Token 存储

```swift
// Token 已在 AuthManager 中使用 Keychain 存储
// 位置: Network/Core/AuthManager.swift
```

### 3. HTTPS

```swift
// 确保生产环境使用 HTTPS
static let baseURL = "https://api.example.com"
```

## 📚 进阶主题

### 1. 自定义导航

```swift
// 使用 NavigationPath
@State private var path = NavigationPath()

NavigationStack(path: $path) {
    // ...
}
```

### 2. 深链接

```swift
.onOpenURL { url in
    handleDeepLink(url)
}
```

### 3. 后台任务

```swift
.backgroundTask(.appRefresh("refresh")) {
    await refreshData()
}
```

## 🆘 常见问题

### Q: 编译错误 "Cannot find type 'XXX'"
A: 确保所有文件都添加到 Xcode 项目中（Target Membership）

### Q: 图片不显示
A: 检查 Info.plist 权限配置和网络请求

### Q: ViewModel 状态不更新
A: 确保使用了 `@Published` 和 `@MainActor`

### Q: 导航不工作
A: 确保使用 `NavigationStack` 而不是旧的 `NavigationView`

## 📞 技术支持

- 查看完整文档: `README.md`
- 查看示例代码: `Examples/NetworkUsageExamples.swift`
- 查看测试用例: `Tests/NetworkTests.swift`
