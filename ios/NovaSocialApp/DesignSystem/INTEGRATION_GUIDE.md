# Nova Design System - 集成指南

> 5 分钟快速集成 Nova 设计系统到你的 SwiftUI 项目

## 快速开始

### 第 1 步: 应用主题管理器

在你的 App 入口文件添加主题管理:

```swift
import SwiftUI

@main
struct YourApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .withThemeManager()  // 👈 添加这一行
        }
    }
}
```

就是这样!你的应用现在已经支持:
- ✅ 浅色/暗黑模式切换
- ✅ 系统主题跟随
- ✅ 主题偏好持久化
- ✅ 全局主题访问

### 第 2 步: 使用第一个组件

```swift
import SwiftUI

struct MyView: View {
    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            DSButton("点击我", style: .primary) {
                print("按钮被点击")
            }
        }
    }
}
```

## 常见场景

### 场景 1: 创建登录表单

```swift
struct LoginView: View {
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            DSTextField(
                text: $email,
                placeholder: "邮箱",
                icon: "envelope.fill"
            )

            DSTextField(
                text: $password,
                placeholder: "密码",
                icon: "lock.fill",
                isSecure: true
            )

            DSButton("登录", fullWidth: true) {
                handleLogin()
            }
        }
        .padding(DesignTokens.Spacing.xl)
    }

    private func handleLogin() {
        // 你的登录逻辑
    }
}
```

### 场景 2: 显示卡片列表

```swift
struct FeedView: View {
    let posts: [Post]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: DesignTokens.Spacing.md) {
                ForEach(posts) { post in
                    DSCard {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                            Text(post.title)
                                .font(.headline)
                            Text(post.content)
                                .font(.body)
                        }
                    }
                }
            }
            .padding()
        }
    }
}
```

### 场景 3: 带加载状态的按钮

```swift
struct SubmitView: View {
    @State private var isLoading = false

    var body: some View {
        DSButton("提交", isLoading: isLoading) {
            submitData()
        }
    }

    private func submitData() {
        isLoading = true

        // 模拟网络请求
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isLoading = false
        }
    }
}
```

### 场景 4: 空状态页面

```swift
struct SearchResultsView: View {
    let results: [SearchResult]

    var body: some View {
        if results.isEmpty {
            DSEmptyState(
                style: .noResults,
                actionTitle: "清除筛选"
            ) {
                clearFilters()
            }
        } else {
            // 显示结果列表
        }
    }
}
```

### 场景 5: 设置页面

```swift
struct SettingsView: View {
    @State private var notificationsEnabled = true
    @State private var darkModeEnabled = false

    var body: some View {
        List {
            DSSectionHeader("通知设置")

            DSListItem(
                title: "推送通知",
                subtitle: "接收新消息提醒",
                isOn: $notificationsEnabled
            )

            DSListItem(
                icon: "moon.fill",
                iconColor: .purple,
                title: "暗黑模式",
                showChevron: true
            ) {
                toggleDarkMode()
            }
        }
    }
}
```

## 主题切换

### 方法 1: 使用 ThemeManager (推荐)

```swift
struct SettingsView: View {
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        Picker("主题", selection: $themeManager.themeMode) {
            ForEach(AppTheme.Mode.allCases) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
    }
}
```

### 方法 2: 快速切换

```swift
// 切换到下一个主题
ThemeManager.shared.toggleTheme()

// 设置特定主题
ThemeManager.shared.setThemeMode(.dark)

// 重置为系统主题
ThemeManager.shared.resetToSystemTheme()
```

## 访问主题

```swift
struct CustomView: View {
    @Environment(\.appTheme) var theme

    var body: some View {
        VStack {
            Text("使用主题颜色")
                .foregroundColor(theme.colors.text)

            Text("使用主题字体")
                .font(theme.typography.bodyLarge)

            Text("检查是否为暗黑模式")
                .foregroundColor(theme.isDarkMode ? .white : .black)
        }
    }
}
```

## 自定义样式

### 扩展现有组件

```swift
extension DSButton {
    static func instagram(
        _ title: String,
        action: @escaping () -> Void
    ) -> DSButton {
        DSButton(
            title,
            icon: "camera.fill",
            style: .primary,
            fullWidth: true,
            action: action
        )
    }
}

// 使用
DSButton.instagram("分享到 Instagram") {
    shareToInstagram()
}
```

### 创建自定义修饰符

