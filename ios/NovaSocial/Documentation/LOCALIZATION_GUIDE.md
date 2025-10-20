# Localization Guide (本地化指南)

## Overview

Nova iOS 应用实现了完整的多语言国际化（i18n）和本地化（l10n）系统，支持中文简体、中文繁体和英文三种语言。

## Architecture

### Core Components

```
Localization/
├── Language.swift                  # 语言枚举和配置
├── LocalizationManager.swift       # 本地化管理器（单例）
├── L10n.swift                      # 类型安全的字符串访问器
├── DateTimeFormatters.swift        # 日期时间格式化
└── NumberFormatters.swift          # 数字格式化

Resources/
├── zh-Hans.lproj/                  # 中文简体资源
│   └── Localizable.strings
├── zh-Hant.lproj/                  # 中文繁体资源
│   └── Localizable.strings
└── en.lproj/                       # 英文资源
    └── Localizable.strings
```

## Usage

### 1. 在 SwiftUI View 中使用本地化字符串

#### 方法 A: 使用 L10n 枚举（推荐）

```swift
import SwiftUI

struct MyView: View {
    var body: some View {
        VStack {
            Text(L10n.Common.cancel)
            Text(L10n.Feed.title)
            Text(L10n.Post.likesCount(42))
        }
    }
}
```

#### 方法 B: 使用 String 扩展

```swift
Text("common.cancel".localized)
Text("feed.title".localized)
```

#### 方法 C: 使用 LocalizedStringKey（自动本地化）

```swift
Text("common.cancel")  // SwiftUI 自动查找本地化
Button("common.save") {
    // ...
}
```

### 2. 带参数的本地化字符串

```swift
// 单个参数
Text(L10n.Notification.likedYourPost(username: "Alice"))

// 多个参数
let format = String.localizedStringWithFormat(
    "post.time_ago.minutes".localized,
    5
)
```

### 3. 日期时间格式化

```swift
import Foundation

let date = Date()

// 完整日期格式
let fullDate = date.fullDateString
// 中文: "2024年1月15日"
// 英文: "January 15, 2024"

// 短日期格式
let shortDate = date.shortDateString
// 中文: "2024/1/15"
// 英文: "1/15/24"

// 相对时间
let relative = date.relativeTimeString
// 中文: "2小时前"
// 英文: "2 hours ago"

// 智能时间显示
let smart = date.smartTimeString
// 今天: "下午3:30"
// 昨天: "昨天 下午3:30"
// 更早: "2024/1/15"
```

### 4. 数字格式化

```swift
let number = 1234567

// 标准数字格式
let standard = number.standardString
// 中文: "1,234,567"
// 英文: "1,234,567"

// 紧凑格式
let compact = number.compactString
// "1.2M"

// 百分比
let percent = 0.75.percentString
// "75%"

// 货币
let currency = 99.99.currencyString(code: "USD")
// 中文: "US$99.99"
// 英文: "$99.99"

// 序数
let ordinal = 3.ordinalString
// 中文: "第3"
// 英文: "3rd"
```

### 5. 切换语言

```swift
// 在 SettingsView 或任何地方
import SwiftUI

struct LanguageSwitcher: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared

    var body: some View {
        Button("Switch to English") {
            localizationManager.setLanguage(.english)
        }
    }
}
```

### 6. 监听语言变化

```swift
struct MyView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared

    var body: some View {
        Text("Current: \(localizationManager.currentLanguage.nativeName)")
            .localizable()  // 自动响应语言变化
    }
}
```

## Adding New Strings

### Step 1: 添加到 L10n.swift

```swift
enum L10n {
    enum MyFeature {
        static let title = "my_feature.title".localized
        static let description = "my_feature.description".localized

        static func itemsCount(_ count: Int) -> String {
            String.localizedStringWithFormat(
                "my_feature.items_count".localized,
                count
            )
        }
    }
}
```

### Step 2: 添加到所有 Localizable.strings

**zh-Hans.lproj/Localizable.strings**:
```
/* 我的功能 */
"my_feature.title" = "我的功能";
"my_feature.description" = "这是一个新功能";
"my_feature.items_count" = "%d 个项目";
```

**zh-Hant.lproj/Localizable.strings**:
```
/* 我的功能 */
"my_feature.title" = "我的功能";
"my_feature.description" = "這是一個新功能";
"my_feature.items_count" = "%d 個項目";
```

**en.lproj/Localizable.strings**:
```
/* My Feature */
"my_feature.title" = "My Feature";
"my_feature.description" = "This is a new feature";
"my_feature.items_count" = "%d items";
```

### Step 3: 在代码中使用

```swift
Text(L10n.MyFeature.title)
Text(L10n.MyFeature.itemsCount(5))
```

## Plural Forms

### 中文（无复数形式）

```swift
"post.likes_count" = "%d 个赞";  // 1个赞, 2个赞, 100个赞
```

### 英文（有复数形式）

使用 `.stringsdict` 文件（可选）或条件处理：

```swift
static func likesCount(_ count: Int) -> String {
    if count == 1 {
        return "post.likes_count_one".localized
    } else {
        return String.localizedStringWithFormat(
            "post.likes_count_other".localized,
            count
        )
    }
}
```

## Best Practices

