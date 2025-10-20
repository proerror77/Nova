# NovaInstagram UI 组件库 - 完整版

> 生产就绪的可复用组件库 - 47个组件，完整状态管理，无限滚动，下拉刷新

---

## 📦 组件清单

### ✅ 已实现组件 (47个)

| 类别 | 组件数 | 文件位置 |
|------|--------|----------|
| 按钮 | 5 | `Components/NovaButton.swift` |
| 卡片 | 5 | `Components/NovaCard.swift` |
| **头像 (新)** | 6 | `Components/NovaAvatar.swift` |
| 输入框 | 3 | `Components/NovaTextField.swift` |
| **列表 (新)** | 7 | `Components/NovaList.swift` |
| 空状态 | 10 | `Components/NovaEmptyState.swift` |
| 加载状态 | 7 | `Components/NovaLoadingState.swift` |
| **ViewModel (新)** | 4 | `ViewModels/BaseViewModel.swift` |

---

## 🆕 新增组件

### 头像组件 (6个)

#### 1. NovaAvatar - 基础头像
```swift
NovaAvatar(
    emoji: "👤",
    size: 44,
    backgroundColor: DesignColors.brandPrimary.opacity(0.1),
    borderColor: .white,
    borderWidth: 2
)

// 尺寸预设
NovaAvatar.sized(.tiny, emoji: "👤")     // 24pt
NovaAvatar.sized(.small, emoji: "👤")    // 32pt
NovaAvatar.sized(.medium, emoji: "👤")   // 44pt
NovaAvatar.sized(.large, emoji: "👤")    // 64pt
NovaAvatar.sized(.xlarge, emoji: "👤")   // 100pt
```

#### 2. NovaAvatarWithStatus - 带在线状态
```swift
NovaAvatarWithStatus(
    emoji: "😊",
    size: 64,
    isOnline: true
)
```

#### 3. NovaAvatarWithBadge - 带消息徽章
```swift
NovaAvatarWithBadge(
    emoji: "💬",
    size: 60,
    badgeCount: 5  // 超过99显示 "99+"
)
```

#### 4. NovaStoryAvatar - Story 头像
```swift
NovaStoryAvatar(
    emoji: "🎨",
    size: 70,
    hasNewStory: true,
    isSeen: false,
    onTap: { print("Story tapped") }
)
```

#### 5. NovaAvatarGroup - 头像组
```swift
NovaAvatarGroup(
    emojis: ["👤", "😊", "🎨", "📱", "🌅"],
    size: 32,
    maxDisplay: 3,  // 显示前3个，其余显示 +2
    spacing: -8
)
```

#### 6. NovaEditableAvatar - 可编辑头像
```swift
NovaEditableAvatar(
    emoji: "👤",
    size: 100,
    onEdit: { print("Edit photo") }
)
```

---

### 列表组件 (7个)

#### 1. NovaRefreshableList - 下拉刷新
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

#### 2. NovaInfiniteScrollList - 无限滚动
```swift
NovaInfiniteScrollList(
    items: items,
    isLoading: viewModel.state.isLoading,
    isLoadingMore: viewModel.isLoadingMore,
    hasMore: viewModel.hasMorePages,
    loadMoreThreshold: 3,  // 距离底部3项时触发
    onLoadMore: {
        await viewModel.loadMore()
    },
    content: { item in
        ItemView(item: item)
    }
)
```

#### 3. NovaEnhancedList - 完整列表方案
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

#### 4. NovaStatefulList - 状态化列表
```swift
NovaStatefulList(
    state: viewModel.state,
    isLoadingMore: viewModel.isLoadingMore,
    hasMore: viewModel.hasMorePages,
    onRefresh: { await viewModel.refresh() },
    onLoadMore: { await viewModel.loadMore() },
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

#### 5. NovaEndOfListView - 列表结束标识
```swift
NovaEndOfListView(message: "没有更多内容了")
```

#### 6. NovaSeparator - 分隔线
```swift
NovaSeparator(
    color: DesignColors.borderLight,
    height: 1
)
```

#### 7. NovaSectionHeader - 区域标题
```swift
NovaSectionHeader(
    title: "推荐用户",
    actionTitle: "查看全部",
    action: { print("View all") }
)
```

---

### ViewModel (4个)

#### 1. ViewState<T> - 统一状态枚举
```swift
enum ViewState<T> {
    case idle        // 初始状态
    case loading     // 加载中
    case loaded(T)   // 加载成功
    case error(Error) // 错误
    case empty       // 空数据
}