```swift
struct CustomCardModifier: ViewModifier {
    @Environment(\.appTheme) var theme

    func body(content: Content) -> some View {
        content
            .padding(DesignTokens.Spacing.lg)
            .background(theme.colors.cardBackground)
            .cornerRadius(DesignTokens.BorderRadius.xl)
            .shadow(
                color: theme.colors.primary.opacity(0.1),
                radius: 10,
                x: 0,
                y: 5
            )
    }
}

extension View {
    func customCard() -> some View {
        modifier(CustomCardModifier())
    }
}

// 使用
someView.customCard()
```

## 动画使用

### 基础动画

```swift
struct AnimatedView: View {
    @State private var isVisible = false

    var body: some View {
        VStack {
            if isVisible {
                Text("淡入出现")
                    .fadeIn()
            }

            DSButton("显示") {
                withAnimation {
                    isVisible.toggle()
                }
            }
        }
    }
}
```

### 列表项动画

```swift
ForEach(items) { item in
    ItemRow(item: item)
        .listRowInsert()
}
.onDelete { indices in
    items.remove(atOffsets: indices)
}
```

### 错误抖动

```swift
struct FormView: View {
    @State private var hasError = false

    var body: some View {
        DSTextField(text: $input)
            .shake(trigger: hasError)

        DSButton("提交") {
            if !isValid {
                hasError.toggle()
            }
        }
    }
}
```

## 响应式布局

### 方法 1: 使用预定义修饰符

```swift
someView.responsivePadding()
```

### 方法 2: 自定义响应式逻辑

```swift
struct ResponsiveView: View {
    @Environment(\.horizontalSizeClass) var sizeClass

    var columns: Int {
        sizeClass == .compact ? 2 : 4
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(), count: columns)) {
            // 网格内容
        }
    }
}
```

## 性能优化

### 1. 使用骨架屏而非加载器

```swift
@State private var isLoading = true
@State private var data: [Item] = []

var body: some View {
    if isLoading {
        DSSkeletonList(count: 5, cardStyle: .post)
    } else {
        List(data) { item in
            ItemRow(item: item)
        }
    }
}
```

### 2. 懒加载大列表

```swift
ScrollView {
    LazyVStack {  // 👈 使用 LazyVStack
        ForEach(largeDataSet) { item in
            DSCard {
                // 内容
            }
        }
    }
}
```

### 3. 避免重复创建主题

```swift
// ❌ 错误: 每次都创建新主题
var body: some View {
    someView.appTheme(AppTheme())
}

// ✅ 正确: 使用共享主题管理器
var body: some View {
    someView.withThemeManager()
}
```

## 调试技巧

### 1. 显示边框调试布局

```swift
#if DEBUG
someView.debugBorder(.red)
someView.debugBackground(.blue.opacity(0.2))
#endif
```

### 2. 检查主题状态

```swift
@EnvironmentObject var themeManager: ThemeManager

var body: some View {
    VStack {
        Text("当前模式: \(themeManager.themeMode.rawValue)")
        Text("是否暗黑: \(themeManager.isDarkMode ? "是" : "否")")
    }
}
```

## 常见问题

### Q: 组件颜色没有随主题变化?

A: 确保使用了 `@Environment(\.appTheme)` 访问主题,而不是直接使用 `ThemeManager.shared`:

```swift
// ❌ 错误
let theme = ThemeManager.shared.currentTheme

// ✅ 正确
@Environment(\.appTheme) var theme
```

### Q: 如何在 Previews 中测试暗黑模式?

A: 使用预定义的主题管理器:

```swift
#Preview {
    YourView()
        .environmentObject(ThemeManager.previewDark)
        .appTheme(ThemeManager.previewDark.currentTheme)
}
```

### Q: 如何自定义组件默认样式?

A: 修改 `DesignTokens.swift` 中的相应值,或创建组件的扩展方法。

### Q: 支持 iPad 吗?

A: 完全支持!所有组件都会根据 `horizontalSizeClass` 自动调整。

## 下一步

- 📖 阅读完整文档: [README.md](README.md)
- 🎨 查看组件展示: 运行 `ComponentShowcase.swift`
- 🔧 自定义主题: 修改 `AppTheme.swift`
- 🚀 开始构建: 使用设计系统打造你的界面!

## 帮助与支持

遇到问题?

1. 查看 [README.md](README.md) 完整文档
2. 运行 ComponentShowcase 查看示例
3. 联系设计系统团队

---

**祝你构建愉快!** 🎉
