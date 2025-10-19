# NovaInstagram UI Layer Optimization Guide

## Overview

完整的 SwiftUI UI 层优化方案，包含可重用组件、状态管理、加载指示器和最佳实践。

---

## 📦 Component Library

### 1. Buttons (`NovaButton.swift`)

**可用组件：**

```swift
// 主要操作按钮
NovaPrimaryButton(
    title: "登錄",
    action: { /* action */ },
    isLoading: false,
    isEnabled: true,
    fullWidth: true,
    icon: "checkmark"  // 可选
)

// 次要操作按钮
NovaSecondaryButton(
    title: "取消",
    action: { /* action */ },
    icon: "xmark"
)

// 文本按钮
NovaTextButton(
    title: "忘記密碼？",
    action: { /* action */ },
    color: DesignColors.brandPrimary
)

// 图标按钮
NovaIconButton(
    icon: "heart",
    action: { /* action */ },
    size: 20
)

// 危险操作按钮
NovaDestructiveButton(
    title: "刪除帳號",
    action: { /* action */ },
    isLoading: false
)
```

**使用场景：**
- Primary: 登录、提交、保存等主要操作
- Secondary: 取消、返回等次要操作
- Text: 链接式操作，如"忘记密码"
- Icon: 工具栏、快速操作
- Destructive: 删除、注销等危险操作

---

### 2. Text Fields (`NovaTextField.swift`)

**可用组件：**

```swift
// 标准输入框
NovaTextField(
    placeholder: "用戶名",
    text: $username,
    icon: "person",
    keyboardType: .default,
    autocapitalization: .never,
    errorMessage: validationError,
    onCommit: { /* 提交操作 */ }
)

// 安全输入框（密码）
NovaTextField(
    placeholder: "密碼",
    text: $password,
    icon: "lock",
    isSecure: true
)

// 搜索框
NovaSearchField(
    text: $searchQuery,
    placeholder: "搜索...",
    onSearch: { /* 搜索操作 */ }
)

// 多行文本编辑器
NovaTextEditor(
    placeholder: "分享您的想法...",
    text: $content,
    minHeight: 100,
    maxHeight: 200
)
```

**特性：**
- ✅ 自动聚焦状态样式
- ✅ 内置清除按钮
- ✅ 错误状态显示
- ✅ 图标支持
- ✅ 键盘类型配置

---

### 3. Cards (`NovaCard.swift`)

**可用组件：**

```swift
// 基础卡片容器
NovaCard(padding: 16, hasShadow: true) {
    Text("卡片內容")
}

// 用户卡片
NovaUserCard(
    avatar: "👤",
    username: "John Doe",
    subtitle: "2小時前",
    onTap: { /* 点击操作 */ }
)

// 统计卡片
NovaStatsCard(stats: [
    .init(title: "貼文", value: "1,234"),
    .init(title: "粉絲", value: "54.3K"),
    .init(title: "追蹤", value: "2,134")
])

// 操作卡片
NovaActionCard(
    icon: "gear",
    title: "設置",
    subtitle: "偏好設置和隱私",
    iconColor: .blue,
    action: { /* 操作 */ }
)

// 图片卡片
NovaImageCard(
    emoji: "🎨",
    size: 100,
    onTap: { /* 查看详情 */ }
)
```

---

## 🔄 Loading States (`NovaLoadingState.swift`)

### 加载指示器

```swift
// 全屏加载遮罩
NovaLoadingOverlay(message: "加載中...")

// 内联加载动画
NovaLoadingSpinner(
    size: 24,
    color: DesignColors.brandPrimary
)

// Shimmer 效果（骨架屏基础）
NovaShimmer()
    .frame(height: 100)
    .cornerRadius(8)
```

### 骨架屏组件

```swift
// 帖子卡片骨架屏
NovaPostCardSkeleton()

// 用户列表骨架屏
NovaUserListSkeleton()

// 通用骨架盒子
NovaSkeletonBox(
    width: 200,
    height: 20,
    cornerRadius: 8
)
```

### 下拉刷新指示器

```swift
NovaPullToRefreshIndicator(isRefreshing: viewModel.isRefreshing)
```

**性能优化：**
- ✅ 使用 `LazyVStack` 延迟加载
- ✅ Shimmer 动画使用 `GeometryReader` 优化
- ✅ 最小化重绘区域

---

## 📭 Empty & Error States (`NovaEmptyState.swift`)

### 空状态组件

```swift
// 通用空状态
NovaEmptyState(
    icon: "photo.on.rectangle.angled",
    title: "暫無內容",
    message: "描述信息...",
    actionTitle: "刷新",
    action: { /* 操作 */ }
)

// 专用空状态
NovaEmptyFeed(onRefresh: { /* 刷新 */ })
NovaEmptySearch(searchQuery: "iOS")
NovaEmptyNotifications()
NovaEmptyFollowing(onFindPeople: { /* 发现用户 */ })
NovaEmptySaved()
```

### 错误状态组件

```swift
// 通用错误状态
NovaErrorState(
    error: error,
    onRetry: { /* 重试 */ }
)

// 无网络连接
NovaNoConnection(onRetry: { /* 重试 */ })

// 权限被拒
NovaPermissionDenied(
    permissionType: "相機",
    onSettings: { /* 打开设置 */ }
)
```

### 内联空状态

```swift
NovaInlineEmpty(
    message: "暫無數據",
    icon: "tray"
)
```

---

## 🏗 ViewModel Integration (`FeedViewModel.swift`)

### ViewState 枚举

```swift
enum ViewState<T> {
    case idle       // 初始状态
    case loading    // 加载中
    case loaded(T)  // 加载完成
    case error(Error) // 错误
    case empty      // 空数据
}
```

### 基础 ViewModel 模式

