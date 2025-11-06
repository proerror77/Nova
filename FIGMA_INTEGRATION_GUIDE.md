# Figma + SwiftUI 集成指南

**项目**: Nova Social iOS App
**Figma 文件**: [icered Design System](https://www.figma.com/design/DoBJCFQ7WzELIXnwQcbVls/icered)
**最后更新**: 2025-11-06

---

## 一、初始设置

### 1.1 获取 Figma Token

1. 登录 [Figma](https://www.figma.com)
2. 点击左上角头像 → Settings
3. 找到 "Account" → "Personal access tokens"
4. 点击 "Create new token"
5. **重要**: 立即复制 token 并保存到安全位置

> ⚠️ **安全提示**: 永远不要在代码或版本控制中提交 token。始终使用环境变量。

### 1.2 配置环境变量

在你的 shell 配置文件中添加（`~/.zshrc` 或 `~/.bash_profile`）：

```bash
# Figma Configuration
export FIGMA_TOKEN="figd_your_token_here"
export FIGMA_FILE_ID="DoBJCFQ7WzELIXnwQcbVls"
```

然后运行：
```bash
source ~/.zshrc  # 或 source ~/.bash_profile
```

验证配置：
```bash
echo $FIGMA_TOKEN
echo $FIGMA_FILE_ID
```

---

## 二、使用工具链

### 2.1 导出设计资产

使用 `figma-export.sh` 导出 Figma 中的所有设计资产（颜色、间距、排版）：

```bash
cd /Users/proerror/Documents/nova
bash scripts/figma-export.sh DoBJCFQ7WzELIXnwQcbVls ./ios/NovaSocial/DesignSystem
```

**生成的文件**:
- `Colors.swift` - 颜色定义
- `Typography.swift` - 排版系统
- `Spacing.swift` - 间距规范

### 2.2 生成 SwiftUI 组件

使用 Python 脚本从 Figma 组件自动生成 SwiftUI 代码：

```bash
python3 scripts/figma-to-swiftui.py
```

**生成的组件**:
- `PrimaryButton.swift` - 主按钮
- `SecondaryButton.swift` - 次按钮
- `Card.swift` - 卡片容器
- `InputField.swift` - 输入框
- `ComponentLibrary.swift` - 组件索引

### 2.3 同步设计系统

运行完整的设计系统同步（包括所有文件）：

```bash
python3 scripts/design-system-sync.py
```

这会生成：
- 完整的颜色系统（主色、辅助色、语义色）
- 排版阶梯（基于黄金比例）
- 间距规范（4px 单位）
- 阴影系统（分级高程）
- 文档和使用说明

---

## 三、在 Xcode 中自动同步

### 3.1 配置构建阶段

1. 打开 Xcode 项目
2. 选择 **Build Phases**
3. 点击 **+ New Run Script Phase**
4. 粘贴以下脚本：

```bash
export FIGMA_TOKEN="${FIGMA_TOKEN}"
${SRCROOT}/scripts/xcode-figma-build-phase.sh
```

5. 确保脚本权限：
```bash
chmod +x scripts/xcode-figma-build-phase.sh
```

现在每次构建时，Figma 设计系统会自动同步。

### 3.2 验证构建集成

```bash
cd /Users/proerror/Documents/nova
chmod +x scripts/xcode-figma-build-phase.sh
./scripts/xcode-figma-build-phase.sh
```

---

## 四、在 SwiftUI 中使用设计系统

### 4.1 颜色

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            // 使用主色
            Text("Primary Color")
                .foregroundColor(BrandColors.Primary.color)

            // 使用语义色
            Text("Success")
                .foregroundColor(BrandColors.Semantic.success)

            // 背景颜色
            Text("On Background")
                .foregroundColor(BrandColors.text)
        }
        .background(BrandColors.background)
    }
}
```

### 4.2 排版

```swift
VStack(spacing: BrandSpacing.md) {
    // Display Large
    Text("Display Large Title")
        .font(BrandTypography.displayLarge)

    // Headline
    Text("Section Header")
        .font(BrandTypography.headlineLarge)

    // Body
    Text("Regular text content")
        .font(BrandTypography.bodyMedium)
}
```

### 4.3 间距和布局

```swift
VStack(spacing: BrandSpacing.md) {
    ForEach(0..<3, id: \.self) { _ in
        Card {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Text("Card Title")
                    .font(BrandTypography.titleMedium)

                Text("Card content goes here")
                    .font(BrandTypography.bodySmall)
            }
        }
    }
}
.padding(BrandSpacing.lg)
```

### 4.4 组件使用

```swift
import SwiftUI

