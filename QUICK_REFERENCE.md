# Figma + SwiftUI 快速参考卡

## 🎨 颜色使用

```swift
// 主色
BrandColors.Primary.color          // #2563EB 蓝色
BrandColors.Primary.light          // 浅蓝
BrandColors.Primary.dark           // 深蓝

// 语义色
BrandColors.Semantic.success       // 绿色
BrandColors.Semantic.warning       // 琥珀色
BrandColors.Semantic.error         // 红色

// 中性色
BrandColors.text                   // 深灰（文本）
BrandColors.textSecondary          // 中灰（次要文本）
BrandColors.background             // 白色（背景）
BrandColors.border                 // 浅灰（边框）
```

## 📝 排版系统

```swift
// Display 级别
BrandTypography.displayLarge       // 57pt, Bold
BrandTypography.displayMedium      // 45pt, Bold
BrandTypography.displaySmall       // 36pt, Bold

// Headline 级别
BrandTypography.headlineLarge      // 32pt, Bold
BrandTypography.headlineMedium     // 28pt, Semibold
BrandTypography.headlineSmall      // 24pt, Semibold

// Title 级别
BrandTypography.titleLarge         // 22pt, Semibold
BrandTypography.titleMedium        // 16pt, Semibold
BrandTypography.titleSmall         // 14pt, Semibold

// Body 级别
BrandTypography.bodyLarge          // 16pt, Regular
BrandTypography.bodyMedium         // 14pt, Regular
BrandTypography.bodySmall          // 12pt, Regular

// Label 级别
BrandTypography.labelLarge         // 14pt, Medium
BrandTypography.labelMedium        // 12pt, Medium
BrandTypography.labelSmall         // 11pt, Medium
```

## 📏 间距系统

```swift
BrandSpacing.xxs                   // 2px
BrandSpacing.xs                    // 4px
BrandSpacing.sm                    // 8px
BrandSpacing.md                    // 16px （常用）
BrandSpacing.lg                    // 24px
BrandSpacing.xl                    // 32px
BrandSpacing.xxl                   // 48px
BrandSpacing.xxxl                  // 64px

// 快捷方式
BrandSpacing.padding               // = md (16px)
BrandSpacing.cornerRadius          // 12px
BrandSpacing.borderWidth           // 1px
```

## 🎛️ 组件快速用法

### 按钮

```swift
PrimaryButton(label: "Save", action: { /* ... */ })

SecondaryButton(label: "Cancel", action: { /* ... */ })

// 自定义
PrimaryButton(
    label: "Custom",
    action: { },
)
```

### 卡片

```swift
Card {
    VStack(alignment: .leading, spacing: BrandSpacing.sm) {
        Text("Card Title")
            .font(BrandTypography.titleMedium)

        Text("Card content here")
            .font(BrandTypography.bodyMedium)
    }
}
```

### 输入框

```swift
@State private var email = ""

InputField(
    text: $email,
    placeholder: "Enter email",
    isSecure: false
)
```

## 🏗️ 常见布局模式

### 垂直堆栈

```swift
VStack(spacing: BrandSpacing.md) {
    Text("Item 1")
    Text("Item 2")
    Text("Item 3")
}
.padding(BrandSpacing.lg)
```

### 水平堆栈

```swift
HStack(spacing: BrandSpacing.sm) {
    Image(systemName: "star")
    Text("4.5 Stars")
}
```

### 卡片列表

```swift
ScrollView {
    VStack(spacing: BrandSpacing.md) {
        ForEach(items, id: \.id) { item in
            Card {
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.title)
                            .font(BrandTypography.titleMedium)
                        Text(item.description)
                            .font(BrandTypography.bodySmall)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                }
            }
        }
    }
    .padding(BrandSpacing.md)
}
```

## 🌓 暗黑模式

```swift
@Environment(\.colorScheme) var colorScheme

var adaptiveBackground: Color {
    colorScheme == .dark ? Color.black : BrandColors.background
}

var body: some View {
    VStack {
        Text("Adaptive")
    }
    .background(adaptiveBackground)
}
```

## 🔧 常用修饰符

### 圆角

```swift
Text("Rounded")
    .padding(BrandSpacing.md)
    .background(BrandColors.Primary.color)
    .cornerRadius(BrandSpacing.cornerRadius)
```

### 边框

```swift
Text("Bordered")
    .padding(BrandSpacing.md)
    .border(BrandColors.border, width: BrandSpacing.borderWidth)
    .cornerRadius(BrandSpacing.cornerRadius)
```

### 阴影

```swift
Card { /* ... */ }
    .shadow(color: Color.black.opacity(0.1), radius: 8)
```

### 响应式

```swift
@Environment(\.horizontalSizeClass) var sizeClass

var body: some View {
    if sizeClass == .compact {
        VStack { /* ... */ }
    } else {
        HStack { /* ... */ }
    }
}
```

## 🎬 动画

```swift
@State private var isExpanded = false

var body: some View {
    VStack {
        if isExpanded {
            Text("Content")
                .transition(.opacity)
        }
    }
    .onTapGesture {
        withAnimation {
            isExpanded.toggle()
        }
    }
}
```

## 📦 完整示例

```swift
import SwiftUI

struct ContentView: View {
    @State private var email = ""
    @State private var showSuccess = false

    var body: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                // Header
                VStack(spacing: BrandSpacing.sm) {
                    Text("Welcome")
                        .font(BrandTypography.displaySmall)

                    Text("Sign up to get started")
                        .font(BrandTypography.bodyMedium)
                        .foregroundColor(BrandColors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Form
                VStack(spacing: BrandSpacing.md) {
                    InputField(
                        text: $email,
                        placeholder: "Email"
                    )

                    PrimaryButton(
                        label: "Get Started",
                        action: {
                            showSuccess = true
                        }
                    )

                    SecondaryButton(
                        label: "Learn More",
                        action: { }
                    )
                }

                // Info Card
                Card {
                    VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(BrandColors.Semantic.info)

                            Text("Tips")
                                .font(BrandTypography.titleSmall)
                        }

                        Text("Use a strong password")
                            .font(BrandTypography.bodySmall)
                            .foregroundColor(BrandColors.textSecondary)
                    }
                }
            }
            .padding(BrandSpacing.lg)
        }
        .background(BrandColors.background)
        .alert("Success!", isPresented: $showSuccess) {
            Button("OK") { }
        }
    }
}

#Preview {
    ContentView()
}
```

## ⚡ 性能提示

```swift
// ✅ 好：缓存计算结果
@State private var computedValue = calculateOnce()

// ❌ 差：每次渲染都计算
Text(calculateEveryTime())

// ✅ 好：使用 Equatable
struct MyView: View, Equatable {
    let data: SomeData

    var body: some View { /* ... */ }
}

// ✅ 好：使用 @Sendable
Button("Tap") {
    Task { @Sendable in
        await asyncOperation()
    }
}
```

## 🔗 相关资源

- 📖 **完整指南**: `FIGMA_INTEGRATION_GUIDE.md`
- 🎨 **设计系统**: `ios/NovaSocial/DesignSystem/README.md`
- ⚙️ **快速启动**: `scripts/quickstart-figma.sh`
- 🔄 **同步**: `python3 scripts/design-system-sync.py`

---

**提示**: 将此文件加入书签以快速参考！
