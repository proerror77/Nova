# Nova Design System - 快速开始 ⚡

> 3 分钟上手 Nova 设计系统

## 第 1 步: 应用主题 (30 秒)

在你的 `App.swift` 中:

```swift
import SwiftUI

@main
struct YourApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .withThemeManager()  // 👈 添加这一行就完成了!
        }
    }
}
```

✅ **完成!** 你的应用现在支持:
- 浅色/暗黑模式切换
- 主题持久化
- 系统主题跟随

---

## 第 2 步: 使用第一个组件 (1 分钟)

### 创建一个按钮

```swift
import SwiftUI

struct MyView: View {
    var body: some View {
        DSButton("点击我", style: .primary) {
            print("按钮被点击!")
        }
    }
}
```

### 更多按钮样式

```swift
DSButton("主按钮", style: .primary) { }
DSButton("辅助", style: .secondary) { }
DSButton("删除", style: .destructive) { }
DSButton("带图标", icon: "heart.fill") { }
```

---

## 第 3 步: 创建表单 (1.5 分钟)

```swift
struct LoginView: View {
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            // 邮箱输入框
            DSTextField(
                text: $email,
                placeholder: "邮箱",
                icon: "envelope.fill"
            )

            // 密码输入框
            DSTextField(
                text: $password,
                placeholder: "密码",
                icon: "lock.fill",
                isSecure: true
            )

            // 登录按钮
            DSButton("登录", fullWidth: true) {
                login()
            }
        }
        .padding()
    }

    func login() {
        print("登录: \(email)")
    }
}
```

---

## 🎨 访问主题

```swift
@Environment(\.appTheme) var theme

Text("使用主题颜色")
    .foregroundColor(theme.colors.text)
    .font(theme.typography.bodyLarge)
```

---

## 📦 常用组件速查

### 按钮
```swift
DSButton("标题", style: .primary) { }
```

### 输入框
```swift
DSTextField(text: $value, placeholder: "提示")
```

### 卡片
```swift
DSCard {
    Text("卡片内容")
}
```

### 进度条
```swift
DSProgressBar(progress: 0.6, showPercentage: true)
```

### 加载器
```swift
DSLoader(style: .circular)
```

### 列表项
```swift
DSListItem(
    icon: "gear",
    title: "设置",
    showChevron: true
) { }
```

### 空状态
```swift
DSEmptyState(style: .noData)
```

---

## 🔥 进阶技巧

### 使用 Design Tokens

```swift
VStack(spacing: DesignTokens.Spacing.md) {
    // 使用标准间距
}
.padding(DesignTokens.Spacing.lg)
.background(theme.colors.surface)
.cornerRadius(DesignTokens.BorderRadius.md)
```

### 添加动画

```swift
someView
    .fadeIn()
    .slideInFromBottom()
    .buttonPress()
```

### 显示加载状态

```swift
someView.loadingOverlay(isShowing: isLoading, text: "加载中...")
```

---

## 📚 下一步

1. **查看所有组件**: 运行 `ComponentShowcase.swift`
2. **阅读完整文档**: [README.md](README.md)
3. **学习集成**: [INTEGRATION_GUIDE.md](INTEGRATION_GUIDE.md)
4. **查看总结**: [SUMMARY.md](SUMMARY.md)

---

## ❓ 遇到问题?

### Q: 组件没有正确显示主题?
A: 确保在 App 入口添加了 `.withThemeManager()`

### Q: 如何切换主题?
A:
```swift
ThemeManager.shared.setThemeMode(.dark)
ThemeManager.shared.toggleTheme()
```

### Q: 如何查看示例?
A: 运行 `ComponentShowcase.swift` 查看所有组件演示

---

**就这么简单!** 开始使用 Nova 设计系统打造精美的 UI 吧! 🚀

完整功能列表:
- ✅ 15+ 核心组件
- ✅ 100+ 组件变体
- ✅ 130+ Design Tokens
- ✅ 浅色/暗黑主题
- ✅ 15+ 预定义动画
- ✅ 完整文档

**祝你开发愉快!** 🎉