struct MyView: View {
    var body: some View {
        VStack(spacing: BrandSpacing.md) {
            PrimaryButton(
                label: "Get Started",
                action: { handleAction() }
            )

            SecondaryButton(
                label: "Learn More",
                action: { handleSecondaryAction() }
            )

            Card {
                VStack {
                    Text("Card Content")
                        .font(BrandTypography.titleMedium)
                }
            }
        }
        .padding(BrandSpacing.md)
    }

    private func handleAction() {
        print("Primary action triggered")
    }

    private func handleSecondaryAction() {
        print("Secondary action triggered")
    }
}
```

### 4.5 暗黑模式支持

```swift
struct AdaptiveView: View {
    @Environment(\.colorScheme) var colorScheme

    var backgroundColor: Color {
        colorScheme == .dark ? Color.black : BrandColors.background
    }

    var body: some View {
        VStack {
            Text("Adaptive Content")
                .foregroundColor(BrandColors.text)
        }
        .background(backgroundColor)
    }
}
```

---

## 五、工作流程

### 5.1 日常开发流程

```
1. 在 Figma 中更新设计
   ↓
2. 运行同步脚本（或构建时自动）
   ↓
3. Swift 代码自动更新
   ↓
4. 在 Xcode 中预览变更
   ↓
5. 提交代码
```

### 5.2 添加新组件

1. **在 Figma 中设计**
   - 创建新组件
   - 定义属性和变体

2. **运行生成脚本**
   ```bash
   python3 scripts/figma-to-swiftui.py
   ```

3. **编辑生成的代码**
   - 添加功能性逻辑
   - 优化性能

4. **添加到组件库**
   - 更新 `ComponentLibrary.swift`
   - 添加 Preview

---

## 六、故障排除

### 问题 1: FIGMA_TOKEN 未识别

**症状**: `FIGMA_TOKEN environment variable not set`

**解决方案**:
```bash
# 检查是否设置
echo $FIGMA_TOKEN

# 如果为空，添加到 shell 配置
echo 'export FIGMA_TOKEN="figd_your_token"' >> ~/.zshrc
source ~/.zshrc
```

### 问题 2: API 连接失败

**症状**: `Failed to fetch file info`

**解决方案**:
1. 检查 token 是否有效（访问 Figma 网站）
2. 检查文件 ID 是否正确
3. 检查网络连接

```bash
# 测试 API 连接
curl -H "X-FIGMA-TOKEN: $FIGMA_TOKEN" \
    "https://api.figma.com/v1/files/DoBJCFQ7WzELIXnwQcbVls"
```

### 问题 3: Python 脚本错误

**症状**: `ModuleNotFoundError: No module named 'requests'`

**解决方案**:
```bash
pip3 install requests
```

### 问题 4: 权限被拒绝

**症状**: `Permission denied: './scripts/figma-export.sh'`

**解决方案**:
```bash
chmod +x scripts/figma-export.sh
chmod +x scripts/figma-to-swiftui.py
chmod +x scripts/design-system-sync.py
chmod +x scripts/xcode-figma-build-phase.sh
```

---

## 七、最佳实践

### 7.1 组织设计系统

```
ios/NovaSocial/
├── DesignSystem/
│   ├── Colors.swift
│   ├── Typography.swift
│   ├── Spacing.swift
│   ├── Shadows.swift
│   └── README.md
├── Components/
│   ├── Buttons/
│   │   ├── PrimaryButton.swift
│   │   └── SecondaryButton.swift
│   ├── Cards/
│   │   └── Card.swift
│   └── Inputs/
│       └── InputField.swift
└── Features/
    ├── Auth/
    ├── Home/
    └── Profile/
