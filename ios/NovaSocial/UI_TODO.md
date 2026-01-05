- [x] 将全局依赖（AuthenticationManager 等）改为 App 注入 + EnvironmentObject，方便预览/单测。
- [x] 底部导航：Alice/Account 选中态样式统一，并用 safeAreaInset 代替 offset/padding。
- [x] Settings/Profile 选择器拆分到 Shared/UI/Components/Pickers，便于创建账号等场景复用。
- [ ] 文案/提示本地化，加载失败或操作失败提供可见提示（含 Dark Mode、消息列表）。
- [ ] 色值统一放入 DesignTokens，并补充暗色模式配色。
- [ ] 表单校验与禁用态优化（Profile 字段为空/非法时提示并禁用保存）。

## 🐛 Bug Fixes

- [ ] **[HIGH] Post 图片上传后失真问题**
  - **问题描述**: 用户通过 Post 上传的照片显示明显失真/模糊
  - **根本原因**: `BackgroundUploadManager.swift` 中图片压缩使用了 `.low` 质量级别
    - 压缩质量: 50%
    - 最大尺寸: 1080px
    - 目标大小: ~100KB（超过则继续降质到 20%）
  - **影响文件**: 
    - `Shared/Services/Upload/BackgroundUploadManager.swift` (第 273、316 行)
    - `Shared/Services/Media/ImageCompressor.swift` (压缩逻辑定义)
  - **修复方案**: 将压缩质量从 `.low` 改为 `.high`
    - `.high`: 85% 质量, 最大 2048px, 目标 ~600KB
  - **预期效果**: 图片清晰度大幅提升，上传速度影响较小
