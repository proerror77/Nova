# Nova iOS Design System

> 企业级 SwiftUI 设计系统 - 为 Nova 社交媒体应用打造

## 📋 目录

- [概述](#概述)
- [设计原则](#设计原则)
- [快速开始](#快速开始)
- [Design Tokens](#design-tokens)
- [主题系统](#主题系统)
- [组件库](#组件库)
- [动画系统](#动画系统)
- [最佳实践](#最佳实践)
- [示例代码](#示例代码)

## 概述

Nova iOS Design System 是一套完整的、可扩展的设计系统,包含:

- **Design Tokens**: 颜色、字体、间距、阴影等设计基础元素
- **主题管理**: 浅色/暗黑模式切换,系统主题跟随
- **组件库**: 30+ 可复用的 UI 组件
- **动画系统**: 预定义的转场和交互动画
- **响应式布局**: 从 iPhone SE 到 iPad 的全面适配

## 设计原则

### 1. 一致性 (Consistency)
所有组件遵循统一的设计语言,使用相同的 Tokens 和样式规范。

### 2. 可访问性 (Accessibility)
符合 WCAG 2.1 AA 标准,支持动态字体、VoiceOver、高对比度模式。

### 3. 性能优先 (Performance)
组件经过优化,避免不必要的重渲染,支持大列表虚拟化。

### 4. 可扩展性 (Extensibility)
基于协议设计,易于扩展和自定义。

## 快速开始

### 安装

设计系统已集成到项目中,无需额外安装。

### 基础使用

#### 1. 应用主题管理器

在 App 入口添加主题管理:

```swift
import SwiftUI

@main
struct NovaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .withThemeManager()  // 👈 添加这一行
        }
    }
}
```

#### 2. 使用组件

```swift
import SwiftUI

struct MyView: View {
    @Environment(\.appTheme) var theme

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            // 按钮
            DSButton("登录", icon: "arrow.right") {
                // 处理点击
            }

            // 输入框
            DSTextField(
                text: $username,
                placeholder: "用户名",
                icon: "person.fill"
            )

            // 卡片
            DSCard {
                Text("卡片内容")
            }
        }
    }
}
```

#### 3. 访问主题

```swift
@Environment(\.appTheme) var theme

// 使用主题颜色
Text("标题")
    .foregroundColor(theme.colors.text)

// 使用主题字体
Text("内容")
    .font(theme.typography.bodyLarge)
```

## Design Tokens

### 颜色系统 (Colors)

```swift
// 品牌主色
DesignTokens.Colors.Primary.primary500  // #2196F3

// 辅助色
DesignTokens.Colors.Secondary.secondary500  // #9C27B0

// 强调色
DesignTokens.Colors.Accent.success  // #4CAF50
DesignTokens.Colors.Accent.warning  // #FF9800
DesignTokens.Colors.Accent.error    // #F44336

// 中性色
DesignTokens.Colors.Neutral.neutral0    // #FFFFFF
DesignTokens.Colors.Neutral.neutral900  // #111827
```

### 间距系统 (Spacing)

基于 8px 基准:

```swift
DesignTokens.Spacing.xs   // 4pt  (0.5x)
DesignTokens.Spacing.sm   // 8pt  (1x)
DesignTokens.Spacing.md   // 16pt (2x)
DesignTokens.Spacing.lg   // 24pt (3x)
DesignTokens.Spacing.xl   // 32pt (4x)
DesignTokens.Spacing.xl2  // 40pt (5x)
DesignTokens.Spacing.xl3  // 48pt (6x)
```

### 字体系统 (Typography)

```swift
// 超大标题
theme.typography.displayLarge   // 60pt, Bold
theme.typography.displayMedium  // 48pt, Bold
theme.typography.displaySmall   // 36pt, Bold

// 标题
theme.typography.headlineLarge  // 30pt, Semibold
theme.typography.headlineMedium // 24pt, Semibold
theme.typography.headlineSmall  // 20pt, Semibold

// 小标题
theme.typography.titleLarge     // 18pt, Medium
theme.typography.titleMedium    // 16pt, Medium
theme.typography.titleSmall     // 14pt, Medium

// 正文
theme.typography.bodyLarge      // 16pt, Regular
theme.typography.bodyMedium     // 14pt, Regular
theme.typography.bodySmall      // 12pt, Regular

// 标签
theme.typography.labelLarge     // 14pt, Medium
theme.typography.labelMedium    // 12pt, Medium
theme.typography.labelSmall     // 10pt, Medium
```

### 圆角系统 (Border Radius)

```swift
DesignTokens.BorderRadius.xs    // 4pt
DesignTokens.BorderRadius.sm    // 8pt
DesignTokens.BorderRadius.md    // 12pt
DesignTokens.BorderRadius.lg    // 16pt
DesignTokens.BorderRadius.xl    // 24pt
DesignTokens.BorderRadius.full  // 9999pt (Circle)
```

### 阴影系统 (Shadows)

```swift
DesignTokens.Shadow.sm  // 轻阴影
DesignTokens.Shadow.md  // 中阴影
DesignTokens.Shadow.lg  // 重阴影
DesignTokens.Shadow.xl  // 超重阴影
```

## 主题系统

### 主题模式

```swift
// 系统提供三种主题模式
enum Mode {
    case light   // 浅色模式
    case dark    // 暗黑模式
    case system  // 跟随系统
}

// 切换主题
ThemeManager.shared.setThemeMode(.dark)

// 切换到下一个主题
ThemeManager.shared.toggleTheme()
```

### 自定义主题颜色

主题颜色会根据模式自动适配:

```swift
@Environment(\.appTheme) var theme

// 这些颜色会自动适配浅色/暗黑模式
theme.colors.primary      // 主色
theme.colors.background   // 背景色
theme.colors.surface      // 表面色
theme.colors.text         // 文本色
theme.colors.border       // 边框色
```

## 组件库

### 按钮 (Buttons)

#### DSButton - 标准按钮

```swift
// 基础按钮
DSButton("点击我") { }

// 不同样式
DSButton("主按钮", style: .primary) { }
DSButton("辅助按钮", style: .secondary) { }
DSButton("幽灵按钮", style: .ghost) { }
DSButton("轮廓按钮", style: .outline) { }
DSButton("危险按钮", style: .destructive) { }

// 不同尺寸
DSButton("小按钮", size: .small) { }
DSButton("中按钮", size: .medium) { }
DSButton("大按钮", size: .large) { }

// 带图标
DSButton("收藏", icon: "heart.fill") { }
DSButton("下一步", icon: "arrow.right", iconPosition: .trailing) { }

// 加载状态
DSButton("提交", isLoading: true) { }

// 全宽按钮
DSButton("登录", fullWidth: true) { }
```

#### DSIconButton - 图标按钮

```swift
DSIconButton(icon: "heart.fill", style: .primary) { }
```

#### DSFloatingActionButton - 浮动操作按钮

```swift
DSFloatingActionButton(icon: "plus") { }
```

### 输入框 (Text Fields)

#### DSTextField - 文本输入框

```swift
@State private var text = ""

// 基础输入框
DSTextField(text: $text, placeholder: "请输入")

// 带图标
DSTextField(
    text: $text,
    placeholder: "用户名",
    icon: "person.fill"
)

// 密码输入框
DSTextField(
    text: $password,
    placeholder: "密码",
    icon: "lock.fill",
    isSecure: true
)

// 错误状态
DSTextField(
    text: $email,
    placeholder: "邮箱",
    isError: true,
    errorMessage: "邮箱格式不正确"
)
```

### 卡片 (Cards)

#### DSCard - 基础卡片

```swift
DSCard {
    VStack {
        Text("标题")
        Text("内容")
    }
}

// 自定义样式
DSCard(padding: 20, cornerRadius: 16) {
    // 内容
}
```

### 徽章 (Badges)

#### DSBadge - 徽章组件

```swift
DSBadge("新", color: .red)
DSBadge("99+", style: .filled)
DSBadge("Hot", style: .outlined, color: .orange)
```

### 警告框 (Alerts)

#### DSAlert - 警告框

```swift
DSAlert(
    type: .success,
    title: "成功",
    message: "操作已完成"
)

DSAlert(
    type: .error,
    title: "错误",
    message: "操作失败,请重试"
)
```

### Toast - 提示消息

#### DSToast - Toast 组件

```swift
DSToast(
    message: "保存成功",
    type: .success,
    isShowing: $showToast
)
```

### 进度条 (Progress Bars)

#### DSProgressBar - 进度条

```swift
// 线性进度条
DSProgressBar(progress: 0.6)
DSProgressBar(progress: 0.8, showPercentage: true)

// 圆形进度条
DSProgressBar(progress: 0.5, style: .circular, showPercentage: true)

// 分段进度条
DSSegmentedProgressBar(totalSteps: 5, currentStep: 2)
```

### 加载器 (Loaders)

#### DSLoader - 加载指示器

```swift
// 不同样式
DSLoader(style: .circular)
DSLoader(style: .dots)
DSLoader(style: .bars)
DSLoader(style: .pulse)
DSLoader(style: .spinner)

// 全屏加载遮罩
someView.loadingOverlay(isShowing: isLoading, text: "加载中...")
```

### 分隔符 (Dividers)

#### DSDivider - 分隔符

```swift
// 基础分隔符
DSDivider()

// 垂直分隔符
DSDivider(direction: .vertical).frame(height: 50)

// 虚线
DSDivider(style: .dashed)

// 带文本的分隔符
DSTextDivider("或")

// 带图标的分隔符
DSIconDivider(icon: "star.fill")

// 内嵌分隔符(列表常用)
DSInsetDivider(leadingInset: 64)
```

### 骨架屏 (Skeletons)

#### DSSkeleton - 骨架屏

```swift
// 基础形状
DSSkeleton(width: 200, height: 20)

// 预设
DSSkeleton.text(lines: 3)
DSSkeleton.avatar(size: 60)
DSSkeleton.image(height: 200)
DSSkeleton.button()

// 卡片模板
DSSkeletonCard(style: .post)
DSSkeletonCard(style: .profile)
DSSkeletonCard(style: .article)

// 列表
DSSkeletonList(count: 3, cardStyle: .post)
```

### 列表项 (List Items)

#### DSListItem - 列表行

```swift
// 带图标
DSListItem(
    icon: "gear",
    title: "设置",
    subtitle: "应用偏好设置",
    showChevron: true
) { }

// 带头像
DSListItem(
    avatarURL: nil,
    title: "用户名",
    subtitle: "最后活跃时间",
    showChevron: true
) { }

// 带开关
DSListItem(
    title: "通知",
    subtitle: "接收推送通知",
    isOn: $notificationsEnabled
)

// 带徽章
DSListItem(
    title: "消息",
    badgeText: "5",
    badgeColor: .red
) { }
```

#### DSEmptyState - 空状态

```swift
DSEmptyState(
    style: .noData,
    actionTitle: "刷新"
) {
    // 刷新操作
}

DSEmptyState(style: .noResults)
DSEmptyState(style: .error)
```

## 动画系统

### 预定义动画

```swift
// 标准动画
Animations.fast      // 快速 (0.2s)
Animations.standard  // 标准 (0.3s)
Animations.slow      // 慢速 (0.5s)

// 弹簧动画
Animations.spring         // 标准弹簧
Animations.springBouncy   // 弹性弹簧
Animations.springSmooth   // 平滑弹簧
```

### 视图动画修饰符

```swift
// 淡入
someView.fadeIn(delay: 0.2)

// 从底部滑入
someView.slideInFromBottom()

// 缩放出现
someView.scaleIn()

// 抖动(错误提示)
someView.shake(trigger: hasError)

// 脉冲
someView.pulse()

// 旋转
someView.rotate()

// 骨架屏闪烁
someView.shimmer()

// 按钮点击反馈
someView.buttonPress()
```

### 转场动画

```swift
// 淡入淡出
.transition(Animations.fadeTransition)

// 缩放
.transition(Animations.scaleTransition)

// 滑动
.transition(Animations.slideTransition)

// 从底部移动
.transition(Animations.moveFromBottomTransition)

// 组合(淡入+缩放)
.transition(Animations.fadeScaleTransition)
```

## 最佳实践

### 1. 使用 Design Tokens

❌ **错误示例**:
```swift
Text("标题")
    .padding(16)
    .background(Color(red: 0.13, green: 0.59, blue: 0.95))
    .cornerRadius(12)
```

✅ **正确示例**:
```swift
Text("标题")
    .padding(DesignTokens.Spacing.md)
    .background(theme.colors.primary)
    .cornerRadius(DesignTokens.BorderRadius.md)
```

### 2. 使用预定义组件

❌ **错误示例**:
```swift
Button(action: { }) {
    Text("提交")
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(.white)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(Color.blue)
        .cornerRadius(12)
}
```

✅ **正确示例**:
```swift
DSButton("提交", fullWidth: true) { }
```

### 3. 使用主题颜色

❌ **错误示例**:
```swift
Text("内容")
    .foregroundColor(.black)
```

✅ **正确示例**:
```swift
@Environment(\.appTheme) var theme

Text("内容")
    .foregroundColor(theme.colors.text)
```

### 4. 响应式布局

```swift
@Environment(\.horizontalSizeClass) var horizontalSizeClass

var padding: CGFloat {
    horizontalSizeClass == .compact
        ? DesignTokens.Spacing.md
        : DesignTokens.Spacing.xl
}

someView.padding(.horizontal, padding)
```

### 5. 可访问性

```swift
DSButton("删除", style: .destructive) { }
    .accessibilityLabel("删除项目")
    .accessibilityHint("双击删除此项目")
```

## 示例代码

### 完整登录界面示例

```swift
struct LoginView: View {
    @Environment(\.appTheme) var theme
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            // Logo
            Image(systemName: "person.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(theme.colors.primary)

            // 标题
            VStack(spacing: DesignTokens.Spacing.sm) {
                Text("欢迎回来")
                    .font(theme.typography.displaySmall)
                Text("登录您的账户")
                    .font(theme.typography.bodyLarge)
                    .foregroundColor(theme.colors.textSecondary)
            }

            // 输入框
            VStack(spacing: DesignTokens.Spacing.md) {
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
            }

            // 按钮
            DSButton(
                "登录",
                fullWidth: true,
                isLoading: isLoading
            ) {
                handleLogin()
            }

            // 分隔符
            DSTextDivider("或")

            // 社交登录
            HStack(spacing: DesignTokens.Spacing.md) {
                DSButton("Apple", icon: "apple.logo", style: .secondary) { }
                DSButton("Google", icon: "g.circle.fill", style: .secondary) { }
            }
        }
        .padding(DesignTokens.Spacing.xl)
    }

    private func handleLogin() {
        // 登录逻辑
    }
}
```

## 组件展示应用

运行 `ComponentShowcase.swift` 查看所有组件的交互演示:

```swift
@main
struct ComponentShowcaseApp: App {
    var body: some Scene {
        WindowGroup {
            ComponentShowcaseView()
                .withThemeManager()
        }
    }
}
```

## 贡献指南

### 添加新组件

1. 在 `DesignSystem/Components/` 创建新文件
2. 遵循命名约定: `DS<ComponentName>.swift`
3. 使用 Design Tokens 而非硬编码值
4. 支持浅色/暗黑模式
5. 添加 Previews
6. 更新此 README

### 修改 Design Tokens

1. 编辑 `DesignSystem/Tokens/DesignTokens.swift`
2. 确保向后兼容
3. 更新文档

## 许可证

MIT License - 仅供 Nova 项目内部使用

## 联系方式

如有问题或建议,请联系设计系统团队。

---

**构建于**: 2025-10-19
**版本**: 1.0.0
**维护者**: Nova iOS Team
