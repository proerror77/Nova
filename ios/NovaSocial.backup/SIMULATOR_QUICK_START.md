# 📱 在 iOS 模拟器中查看 UI

本指南帮助你快速在模拟器中运行和查看 Nova Social 的完整 UI。

---

## 🚀 快速方式（2 分钟）

### 方式 1：直接在 Xcode 中预览（最快！）

```bash
# 1. 打开 Xcode
open -a Xcode /Users/proerror/Documents/nova/ios/NovaSocial

# 2. 在 Xcode 中：
#    - 选择 NovaSocialApp.swift
#    - 在右侧点击 "Resume" 按钮查看预览
#    - 或按 ⌘⌥P 显示预览面板
```

**预览内容**：
- ✅ Feed 流（包含帖子、点赞、评论）
- ✅ Explore 页面（搜索、网格布局）
- ✅ Profile 页面（用户信息、统计、帖子网格）
- ✅ 多语言支持（中文、英文演示）

---

## 🏃 方式 2：在模拟器中运行（推荐）

### 步骤 1：启动模拟器
```bash
# 列出可用的模拟器
xcrun simctl list devices

# 启动 iPhone 15 模拟器（或其他型号）
xcrun simctl boot "iPhone 15"

# 或直接打开 Simulator 应用
open -a Simulator
```

### 步骤 2：在 Xcode 中打开项目
```bash
# 方式 A：命令行打开
open -a Xcode /Users/proerror/Documents/nova/ios/NovaSocial

# 方式 B：手动打开
# 1. 打开 Xcode
# 2. File → Open → 选择 /Users/proerror/Documents/nova/ios/NovaSocial
```

### 步骤 3：配置和运行
```
Xcode 中操作：
1. 顶部工具栏：选择 iPhone 15 (或其他模拟器)
2. 按 ⌘R (Command + R) 编译并运行
3. 等待应用在模拟器中启动
```

---

## 🎯 UI 元素预览

### Feed 标签页 (首选项卡)
```
┌──────────────────────┐
│     🏠 Feed  🔍 📱   │  ← 标签栏
├──────────────────────┤
│ 👤 User 1 • 2h ago  │
│ ━━━━━━━━━━━━━━━━━━  │
│ 这是一条精彩的帖子  │
│ 🎉 多语言演示内容   │
│                      │
│ ❤️ 12  💬 5  ↗️ Share│
├──────────────────────┤
│ 👤 User 2 • 1h ago  │
│ ...                  │
└──────────────────────┘
```

**特点**：
- ✅ 头像占位符
- ✅ 用户信息和时间戳
- ✅ 帖子内容（支持多语言）
- ✅ 交互按钮（点赞、评论、分享）
- ✅ 可滚动列表

### Explore 标签页
```
┌──────────────────────┐
│ 🔍 搜索用户、帖子... │  ← 搜索栏
├──────────────────────┤
│ [Post 1] [Post 2]   │
│ [Post 3] [Post 4]   │  ← 网格布局
│ [Post 5] [Post 6]   │
│ ...                  │
└──────────────────────┘
```

**特点**：
- ✅ 搜索栏（支持清除）
- ✅ 3 列网格布局
- ✅ 响应式设计
- ✅ 可滚动

### Profile 标签页
```
┌──────────────────────┐
│       👤 用户头像     │
│    John Doe          │
│    @johndoe          │
│  Product Designer    │
│                      │
│ 1.2K | 5.4K | 892   │  ← 统计
│ Posts│Followers│...  │
│                      │
│ [编辑资料] [...]     │  ← 按钮
├──────────────────────┤
│ [1] [2] [3]         │
│ [4] [5] [6]         │  ← 帖子网格
│ [7] [8] [9]         │
└──────────────────────┘
```

**特点**：
- ✅ 用户信息卡片
- ✅ 粉丝/关注统计
- ✅ 编辑和菜单按钮
- ✅ 用户帖子网格

---

## 🛠️ 故障排除

### 问题 1：Xcode 报错 "Cannot find module"
**解决方案**：
```bash
# 清理 Xcode 缓存
xcode-select --reset

# 或重新启动 Xcode
killall Xcode
open -a Xcode
```

### 问题 2：模拟器无法启动
**解决方案**：
```bash
# 检查可用模拟器
xcrun simctl list devices

# 删除并重新创建模拟器
xcrun simctl erase all

# 打开 Xcode 并创建新模拟器
# Xcode → Window → Devices and Simulators
```

### 问题 3：编译错误
**解决方案**：
```bash
# 删除 DerivedData
rm -rf ~/Library/Developer/Xcode/DerivedData/*

# 重新编译
cd /Users/proerror/Documents/nova/ios/NovaSocial
xcodebuild clean build
```

---

## 🎨 自定义预览

### 修改主题
编辑 `NovaSocialApp.swift`：
```swift
.preferredColorScheme(.dark)  // 改为暗黑模式
.preferredColorScheme(.light) // 改为浅色模式
```

### 修改设备预览
编辑预览配置：
```swift
#Preview {
    ContentView()
        .preferredColorScheme(nil)
        .previewDevice("iPhone 15")      // 更改设备
        .previewDevice("iPhone SE (3rd generation)")
        .previewDevice("iPad Pro (12.9-inch)")
}
```

---

## 📋 检查清单

运行时请验证以下功能：

- [ ] **Feed 标签页**
  - [ ] 显示 5 条帖子
  - [ ] 每条帖子显示用户、时间、内容
  - [ ] 点赞、评论、分享按钮可见
  - [ ] 列表可上下滚动

- [ ] **Explore 标签页**
  - [ ] 搜索栏正常显示
  - [ ] 网格布局 3 列
  - [ ] 12 个帖子占位符显示
  - [ ] 可以滚动

- [ ] **Profile 标签页**
  - [ ] 用户头像、名称、简介显示
  - [ ] 统计数据正确（1.2K / 5.4K / 892）
  - [ ] 编辑按钮和菜单按钮可见
  - [ ] 9 个帖子网格显示

- [ ] **通用**
  - [ ] 标签栏显示 3 个标签
  - [ ] 标签切换响应迅速
  - [ ] 文本清晰易读
  - [ ] 颜色搭配合理

---

## 📞 获取更多帮助

需要更多信息？查看这些文档：

- `QUICK_START.md` - 项目快速开始
- `PROJECT_STRUCTURE.md` - 项目结构
- `DesignSystem/QUICKSTART.md` - 设计系统
- `Documentation/FeedOptimizationGuide.md` - Feed 优化详情

---

**祝你使用愉快！** 🎉

有问题？所有代码都在 `/Users/proerror/Documents/nova/ios/NovaSocial/` 中。
