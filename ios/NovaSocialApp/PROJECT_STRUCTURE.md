# Nova Social iOS - 完整项目结构

## 📊 统计数据

- **总文件数**: 57 个 Swift 文件
- **UI 层**: 15 个 View + 7 个 ViewModel
- **网络层**: 16 个文件（已存在）
- **测试**: 12 个测试文件（已存在）

## 🏗 完整文件树

```
NovaSocial/
│
├── 📱 App/ (应用入口) - 2 个文件
│   ├── NovaSocialApp.swift          # @main 入口点，AppState 定义
│   └── ContentView.swift            # 根视图（认证/主应用切换）+ MainTabView
│
├── 🧠 ViewModels/ (视图模型) - 7 个文件
│   │
│   ├── Auth/
│   │   └── AuthViewModel.swift                    # 登录/注册状态管理
│   │
│   ├── Feed/
│   │   ├── FeedViewModel.swift                    # Feed 流状态（分页、刷新、点赞）
│   │   └── PostDetailViewModel.swift              # 帖子详情状态（评论、点赞）
│   │
│   ├── Post/
│   │   └── CreatePostViewModel.swift              # 创建帖子状态（图片、上传）
│   │
│   ├── User/
│   │   └── UserProfileViewModel.swift             # 用户资料状态（关注、帖子）
│   │
│   └── Common/
│       ├── ExploreViewModel.swift                 # 探索页状态（帖子、搜索）
│       └── NotificationViewModel.swift            # 通知状态（列表、已读）
│
├── 🎨 Views/ (SwiftUI 视图) - 15 个文件
│   │
│   ├── Auth/ (认证页面) - 3 个文件
│   │   ├── AuthenticationView.swift               # 认证容器（登录/注册切换）
│   │   ├── LoginView.swift                        # 登录页面
│   │   └── RegisterView.swift                     # 注册页面
│   │
│   ├── Feed/ (Feed 页面) - 3 个文件
│   │   ├── FeedView.swift                         # Feed 主页面（列表、刷新）
│   │   ├── PostCell.swift                         # 帖子卡片组件（包含 PostHeaderView）
│   │   └── PostDetailView.swift                   # 帖子详情页（评论列表、输入）
│   │
│   ├── Post/ (帖子创建) - 1 个文件
│   │   └── CreatePostView.swift                   # 创建帖子页（图片选择、上传、ImagePicker）
│   │
│   ├── User/ (用户页面) - 2 个文件
│   │   ├── ProfileView.swift                      # 用户资料页（包含 ProfileHeaderView, StatView, PostsGridView）
│   │   └── SettingsView.swift                     # 设置页面
│   │
│   ├── Explore/ (探索和通知) - 2 个文件
│   │   ├── ExploreView.swift                      # 探索页面（搜索、网格、SearchBar, UserRowView）
│   │   └── NotificationView.swift                 # 通知页面（列表、跳转、NotificationCell）
│   │
│   └── Common/ (可复用组件) - 4 个文件
│       ├── Styles.swift                           # 按钮和输入框样式
│       ├── LoadingView.swift                      # 加载组件（LoadingView, LoadingOverlay）
│       ├── ErrorMessageView.swift                 # 错误和空状态（ErrorMessageView, EmptyStateView）
│       └── AsyncImageView.swift                   # 异步图片（AsyncImageView, CachedAsyncImage）
│
├── 🌐 Network/ (网络层 - 已存在) - 16 个文件
│   │
│   ├── Core/                                      # 核心网络组件
│   │   ├── APIClient.swift                        # 网络请求客户端
│   │   ├── AuthManager.swift                      # 认证管理（Token、Keychain）
│   │   ├── RequestInterceptor.swift               # 请求拦截器（重试、刷新）
│   │   └── RequestDeduplicator.swift              # 请求去重
│   │
│   ├── Models/                                    # 数据模型
│   │   ├── APIModels.swift                        # 核心数据模型
│   │   ├── APIError.swift                         # 错误类型
│   │   └── APIResponses.swift                     # 响应模型
│   │
│   ├── Repositories/                              # Repository 层
│   │   ├── AuthRepository.swift                   # 认证业务逻辑
│   │   ├── FeedRepository.swift                   # Feed 业务逻辑（含缓存）
│   │   ├── PostRepository.swift                   # 帖子业务逻辑
│   │   ├── UserRepository.swift                   # 用户业务逻辑
│   │   └── NotificationRepository.swift           # 通知业务逻辑
│   │
│   ├── Services/                                  # 服务层
│   │   ├── CacheManager.swift                     # 缓存管理
│   │   ├── NetworkMonitor.swift                   # 网络监控
│   │   ├── PerformanceKit.swift                   # 性能监控
│   │   ├── PerformanceMetrics.swift               # 性能指标
│   │   ├── PerformanceDebugView.swift             # 性能调试视图
│   │   ├── RequestDeduplicator.swift              # 请求去重服务
│   │   └── URLCacheConfig.swift                   # URL 缓存配置
│   │
│   └── Utils/                                     # 工具类
│       ├── AppConfig.swift                        # 应用配置
│       └── Logger.swift                           # 日志工具
│
├── 🧪 Tests/ (测试 - 已存在) - 12 个文件
│   │
│   ├── NetworkTests.swift                         # 网络层测试
│   ├── PerformanceTests.swift                     # 性能测试
│   │
│   ├── Unit/                                      # 单元测试
│   │   ├── AuthRepositoryTests.swift              # 认证测试
│   │   ├── FeedRepositoryTests.swift              # Feed 测试
│   │   ├── CacheTests.swift                       # 缓存测试
│   │   ├── ConcurrencyTests.swift                 # 并发测试
│   │   └── ErrorHandlingTests.swift               # 错误处理测试
│   │
│   ├── Performance/                               # 性能测试
│   │   └── NetworkPerformanceTests.swift          # 网络性能测试
│   │
│   └── Mocks/                                     # Mock 对象
│       ├── MockAuthManager.swift                  # Mock 认证管理器
│       ├── MockURLProtocol.swift                  # Mock URL 协议
│       └── TestFixtures.swift                     # 测试数据
│
├── 📖 Examples/ (示例代码 - 已存在) - 2 个文件
│   ├── NetworkUsageExamples.swift                 # 网络层使用示例
│   └── PerformanceOptimizationExamples.swift      # 性能优化示例
│
├── 📄 Documentation/ (文档)
│   ├── README.md                                  # 项目说明
│   ├── QUICK_START.md                             # 快速入门
│   └── PROJECT_STRUCTURE.md                       # 本文件
│
└── TOKEN_REFRESH_EXAMPLE.swift                    # Token 刷新示例

```

