# Nova Social iOS 可访问性测试清单

## ✅ VoiceOver 测试清单

### 基础检查
- [ ] **启用 VoiceOver**: 设置 → 辅助功能 → VoiceOver → 开启
- [ ] **所有按钮有清晰的 label**: 点击任何按钮时，VoiceOver 读出准确描述
- [ ] **所有图片有描述**: 头像、帖子图片等都有语义化描述
- [ ] **装饰性图片被隐藏**: Logo、背景图等不被 VoiceOver 读出
- [ ] **焦点顺序正确**: 从上到下、从左到右的逻辑顺序

### 表单可访问性
- [ ] **输入框有 label**: 邮箱、密码等字段有清晰标签
- [ ] **输入框有 hint**: 提供额外说明（如"请输入您的邮箱"）
- [ ] **输入框有 value**: 读出当前输入的值或"未填写"
- [ ] **错误消息可读**: 表单验证错误时，VoiceOver 读出错误信息
- [ ] **提交按钮状态**: 读出"正在加载"或"登录"等状态

### Feed 流测试
- [ ] **帖子内容可读**: VoiceOver 读出用户名、文字内容、点赞数
- [ ] **操作按钮可用**: 点赞、评论、分享、收藏按钮都能触发
- [ ] **自定义操作**: 可以通过 VoiceOver 转轮快速操作
- [ ] **无限滚动**: 到达底部时，VoiceOver 提示"正在加载更多"

### 导航测试
- [ ] **Tab 切换**: 底部 Tab 有清晰的 label（首页、探索、发布等）
- [ ] **返回按钮**: 导航栏返回按钮读出"返回"
- [ ] **关闭按钮**: Modal 关闭按钮读出"关闭"

---

## 📏 触控区域测试清单

### 最小尺寸要求
- [ ] **所有按钮 ≥ 44x44pt**: 使用 `.minTouchTarget()` modifier
- [ ] **可交互元素间距 ≥ 8pt**: 避免误触
- [ ] **底部 Tab 按钮**: 高度至少 44pt

### 特殊元素
- [ ] **点赞按钮**: 44x44pt 可触碰区域
- [ ] **关注按钮**: 高度 44pt
- [ ] **头像**: 可点击区域覆盖整个头像
- [ ] **帖子图片**: 整张图片可点击

---

## 🎨 颜色对比度测试清单

### 文本对比度
- [ ] **正文文本对比度 ≥ 4.5:1**: 黑色文字 vs 白色背景
- [ ] **大号文本对比度 ≥ 3:1**: 标题、用户名等
- [ ] **按钮文字**: 白色文字 vs 蓝色背景（对比度检查）
- [ ] **链接文字**: 蓝色链接 vs 白色背景

### 色盲友好
- [ ] **不仅依赖颜色**: 错误消息有图标 + 文字
- [ ] **点赞状态**: 实心❤️ vs 空心♡（不仅是颜色变化）
- [ ] **关注状态**: "已关注" vs "关注"（文字提示）

### 工具推荐
- Xcode Accessibility Inspector（内置）
- Contrast Checker（在线工具）
- Color Oracle（模拟色盲）

---

## ⌨️ 键盘导航测试清单

### iPad 外接键盘
- [ ] **Tab 键导航**: 按 Tab 键在可交互元素间切换
- [ ] **Enter 键激活**: 按 Enter 激活当前聚焦的按钮
- [ ] **Esc 键关闭**: 按 Esc 关闭 Modal 或弹窗
- [ ] **方向键**: 在列表中上下移动

### 快捷键（可选）
- [ ] **Cmd + N**: 创建新帖子
- [ ] **Cmd + W**: 关闭当前页面
- [ ] **Cmd + T**: 切换 Tab

---

## 📱 Dynamic Type 测试清单

### 文字大小
- [ ] **最小字体**: 16pt（正文）
- [ ] **支持放大**: 文字大小随系统设置缩放
- [ ] **最大缩放**: 支持到 accessibility3（超大字体）
- [ ] **不截断**: 大字体时，文字不被截断
- [ ] **布局自适应**: 元素高度随文字大小调整

### 测试步骤
1. 打开设置 → 辅助功能 → 显示与文字大小 → 更大字体
2. 拖动滑块到最大
3. 打开 Nova Social，检查所有页面

---

## 🎬 动画安全测试清单

### Reduce Motion
- [ ] **检测设置**: 使用 `AccessibilitySettings.reduceMotion`
- [ ] **禁用动画**: 减少动画开启时，移除 `.animation()` 效果
- [ ] **保留功能**: 即使没有动画，功能正常工作
- [ ] **替代方案**: 用淡入淡出替代复杂动画

### 测试步骤
1. 打开设置 → 辅助功能 → 动态效果 → 减少动态效果
2. 打开 Nova Social
3. 测试点赞、刷新、导航等操作