### 1. 使用类型安全的 L10n

✅ **推荐**:
```swift
Text(L10n.Common.cancel)
```

❌ **避免**:
```swift
Text("取消")  // 硬编码字符串
Text("common.cancel")  // 缺乏类型安全
```

### 2. 永远不要硬编码用户可见文本

✅ **推荐**:
```swift
Button(L10n.Common.save) { }
```

❌ **避免**:
```swift
Button("保存") { }
```

### 3. 使用占位符而非字符串拼接

✅ **推荐**:
```swift
L10n.Notification.likedYourPost(username: user.name)
// "%@ 赞了你的帖子"
```

❌ **避免**:
```swift
"\(user.name) 赞了你的帖子"
```

### 4. 为日期和数字使用格式化器

✅ **推荐**:
```swift
date.fullDateString
number.compactString
```

❌ **避免**:
```swift
"\(date)"
"\(number)"
```

### 5. 提供上下文注释

```swift
/* 设置 - 用于设置页面标题 */
"settings.title" = "设置";

/* 设置 - 用于设置按钮动作 */
"settings.action" = "设置";
```

## Testing Localization

### 1. Xcode Scheme 测试

1. Edit Scheme → Run → Options
2. 选择 "Application Language"
3. 运行应用查看不同语言

### 2. 模拟器切换语言

1. 设置 → 通用 → 语言与地区
2. 添加语言并重启应用

### 3. 代码切换测试

```swift
#if DEBUG
struct LocalizationTestView: View {
    var body: some View {
        VStack {
            Button("中文简体") {
                LocalizationManager.shared.setLanguage(.chineseSimplified)
            }
            Button("繁體中文") {
                LocalizationManager.shared.setLanguage(.chineseTraditional)
            }
            Button("English") {
                LocalizationManager.shared.setLanguage(.english)
            }
        }
    }
}
#endif
```

## Pseudo-Localization (伪本地化测试)

用于检测硬编码字符串和布局问题：

```swift
#if DEBUG
extension String {
    var pseudoLocalized: String {
        "[[\(self)]]"
    }
}
#endif
```

## Common Issues & Solutions

### Issue 1: 字符串未本地化

**症状**: 显示 key 而不是本地化文本

**解决方案**:
1. 检查 `.strings` 文件是否包含该 key
2. 确保 `.lproj` 目录正确添加到 Xcode 项目
3. Clean Build Folder (⇧⌘K)

### Issue 2: 参数格式错误

**症状**: 参数未正确替换

**解决方案**:
```swift
// ❌ 错误
"post.likes_count" = "%@ 个赞";  // 用 %@ 代替 %d

// ✅ 正确
"post.likes_count" = "%d 个赞";  // 整数用 %d
```

### Issue 3: 语言切换后界面未更新

**解决方案**:
```swift
// 添加 .localizable() modifier
.localizable()

// 或使用 @ObservedObject
@ObservedObject private var localizationManager = LocalizationManager.shared
```

## Adding a New Language

### 1. 创建新的 .lproj 目录

```bash
mkdir -p Resources/ja.lproj
```

### 2. 添加 Localizable.strings

```bash
touch Resources/ja.lproj/Localizable.strings
```

### 3. 更新 Language.swift

```swift
enum Language: String, CaseIterable {
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case english = "en"
    case japanese = "ja"  // 新增

    var displayName: String {
        switch self {
        case .japanese:
            return "日本語"
        // ...
        }
    }
}
```

### 4. 翻译所有字符串

复制现有 `Localizable.strings` 并翻译所有内容。

### 5. 在 Xcode 中添加本地化

1. 选择项目 → Info
2. Localizations → 添加新语言
3. 选择要包含的文件

## Translation Workflow

### 1. 导出待翻译字符串

```bash
# 生成 XLIFF 文件
xcodebuild -exportLocalizations -project NovaSocial.xcodeproj -localizationPath ./Localizations
```

### 2. 翻译 XLIFF 文件

使用专业翻译工具或服务。

### 3. 导入翻译

```bash
xcodebuild -importLocalizations -project NovaSocial.xcodeproj -localizationPath ./Localizations/zh-Hans.xliff
```

## Performance Considerations

### 1. 缓存本地化字符串

`LocalizationManager` 自动缓存 Bundle，避免重复加载。

### 2. 避免频繁切换语言

语言切换会触发整个 UI 刷新，应避免在循环中切换。

### 3. 预加载常用字符串

```swift
struct Preloader {
    static func preloadCommonStrings() {
        _ = L10n.Common.cancel
        _ = L10n.Common.confirm
        // ...
    }
}
```

## Accessibility & VoiceOver

所有本地化字符串自动支持 VoiceOver：

```swift
Text(L10n.Common.cancel)
    .accessibilityLabel(L10n.Common.cancel)  // 自动使用本地化
```

## Summary

- ✅ 使用 `L10n` 枚举访问所有字符串
- ✅ 使用格式化器处理日期、时间和数字
- ✅ 避免硬编码用户可见文本
- ✅ 为新功能同步更新所有语言文件
- ✅ 使用 `.localizable()` modifier 响应语言变化
- ✅ 测试所有支持的语言

---

**最后更新**: 2024-10-19
**维护者**: Nova iOS Team