## 🎯 核心组件说明

### 应用入口 (App/)

#### NovaSocialApp.swift
```swift
- @main 应用入口点
- AppState 全局状态管理类
- 检查登录状态
- 提供 EnvironmentObject
```

#### ContentView.swift
```swift
- 根视图（认证/主应用切换）
- MainTabView（5 个 Tab）
  - Home (FeedView)
  - Explore (ExploreView)
  - Create (CreatePostView)
  - Notifications (NotificationView)
  - Profile (ProfileView)
```

### 视图模型层 (ViewModels/)

所有 ViewModel 都遵循以下模式：

```swift
@MainActor                          // 确保线程安全
final class XXXViewModel: ObservableObject {
    @Published var data: [Model]    // 响应式数据
    @Published var isLoading: Bool  // 加载状态
    @Published var errorMessage: String?  // 错误消息

    func loadData() async { }       // 异步数据加载
    func refresh() async { }        // 刷新数据
    private func showError() { }    // 错误处理
}
```

#### 7 个核心 ViewModel：

1. **AuthViewModel** - 认证状态
   - 登录/注册表单验证
   - 异步登录/注册
   - 错误处理

2. **FeedViewModel** - Feed 流
   - 分页加载
   - 下拉刷新
   - 无限滚动
   - 乐观点赞更新

