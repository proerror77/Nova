# Figma Tokens Studio 设置指南

为设计师提供的 Figma Tokens Studio 导入和管理指南。

## 📋 前置条件

- ✅ Figma 账户
- ✅ Tokens Studio 插件（已安装）
- ✅ 对项目有编辑权限

## 🚀 快速开始

### Step 1: 打开 Tokens Studio 插件

1. 在 Figma 中打开 Nova 项目
2. **Assets** → **Plugins** → **Tokens Studio**
3. 点击 **Tokens** 标签

### Step 2: 导入 tokens.design.json

1. **Tokens Studio** → **Settings** （齿轮图标）
2. 点击 **JSON / API** 标签
3. 选择 **Import Tokens from JSON**
4. **上传文件**: `frontend/design-system/tokens.design.json`
5. 点击 **Import** 确认

### Step 3: 确认导入成功

应该看到 4 个主题集合：
- ✅ `brandA.light`
- ✅ `brandA.dark`
- ✅ `brandB.light`
- ✅ `brandB.dark`

---

## 🎨 主题切换

### 查看不同主题

1. **Tokens Studio** → **Theme 选择器** （顶部）
2. 选择要预览的主题：
   - BrandA Light
   - BrandA Dark
   - BrandB Light
   - BrandB Dark

### 实时预览

当选择不同主题时，所有绑定到 tokens 的组件会**立即更新颜色**。

---

## 🔧 编辑 Tokens

### 编辑颜色值

1. **Tokens Studio** → **选择主题**（例如 "BrandA Light"）
2. 展开 **color** 部分
3. 点击要编辑的颜色（例如 `bg.surface`）
4. 修改 hex 值
5. 更改**自动保存**到 JSON

### 编辑排版

1. 展开 **type** 部分
2. 点击 `scale` 部分
3. 编辑 fontSize、lineHeight、fontWeight
4. 自动保存

### 编辑间距

1. 展开 **space** 部分
2. 修改 px 值（例如 `sm: 8` → `sm: 10`）
3. **所有使用 {space.sm} 的组件自动更新**

---

## 🔄 工作流程

### 典型工作流

```
1. 设计师在 Figma 中修改 token
   ↓
2. Tokens Studio 自动更新 JSON
   ↓
3. 导出 JSON
   ↓
4. 更新 frontend/design-system/tokens.design.json
   ↓
5. 开发者重新生成平台代码
   ↓
6. iOS/Android 自动反映新颜色
```

### 导出步骤

1. **修改完成后**，点击 **Tokens Studio** → **Settings**
2. 选择 **Export Tokens as JSON**
3. **复制 JSON** 内容
4. 更新 `frontend/design-system/tokens.design.json`
5. 通知开发者重新生成代码

---

## 🎯 绑定 Figma 组件

### 为 Button 组件绑定颜色 Token

1. **选择组件** → Button
2. **右键** → **Edit component**
3. 选择背景形状
4. **右侧面板** → **Fill 颜色值**
5. 点击颜色旁的 **Token 图标**（魔法棒）
6. 选择 `brand.primary`
7. **应用**

### 结果

现在当你在 Tokens Studio 中改变 `brand.primary` 时，所有 Button 组件会自动更新。

---

## 📊 Token 结构说明

```json
{
  "core": {              // 基础 tokens（所有主题共用）
    "color": {
      "palette": {       // 原始颜色库
        "gray": { 0-900 },
        "blue": { 500-700 },
        "coral": { 500-700 },
        "green": { 500 },
        "amber": { 500 }
      }
    },
    "type": { ... },     // 字体定义
    "space": { ... },    // 间距定义
    "radius": { ... },   // 圆角定义
    "motion": { ... }    // 动效定义
  },

  "brandA.light": {      // Brand A 浅色主题
    "color": {
      "bg": { ... },       // 背景颜色
      "fg": { ... },       // 前景颜色
      "brand": { ... },    // 品牌色
      "border": { ... },   // 边框颜色
      "state": { ... }     // 状态颜色
    }
  },

  "brandA.dark": { ... },   // Brand A 深色主题
  "brandB.light": { ... },  // Brand B 浅色主题
  "brandB.dark": { ... }    // Brand B 深色主题
}
```

---

## ✅ 最佳实践

### Do ✅

- **使用语义化名称**: `brand.primary` 而不是 `color1`
- **分组组织**: 在 UI 中按功能分组 (bg/fg/brand/border/state)
- **定期导出**: 每次修改后导出新的 JSON
- **版本控制**: 在 git 中跟踪 tokens.design.json
- **测试**: 在所有 4 个主题中测试颜色

### Don't ❌

- **不要手动编辑 JSON**: 使用 Figma UI 编辑
- **不要创建不必要的 tokens**: 优先使用现有 token
- **不要跳过深色主题**: 确保所有主题都定义了
- **不要忘记导出**: 修改后记得导出给开发者

---

## 🔗 引用关系

### Token 引用

```json
{
  "brandA.light": {
    "color": {
      "bg": {
        "surface": { "value": "{core.color.palette.gray.0}" }
                             ↑ 引用核心 palette
      }
    }
  }
}
```

**好处**:
- 修改 `core.color.palette.gray.0` 时，所有使用它的主题自动更新
- 单一数据源，无重复

---

## 🐛 常见问题

### Q: JSON 导入后看不到 tokens？

**A**:
1. 确认文件格式正确（有效的 JSON）
2. 检查 $metadata 和 $themes 部分
3. 重新刷新 Figma 页面
4. 重新打开 Tokens Studio 插件

### Q: 修改后组件没有更新？

**A**:
1. 确认组件已绑定到正确的 token
2. 检查绑定是否生效（看魔法棒图标）
3. 在 Tokens Studio 中手动刷新
4. 重新选择主题查看变化

### Q: 如何为新品牌 (BrandC) 添加 tokens？

**A**:
1. 在 JSON 中添加 `"brandC.light": { ... }` 和 `"brandC.dark": { ... }`
2. 在 $themes 中添加两个新主题配置
3. 填充 11 个语义颜色
4. 导入更新后的 JSON
5. 在 Tokens Studio 中选择新主题预览

### Q: 颜色看起来不对？

**A**:
1. 检查 Figma 的色彩模式设置（sRGB vs. P3）
2. 在多个设备/浏览器上验证
3. 比较 hex 值和 iOS/Android 实现中的值
4. 考虑 Figma 到原生平台的色彩管理差异

---

## 📱 与开发的协作

### 设计师应该提供

1. ✅ **导出的 tokens.design.json**
2. ✅ **所有 4 主题的预览截图**
3. ✅ **变更日志** (哪些 tokens 被修改)
4. ✅ **新品牌/主题的规范**

### 开发者会

1. 使用 JSON 生成 iOS xcassets 和 Android colors.xml
2. 自动生成 Theme.swift 和 Theme.kt
3. 运行验证以确保颜色匹配
4. 部署到应用程序

### 反馈循环

```
设计师修改 → 导出 JSON → 开发者生成代码 → 开发者运行应用
                                           ↓
                                      视觉审查
                                           ↓
                                      (需要调整？)
                                           ↓
                              设计师调整 token 值
```

---

## 📚 更多资源

- 🔗 [Tokens Studio 官方文档](https://tokens.studio/)
- 🔗 [Figma Tokens 设计系统指南](https://www.figma.com/design-systems/)
- 📖 [Nova Design System 规范](./design.md)
- 💻 [开发者集成指南](./INTEGRATION_GUIDE.md)

---

**最后更新**: 2025-10-18
**面向对象**: 设计师
**难度**: 初级 ⭐
