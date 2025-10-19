# Nova iOS App

## 项目概述
Nova 是一个生产级别的 iOS 社交媒体应用,使用 SwiftUI 构建,遵循 MVVM 架构模式。

## 快速开始

### 环境要求
- macOS 14.0+
- Xcode 15.0+
- iOS 16.0+ (Deployment Target)
- Swift 5.9+

### 安装步骤
```bash
# 1. Clone repository
git clone https://github.com/nova/ios.git
cd ios/NovaApp

# 2. Generate Xcode project (if using XcodeGen)
xcodegen generate

# 3. Open project
open NovaApp.xcodeproj

# 4. Build and run (⌘R)
```

## 项目结构

```
NovaApp/
├── NovaApp/                    # 主应用代码
│   ├── App.swift              # 应用入口 (@main)
│   ├── Navigation/            # 路由系统
│   │   ├── AppRouter.swift    # 21个路由定义
│   │   ├── NavigationCoordinator.swift
│   │   └── DeepLinkHandler.swift
│   ├── Auth/                  # 认证模块 (4个视图)
│   ├── Feed/                  # Feed模块 (3个视图)
│   ├── Create/                # 创建模块 (5个视图)
│   ├── Search/                # 搜索模块 (3个视图)
│   ├── Profile/               # 个人资料模块 (3个视图)
│   ├── Notifications/         # 通知模块 (2个视图)
│   ├── Settings/              # 设置模块 (3个视图)
│   ├── Data/                  # 数据层
│   │   ├── Repositories/      # 6个Repository
│   │   ├── Remote/            # APIClient + Endpoints
│   │   └── Local/             # Cache + Queue + Keychain
│   ├── DesignSystem/          # 设计系统
│   │   ├── Theme.swift        # 颜色/字体/间距
│   │   └── Components/        # 可复用组件
│   ├── Analytics/             # 分析系统
│   │   ├── Events.swift       # 16+事件类型
│   │   ├── AnalyticsTracker.swift
│   │   └── ClickHouseClient.swift
│   └── Utils/                 # 工具类
├── Tests/                     # 测试
│   ├── Unit/                  # 单元测试 (70%)
│   └── Integration/           # 集成测试 (25%)
├── Docs/                      # 文档 (8个MD文件)
│   ├── PROJECT_ARCHITECTURE.md
│   ├── ROUTING_MAP.md
│   ├── API_SPEC.md
│   ├── DATA_FLOW.md
│   ├── PERFORMANCE_CHECKLIST.md
│   ├── ACCESSIBILITY.md
│   ├── TESTING_STRATEGY.md
│   └── DEPLOYMENT_CHECKLIST.md
├── FIGMA_FRAMES.csv           # Figma框架映射
├── SPRINT_PLAN.md             # 2周冲刺计划
└── project.yml                # XcodeGen配置
```

## 核心功能

### 已实现 (架构/模板)
- ✅ **认证系统** - Email/密码登录 + Apple Sign In
- ✅ **Feed流** - 无限滚动 + 骨架加载器 + 缓存 (30s TTL)
- ✅ **Post交互** - 点赞/取消点赞 (乐观更新)
- ✅ **创建Post** - 照片选择 → 编辑 → 上传 (预签名URL)
- ✅ **搜索** - 用户搜索 (300ms节流)
- ✅ **个人资料** - 查看/编辑个人资料
- ✅ **通知** - 活动Feed (点赞/评论/关注)
- ✅ **设置** - 账户管理 + 隐私政策
- ✅ **分析** - 16+事件类型 → ClickHouse批量上传
- ✅ **离线支持** - 离线队列 (失败重试3次)
- ✅ **深度链接** - nova://app/* 和 https://nova.app/*

### 待完成 (Week 1-2)
- [ ] 完成所有View的实际实现 (当前为模板)
- [ ] 后端API集成 (15个端点)
- [ ] 单元测试 (目标覆盖率80%+)
- [ ] 性能优化 (达到P50延迟目标)
- [ ] 无障碍性审核
- [ ] TestFlight Beta测试

## 技术栈

### 框架
- **SwiftUI** - 声明式UI
- **Combine** - 响应式编程
- **AuthenticationServices** - Apple Sign In
- **Foundation** - 网络/数据处理

### 架构模式
- **MVVM** - Model-View-ViewModel
- **Repository Pattern** - 数据抽象
- **Coordinator Pattern** - 导航管理
- **Service Layer** - 业务逻辑

### 数据流
```
View → ViewModel → Repository → APIClient → Backend
         ↓
    @Published (reactive updates)
         ↓
    CacheManager (local persistence)
         ↓
    ActionQueue (offline queue)
```

## API集成

### 基础URL
```
生产环境: https://api.nova.app
开发环境: https://dev-api.nova.app
```

### 端点总数: 15
- 认证: 4个 (sign in, sign up, Apple, refresh)
- Feed: 2个 (feed, post detail)
- Post操作: 4个 (create, like, unlike, delete)
- 评论: 2个 (fetch, create)
- 搜索: 1个 (search users)
- 个人资料: 2个 (fetch, update, delete)