### 闪烁内容（如有）
- [ ] **频率 < 3Hz**: 避免触发癫痫
- [ ] **可停止**: 提供停止动画的选项

---

## 🔍 具体页面测试

### 登录页面 (LoginView)
- [x] **邮箱输入框**: VoiceOver 读"邮箱地址，文本框，未填写"
- [x] **密码输入框**: VoiceOver 读"密码，安全文本框，已输入"
- [x] **忘记密码按钮**: 44x44pt 可触碰区域
- [x] **登录按钮**: 高度 48pt，禁用时提示"请填写完整信息"
- [ ] **错误消息**: 红色文字 + 图标，对比度 ≥ 4.5:1

### Feed 页面 (FeedView)
- [x] **帖子卡片**: VoiceOver 读完整帖子信息
- [x] **点赞按钮**: "已点赞" vs "点赞"，44x44pt
- [x] **评论按钮**: "评论，按钮，双击查看评论"
- [x] **头像**: "用户名 的头像，图片，双击查看资料"
- [ ] **下拉刷新**: VoiceOver 读"正在刷新"

### 创建帖子 (CreatePostView)
- [ ] **图片选择**: VoiceOver 读"选择图片，按钮"
- [ ] **文字输入**: 支持 Dynamic Type
- [ ] **发布按钮**: 禁用时读出原因

### 用户资料 (ProfileView)
- [ ] **头像**: 大头像可点击查看大图
- [ ] **关注按钮**: 状态明确（已关注 vs 关注）
- [ ] **帖子网格**: 每张图片有 alt text

### 通知页面 (NotificationView)
- [ ] **未读标识**: 不仅是颜色，有"未读"文字
- [ ] **通知内容**: VoiceOver 读完整通知信息
- [ ] **操作按钮**: 关注、查看等按钮 44x44pt

---

## 🛠 测试工具

### Xcode 内置工具
1. **Accessibility Inspector**（⌘ + 7）
   - 检查 label、hint、value
   - 检查触控区域大小
   - 检查对比度

2. **Environment Overrides**
   - 测试 Dynamic Type
   - 测试暗黑模式
   - 测试 Reduce Motion

3. **Instruments - Accessibility**
   - 记录 VoiceOver 使用
   - 发现可访问性问题

### 第三方工具
- **Contrast**（macOS）: 对比度检查
- **Color Oracle**: 模拟色盲
- **WAVE**（Web）: 对比度和可访问性检查

---

## 📊 测试报告模板

```markdown
## 可访问性测试报告

**测试日期**: 2025-10-19
**测试人**: [姓名]
**iOS 版本**: 18.0
**设备**: iPhone 15 Pro

### VoiceOver 测试
- ✅ 所有按钮有 label
- ❌ 帖子图片缺少 alt text（已修复）
- ✅ 焦点顺序正确

### 触控区域测试
- ✅ 所有按钮 ≥ 44x44pt
- ✅ 底部 Tab 高度 50pt

### 对比度测试
- ✅ 正文文字对比度 8.5:1
- ⚠️ 次要文字对比度 3.2:1（建议提高到 4.5:1）

### Dynamic Type 测试
- ✅ 文字大小正确缩放
- ✅ 布局自适应

### Reduce Motion 测试
- ✅ 动画可禁用
- ✅ 功能不受影响

### 发现的问题
1. [问题描述]
2. [修复方案]

### 总体评分
**可访问性得分**: 95/100
**建议**: [改进建议]
```

---

## 🎯 快速自测（30秒）

1. **启用 VoiceOver** → 点击首页 → 能听到帖子内容吗？
2. **放大文字** → 打开应用 → 文字是否被截断？
3. **启用减少动画** → 刷新 Feed → 功能正常吗？
4. **外接键盘** → 按 Tab 键 → 能导航吗？

---

## 📚 参考资源

- [Apple Human Interface Guidelines - Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [WCAG 2.1 Guidelines](https://www.w3.org/WAI/WCAG21/quickref/)
- [SwiftUI Accessibility Documentation](https://developer.apple.com/documentation/swiftui/accessibility)
- [Color Contrast Checker](https://webaim.org/resources/contrastchecker/)

---

## ✅ 完成标准

**应用可以提交 App Store 的条件**:

- ✅ 所有交互元素有明确的 accessibility label
- ✅ 所有按钮 ≥ 44x44pt
- ✅ 文本对比度 ≥ 4.5:1
- ✅ 支持 VoiceOver 完整导航
- ✅ 支持 Dynamic Type
- ✅ 尊重 Reduce Motion 设置
- ✅ 通过 Xcode Accessibility Inspector 检查
- ✅ 至少一个视障用户测试通过

**理想标准（可选）**:

- 🎯 支持自定义 VoiceOver 操作
- 🎯 支持键盘快捷键
- 🎯 提供可访问性设置页面
- 🎯 支持辅助触控（Assistive Touch）
- 🎯 支持听写输入
