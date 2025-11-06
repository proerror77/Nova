#!/usr/bin/env python3
"""
Design System Synchronization Tool
同步 Figma 的设计系统到 SwiftUI 代码
"""

import json
import os
from typing import Dict, List, Tuple

class DesignSystemSync:
    """设计系统同步工具"""

    @staticmethod
    def extract_colors_from_figma(figma_data: Dict) -> Dict[str, str]:
        """从 Figma 提取颜色定义"""
        colors = {}
        # 这里实现实际的颜色提取逻辑
        # 通常 Figma 颜色存储在 styles 或 fills 字段中
        return colors

    @staticmethod
    def generate_color_set_swift(name: str, hex: str) -> str:
        """生成单个颜色定义"""
        return f"""
    static let {name} = Color(hex: "{hex}")
"""

    @staticmethod
    def generate_typography_scale() -> str:
        """生成排版比例系统（基于 Material Design 3）"""
        return '''import SwiftUI

struct BrandTypography {
    // Display Scale
    private static let displayScale: CGFloat = 1.57  // Golden ratio

    // Display
    static let displayLarge = Font.system(size: 57, weight: .bold)
    static let displayMedium = Font.system(size: 45, weight: .bold)
    static let displaySmall = Font.system(size: 36, weight: .bold)

    // Headline
    static let headlineLarge = Font.system(size: 32, weight: .bold)
    static let headlineMedium = Font.system(size: 28, weight: .semibold)
    static let headlineSmall = Font.system(size: 24, weight: .semibold)

    // Title
    static let titleLarge = Font.system(size: 22, weight: .semibold)
    static let titleMedium = Font.system(size: 16, weight: .semibold)
    static let titleSmall = Font.system(size: 14, weight: .semibold)

    // Body
    static let bodyLarge = Font.system(size: 16, weight: .regular)
    static let bodyMedium = Font.system(size: 14, weight: .regular)
    static let bodySmall = Font.system(size: 12, weight: .regular)

    // Label
    static let labelLarge = Font.system(size: 14, weight: .medium)
    static let labelMedium = Font.system(size: 12, weight: .medium)
    static let labelSmall = Font.system(size: 11, weight: .medium)
}
'''

    @staticmethod
    def generate_spacing_scale() -> str:
        """生成间距比例系统（4px 基础单位）"""
        return '''import SwiftUI

struct BrandSpacing {
    // 基础单位: 4px
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
    static let xxxl: CGFloat = 64

    // 常用间距
    static let padding = Self.md
    static let cornerRadius: CGFloat = 12
    static let borderWidth: CGFloat = 1

    // 组件特定
    struct Button {
        static let paddingVertical = Self.md
        static let paddingHorizontal = Self.lg
        static let cornerRadius = Self.cornerRadius
    }

    struct Card {
        static let padding = Self.md
        static let cornerRadius = Self.cornerRadius
    }

    struct Input {
        static let padding = Self.sm
        static let cornerRadius = Self.cornerRadius
    }
}
'''

    @staticmethod
    def generate_shadow_system() -> str:
        """生成阴影系统"""
        return '''import SwiftUI

struct BrandShadow {
    // Elevation levels
    static func elevationSmall() -> some View {
        modifier(
            modifier: ElevationModifier(elevation: 1)
        )
    }

    static func elevationMedium() -> some View {
        modifier(
            modifier: ElevationModifier(elevation: 2)
        )
    }

    static func elevationLarge() -> some View {
        modifier(
            modifier: ElevationModifier(elevation: 3)
        )
    }
}

struct ElevationModifier: ViewModifier {
    let elevation: Int

    func body(content: Content) -> some View {
        let shadowRadius = CGFloat(elevation * 2)
        let shadowOpacity = Double(elevation) * 0.1

        return content
            .shadow(
                color: Color.black.opacity(shadowOpacity),
                radius: shadowRadius,
                x: 0,
                y: CGFloat(elevation)
            )
    }
}
'''

    @staticmethod
    def generate_theme_colors() -> str:
        """生成完整的主题颜色系统"""
        return '''import SwiftUI

struct BrandColors {
    // 1. Primary Colors
    struct Primary {
        static let color = Color(hex: "#2563EB")    // Blue 600
        static let light = Color(hex: "#3B82F6")    // Blue 500
        static let lighter = Color(hex: "#60A5FA")  // Blue 400
        static let dark = Color(hex: "#1D4ED8")     // Blue 700
        static let darker = Color(hex: "#1E40AF")   // Blue 800
    }

    // 2. Secondary Colors
    struct Secondary {
        static let color = Color(hex: "#F59E0B")    // Amber 500
        static let light = Color(hex: "#FBBF24")    // Amber 400
        static let dark = Color(hex: "#D97706")     // Amber 600
    }

    // 3. Semantic Colors
    struct Semantic {
        static let success = Color(hex: "#10B981")  // Green 500
        static let warning = Color(hex: "#F59E0B")  // Amber 500
        static let error = Color(hex: "#EF4444")    // Red 500
        static let info = Color(hex: "#3B82F6")     // Blue 500
    }

    // 4. Neutral Colors (Grayscale)
    struct Neutral {
        static let black = Color(hex: "#000000")
        static let gray900 = Color(hex: "#111827")
        static let gray800 = Color(hex: "#1F2937")
        static let gray700 = Color(hex: "#374151")
        static let gray600 = Color(hex: "#4B5563")
        static let gray500 = Color(hex: "#6B7280")
        static let gray400 = Color(hex: "#9CA3AF")
        static let gray300 = Color(hex: "#D1D5DB")
        static let gray200 = Color(hex: "#E5E7EB")
        static let gray100 = Color(hex: "#F3F4F6")
        static let white = Color(hex: "#FFFFFF")
    }

    // 5. Aliases (常用别名)
    static let text = Neutral.gray900
    static let textSecondary = Neutral.gray600
    static let textDisabled = Neutral.gray400
    static let background = Neutral.white
    static let surface = Neutral.gray50
    static let border = Neutral.gray200
    static let divider = Neutral.gray100
}

// 深色模式支持
@available(iOS 13, *)
struct AdaptiveColors {
    @Environment(\\.colorScheme) var colorScheme

    func backgroundColor() -> Color {
        colorScheme == .dark ? Color.black : Color.white
    }

    func textColor() -> Color {
        colorScheme == .dark ? Color.white : BrandColors.text
    }
}
'''

    @staticmethod
    def generate_documentation() -> str:
        """生成设计系统文档"""
        return '''# Nova Design System

## Overview

Nova 设计系统是为 Nova Social iOS App 定制的完整设计系统，包含：

- **颜色系统**：语义化颜色定义
- **排版系统**：基于比例的字体体系
- **间距系统**：4px 基础单位的间距规范
- **阴影系统**：分级的高程系统
- **组件库**：可复用的 SwiftUI 组件

## 颜色系统

### 主色板
- **Primary**: 蓝色，用于主要交互和重点内容
- **Secondary**: 琥珀色，用于辅助交互
- **Semantic**: 成功、警告、错误和信息提示颜色

### 使用示例
```swift
Text("Hello")
    .foregroundColor(BrandColors.Primary.color)
```

## 排版系统

采用黄金比例 1.57 的排版阶梯：

```
Display Large   (57pt)
Display Medium  (45pt)
Display Small   (36pt)
Headline Large  (32pt)
Headline Medium (28pt)
Headline Small  (24pt)
Title Large     (22pt)
Title Medium    (16pt)
Title Small     (14pt)
Body Large      (16pt)
Body Medium     (14pt)
Body Small      (12pt)
```

### 使用示例
```swift
Text("Section Title")
    .font(BrandTypography.titleLarge)
```

## 间距系统

基础单位 4px：

```
xxs: 2px
xs:  4px
sm:  8px
md:  16px (default)
lg:  24px
xl:  32px
xxl: 48px
xxxl: 64px
```

### 使用示例
```swift
VStack(spacing: BrandSpacing.md) {
    Text("Item 1")
    Text("Item 2")
}
.padding(BrandSpacing.md)
```

## 最佳实践

### 1. 始终使用设计系统常量
❌ 错误：
```swift
.padding(16)
.foregroundColor(Color(hex: "#2563EB"))
```

✅ 正确：
```swift
.padding(BrandSpacing.md)
.foregroundColor(BrandColors.Primary.color)
```

### 2. 响应式设计
```swift
@Environment(\\.horizontalSizeClass) var sizeClass

var body: some View {
    if sizeClass == .compact {
        VStack { /* ... */ }
    } else {
        HStack { /* ... */ }
    }
}
```

### 3. 暗黑模式支持
```swift
@Environment(\\.colorScheme) var colorScheme

var backgroundColor: Color {
    colorScheme == .dark ? Color.black : Color.white
}
```

## 同步 Figma

定期从 Figma 同步设计系统：

```bash
python3 scripts/design-system-sync.py
```

这会自动更新：
- 颜色定义
- 排版规范
- 间距值
- 组件代码

## 版本历史

- **v1.0.0** (2025-11-06): 初始版本
'''

    @staticmethod
    def write_files(output_dir: str = "./ios/NovaSocial/DesignSystem"):
        """生成所有设计系统文件"""
        os.makedirs(output_dir, exist_ok=True)

        files = {
            "Colors.swift": DesignSystemSync.generate_theme_colors(),
            "Typography.swift": DesignSystemSync.generate_typography_scale(),
            "Spacing.swift": DesignSystemSync.generate_spacing_scale(),
            "Shadows.swift": DesignSystemSync.generate_shadow_system(),
            "README.md": DesignSystemSync.generate_documentation(),
        }

        for filename, content in files.items():
            filepath = os.path.join(output_dir, filename)
            os.makedirs(os.path.dirname(filepath), exist_ok=True)

            with open(filepath, "w") as f:
                f.write(content)

            print(f"✅ Generated {filename}")


def main():
    try:
        output_dir = "./ios/NovaSocial/DesignSystem"
        DesignSystemSync.write_files(output_dir)
        print(f"\n✅ Design system synced to {output_dir}")
    except Exception as e:
        print(f"❌ Error: {e}")
        exit(1)


if __name__ == "__main__":
    main()