详见: [API_SPEC.md](./API_SPEC.md)

## 性能目标

| 指标 | 目标 (P50) |
|------|-----------|
| Feed初始加载 | < 500ms |
| Post详情 | < 300ms |
| 搜索结果 | < 400ms |
| 个人资料加载 | < 350ms |
| 图片上传 (2MB) | < 2.5s |

详见: [PERFORMANCE_CHECKLIST.md](./PERFORMANCE_CHECKLIST.md)

## 分析事件

### 16+事件类型
- **生命周期**: app_open, app_background, app_foreground
- **认证**: sign_in, sign_up, sign_out
- **Feed**: feed_view, post_impression, post_tap, post_like, post_unlike
- **评论**: comment_view, comment_create
- **上传**: upload_start, upload_success, upload_fail
- **搜索**: search_submit, search_result_click
- **个人资料**: profile_view, profile_update
- **通知**: notification_open
- **账户**: account_delete

详见: [Analytics/Events.swift](./NovaApp/Analytics/Events.swift)

## 测试策略

### 测试金字塔
- **单元测试 (70%)** - ViewModels, Repositories, Services
- **集成测试 (25%)** - 完整流程测试
- **E2E测试 (5%)** - 关键用户旅程

### 运行测试
```bash
# 所有测试
xcodebuild test -scheme NovaApp -destination 'platform=iOS Simulator,name=iPhone 15'

# 单个测试类
xcodebuild test -scheme NovaApp -only-testing:NovaAppTests/FeedViewModelTests

# 带覆盖率
xcodebuild test -scheme NovaApp -enableCodeCoverage YES
```

详见: [TESTING_STRATEGY.md](./TESTING_STRATEGY.md)

## 无障碍性

### 目标: WCAG 2.1 AA合规
- ✅ VoiceOver支持 (所有图片有标签)
- ✅ Dynamic Type支持 (所有字体可缩放)
- ✅ 颜色对比度 (最小4.5:1)
- ✅ Reduce Motion支持

详见: [ACCESSIBILITY.md](./ACCESSIBILITY.md)

## 深度链接

### 支持的URL格式
```
# 自定义Scheme
nova://app/post/abc123

# Web URL (用于分享)
https://nova.app/post/abc123

# 遗留格式 (向后兼容)
nova://post?id=abc123
```

### 示例
```swift
// 导航到Post详情
navigator.navigate(to: .postDetail(postId: "abc123"))

// 生成深度链接
DeepLinkHandler.generateWebLink(for: .postDetail(postId: "abc123"))
// → https://nova.app/post/abc123
```

详见: [ROUTING_MAP.md](./ROUTING_MAP.md)

## 部署

### TestFlight
1. 增加build number
2. Archive项目
3. 上传到App Store Connect
4. 提交Beta信息
5. 邀请测试者

### App Store
1. 提交App信息 (名称, 描述, 截图)
2. 填写App Review信息 (包括演示账户)
3. 提交审核
4. 监控状态 (2-7天)

详见: [DEPLOYMENT_CHECKLIST.md](./DEPLOYMENT_CHECKLIST.md)

## 贡献指南

### 分支策略
- `main` - 生产分支
- `develop` - 开发分支
- `feature/*` - 功能分支
- `hotfix/*` - 紧急修复分支

### 提交规范
```
feat: Add user profile editing
fix: Resolve feed loading crash
perf: Optimize image compression
docs: Update API documentation
test: Add FeedViewModel tests
```

### PR检查清单
- [ ] 所有测试通过
- [ ] SwiftLint无警告
- [ ] 更新文档 (如需要)
- [ ] 添加单元测试 (对于新功能)

## 常见问题

### Q: 如何切换API环境?
A: 在`APIClient.swift`中修改`baseURL`:
```swift
private init() {
    #if DEBUG
    self.baseURL = URL(string: "https://dev-api.nova.app")!
    #else
    self.baseURL = URL(string: "https://api.nova.app")!
    #endif
}
```

### Q: 如何清除缓存?
A: 调用`CacheManager.shared.clearAll()`

### Q: 如何测试深度链接?
A: 在模拟器中运行:
```bash
xcrun simctl openurl booted "nova://app/post/test123"
```

## 文档

- [项目架构](./PROJECT_ARCHITECTURE.md)
- [路由映射](./ROUTING_MAP.md)
- [API规范](./API_SPEC.md)
- [数据流](./DATA_FLOW.md)
- [性能检查清单](./PERFORMANCE_CHECKLIST.md)
- [无障碍性指南](./ACCESSIBILITY.md)
- [测试策略](./TESTING_STRATEGY.md)
- [部署检查清单](./DEPLOYMENT_CHECKLIST.md)
- [2周冲刺计划](./SPRINT_PLAN.md)

## 联系方式

- **项目主页**: https://nova.app
- **支持**: support@nova.app
- **后端团队**: backend@nova.app

## 许可证
MIT License - 详见 [LICENSE](./LICENSE)

---

**版本**: 1.0.0
**最后更新**: 2025-10-18
**作者**: Nova团队