3. **PostDetailViewModel** - 帖子详情
   - 评论列表加载
   - 添加评论
   - 点赞切换

4. **CreatePostViewModel** - 创建帖子
   - 图片选择
   - 上传进度
   - 表单验证

5. **UserProfileViewModel** - 用户资料
   - 加载用户信息
   - 关注/取消关注
   - 用户帖子网格

6. **ExploreViewModel** - 探索
   - 探索帖子网格
   - 用户搜索（防抖）
   - 搜索结果

7. **NotificationViewModel** - 通知
   - 通知列表
   - 标记已读
   - 未读计数

### 视图层 (Views/)

#### 认证页面 (3 个)
- AuthenticationView: 登录/注册切换容器
- LoginView: 登录表单
- RegisterView: 注册表单

#### Feed 页面 (3 个)
- FeedView: Feed 主列表
- PostCell: 单个帖子卡片
- PostDetailView: 帖子详情（含评论）

#### 帖子创建 (1 个)
- CreatePostView: 创建帖子（含 ImagePicker）

#### 用户页面 (2 个)
- ProfileView: 用户资料（含多个子组件）
- SettingsView: 设置页面

#### 探索和通知 (2 个)
- ExploreView: 探索页（含搜索）
- NotificationView: 通知列表

#### 可复用组件 (4 个)
- **Styles.swift**: 按钮和输入框样式
  - PrimaryButtonStyle
  - SecondaryButtonStyle
  - RoundedTextFieldStyle

- **LoadingView.swift**: 加载组件
  - LoadingView（基础加载）
  - LoadingOverlay（遮罩加载）

- **ErrorMessageView.swift**: 错误和空状态
  - ErrorMessageView（错误提示）
  - EmptyStateView（空状态占位）

- **AsyncImageView.swift**: 异步图片
  - AsyncImageView（基础异步）
  - CachedAsyncImage（带缓存）

### 网络层 (Network/)

完整的 Repository 模式网络层：

- **5 个 Repository**: Auth, Feed, Post, User, Notification
- **缓存支持**: FeedCache（UserDefaults）
- **离线优先**: 先返回缓存，后台刷新
- **Token 管理**: 自动刷新、Keychain 存储
- **错误处理**: 统一错误类型
- **性能监控**: 完整的性能追踪

## 📐 架构图

```
┌─────────────────────────────────────────────────────┐
│                   SwiftUI Views                     │
│  ┌──────────┬──────────┬──────────┬──────────┐    │
│  │  Auth    │   Feed   │   Post   │  Profile  │    │
│  └────┬─────┴─────┬────┴─────┬────┴────┬─────┘    │
└───────┼───────────┼──────────┼─────────┼──────────┘
        │           │          │         │
        ▼           ▼          ▼         ▼
┌─────────────────────────────────────────────────────┐
│                   ViewModels                        │
│         (@Published, @MainActor, Combine)           │
└─────────────────────┬───────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────┐
│                  Repositories                       │
│    (Business Logic, Caching, Error Handling)        │
└─────────────────────┬───────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────┐
│                   APIClient                         │
│     (Networking, Auth, Retry, Deduplication)        │
└─────────────────────┬───────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────┐
│                Backend API (Rust)                   │
└─────────────────────────────────────────────────────┘
```

## 🔄 数据流

### 1. 用户登录流程
```
LoginView
  ↓ 用户输入
AuthViewModel.login()
  ↓ 调用
AuthRepository.login()
  ↓ 网络请求
APIClient.request()
  ↓ 成功响应
AuthManager.saveAuth()
  ↓ 更新状态
AppState.isAuthenticated = true
  ↓ UI 切换
MainTabView 显示
```

