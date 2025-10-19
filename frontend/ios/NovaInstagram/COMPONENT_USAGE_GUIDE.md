# NovaInstagram 组件使用指南

完整的可复用 UI 组件库和状态管理解决方案。

## 目录

1. [基础组件](#基础组件)
2. [头像组件](#头像组件)
3. [加载状态](#加载状态)
4. [列表功能](#列表功能)
5. [状态管理](#状态管理)
6. [完整示例](#完整示例)

---

## 基础组件

### 按钮 (NovaButton.swift)

#### 主要按钮 - Primary Button
```swift
NovaPrimaryButton(
    title: "登录",
    action: { print("Login") },
    isLoading: false,
    isEnabled: true,
    fullWidth: true,
    icon: "arrow.right"
)
```

#### 次要按钮 - Secondary Button
```swift
NovaSecondaryButton(
    title: "取消",
    action: { print("Cancel") },
    fullWidth: true,
    icon: "xmark"
)
```

#### 文本按钮 - Text Button
```swift
NovaTextButton(
    title: "忘记密码？",
    action: { print("Forgot") },
    color: DesignColors.brandPrimary
)
```

#### 图标按钮 - Icon Button
```swift
NovaIconButton(
    icon: "heart",
    action: { print("Like") },
    size: 20,
    color: DesignColors.textPrimary
)
```

#### 危险按钮 - Destructive Button
```swift
NovaDestructiveButton(
    title: "删除账户",
    action: { print("Delete") },
    isLoading: false
)
```

---

### 卡片 (NovaCard.swift)

#### 基础卡片
```swift
NovaCard {
    Text("卡片内容")
        .padding()
}
```

#### 用户卡片
```swift
NovaUserCard(
    avatar: "👤",
    username: "John Doe",
    subtitle: "2小时前",
    size: 44,
    onTap: { print("User tapped") }
)
```

#### 统计卡片
```swift
NovaStatsCard(stats: [
    .init(title: "贴文", value: "1,234"),
    .init(title: "粉丝", value: "54.3K"),
    .init(title: "追蹤", value: "2,134")
])
```

#### 操作卡片
```swift
NovaActionCard(
    icon: "gear",
    title: "设置",
    subtitle: "偏好设置和隐私",
    iconColor: DesignColors.brandPrimary,
    showChevron: true,
    action: { print("Settings") }
)
```

---

### 输入框 (NovaTextField.swift)

#### 标准输入框
```swift
@State private var text = ""

NovaTextField(
    placeholder: "用户名",
    text: $text,
    icon: "person",
    keyboardType: .default,
    autocapitalization: .sentences,
    errorMessage: nil,
    onCommit: { print("Submit") }
)
```

#### 密码输入框
```swift
NovaTextField(
    placeholder: "密码",
    text: $password,
    icon: "lock",
    isSecure: true
)
```

#### 搜索框
```swift
NovaSearchField(
    text: $searchText,
    placeholder: "搜索...",
    onSearch: { print("Search: \(searchText)") }
)
```

#### 多行文本编辑器
```swift
NovaTextEditor(
    placeholder: "分享您的想法...",
    text: $caption,
    minHeight: 100,
    maxHeight: 200
)
```

---

### 空状态 (NovaEmptyState.swift)

#### 通用空状态
```swift
NovaEmptyState(
    icon: "tray",
    title: "暂无内容",
    message: "当前没有任何数据",
    actionTitle: "刷新",
    action: { refresh() },
    iconColor: DesignColors.textSecondary
)
```

#### 专用空状态
```swift
// 空动态
NovaEmptyFeed(onRefresh: { await refresh() })

// 空搜索结果
NovaEmptySearch(searchQuery: "iOS")

// 空通知
NovaEmptyNotifications()

// 无网络连接
NovaNoConnection(onRetry: { retry() })
```

#### 错误状态
```swift
NovaErrorState(
    error: error,
    onRetry: { await loadData() }
)
```

---

## 头像组件

### 基础头像 (NovaAvatar.swift)

#### 标准头像
```swift
NovaAvatar(
    emoji: "👤",
    size: 44,
    backgroundColor: DesignColors.brandPrimary.opacity(0.1),
    borderColor: .white,
    borderWidth: 2
)
```

#### 尺寸预设
```swift
NovaAvatar.sized(.tiny, emoji: "👤")      // 24pt
NovaAvatar.sized(.small, emoji: "👤")     // 32pt
NovaAvatar.sized(.medium, emoji: "👤")    // 44pt
NovaAvatar.sized(.large, emoji: "👤")     // 64pt
NovaAvatar.sized(.xlarge, emoji: "👤")    // 100pt
```

---

### 头像变体

#### 带在线状态
```swift
NovaAvatarWithStatus(
    emoji: "😊",
    size: 64,
    isOnline: true
)
```

#### 带消息徽章
```swift
NovaAvatarWithBadge(
    emoji: "💬",
    size: 60,
    badgeCount: 5
)
```

#### Story 头像
```swift
NovaStoryAvatar(
    emoji: "🎨",
    size: 70,
    hasNewStory: true,
    isSeen: false,
    onTap: { print("Story tapped") }
)
```

#### 头像组（重叠显示）
```swift
NovaAvatarGroup(
    emojis: ["👤", "😊", "🎨", "📱", "🌅"],
    size: 32,
    maxDisplay: 3,  // 显示前3个，其余显示为 +N
    spacing: -8
)
```

#### 可编辑头像
```swift
NovaEditableAvatar(
    emoji: "👤",
    size: 100,
    onEdit: { print("Edit photo") }
)
```

---

## 加载状态

### 加载指示器 (NovaLoadingState.swift)

#### 全屏加载遮罩
```swift
if showLoading {
    NovaLoadingOverlay(message: "处理中...")
}
```

#### 内联加载指示器
```swift
NovaLoadingSpinner(
    size: 24,
    color: DesignColors.brandPrimary,
    lineWidth: 2
)
```

#### 下拉刷新指示器
```swift
NovaPullToRefreshIndicator(isRefreshing: isRefreshing)
```

---

### 骨架屏 (Skeleton Screens)

#### 贴文骨架屏
```swift
NovaPostCardSkeleton()
```

#### 用户列表骨架屏
```swift
NovaUserListSkeleton()
```

#### 通用骨架框
```swift
NovaSkeletonBox(
    width: 200,
    height: 20,
    cornerRadius: 8
)
```

#### Shimmer 效果
```swift
// 自动包含在骨架屏中
Rectangle()
    .fill(Color.gray.opacity(0.2))
    .frame(height: 100)
    .overlay(NovaShimmer())
    .clipShape(RoundedRectangle(cornerRadius: 8))
```

---

## 列表功能

### 下拉刷新 (NovaList.swift)

```swift
NovaRefreshableList(
    onRefresh: {
        await viewModel.refresh()
    }
) {
    VStack {
        ForEach(items) { item in
            ItemView(item: item)
        }
    }
}
```

---

### 无限滚动 + 分页

```swift
NovaInfiniteScrollList(
    items: items,
    isLoading: viewModel.state.isLoading,
    isLoadingMore: viewModel.isLoadingMore,
    hasMore: viewModel.hasMorePages,
    loadMoreThreshold: 3,  // 距离底部3个项目时触发
    onLoadMore: {
        await viewModel.loadMore()
    },
    content: { item in
        ItemView(item: item)
    },
    loadingContent: {
        NovaLoadingSpinner()
    }
)
```

---

### 完整列表方案（刷新 + 分页）

```swift
NovaEnhancedList(
    items: viewModel.items,
    isLoadingMore: viewModel.isLoadingMore,
    hasMore: viewModel.hasMorePages,
    onRefresh: {
        await viewModel.refresh()
    },
    onLoadMore: {
        await viewModel.loadMore()
    },
    content: { item in
        ItemView(item: item)
    }
)
```

---

### 状态化列表（处理所有状态）

```swift
NovaStatefulList(
    state: viewModel.state,
    isLoadingMore: viewModel.isLoadingMore,
    hasMore: viewModel.hasMorePages,
    onRefresh: {
        await viewModel.refresh()
    },
    onLoadMore: {
        await viewModel.loadMore()
    },
    content: { item in
        ItemView(item: item)
    },
    emptyContent: {
        NovaEmptyState(
            icon: "tray",
            title: "暂无数据",
            message: "当前列表为空"
        )
    },
    errorContent: { error in
        NovaErrorState(error: error) {
            await viewModel.loadData()
        }
    }
)
```

---

## 状态管理

### ViewState 枚举

```swift
enum ViewState<T> {
    case idle        // 初始状态
    case loading     // 加载中
    case loaded(T)   // 加载成功
    case error(Error) // 错误
    case empty       // 空数据
}

// 便捷属性
state.isLoading  // Bool
state.data       // T?
state.error      // Error?
```

---

### GenericListViewModel - 列表数据

```swift
class UserListViewModel: GenericListViewModel<User> {
    init() {
        super.init(pageSize: 20) { page, pageSize in
            // 获取数据
            try await api.fetchUsers(page: page, size: pageSize)
        }
    }
}

// 使用
@StateObject private var viewModel = UserListViewModel()

viewModel.loadData()      // 初始加载
viewModel.refresh()       // 刷新
viewModel.loadMore()      // 加载更多
viewModel.updateItem(user) // 更新项目
viewModel.removeItem(user) // 删除项目
viewModel.addItem(user)    // 添加项目
```

---

### SimpleDataViewModel - 单一数据对象

```swift
class ProfileViewModel: SimpleDataViewModel<Profile> {
    init() {
        super.init {
            try await api.fetchProfile()
        }
    }
}

// 使用
@StateObject private var viewModel = ProfileViewModel()

viewModel.loadData()   // 加载数据
viewModel.refresh()    // 刷新
```

---

### FormViewModel - 表单处理

```swift
class LoginFormViewModel: FormViewModel {
    @Published var email = ""
    @Published var password = ""

    func validateEmail() -> Bool {
        guard ValidationRules.required(email) else {
            setError(field: "email", message: "邮箱不能为空")
            return false
        }

        guard ValidationRules.email(email) else {
            setError(field: "email", message: "请输入有效的邮箱地址")
            return false
        }

        clearError(field: "email")
        return true
    }

    func login() async {
        let valid = validateEmail() && validatePassword()
        guard valid else { return }

        await submit {
            try await api.login(email: email, password: password)
        }
    }
}

// 使用
@StateObject private var viewModel = LoginFormViewModel()

NovaTextField(
    placeholder: "邮箱",
    text: $viewModel.email,
    errorMessage: viewModel.validationErrors["email"]
)

NovaPrimaryButton(
    title: "登录",
    action: { await viewModel.login() },
    isLoading: viewModel.formState.isSubmitting
)
```

---

### 验证规则

```swift
// 内置规则
ValidationRules.required(value)
ValidationRules.email(value)
ValidationRules.minLength(6)(value)
ValidationRules.maxLength(100)(value)
ValidationRules.numeric(value)
ValidationRules.alphanumeric(value)
ValidationRules.matches(pattern)(value)

// 使用示例
func validatePassword() -> Bool {
    let rules: [(String) -> Bool] = [
        ValidationRules.required,
        ValidationRules.minLength(8),
        ValidationRules.matches(".*[A-Z].*") // 至少一个大写字母
    ]

    for rule in rules {
        if !rule(password) {
            setError(field: "password", message: "密码格式不正确")
            return false
        }
    }
    return true
}
```

---

## 完整示例

### 示例 1: 用户列表（所有功能）

```swift
struct UserListView: View {
    @StateObject private var viewModel = UserListViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                NovaSectionHeader(
                    title: "用户列表",
                    actionTitle: "查看全部",
                    action: { print("View all") }
                )

                NovaStatefulList(
                    state: viewModel.state,
                    isLoadingMore: viewModel.isLoadingMore,
                    hasMore: viewModel.hasMorePages,
                    onRefresh: { await viewModel.refresh() },
                    onLoadMore: { await viewModel.loadMore() },
                    content: { user in
                        HStack(spacing: 12) {
                            NovaAvatarWithStatus(
                                emoji: user.avatar,
                                size: 50,
                                isOnline: user.isOnline
                            )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.name)
                                    .font(.system(size: 15, weight: .semibold))
                                Text(user.email)
                                    .font(.system(size: 13))
                                    .foregroundColor(DesignColors.textSecondary)
                            }

                            Spacer()

                            NovaSecondaryButton(
                                title: "关注",
                                action: { /* Follow */ },
                                fullWidth: false
                            )
                        }
                        .padding(16)
                    },
                    emptyContent: {
                        NovaEmptyState(
                            icon: "person.2.slash",
                            title: "暂无用户",
                            message: "当前没有找到任何用户"
                        )
                    },
                    errorContent: { error in
                        NovaErrorState(error: error) {
                            await viewModel.loadData()
                        }
                    }
                )
            }
        }
        .task {
            await viewModel.loadData()
        }
    }
}
```

---

### 示例 2: 登录表单

```swift
struct LoginView: View {
    @StateObject private var viewModel = LoginFormViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(DesignColors.brandPrimary)

                Text("欢迎回来")
                    .font(.system(size: 28, weight: .bold))

                VStack(spacing: 16) {
                    NovaTextField(
                        placeholder: "邮箱地址",
                        text: $viewModel.email,
                        icon: "envelope",
                        keyboardType: .emailAddress,
                        autocapitalization: .never,
                        errorMessage: viewModel.validationErrors["email"]
                    )
                    .onChange(of: viewModel.email) { _ in
                        viewModel.clearError(field: "email")
                    }

                    NovaTextField(
                        placeholder: "密码",
                        text: $viewModel.password,
                        icon: "lock",
                        isSecure: true,
                        errorMessage: viewModel.validationErrors["password"]
                    )
                }
                .padding(.horizontal, 24)

                NovaPrimaryButton(
                    title: "登录",
                    action: { await viewModel.login() },
                    isLoading: viewModel.formState.isSubmitting
                )
                .padding(.horizontal, 24)

                if case .error(let message) = viewModel.formState {
                    Text(message)
                        .foregroundColor(.red)
                }
            }
        }
    }
}
```

---

### 示例 3: Story 头像滚动条

```swift
struct StoryScrollView: View {
    let stories = [
        Story(emoji: "🎨", username: "Emma", hasNew: true, isSeen: false),
        Story(emoji: "📱", username: "Alex", hasNew: true, isSeen: true),
        Story(emoji: "🌅", username: "Sarah", hasNew: false, isSeen: false),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(stories) { story in
                    VStack(spacing: 8) {
                        NovaStoryAvatar(
                            emoji: story.emoji,
                            size: 70,
                            hasNewStory: story.hasNew,
                            isSeen: story.isSeen,
                            onTap: { print("Story tapped") }
                        )

                        Text(story.username)
                            .font(.system(size: 12))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
```

---

## 性能优化建议

### 1. 使用 LazyVStack 而非 VStack
```swift
// 好 - 延迟渲染
LazyVStack {
    ForEach(items) { item in
        ItemView(item: item)
    }
}

// 差 - 一次性渲染所有项目
VStack {
    ForEach(items) { item in
        ItemView(item: item)
    }
}
```

### 2. 使用 @StateObject 而非 @ObservedObject
```swift
// 好 - ViewModel 只初始化一次
@StateObject private var viewModel = MyViewModel()

// 差 - 每次视图重建都会重新创建
@ObservedObject var viewModel = MyViewModel()
```

### 3. 避免在列表中创建新视图
```swift
// 好 - 提取为单独的视图
struct ItemView: View {
    let item: Item
    var body: some View { /* ... */ }
}

ForEach(items) { item in
    ItemView(item: item)
}

// 差 - 每次都重建
ForEach(items) { item in
    HStack { /* ... */ }
}
```

### 4. 使用 .task 而非 .onAppear
```swift
// 好 - 支持取消和结构化并发
.task {
    await viewModel.loadData()
}

// 差 - 需要手动管理 Task
.onAppear {
    Task {
        await viewModel.loadData()
    }
}
```

---

## 无障碍支持

所有组件都支持 VoiceOver 和动态字体大小。建议：

```swift
// 为自定义控件添加无障碍标签
Button(action: { /* ... */ }) {
    Image(systemName: "heart")
}
.accessibilityLabel("点赞")
.accessibilityHint("双击以点赞此贴文")

// 为重要元素添加语义
Text(username)
    .accessibilityAddTraits(.isHeader)

// 为装饰性元素隐藏无障碍
Image(systemName: "sparkles")
    .accessibilityHidden(true)
```

---

## 主题自定义

修改 `DesignColors` 以自定义主题：

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

## 测试建议

### 单元测试 ViewModel
```swift
@MainActor
class UserListViewModelTests: XCTestCase {
    func testLoadData() async throws {
        let viewModel = UserListViewModel()

        await viewModel.loadData()

        XCTAssertNotNil(viewModel.state.data)
        XCTAssertGreaterThan(viewModel.state.data?.count ?? 0, 0)
    }

    func testLoadMore() async throws {
        let viewModel = UserListViewModel()

        await viewModel.loadData()
        let initialCount = viewModel.state.data?.count ?? 0

        await viewModel.loadMore()
        let newCount = viewModel.state.data?.count ?? 0

        XCTAssertGreaterThan(newCount, initialCount)
    }
}
```

---

## 常见问题

**Q: 如何自定义骨架屏？**
```swift
// 创建自定义骨架屏
struct CustomSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay(NovaShimmer())
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                NovaSkeletonBox(width: 140, height: 14)
                NovaSkeletonBox(width: 100, height: 12)
            }
        }
    }
}
```

**Q: 如何处理网络错误？**
```swift
// 在 ViewModel 中捕获错误
do {
    let data = try await api.fetch()
    state = .loaded(data)
} catch {
    state = .error(error)
    errorMessage = error.localizedDescription
}

// 在视图中显示错误
if case .error(let error) = viewModel.state {
    NovaErrorState(error: error) {
        await viewModel.retry()
    }
}
```

**Q: 如何实现拉到底部自动加载？**
```swift
// 使用 NovaInfiniteScrollList，它会自动处理
NovaInfiniteScrollList(
    items: items,
    loadMoreThreshold: 3,  // 距离底部3项时触发
    onLoadMore: {
        await viewModel.loadMore()
    },
    content: { item in
        ItemView(item: item)
    }
)
```

---

## 更多资源

- [SwiftUI 官方文档](https://developer.apple.com/documentation/swiftui/)
- [WWDC SwiftUI Sessions](https://developer.apple.com/videos/frameworks/swiftui)
- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)

---

**版本**: 1.0.0
**最后更新**: 2025-10-19
**维护者**: NovaInstagram Team