```

### 7.2 代码规范

**✅ 使用设计系统常量**:
```swift
.padding(BrandSpacing.md)
.foregroundColor(BrandColors.Primary.color)
.font(BrandTypography.titleLarge)
```

**❌ 避免硬编码值**:
```swift
.padding(16)          // 使用 BrandSpacing.md
.foregroundColor(.blue)  // 使用 BrandColors
.font(.system(size: 16)) // 使用 BrandTypography
```

### 7.3 版本控制

**.gitignore**:
```
# 不提交 Figma token
*.token
.env
.env.local

# 排除 Xcode 缓存
DerivedData/
Build/
```

### 7.4 定期更新

设置提醒每周同步设计系统：
```bash
# 添加到 crontab
0 9 * * 1 cd /Users/proerror/Documents/nova && python3 scripts/design-system-sync.py
```

---

## 八、高级使用

### 8.1 自定义颜色值

编辑 `design-system-sync.py` 中的 `generate_theme_colors()` 函数：

```python
struct Primary {
    static let color = Color(hex: "#2563EB")    // 修改这里
    static let light = Color(hex: "#3B82F6")
    # ...
}
```

### 8.2 扩展排版系统

在 `Typography.swift` 中添加自定义字体：

```swift
struct BrandTypography {
    // 现有样式...

    // 自定义样式
    static let specialFont = Font.custom("CustomFont", size: 18)
}
```

### 8.3 条件导出

只导出特定的 Figma 页面或组件，修改脚本的 EXPORT_PAYLOAD：

```bash
# 修改 figma-export.sh 中的 payload
EXPORT_PAYLOAD=$(cat <<EOF
{
  "ids": ["page-id-1", "page-id-2"],
  "format": "svg"
}
EOF
)
```

---

## 九、生成的文件结构

### 颜色系统 (Colors.swift)
```
BrandColors
├── Primary (主色)
├── Secondary (辅助色)
├── Semantic (语义色)
│   ├── success
│   ├── warning
│   ├── error
│   └── info
└── Neutral (中性色)
    ├── black, gray900-100
    └── white
```

### 排版系统 (Typography.swift)
```
BrandTypography
├── Display (3级)
├── Headline (3级)
├── Title (3级)
├── Body (3级)
└── Label (3级)
```

### 间距系统 (Spacing.swift)
```
BrandSpacing
├── xxs (2px)
├── xs-xxxl (4-64px)
└── 组件特定间距
    ├── Button
    ├── Card
    └── Input
```

---

## 十、FAQ

**Q: 如何更新 Figma 中的颜色后自动更新代码？**
A: 配置 Xcode Build Phase 脚本，每次构建时自动同步。

**Q: 可以为不同的品牌创建多套设计系统吗？**
A: 可以，在 `design-system-sync.py` 中创建多个函数，如 `generate_dark_theme()` 等。

**Q: 如何在团队中共享这些工具？**
A: 所有脚本都在项目中，使用 git 共享。确保文档 (README.md) 充分清晰。

**Q: 支持哪些图像格式导出？**
A: 脚本支持 SVG, PNG, PDF 等（修改 `figma-export.sh` 中的 format 参数）。

---

## 总结

你现在拥有了一套完整的 Figma + SwiftUI 集成工具链：

✅ 设计资产导出工具
✅ SwiftUI 组件生成器
✅ 完整的设计系统库
✅ Xcode 自动同步脚本
✅ 详细的使用文档

开始使用吧！🚀
