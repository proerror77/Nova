# Component Index - 组件索引

> 快速查找和使用 NovaInstagram UI 组件

---

## 📑 目录

- [Buttons 按钮](#buttons-按钮)
- [Text Fields 输入框](#text-fields-输入框)
- [Cards 卡片](#cards-卡片)
- [Loading States 加载状态](#loading-states-加载状态)
- [Empty & Error States 空状态和错误](#empty--error-states-空状态和错误)
- [ViewModels 视图模型](#viewmodels-视图模型)

---

## Buttons 按钮

### NovaPrimaryButton

**用途：** 主要操作按钮（登录、提交、保存）

**参数：**
```swift
title: String               // 按钮文本
action: () -> Void          // 点击事件
isLoading: Bool = false     // 加载状态
isEnabled: Bool = true      // 启用状态
fullWidth: Bool = true      // 是否全宽
icon: String? = nil         // SF Symbol 图标名
```

**示例：**
```swift
NovaPrimaryButton(
    title: "登录",
    action: { login() },
    isLoading: viewModel.isLoading,
    icon: "arrow.right"
)
```

**预览：**
- 默认：蓝色背景，白色文字
- 加载中：显示 ProgressView
- 禁用：灰色背景，不可点击

---

### NovaSecondaryButton

**用途：** 次要操作按钮（取消、返回）

**参数：**
```swift
title: String
action: () -> Void
isEnabled: Bool = true
fullWidth: Bool = true
icon: String? = nil
```

**示例：**
```swift
NovaSecondaryButton(
    title: "取消",
    action: { dismiss() },
    icon: "xmark"
)
```

**预览：**
- 默认：透明背景，蓝色边框和文字
- 禁用：灰色边框和文字

---

### NovaTextButton

**用途：** 文本链接式按钮（忘记密码、了解更多）

**参数：**
```swift
title: String
action: () -> Void
isEnabled: Bool = true
color: Color = DesignColors.brandPrimary
```

**示例：**
```swift
NovaTextButton(
    title: "忘记密码？",
    action: { showPasswordReset() }
)
```

**预览：**
- 默认：蓝色文字，无背景
- 点击：轻微透明度变化

---

### NovaIconButton

**用途：** 图标按钮（工具栏、快速操作）

**参数：**
```swift
icon: String              // SF Symbol 名称
action: () -> Void
size: CGFloat = 20
color: Color = DesignColors.textPrimary
isEnabled: Bool = true
```

**示例：**
```swift
NovaIconButton(
    icon: "heart",
    action: { likePost() },
    size: 22,
    color: .red
)
```

**预览：**
- 最小点击区域：44x44pt
- 图标居中显示

---

### NovaDestructiveButton

**用途：** 危险操作按钮（删除、注销）

**参数：**
```swift
title: String
action: () -> Void
isLoading: Bool = false
fullWidth: Bool = true
```

**示例：**
```swift
NovaDestructiveButton(
    title: "删除账号",
    action: { deleteAccount() },
    isLoading: isDeletingAccount
)
```

**预览：**
- 红色背景，白色文字
- 建议配合确认对话框使用

---

## Text Fields 输入框

### NovaTextField

**用途：** 标准文本输入框

**参数：**
```swift
placeholder: String
text: Binding<String>
icon: String? = nil
isSecure: Bool = false
keyboardType: UIKeyboardType = .default
autocapitalization: TextInputAutocapitalization = .sentences
errorMessage: String? = nil
onCommit: (() -> Void)? = nil
```

**示例：**
```swift
// 普通输入
NovaTextField(
    placeholder: "用户名",
    text: $username,
    icon: "person"
)

// 密码输入
NovaTextField(
    placeholder: "密码",
    text: $password,
    icon: "lock",
    isSecure: true
)

// 带错误提示
NovaTextField(
    placeholder: "邮箱",
    text: $email,
    icon: "envelope",
    keyboardType: .emailAddress,
    errorMessage: emailError
)
```

**特性：**
- 聚焦时边框高亮
- 自动显示清除按钮
- 错误状态红色边框
- 支持回车提交

---

### NovaSearchField

**用途：** 搜索输入框

**参数：**
```swift
text: Binding<String>
placeholder: String = "搜索..."
onSearch: (() -> Void)? = nil
```

**示例：**
```swift
NovaSearchField(
    text: $searchQuery,
    placeholder: "搜索用户、标签...",
    onSearch: { performSearch() }
)
```

**特性：**
- 圆角设计
- 内置搜索图标
- 自动清除按钮

---

### NovaTextEditor

**用途：** 多行文本编辑器

**参数：**
```swift
placeholder: String
text: Binding<String>
minHeight: CGFloat = 100
maxHeight: CGFloat = 200
```

**示例：**
```swift
NovaTextEditor(
    placeholder: "分享你的想法...",
    text: $postContent,
    minHeight: 120,
    maxHeight: 300
)
```

**特性：**
- 可滚动
- 高度自适应
- 占位符支持

---

## Cards 卡片

### NovaCard

**用途：** 基础卡片容器

**参数：**
```swift
padding: CGFloat = 12
backgroundColor: Color = DesignColors.surfaceElevated
hasShadow: Bool = true
content: () -> Content
```

**示例：**
```swift
NovaCard(padding: 16) {
    VStack {
        Text("标题")
        Text("内容")
    }
}
```

---

### NovaUserCard

**用途：** 用户信息卡片

**参数：**
```swift
avatar: String          // Emoji 或图片
username: String
subtitle: String?
size: CGFloat = 44
onTap: (() -> Void)? = nil
```

**示例：**
```swift
NovaUserCard(
    avatar: "👤",
    username: "John Doe",
    subtitle: "iOS 开发者",
    onTap: { showProfile() }
)
```

---

### NovaStatsCard

**用途：** 统计数据卡片

**参数：**
```swift
stats: [Stat]

struct Stat {
    let title: String
    let value: String
}
```

**示例：**
```swift
NovaStatsCard(stats: [
    .init(title: "帖子", value: "1,234"),
    .init(title: "粉丝", value: "54.3K"),
    .init(title: "关注", value: "2,134")
])
```

---

### NovaActionCard

**用途：** 可点击的操作卡片（设置项）

**参数：**
```swift
icon: String
title: String
subtitle: String?
iconColor: Color = DesignColors.brandPrimary
showChevron: Bool = true
action: () -> Void
```

**示例：**
```swift
NovaActionCard(
    icon: "gear",
    title: "设置",
    subtitle: "账号和隐私",
    action: { openSettings() }
)
```

---

### NovaImageCard

**用途：** 图片缩略图卡片

**参数：**
```swift
emoji: String           // 或替换为 Image
size: CGFloat = 100
onTap: (() -> Void)? = nil
```

**示例：**
```swift
NovaImageCard(
    emoji: "🎨",
    size: 120,
    onTap: { viewFullImage() }
)
```

---

## Loading States 加载状态

### NovaLoadingOverlay

**用途：** 全屏加载遮罩

**参数：**
```swift
message: String = "加载中..."
```

**示例：**
```swift
ZStack {
    ContentView()
    if isLoading {
        NovaLoadingOverlay(message: "正在处理...")
    }
}
```

---

### NovaLoadingSpinner

**用途：** 内联加载动画

**参数：**
```swift
size: CGFloat = 24
color: Color = DesignColors.brandPrimary
lineWidth: CGFloat = 2
```

**示例：**
```swift
HStack {
    NovaLoadingSpinner(size: 20)
    Text("加载中...")
}
```

---

### NovaShimmer

**用途：** Shimmer 渐变效果

**参数：**
```swift
baseColor: Color = Color.gray.opacity(0.2)
highlightColor: Color = Color.gray.opacity(0.05)
```

**示例：**
```swift
Rectangle()
    .fill(Color.gray.opacity(0.2))
    .frame(height: 100)
    .overlay(NovaShimmer())
    .clipShape(RoundedRectangle(cornerRadius: 8))
```

---

### NovaPostCardSkeleton

**用途：** 帖子卡片骨架屏

**示例：**
```swift
if viewModel.isLoading {
    ForEach(0..<3, id: \.self) { _ in
        NovaPostCardSkeleton()
    }
}
```

---

### NovaUserListSkeleton

**用途：** 用户列表骨架屏

**示例：**
```swift
if viewModel.isLoading {
    ForEach(0..<5, id: \.self) { _ in
        NovaUserListSkeleton()
    }
}
```

---

### NovaSkeletonBox

**用途：** 通用骨架占位符

**参数：**
```swift
width: CGFloat? = nil
height: CGFloat
cornerRadius: CGFloat = 8
```

**示例：**
```swift
VStack(spacing: 8) {
    NovaSkeletonBox(width: 200, height: 20)
    NovaSkeletonBox(height: 100)
    NovaSkeletonBox(width: 150, height: 16)
}
```

---

### NovaPullToRefreshIndicator

**用途：** 下拉刷新指示器

**参数：**
```swift
isRefreshing: Bool
```

**示例：**
```swift
ScrollView {
    if viewModel.isRefreshing {
        NovaPullToRefreshIndicator(isRefreshing: true)
    }
    // 内容...
}
```

---

## Empty & Error States 空状态和错误

### NovaEmptyState

**用途：** 通用空状态

**参数：**
```swift
icon: String
title: String
message: String
actionTitle: String? = nil
action: (() -> Void)? = nil
iconColor: Color = DesignColors.textSecondary
```

**示例：**
```swift
NovaEmptyState(
    icon: "tray",
    title: "暂无数据",
    message: "尝试刷新或添加新内容",
    actionTitle: "刷新",
    action: { refresh() }
)
```

---

### 预设空状态

#### NovaEmptyFeed
```swift
NovaEmptyFeed(onRefresh: { refresh() })
```

#### NovaEmptySearch
```swift
NovaEmptySearch(searchQuery: "iOS")
```

#### NovaEmptyNotifications
```swift
NovaEmptyNotifications()
```

#### NovaEmptyFollowing
```swift
NovaEmptyFollowing(onFindPeople: { showExplore() })
```

#### NovaEmptySaved
```swift
NovaEmptySaved()
```

---

### NovaErrorState

**用途：** 通用错误状态

**参数：**
```swift
error: Error
onRetry: (() -> Void)? = nil
```

**示例：**
```swift
NovaErrorState(
    error: error,
    onRetry: { Task { await viewModel.reload() } }
)
```

---

### NovaNoConnection

**用途：** 无网络连接状态

**参数：**
```swift
onRetry: () -> Void
```

**示例：**
```swift
NovaNoConnection(onRetry: { checkConnection() })
```

---

### NovaPermissionDenied

**用途：** 权限被拒状态

**参数：**
```swift
permissionType: String
onSettings: () -> Void
```

**示例：**
```swift
NovaPermissionDenied(
    permissionType: "相机",
    onSettings: { openAppSettings() }
)
```

---

### NovaInlineEmpty

**用途：** 内联空状态提示

**参数：**
```swift
message: String
icon: String? = nil
```

**示例：**
```swift
NovaInlineEmpty(
    message: "暂无评论",
    icon: "bubble.left"
)
```

---

## ViewModels 视图模型

### ViewState<T>

**用途：** 统一的视图状态枚举

**枚举值：**
```swift
case idle           // 初始状态
case loading        // 加载中
case loaded(T)      // 数据已加载
case error(Error)   // 错误状态
case empty          // 空数据
```

**辅助属性：**
```swift
var isLoading: Bool       // 是否加载中
var data: T?              // 获取数据
var error: Error?         // 获取错误
```

**示例：**
```swift
@Published private(set) var state: ViewState<[Post]> = .idle

func load() async {
    state = .loading
    do {
        let posts = try await api.fetchPosts()
        state = posts.isEmpty ? .empty : .loaded(posts)
    } catch {
        state = .error(error)
    }
}
```

---

### FeedViewModel

**用途：** Feed 列表的完整 ViewModel 实现

**核心方法：**
```swift
func loadInitialFeed() async     // 初始加载
func refresh() async              // 下拉刷新
func loadMore() async             // 分页加载
func likePost(_ post: PostModel)  // 点赞
func savePost(_ post: PostModel)  // 保存
func deletePost(_ post: PostModel) async // 删除
```

**使用示例：**
```swift
@StateObject private var viewModel = FeedViewModel()

var body: some View {
    switch viewModel.state {
    case .loading:
        NovaPostCardSkeleton()
    case .loaded(let posts):
        List(posts) { /* ... */ }
            .refreshable {
                await viewModel.refresh()
            }
    case .error(let error):
        NovaErrorState(error: error, onRetry: {
            Task { await viewModel.loadInitialFeed() }
        })
    case .empty:
        NovaEmptyFeed(onRefresh: {
            Task { await viewModel.refresh() }
        })
    default:
        ProgressView()
    }
}
```

---

## 🔍 快速查找

### 按使用场景

| 场景 | 推荐组件 |
|------|---------|
| 主要操作 | `NovaPrimaryButton` |
| 次要操作 | `NovaSecondaryButton` |
| 文本输入 | `NovaTextField` |
| 密码输入 | `NovaTextField(isSecure: true)` |
| 搜索功能 | `NovaSearchField` |
| 用户信息 | `NovaUserCard` |
| 统计数据 | `NovaStatsCard` |
| 设置项 | `NovaActionCard` |
| 加载中 | `NovaLoadingSpinner` / `NovaPostCardSkeleton` |
| 空数据 | `NovaEmptyState` / 预设空状态 |
| 错误处理 | `NovaErrorState` |
| 下拉刷新 | `NovaPullToRefreshIndicator` + `.refreshable` |

---

### 按文件位置

| 组件类别 | 文件 |
|---------|------|
| 按钮 | `Components/NovaButton.swift` |
| 输入框 | `Components/NovaTextField.swift` |
| 卡片 | `Components/NovaCard.swift` |
| 加载状态 | `Components/NovaLoadingState.swift` |
| 空状态 | `Components/NovaEmptyState.swift` |
| ViewModel | `ViewModels/FeedViewModel.swift` |

---

## 💡 使用技巧

### 1. 组合使用
```swift
NovaCard {
    NovaUserCard(/* ... */)
}
```

### 2. 条件渲染
```swift
Group {
    if isLoading {
        NovaLoadingSpinner()
    } else if items.isEmpty {
        NovaEmptyState(/* ... */)
    } else {
        List(items) { /* ... */ }
    }
}
```

### 3. 状态管理最佳实践
```swift
// ✅ 推荐
@Published private(set) var state: ViewState<Data> = .idle

// ❌ 避免
@Published var isLoading = false
@Published var error: Error? = nil
@Published var data: Data? = nil
```

---

**最后更新：** 2025-10-19
