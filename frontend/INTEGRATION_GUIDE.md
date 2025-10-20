# Nova Design System - Cross-Platform Integration Guide

跨平台设计系统完整集成指南。支持 2 品牌 × 2 主题 × 2 平台 = 8 个主题组合。

## 📋 目录

- [项目结构](#项目结构)
- [iOS 集成](#ios-集成)
- [Android 集成](#android-集成)
- [主题切换](#主题切换)
- [组件开发](#组件开发)
- [常见问题](#常见问题)

---

## 项目结构

```
nova/frontend/
├── design-system/
│   └── tokens.design.json          # Figma Tokens Studio 源文件（跨平台共用）
│
├── ios/
│   ├── DesignTokens/               # 44 个颜色资源包（4 主题 × 11 颜色）
│   ├── Theme.swift                 # SwiftUI 主题运行时系统
│   ├── ExamplePostCard.swift       # 参考组件实现
│   ├── README.md                   # iOS 详细文档
│   └── QUICKSTART.md               # iOS 快速开始
│
├── android/
│   ├── res/
│   │   ├── values/colors.xml       # 浅色主题颜色
│   │   ├── values-night/colors.xml # 深色主题颜色
│   │   └── values/dimens.xml       # 尺寸 tokens
│   ├── com/nova/designsystem/theme/ # Compose 主题系统
│   ├── examples/PostCard.kt        # 参考组件实现
│   └── README.md                   # Android 详细文档
│
├── INTEGRATION_GUIDE.md            # 此文件
├── FIGMA_SETUP.md                  # 设计师指南
└── COMPONENT_EXAMPLES.md           # 组件示例库
```

---

## iOS 集成

### Step 1: 添加颜色资源

1. **在 Xcode 中打开项目**
2. **导航到**: File → Add Files to Project
3. **选择**: `frontend/ios/DesignTokens` 文件夹
4. **配置**:
   - ✅ Copy items if needed
   - ✅ Create groups (not folder references)
   - ✅ Add to target

### Step 2: 添加 Theme.swift

1. **复制文件**: `frontend/ios/Theme.swift` → 项目目录
2. **File → Add Files to Project** → 选择 Theme.swift
3. **确保添加到正确的 Target**

### Step 3: 在 App 中注入主题

```swift
import SwiftUI

@main
struct NovaApp: App {
    @Environment(\.colorScheme) var colorScheme

    var body: some Scene {
        WindowGroup {
            ContentView()
                .theme(.brandA, colorScheme: colorScheme)  // 注入主题
        }
    }
}
```

### Step 4: 在 View 中使用主题

```swift
import SwiftUI

struct PostCard: View {
    @Environment(\.theme) var theme  // 读取主题

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.sm) {
            Text("Hello Nova")
                .font(theme.type.titleLG)
                .foregroundColor(theme.colors.fgPrimary)

            Divider()
                .background(theme.colors.borderSubtle)
        }
        .padding(theme.space.lg)
        .background(theme.colors.bgElevated)
        .cornerRadius(theme.metric.postCorner)
    }
}
```

### Step 5: 运行预览

在 Xcode 中运行 ExamplePostCard 预览，查看 4 个主题变体效果。

---

## Android 集成

### Step 1: 添加资源文件

1. **创建目录结构**: `app/src/main/res/`
2. **复制文件**:
   - `values/colors.xml`
   - `values-night/colors.xml`
   - `values/dimens.xml`

### Step 2: 添加 Compose 主题代码

1. **创建包**: `com.nova.designsystem.theme`
2. **复制所有文件**:
   - `Color.kt`
   - `Type.kt`
   - `Spacing.kt`
   - `Theme.kt`
   - `LocalTheme.kt`

### Step 3: 在 Activity 中应用主题

```kotlin
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            NovaTheme(skin = BrandSkin.BRAND_A) {
                // 你的应用内容
                MainScreen()
            }
        }
    }
}
```

### Step 4: 在 Composable 中使用主题

```kotlin
@Composable
fun PostCard() {
    val colors = LocalColorScheme.current
    val spacing = LocalSpacing.current

    Box(
        modifier = Modifier
            .background(colors.bgElevated)
            .padding(spacing.lg)
            .clip(RoundedCornerShape(12.dp))
    ) {
        Text(
            "Hello Nova",
            style = LocalTypography.current.titleLG,
            color = colors.fgPrimary
        )
    }
}
```

### Step 5: 运行预览

在 Android Studio 中运行 PostCard Preview，查看 4 个主题变体。

---

## 主题切换

### iOS - 运行时品牌切换

```swift
// 保存用户选择
UserDefaults.standard.set("brandB", forKey: "selectedBrand")

// 切换主题（需要在 View 层重新注入）
@State private var selectedBrand: BrandSkin = .brandA

Button("Switch to BrandB") {
    selectedBrand = .brandB
}

ContentView()
    .theme(selectedBrand, colorScheme: colorScheme)
```

### Android - 运行时品牌切换

```kotlin
@Composable
fun NovaApp() {
    val selectedBrand = remember { mutableStateOf(BrandSkin.BRAND_A) }

    Column {
        Button(onClick = { selectedBrand.value = BrandSkin.BRAND_B }) {
            Text("Switch to BrandB")
        }

        NovaTheme(skin = selectedBrand.value) {
            MainScreen()
        }
    }
}
```

---

## 组件开发

### 关键原则

1. **始终通过 @Environment/@CompositionLocal 获取主题**
   - ❌ 不要硬编码颜色值
   - ✅ 使用 `theme.colors.brandPrimary`

2. **使用语义化颜色名**
   - ❌ 不要 `Color(#0086C9)`
   - ✅ 使用 `theme.colors.brandPrimary`

3. **尊重间距系统**
   - ❌ 不要 `padding(15)`
   - ✅ 使用 `theme.space.md` (12dp) 或 `theme.space.lg` (16dp)

4. **遵守圆角规范**
   - 小组件: `theme.radius.sm` (8dp)
   - 卡片: `theme.radius.md` (12dp)
   - 大容器: `theme.radius.lg` (16dp)

### 示例：新组件模板

#### iOS

```swift
struct MyComponent: View {
    @Environment(\.theme) var theme

    var body: some View {
        VStack(spacing: theme.space.md) {
            // 内容
        }
        .padding(theme.space.lg)
        .background(theme.colors.bgElevated)
        .cornerRadius(theme.radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius.md)
                .stroke(theme.colors.borderSubtle, lineWidth: 1)
        )
    }
}
```

#### Android

```kotlin
@Composable
fun MyComponent() {
    val colors = LocalColorScheme.current
    val spacing = LocalSpacing.current
    val radius = LocalRadius.current

    Box(
        modifier = Modifier
            .background(colors.bgElevated, RoundedCornerShape(radius.md.dp))
            .border(1.dp, colors.borderSubtle, RoundedCornerShape(radius.md.dp))
            .padding(spacing.lg.dp)
    ) {
        // 内容
    }
}
```

---

## 常见问题

### Q: 如何在 iOS 中预览所有 4 个主题？

```swift
#Preview("BrandA Light") {
    PostCard().theme(.brandA, colorScheme: .light)
}

#Preview("BrandA Dark") {
    PostCard().theme(.brandA, colorScheme: .dark)
}

#Preview("BrandB Light") {
    PostCard().theme(.brandB, colorScheme: .light)
}

#Preview("BrandB Dark") {
    PostCard().theme(.brandB, colorScheme: .dark)
}
```

### Q: 如何在 Android 中预览所有 4 个主题？

```kotlin
@Preview(name = "BrandA Light")
@Composable
private fun PostCardPreviewBrandALight() {
    NovaTheme(skin = BrandSkin.BRAND_A, isDark = false) {
        PostCard()
    }
}

// ... 其他 3 个组合
```

### Q: 如何添加新的品牌？

1. 编辑 `tokens.design.json` → 添加 `brandC.light` 和 `brandC.dark`
2. 导出 tokens → 生成 xcassets 和 colors.xml
3. 更新 `enum BrandSkin` 添加 `case brandC`

### Q: 颜色不匹配怎么办？

1. 验证 tokens.design.json 中的 hex 值
2. iOS: 检查 xcassets 中的 RGB 值是否正确归一化（0.0-1.0）
3. Android: 检查 colors.xml 中的 hex 值格式（#RRGGBB）

### Q: 性能会受影响吗？

- **iOS**: Theme 查询是 O(1) 操作，无性能问题
- **Android**: CompositionLocal 零额外分配，性能最优

---

## 快速参考

### 颜色使用

| 用途 | iOS | Android |
|------|-----|---------|
| 背景 | `theme.colors.bgSurface` | `colors.bgSurface` |
| 前景文字 | `theme.colors.fgPrimary` | `colors.fgPrimary` |
| 品牌色 | `theme.colors.brandPrimary` | `colors.brandPrimary` |
| 边框 | `theme.colors.borderSubtle` | `colors.borderSubtle` |
| 成功 | `theme.colors.stateSuccess` | `colors.stateSuccess` |

### 间距使用

| 值 | px | 用途 |
|----|----|----|
| xs | 4  | 极小间距 |
| sm | 8  | 紧凑间距 |
| md | 12 | 标准间距 |
| lg | 16 | 宽松间距 |
| xl | 24 | 大间距 |
| 2xl| 32 | 超大间距 |

### 圆角使用

| 值 | px | 用途 |
|----|----|----|
| sm | 8  | 小按钮、输入框 |
| md | 12 | 卡片、对话框 |
| lg | 16 | 大容器、主视图 |

---

## 支持

- 📖 **iOS 详细文档**: `frontend/ios/README.md`
- 📖 **Android 详细文档**: `frontend/android/README.md`
- 🎨 **Figma 设置**: `FIGMA_SETUP.md`
- 💡 **组件示例**: `COMPONENT_EXAMPLES.md`
- 📋 **规范**: `frontend/design.md`

---

**最后更新**: 2025-10-18
**版本**: 1.0.0
**状态**: ✅ 生产就绪