// 使用
@Published private(set) var state: ViewState<[Item]> = .idle
```

#### 2. GenericListViewModel - 列表 ViewModel
```swift
class UserListViewModel: GenericListViewModel<User> {
    init() {
        super.init(pageSize: 20) { page, pageSize in
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

#### 3. SimpleDataViewModel - 简单数据 ViewModel
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

viewModel.loadData()   // 加载
viewModel.refresh()    // 刷新
```

#### 4. FormViewModel - 表单 ViewModel
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

## 🎯 完整使用示例

### 示例 1: 用户列表（全功能）

```swift
struct UserListView: View {
    @StateObject private var viewModel = UserListViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 区域标题
                NovaSectionHeader(
                    title: "用户列表",
                    actionTitle: "查看全部",
                    action: { print("View all") }
                )

                // 状态化列表
                NovaStatefulList(
                    state: viewModel.state,
                    isLoadingMore: viewModel.isLoadingMore,
                    hasMore: viewModel.hasMorePages,
                    onRefresh: { await viewModel.refresh() },
                    onLoadMore: { await viewModel.loadMore() },
                    content: { user in
                        // 用户行
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

### 示例 2: 登录表单

```swift
struct LoginView: View {
    @StateObject private var viewModel = LoginFormViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Logo
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(DesignColors.brandPrimary)
                    .padding(.top, 40)

                // 标题
                VStack(spacing: 8) {
                    Text("欢迎回来")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(DesignColors.textPrimary)

                    Text("登录您的账户以继续")
                        .font(.system(size: 15))
                        .foregroundColor(DesignColors.textSecondary)
                }

                // 表单
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

                    HStack {
                        Spacer()
                        NovaTextButton(
                            title: "忘记密码？",
                            action: { print("Forgot password") }
                        )
                    }
                }
                .padding(.horizontal, 24)

                // 登录按钮
                VStack(spacing: 12) {
                    NovaPrimaryButton(
                        title: "登录",
                        action: { await viewModel.login() },
                        isLoading: viewModel.formState.isSubmitting
                    )
                    .padding(.horizontal, 24)

                    // 错误提示
                    if case .error(let message) = viewModel.formState {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(message)
                        }
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                    }

                    // 成功提示
                    if case .success = viewModel.formState {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("登录成功！")
                        }
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                dismiss()
                            }
                        }
                    }
                }

                // 注册链接
                HStack(spacing: 4) {
                    Text("还没有账户？")
                        .font(.system(size: 14))
                        .foregroundColor(DesignColors.textSecondary)

                    NovaTextButton(
                        title: "立即注册",
                        action: { print("Sign up") }
                    )
                }

                Spacer()
            }
            .padding(.bottom, 40)
        }
        .background(DesignColors.surfaceLight)
    }
}
```

### 示例 3: Story 滚动条

```swift
struct StoryScrollView: View {
    let stories = [
        Story(emoji: "🎨", username: "Emma", hasNew: true, isSeen: false),
        Story(emoji: "📱", username: "Alex", hasNew: true, isSeen: true),
        Story(emoji: "🌅", username: "Sarah", hasNew: false, isSeen: false),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stories")
                .font(.system(size: 18, weight: .bold))
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    // 添加 Story 按钮
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(DesignColors.surfaceElevated)
                                .frame(width: 70, height: 70)

                            Image(systemName: "plus")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(DesignColors.brandPrimary)
                        }

                        Text("你的")
                            .font(.system(size: 12))
                    }

                    // 其他用户的 Story
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
}
```

---

## 🔧 验证规则

```swift
// 内置规则
ValidationRules.required(value)
ValidationRules.email(value)
ValidationRules.minLength(6)(value)
ValidationRules.maxLength(100)(value)
ValidationRules.numeric(value)
ValidationRules.alphanumeric(value)
ValidationRules.matches(pattern)(value)

// 自定义规则
func validatePassword() -> Bool {
    let rules: [(String) -> Bool] = [
        ValidationRules.required,
        ValidationRules.minLength(8),
        ValidationRules.matches(".*[A-Z].*"), // 至少一个大写字母
        ValidationRules.matches(".*[0-9].*")  // 至少一个数字
    ]

    for rule in rules {
        if !rule(password) {
            setError(field: "password", message: "密码格式不正确")
            return false
        }
    }

    clearError(field: "password")
    return true
}
```

---

## 🎨 设计系统

### 颜色
```swift
DesignColors.brandPrimary       // #3380F2 - 主品牌色
DesignColors.brandAccent        // #FF4D66 - 强调色
DesignColors.surfaceLight       // #F7F7F9 - 浅色背景
DesignColors.surfaceElevated    // #FFFFFF - 卡片背景
DesignColors.textPrimary        // #000000 - 主文本
DesignColors.textSecondary      // Gray - 次要文本
DesignColors.borderLight        // #E6E6EB - 边框
```

### 间距
```swift
4pt   // Tiny
8pt   // Compact
12pt  // Default
16pt  // Comfortable
24pt  // Spacious
32pt  // Large
```

### 圆角
```swift
8pt   // Small (icons, images)
12pt  // Medium (buttons, cards)
16pt  // Large (sheets, dialogs)
20pt  // XLarge (search bars)
50%   // Round (avatars)
```

---

## 📱 性能优化

### 1. 使用 LazyVStack
```swift
// ✅ 好 - 延迟渲染
LazyVStack {
    ForEach(items) { item in ItemView(item: item) }
}

// ❌ 差 - 一次性渲染所有
VStack {
    ForEach(items) { item in ItemView(item: item) }
}
```

### 2. 使用 @StateObject
```swift
// ✅ 好
@StateObject private var viewModel = MyViewModel()

// ❌ 差
@ObservedObject var viewModel = MyViewModel()
```

### 3. 提取子视图
```swift
// ✅ 好
struct ItemView: View {
    let item: Item
    var body: some View { /* ... */ }
}

// ❌ 差
ForEach(items) { item in
    HStack { /* 复杂布局 */ }
}
```

### 4. 使用 .task
```swift
// ✅ 好
.task { await viewModel.loadData() }

// ❌ 差
.onAppear { Task { await viewModel.loadData() } }
```

---

## 📚 文档

- **组件索引**: `COMPONENT_INDEX.md`
- **使用指南**: `COMPONENT_USAGE_GUIDE.md`
- **优化指南**: `UI_OPTIMIZATION_GUIDE.md`
- **README**: `README.md`

---

## ✅ 检查清单

- [x] 5个按钮组件
- [x] 5个卡片组件
- [x] 6个头像组件
- [x] 3个输入框组件
- [x] 7个列表组件
- [x] 10个空状态组件
- [x] 7个加载状态组件
- [x] 4个 ViewModel
- [x] 完整文档
- [x] 使用示例
- [x] 性能优化指南

---

**版本**: 2.0.0
**最后更新**: 2025-10-19
**状态**: ✅ 生产就绪
**组件总数**: 47