### 2. Feed 加载流程
```
FeedView.task
  ↓ 触发
FeedViewModel.loadFeed()
  ↓ 检查缓存
FeedRepository.loadFeed()
  ├─ 有缓存：立即返回 + 后台刷新
  └─ 无缓存：网络请求
    ↓ 请求
APIClient.request()
  ↓ 响应
FeedCache.cacheFeed()
  ↓ 更新
@Published var posts
  ↓ 渲染
FeedView 显示列表
```

### 3. 点赞流程（乐观更新）
```
PostCell 点击 ❤️
  ↓ 立即
FeedViewModel.toggleLike()
  ├─ 立即更新本地状态
  │   isLiked = true
  │   likeCount += 1
  │   UI 立即响应
  │
  └─ 后台同步
      PostRepository.likePost()
        ↓ 成功：保持状态
        ↓ 失败：回滚状态
```

## 🎨 UI 组件复用策略

### 高度复用的组件

1. **AsyncImageView** - 使用 12+ 次
   - PostCell、ProfileView、NotificationCell
   - ExploreView、CommentCell、UserRowView

2. **LoadingView** - 使用 8+ 次
   - 所有列表页的初始加载
   - 所有 ViewModel 的 isLoading 状态

3. **ErrorMessageView** - 使用 7+ 次
   - 所有表单的错误提示
   - 所有 ViewModel 的错误处理

4. **EmptyStateView** - 使用 6+ 次
   - FeedView、ProfileView、ExploreView
   - NotificationView、SearchResults

5. **ButtonStyles** - 使用 10+ 次
   - 所有表单提交按钮
   - 所有操作按钮

## 📊 代码规模

### View 层
- 15 个主视图文件
- 约 2000 行 SwiftUI 代码
- 平均每个 View 约 130 行

### ViewModel 层
- 7 个 ViewModel 文件
- 约 1000 行状态管理代码
- 平均每个 ViewModel 约 140 行

### 可复用组件
- 4 个组件文件
- 约 400 行可复用代码
- 被使用 50+ 次

### 网络层（已存在）
- 16 个网络文件
- 约 2500 行网络代码

## 🚀 技术栈

- **UI 框架**: SwiftUI (iOS 16+)
- **架构**: MVVM + Repository 模式
- **异步**: async/await + Combine
- **导航**: NavigationStack (iOS 16+)
- **状态管理**: @Published + @StateObject + @EnvironmentObject
- **网络**: URLSession + Codable
- **缓存**: UserDefaults (简单缓存)
- **安全**: Keychain (Token 存储)

## 📱 支持的功能

- ✅ 用户认证（登录/注册/登出）
- ✅ Feed 流（无限滚动、下拉刷新）
- ✅ 帖子详情（评论列表、添加评论）
- ✅ 创建帖子（图片上传、进度显示）
- ✅ 用户资料（关注、帖子网格、统计）
- ✅ 探索页面（帖子网格）
- ✅ 用户搜索（防抖搜索）
- ✅ 通知系统（列表、标记已读）
- ✅ 设置页面（登出）
- ✅ 离线缓存（Feed 缓存）
- ✅ 乐观更新（点赞、关注）
- ✅ 错误处理（统一错误处理）
- ✅ 加载状态（Loading、Refreshing）

## 🎯 下一步扩展

### 短期（1-2 周）
- [ ] Core Data 持久化
- [ ] Kingfisher 图片缓存
- [ ] 单元测试（ViewModel 层）
- [ ] UI 测试

### 中期（1-2 月）
- [ ] 故事（Stories）功能
- [ ] 私信系统
- [ ] 推送通知
- [ ] 深链接

### 长期（3+ 月）
- [ ] 视频支持（Reels）
- [ ] AR 滤镜
- [ ] 直播功能
- [ ] iPad 适配

## 📄 相关文档

- [README.md](README.md) - 项目完整说明
- [QUICK_START.md](QUICK_START.md) - 快速启动指南
- [Examples/NetworkUsageExamples.swift](Examples/NetworkUsageExamples.swift) - 网络层使用示例