```swift
@MainActor
class FeedViewModel: ObservableObject {
    @Published private(set) var state: ViewState<[PostModel]> = .idle
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingMore = false

    func loadInitialFeed() async { /* ... */ }
    func refresh() async { /* ... */ }
    func loadMore() async { /* ... */ }
}
```

### View 集成示例

```swift
struct EnhancedFeedView: View {
    @StateObject private var viewModel = FeedViewModel()

    var body: some View {
        switch viewModel.state {
        case .idle:
            ProgressView()
        case .loading:
            loadingView
        case .loaded(let posts):
            feedView(posts: posts)
        case .error(let error):
            errorView(error: error)
        case .empty:
            emptyView
        }
    }
}
```

---

## 📱 Complete Implementation Example

### 带下拉刷新和分页的列表

```swift
ScrollView {
    // 刷新指示器
    if viewModel.isRefreshing {
        NovaPullToRefreshIndicator(isRefreshing: true)
    }

    LazyVStack(spacing: 12) {
        ForEach(posts) { post in
            PostCard(post: post)
                .onAppear {
                    // 触发分页加载
                    if post.id == posts.last?.id {
                        Task { await viewModel.loadMore() }
                    }
                }
        }

        // 加载更多指示器
        if viewModel.isLoadingMore {
            HStack {
                NovaLoadingSpinner(size: 20)
                Text("加載更多...")
            }
            .padding()
        }
    }
}
.refreshable {
    await viewModel.refresh()
}
```

---

## 🎯 Best Practices

### 1. 状态管理
- ✅ 使用 `ViewState` 枚举统一管理加载状态
- ✅ 分离 `isRefreshing` 和 `isLoadingMore` 状态
- ✅ 使用 `@MainActor` 确保 UI 更新在主线程

### 2. 性能优化
- ✅ 使用 `LazyVStack` 替代 `VStack`
- ✅ 分页加载避免一次性加载大量数据
- ✅ 骨架屏动画使用 `.repeatForever` 避免重复创建

### 3. 用户体验
- ✅ 提供即时反馈（加载指示器、Toast）
- ✅ 错误状态提供重试按钮
- ✅ 空状态提供明确的操作指引
- ✅ 下拉刷新使用系统 `.refreshable` modifier

### 4. 无障碍支持
- ✅ 所有图标按钮提供 `.accessibilityLabel`
- ✅ 加载状态提供语音描述
- ✅ 错误信息清晰易读

### 5. 测试友好
- ✅ ViewModel 与 View 分离
- ✅ 使用 Mock 数据进行预览
- ✅ 状态可独立测试

---

## 📂 File Structure

```
NovaInstagram/
├── Components/
│   ├── NovaButton.swift          # 按钮组件库
│   ├── NovaTextField.swift       # 输入框组件库
│   ├── NovaCard.swift            # 卡片组件库
│   ├── NovaLoadingState.swift    # 加载状态组件
│   └── NovaEmptyState.swift      # 空状态组件
├── ViewModels/
│   └── FeedViewModel.swift       # Feed ViewModel 示例
├── Views/
│   └── EnhancedFeedView.swift    # 增强版 Feed 视图
└── UI_OPTIMIZATION_GUIDE.md      # 本文档
```

---

## 🚀 Quick Start

### 1. 创建基础 ViewModel

```swift
@MainActor
class MyViewModel: ObservableObject {
    @Published private(set) var state: ViewState<[MyModel]> = .idle

    func load() async {
        state = .loading
        // API 调用...
        state = .loaded(data)
    }
}
```

### 2. 创建 View

```swift
struct MyView: View {
    @StateObject private var viewModel = MyViewModel()

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                NovaPostCardSkeleton() // 骨架屏
            case .loaded(let items):
                List(items) { /* ... */ }
            case .error(let error):
                NovaErrorState(error: error, onRetry: {
                    Task { await viewModel.load() }
                })
            case .empty:
                NovaEmptyState(/* ... */)
            default:
                ProgressView()
            }
        }
        .task { await viewModel.load() }
    }
}
```

### 3. 添加下拉刷新和分页

```swift
ScrollView {
    LazyVStack {
        ForEach(items) { item in
            ItemView(item: item)
                .onAppear {
                    if item.id == items.last?.id {
                        Task { await viewModel.loadMore() }
                    }
                }
        }
    }
}
.refreshable {
    await viewModel.refresh()
}
```

---

## 🎨 Design Tokens

所有组件使用统一的设计系统：

```swift
struct DesignColors {
    static let brandPrimary = Color(red: 0.2, green: 0.5, blue: 0.95)
    static let brandAccent = Color(red: 1.0, green: 0.3, blue: 0.4)
    static let surfaceLight = Color(red: 0.97, green: 0.97, blue: 0.98)
    static let surfaceElevated = Color.white
    static let textPrimary = Color.black
    static let textSecondary = Color.gray
    static let borderLight = Color(red: 0.9, green: 0.9, blue: 0.92)
}
```

---

## 📊 Component Accessibility Checklist

- ✅ **NovaPrimaryButton**: 支持 VoiceOver，禁用状态清晰
- ✅ **NovaTextField**: 提供错误描述，聚焦状态明确
- ✅ **NovaEmptyState**: 清晰的操作指引
- ✅ **NovaLoadingSpinner**: 提供加载状态语音反馈
- ✅ **NovaErrorState**: 错误信息可读性强，提供重试操作

---

## 📝 Notes

- 所有组件支持 iOS 16+
- 使用 `@MainActor` 确保线程安全
- 所有异步操作使用 `async/await`
- 预览模式完整支持 Xcode Previews
- 遵循 Apple Human Interface Guidelines

---

**Updated:** 2025-10-19
**Version:** 1.0.0
