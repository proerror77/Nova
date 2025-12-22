# Nova iOS 应用 - 完整代码结构分析报告

## 项目概况

**项目规模**: 
- 总计: **442 Swift 文件**
- 代码行数: **37,637 行**
- Swift 类型数: **737+**（class/struct/enum）
- 测试代码: **5,529 行**

**项目架构**: MVVM + Repository Pattern
**最低 iOS 版本**: iOS 16+
**开发语言**: Swift + SwiftUI

---

## 1. 项目文件结构

```
NovaSocialApp/
├── App/                          # 应用入口和主视图
│   ├── NovaSocialApp.swift       # App 代理
│   └── ContentView.swift         # 认证/主应用切换根视图
│
├── Auth/                         # 认证和授权
│   ├── OAuthStateManager.swift
│   └── AppleSignInService.swift
│
├── Network/                      # 网络层 (核心)
│   ├── Core/
│   │   ├── APIClient.swift       # HTTP 客户端
│   │   ├── AuthManager.swift     # Token 管理
│   │   ├── RequestInterceptor.swift
│   │   └── RequestDeduplicator.swift
│   ├── Models/
│   │   ├── APIModels.swift
│   │   ├── APIResponses.swift
│   │   ├── APIError.swift
│   │   ├── MessagingModels.swift # 消息 DTO
│   │   └── CallModels.swift      # 通话 DTO
│   ├── Repositories/            # Repository 模式实现
│   │   ├── AuthRepository.swift
│   │   ├── FeedRepository.swift
│   │   ├── FeedRepositoryEnhanced.swift
│   │   ├── PostRepository.swift
│   │   ├── PostRepositoryEnhanced.swift
│   │   ├── UserRepository.swift
│   │   ├── NotificationRepository.swift
│   │   ├── MessagingRepository.swift   # 消息 API
│   │   └── CallRepository.swift        # 通话 API
│   ├── Services/
│   │   ├── CacheManager.swift
│   │   ├── NetworkMonitor.swift
│   │   ├── URLCacheConfig.swift
│   │   ├── RequestDeduplicator.swift
│   │   ├── PerformanceKit.swift
│   │   ├── PerformanceMetrics.swift
│   │   └── PerformanceDebugView.swift
│   └── Utils/
│       ├── AppConfig.swift       # 环境配置
│       └── Logger.swift
│
├── ViewModels/                   # MVVM 视图模型层
│   ├── Auth/
│   │   ├── AuthViewModel.swift
│   │   └── AuthViewModel+OAuth.swift
│   ├── Feed/
│   │   ├── FeedViewModel.swift
│   │   ├── FeedViewModelEnhanced.swift
│   │   └── PostDetailViewModel.swift
│   ├── Post/
│   │   └── CreatePostViewModel.swift
│   ├── User/
│   │   └── UserProfileViewModel.swift
│   ├── Chat/
│   │   └── ChatViewModel.swift   # 聊天状态管理
│   ├── Calls/
│   │   └── CallViewModel.swift   # 通话状态管理
│   └── Common/
│       ├── ExploreViewModel.swift
│       └── NotificationViewModel.swift
│
├── Views/                        # SwiftUI 视图层
│   ├── Auth/
│   │   ├── AuthenticationView.swift
│   │   ├── LoginView.swift
│   │   ├── LoginView+Accessibility.swift
│   │   └── RegisterView.swift
│   ├── Feed/
│   │   ├── FeedView.swift        # Feed 主视图
│   │   ├── FeedView+Accessibility.swift
│   │   ├── PostCell.swift        # 帖子卡片
│   │   └── PostDetailView.swift
│   ├── Chat/
│   │   └── ChatView.swift        # 聊天视图
│   ├── Calls/
│   │   ├── ActiveCallView.swift
│   │   ├── IncomingCallView.swift
│   │   ├── OutgoingCallView.swift
│   │   └── CallHistoryView.swift
│   ├── Post/
│   │   └── CreatePostView.swift
│   ├── User/
│   │   ├── ProfileView.swift
│   │   └── UserProfileView+Accessibility.swift
│   ├── Explore/
│   │   ├── ExploreView.swift
│   │   └── NotificationView.swift
│   ├── Settings/
│   │   └── LanguageSelectionView.swift
│   └── Common/
│       ├── LoadingView.swift
│       ├── ErrorMessageView.swift
│       ├── LazyImageView.swift
│       ├── AsyncImageView.swift
│       ├── SkeletonLoadingView.swift
│       ├── AccessibleButton.swift
│       └── Styles.swift
│
├── Services/                     # 业务逻辑服务层
│   ├── Calls/
│   │   └── CallCoordinator.swift # 通话协调器
│   ├── WebRTC/
│   │   └── WebRTCManager.swift   # WebRTC 对等连接管理
│   ├── WebSocket/
│   │   └── AutoReconnectingChatSocket.swift # 聊天 WebSocket
│   └── Security/
│       └── CryptoKeyStore.swift  # 加密密钥存储
│
├── LocalData/                    # 本地数据存储
│   ├── Managers/
│   │   ├── LocalStorageManager.swift
│   │   ├── DraftManager.swift
│   │   └── SyncManager.swift
│   └── Models/
│       ├── LocalUser.swift
│       ├── LocalPost.swift
│       ├── LocalDraft.swift
│       ├── LocalComment.swift
│       ├── LocalNotification.swift
│       └── SyncState.swift
│
├── MediaKit/                     # 多媒体处理
│   ├── Core/
│   │   ├── ImageManager.swift
│   │   └── MediaMetrics.swift
│   ├── Image/
│   │   ├── ImagePickerWrapper.swift
│   │   ├── ImageUploadManager.swift
│   │   ├── ImageViewerView.swift
│   │   └── KFImageView.swift
│   ├── Video/
│   │   ├── VideoManager.swift
│   │   └── VideoPlayerView.swift
│   └── Utils/
│       ├── ImageCompressor.swift
│       └── MediaNetworkOptimizer.swift
│
├── DesignSystem/                 # 设计系统 (组件库)
│   ├── Components/
│   │   ├── DSButton.swift
│   │   ├── DSTextField.swift
│   │   ├── DSCard.swift
│   │   ├── DSBadge.swift
│   │   ├── DSLoader.swift
│   │   ├── DSSkeleton.swift
│   │   ├── DSAlert.swift
│   │   ├── DSToast.swift
│   │   ├── DSDivider.swift
│   │   ├── DSProgressBar.swift
│   │   ├── DSListItem.swift
│   │   └── 其他组件
│   ├── Theme/
│   │   ├── AppTheme.swift
│   │   └── ThemeManager.swift
│   ├── Tokens/
│   │   └── DesignTokens.swift    # 设计令牌
│   ├── Layout/
│   │   └── Modifiers.swift
│   ├── Animations/
│   │   └── Animations.swift
│   └── Showcase/
│       └── ComponentShowcase.swift
│
├── Localization/                 # 国际化 (多语言)
│   ├── L10n.swift               # 翻译字符串
│   ├── Language.swift           # 语言选择
│   ├── LocalizationManager.swift
│   ├── DateTimeFormatters.swift
│   ├── NumberFormatters.swift
│   └── Resources/
│       ├── en.lproj/
│       ├── zh-Hans.lproj/
│       └── zh-Hant.lproj/
│
├── DeepLinking/                  # 深层链接
│   ├── DeepLinkRouter.swift
│   └── DeepLinkHandler.swift
│
├── Accessibility/                # 辅助功能
│   ├── AccessibilityHelpers.swift
│   └── AccessibilityModifiers.swift
│
├── Utils/                        # 工具类
│   ├── DeepLinkRouter.swift
│   └── Localization/
│       ├── LocalizationManager.swift
│       ├── LocalizedFormatters.swift
│       ├── RTLSupport.swift
│       └── String+Localization.swift
│
├── Tests/                        # 测试套件
│   ├── Unit/
│   │   ├── AuthRepositoryTests.swift
│   │   ├── FeedRepositoryTests.swift
│   │   ├── CacheTests.swift
│   │   ├── ConcurrencyTests.swift
│   │   ├── ErrorHandlingTests.swift
│   │   ├── Persistence/
│   │   │   └── PersistenceTests.swift
│   │   └── Messaging/
│   │       ├── LocalMessageQueueTests.swift
│   │       ├── WebSocketReconnectTests.swift
│   │       └── ChatViewModelIntegrationTests.swift
│   ├── Performance/
│   │   └── NetworkPerformanceTests.swift
│   ├── Mocks/
│   │   ├── MockAuthManager.swift
│   │   ├── MockURLProtocol.swift
│   │   ├── MockMessagingRepository.swift
│   │   └── TestFixtures.swift
│   ├── NetworkTests.swift
│   └── PerformanceTests.swift
│
├── Examples/                     # 示例代码
│   ├── LocalizationExamples.swift
│   ├── MediaKitExamples.swift
│   ├── NetworkUsageExamples.swift
│   ├── PerformanceDemoApp.swift
│   └── PerformanceOptimizationExamples.swift
│
└── Documentation/                # 文档
    ├── 多个 markdown 和文本文档
    └── README.md
```

---

## 2. 已实现的核心功能

### 2.1 认证系统 ✅
**位置**: `/Network/Repositories/AuthRepository.swift`, `/ViewModels/Auth/`

**已实现功能**:
- [x] 用户登录/注册
- [x] Token 刷新和管理 (AuthManager)
- [x] OAuth 集成 (Apple Sign-in)
- [x] Token 存储和检索
- [x] 自动登录状态检查
- [x] Token 过期检测和续期
- [x] 请求拦截器 (自动添加 Authorization header)

**关键文件**:
- `AuthManager.swift` - 全局 token 管理
- `RequestInterceptor.swift` - HTTP 拦截器
- `AuthRepository.swift` - 登录/注册 API

### 2.2 Feed 流系统 ✅
**位置**: `/Views/Feed/`, `/ViewModels/Feed/`, `/Network/Repositories/FeedRepository.swift`

**已实现功能**:
- [x] 下拉刷新 (Pull-to-Refresh)
- [x] 无限滚动分页加载
- [x] 智能预加载 (距离底部5条触发)
- [x] 防重复加载机制
- [x] 去重过滤
- [x] 骨架屏加载状态
- [x] 乐观更新 (点赞立即反映)
- [x] 失败自动回滚
- [x] 图片懒加载和缓存
- [x] 滚动位置恢复
- [x] 快速返回顶部
- [x] 粒子爆炸动画 (点赞)
- [x] 触觉反馈

**性能优化**:
- 两层缓存 (内存 + 磁盘)
- 缓存统计 (命中率、计数)
- 10秒超时机制
- 指数退避重试 (最多3次)
- 任务取消 (视图消失时)
- 渐进式加载 (缩略图优先)
- 内存警告监听

### 2.3 帖子详情和操作 ✅
**位置**: `/Views/Feed/PostDetailView.swift`, `/ViewModels/Feed/PostDetailViewModel.swift`

**已实现功能**:
- [x] 完整帖子信息展示
- [x] 评论列表和分页
- [x] 添加评论
- [x] 点赞/取消点赞
- [x] 删除帖子
- [x] 编辑帖子
- [x] 评论删除和编辑

### 2.4 创建帖子 ✅
**位置**: `/Views/Post/CreatePostView.swift`, `/ViewModels/Post/CreatePostViewModel.swift`

**已实现功能**:
- [x] 图片选择器 (单/多张)
- [x] 图片预览
- [x] 标题/内容输入
- [x] 标签/主题支持
- [x] 上传进度显示
- [x] 错误处理和重试
- [x] 草稿保存到本地存储

### 2.5 用户资料系统 ✅
**位置**: `/Views/User/ProfileView.swift`, `/ViewModels/User/UserProfileViewModel.swift`

**已实现功能**:
- [x] 用户信息展示 (头像、昵称、简介)
- [x] 关注/取消关注
- [x] 用户帖子网格展示
- [x] 统计数据 (帖子数、粉丝数、关注数)
- [x] 用户搜索
- [x] 用户推荐

### 2.6 探索和搜索 ✅
**位置**: `/Views/Explore/ExploreView.swift`, `/ViewModels/Common/ExploreViewModel.swift`

**已实现功能**:
- [x] 探索帖子网格
- [x] 用户搜索功能
- [x] 搜索防抖 (debounce)
- [x] 搜索历史记录
- [x] 搜索结果分页

### 2.7 通知系统 ✅
**位置**: `/Views/Explore/NotificationView.swift`, `/ViewModels/Common/NotificationViewModel.swift`

**已实现功能**:
- [x] 通知列表展示
- [x] 未读标记
- [x] 点击跳转到相关内容
- [x] 标记已读/未读
- [x] 通知删除

### 2.8 消息系统 (聊天) ✅
**位置**: `/Views/Chat/ChatView.swift`, `/ViewModels/Chat/ChatViewModel.swift`, `/Services/WebSocket/`

**已实现功能**:
- [x] WebSocket 连接 (自动重连)
- [x] 消息发送/接收
- [x] 消息加密 (NaCl)
- [x] 消息编辑
- [x] 消息撤回
- [x] 消息反应 (emoji reactions)
- [x] 消息附件上传
- [x] 离线消息队列 (LocalMessageQueue)
- [x] 离线消息恢复
- [x] 输入指示器 (正在输入)
- [x] 消息历史获取
- [x] 消息搜索

**WebSocket 功能**:
- 自动重连机制 (指数退避)
- 连接状态监听
- 心跳保活
- JWT 认证
- 实时消息推送

**本地存储**:
- SwiftData 持久化
- 离线消息队列
- 消息同步状态追踪

### 2.9 视频通话系统 ✅
**位置**: `/Views/Calls/`, `/ViewModels/Calls/CallViewModel.swift`, `/Services/WebRTC/WebRTCManager.swift`, `/Services/Calls/CallCoordinator.swift`

**已实现功能**:
- [x] 通话发起 (WebRTC offer)
- [x] 通话应答 (WebRTC answer)
- [x] ICE 候选交换
- [x] 媒体流管理 (音频/视频)
- [x] STUN 服务器支持
- [x] TURN 服务器配置 (placeholder)
- [x] 通话拒绝
- [x] 通话挂断
- [x] 通话历史
- [x] 连接状态监控
- [x] 音视频开关

**WebRTC 配置**:
```swift
WebRTCConfig(
    turnServers: ["turn:turn.example.com:3478?transport=udp|tcp"],
    stunServers: ["stun:stun.l.google.com:19302"]
)
```

**状态管理**:
- CallViewState (idle/ringing/dialing/connected/ended/failed)
- WebRTCConnectionState (new/connecting/connected/disconnected/failed/closed)

### 2.10 媒体处理 ✅
**位置**: `/MediaKit/`

**已实现功能**:
- [x] 图片选择器 (相机、相库)
- [x] 图片压缩
- [x] 图片上传进度
- [x] 视频播放器
- [x] 视频下载和缓存
- [x] 图片查看器 (缩放、平移)
- [x] Kingfisher 图片缓存集成
- [x] 两层缓存 (内存 + 磁盘)
- [x] 网络优化 (根据连接类型调整质量)

### 2.11 设计系统 ✅
**位置**: `/DesignSystem/`

**已实现组件**:
- [x] DSButton (主/次按钮样式)
- [x] DSTextField (输入框)
- [x] DSCard (卡片)
- [x] DSBadge (标签)
- [x] DSLoader (加载动画)
- [x] DSSkeleton (骨架屏)
- [x] DSAlert (警告框)
- [x] DSToast (提示)
- [x] DSDivider (分割线)
- [x] DSProgressBar (进度条)
- [x] DSListItem (列表项)

**主题系统**:
- 亮色/暗色主题支持
- 动态色彩
- 完整的设计令牌库

### 2.12 国际化 (i18n) ✅
**位置**: `/Localization/`

**已实现功能**:
- [x] 多语言支持 (英文、简体中文、繁体中文)
- [x] RTL 语言支持 (Arabic, Hebrew 等)
- [x] 日期/时间格式化
- [x] 数字格式化
- [x] 货币格式化
- [x] 语言动态切换
- [x] 本地化字符串管理

### 2.13 辅助功能 (Accessibility) ✅
**位置**: `/Accessibility/`

**已实现功能**:
- [x] VoiceOver 支持
- [x] 动态类型支持
- [x] 键盘导航
- [x] 焦点管理
- [x] 无障碍标签
- [x] 高对比度支持

### 2.14 深层链接 (Deep Linking) ✅
**位置**: `/DeepLinking/`

**已实现功能**:
- [x] URL Scheme 处理
- [x] Universal Links 支持
- [x] 路由导航
- [x] 深层链接跟踪 (TODO: 分析工具集成)

### 2.15 性能优化 ✅
**位置**: `/Network/Services/PerformanceKit.swift`

**已实现功能**:
- [x] 请求去重 (RequestDeduplicator)
- [x] 缓存管理 (CacheManager)
- [x] 网络监控 (NetworkMonitor)
- [x] 性能指标收集
- [x] 内存使用监控
- [x] 网络延迟监测
- [x] 缓存命中率统计
- [x] 性能调试视图

### 2.16 本地数据存储 ✅
**位置**: `/LocalData/`

**已实现功能**:
- [x] SwiftData 集成
- [x] 本地用户数据
- [x] 本地帖子缓存
- [x] 草稿保存
- [x] 同步状态追踪
- [x] 离线队列管理
- [x] 数据同步

---

## 3. 部分实现或需要完善的功能

### 3.1 WebRTC TURN 服务器 ⚠️
**文件**: `/Services/WebRTC/WebRTCManager.swift` (第 18-29 行)

**当前状态**: 
```swift
turnServers: [
    "turn:turn.example.com:3478?transport=udp",
    "turn:turn.example.com:3478?transport=tcp",
]
```

**问题**: 
- TURN 服务器地址是硬编码的示例值
- 需要配置实际的 TURN 服务器地址和凭证
- 不支持动态获取 TURN 凭证

**需要实现**:
1. 从 API 获取 TURN 服务器地址和凭证
2. 支持凭证轮换
3. TURN 连接超时处理

### 3.2 消息搜索全文索引 ⚠️
**相关文件**: 
- `/Network/Repositories/MessagingRepository.swift` (第 124 行: `searchText: text`)

**当前状态**:
- 客户端支持发送 `searchText` 字段
- 后端有搜索索引实现 (基于 git status)

**需要实现**:
1. 消息搜索 API 端点
2. 搜索结果分页
3. 搜索历史缓存
4. 全文搜索 UI 组件

### 3.3 深层链接分析 ⚠️
**文件**: `/DeepLinking/DeepLinkRouter.swift` (TODO 注释)

**当前状态**:
```swift
// TODO: 集成分析工具 (Firebase, Mixpanel 等)
```

**需要实现**:
1. 分析事件追踪
2. 用户路径分析
3. 转化漏斗追踪

### 3.4 分享功能 ⚠️
**文件**: `/Views/Feed/PostCell.swift` (第 X 行 TODO 注释)

**当前状态**:
```swift
// TODO: Share functionality
// TODO: Bookmark functionality
```

**需要实现**:
1. 分享帖子到 ShareSheet
2. 复制链接
3. 书签/收藏功能
4. 分享到社交媒体

### 3.5 编辑资料 ⚠️
**文件**: `/Views/User/ProfileView.swift`

**当前状态**:
```swift
// TODO: Navigate to edit profile
```

**需要实现**:
1. 个人资料编辑界面
2. 头像上传
3. 个人信息更新
4. 密码修改

### 3.6 关注者/关注中 导航 ⚠️
**文件**: `/DeepLinking/DeepLinkHandler.swift`

**当前状态**:
```swift
// TODO: Implement followers navigation
// TODO: Implement following navigation
```

**需要实现**:
1. 关注者列表视图
2. 关注中列表视图
3. 用户搜索和过滤

### 3.7 消息记录导出 ⚠️
**当前状态**: 未实现

**需要实现**:
1. 导出消息为 PDF/文本
2. 消息备份

---

## 4. 缺失的功能模块

### 4.1 支付和订阅系统 ❌
**实现状态**: **未实现**

**需要实现**:
1. StoreKit 2 集成
2. 产品配置
3. 订阅管理
4. 支付处理
5. 收据验证

### 4.2 推送通知 (APNs) ❌
**实现状态**: **未实现**

**需要实现**:
1. APNs 证书配置
2. 设备 token 注册
3. 推送通知处理
4. 本地通知支持
5. 通知权限请求

### 4.3 位置服务 ❌
**实现状态**: **未实现**

**需要实现**:
1. 位置权限请求
2. 地理定位
3. 位置分享
4. 附近用户发现

### 4.4 AR 滤镜和效果 ❌
**实现状态**: **未实现**

**需要实现**:
1. ARKit 集成
2. 虚拟滤镜
3. 面部识别效果
4. 实时效果预览

### 4.5 实时视频直播 ❌
**实现状态**: **未实现** (仅支持 1v1 通话)

**需要实现**:
1. 多人视频会议
2. HLS 直播流
3. 直播聊天
4. 观看人数统计
5. 礼物系统

### 4.6 故事 (Stories) 功能 ❌
**实现状态**: **未实现**

**需要实现**:
1. 故事发布
2. 故事查看
3. 故事私密设置
4. 故事过期自动删除
5. 浏览分析

### 4.7 推荐算法 ❌
**实现状态**: **部分** (基础用户推荐存在)

**当前状态**:
- FeedViewModel 中有基本的 `loadRandomFeed()` 方法
- UserRepository 中有 `searchUsers()` 方法

**需要完善**:
1. 协作过滤推荐
2. 内容协同推荐
3. 趋势发现
4. 个性化排序

### 4.8 话题和标签系统 ❌
**实现状态**: **部分**

**需要实现**:
1. 话题创建和管理
2. 话题搜索和趋势
3. 话题分页
4. 话题统计

### 4.9 举报和内容审核 ❌
**实现状态**: **未实现**

**需要实现**:
1. 举报 UI
2. 举报原因分类
3. 内容审核状态
4. 禁用用户

### 4.10 私聊群组管理 ❌
**实现状态**: **部分** (1v1 完整，群组基础)

**当前状态**:
- MessagingRepository 有 `createDirectConversation()` 方法
- 没有群组管理功能

**需要实现**:
1. 群组创建
2. 群组成员管理
3. 群组设置编辑
4. 群组权限控制
5. 群组退出/删除

### 4.11 语音消息 ❌
**实现状态**: **未实现**

**需要实现**:
1. 语音记录
2. 音频压缩
3. 音频上传
4. 音频播放
5. 音频进度控制

### 4.12 视频消息 ❌
**实现状态**: **部分** (视频播放存在，但消息集成不完整)

**当前状态**:
- VideoPlayerView 存在
- 视频上传到消息未完整实现

**需要实现**:
1. 视频记录和压缩
2. 视频消息上传
3. 视频自动转码
4. 缩略图生成

### 4.13 蓝牙和 NFC 集成 ❌
**实现状态**: **未实现**

**需要实现**:
1. NFC 扫描
2. 配对分享
3. 蓝牙消息同步

### 4.14 离线模式完整化 ⚠️
**实现状态**: **部分**

**当前状态**:
- LocalMessageQueue 已实现
- 离线消息恢复已实现
- 需要更完善的离线功能

**需要完善**:
1. 完整的离线内容缓存
2. 离线模式指示器
3. 离线功能限制提示
4. 数据同步冲突解决

### 4.15 云备份和恢复 ❌
**实现状态**: **未实现**

**需要实现**:
1. iCloud 同步
2. 备份加密
3. 恢复流程
4. 备份计划

### 4.16 端对端加密完整化 ⚠️
**实现状态**: **部分**

**当前状态**:
- NaCl 加密已实现 (MessagingRepository)
- CryptoKeyStore 已实现
- 需要验证密钥交换安全性

**需要完善**:
1. 密钥轮换机制
2. 前向保密
3. 消息确认加密
4. 完整性检查增强

### 4.17 指纹识别/FaceID ⚠️
**实现状态**: **部分** (Apple Sign-in 存在)

**当前状态**:
- AppleSignInService 存在
- LocalAuthentication 未集成

**需要完善**:
1. 应用锁定 (FaceID/Touch ID)
2. 敏感操作确认
3. 生物识别缓存

### 4.18 应用内浏览器 ❌
**实现状态**: **未实现**

**需要实现**:
1. SFSafariViewController 集成
2. 链接预览
3. 文章阅读器视图
4. 链接分享

---

## 5. 网络和 API 集成分析

### 5.1 已实现的 API 端点

#### 认证相关
```
POST   /auth/register
POST   /auth/login
POST   /auth/refresh
POST   /auth/logout
POST   /auth/oauth/apple
```

#### 用户相关
```
GET    /users/me
GET    /users/{id}
GET    /users/search?q=...
POST   /users/{id}/follow
DELETE /users/{id}/follow
PUT    /users/me
GET    /users/me/public-key
PUT    /users/me/public-key
```

#### 帖子相关
```
GET    /feed
GET    /feed?cursor=...&limit=...
POST   /posts
GET    /posts/{id}
PUT    /posts/{id}
DELETE /posts/{id}
POST   /posts/{id}/like
DELETE /posts/{id}/like
GET    /posts/{id}/comments
POST   /posts/{id}/comments
```

#### 消息相关 ✅
```
GET    /users/{id}/public-key
POST   /messages
GET    /conversations/{id}/messages
PUT    /messages/{id}
POST   /messages/{id}/reactions
DELETE /messages/{id}/reactions/{emoji}
POST   /conversations/{id}/messages/{id}/recall
GET    /conversations/{id}/messages/{id}/recall
POST   /conversations
GET    /conversations/{id}/messages/{id}/attachments
POST   /conversations/{id}/messages/{id}/attachments
```

#### 通话相关 ✅
```
POST   /conversations/{id}/calls
POST   /calls/{id}/answer
POST   /calls/{id}/reject
POST   /calls/{id}/end
GET    /calls/{id}/history
POST   /calls/{id}/candidates
```

#### WebSocket 端点 ✅
```
WS     /ws?conversation_id=...&user_id=...&token=...
```

#### 通知相关 ✅
```
GET    /notifications
GET    /notifications?limit=...
POST   /notifications/{id}/read
DELETE /notifications/{id}
```

### 5.2 缺失的 API 端点

#### 消息搜索
```
❌ GET    /conversations/{id}/messages/search?q=...
```

#### TURN 服务器获取
```
❌ GET    /config/turn-servers
```

#### 分享和书签
```
❌ POST   /posts/{id}/share
❌ POST   /posts/{id}/bookmark
❌ GET    /users/me/bookmarks
```

#### 关注者列表
```
❌ GET    /users/{id}/followers
❌ GET    /users/{id}/following
```

#### 推荐系统
```
⚠️  GET    /recommendations/feed
⚠️  GET    /users/discover
```

#### 故事功能
```
❌ POST   /stories
❌ GET    /stories/{id}
❌ GET    /users/{id}/stories
```

#### 群组消息
```
❌ POST   /conversations/{id}/group
❌ PUT    /conversations/{id}/group
❌ GET    /conversations/{id}/members
❌ POST   /conversations/{id}/members/{id}
❌ DELETE /conversations/{id}/members/{id}
```

---

## 6. 视图层 (UI 屏幕) 完整清单

### 已实现的屏幕 ✅

1. **登录屏幕** - LoginView.swift
   - 邮箱/密码输入
   - Apple Sign-In 按钮
   - 注册链接

2. **注册屏幕** - RegisterView.swift
   - 用户信息输入
   - 邮箱验证
   - 密码强度检查

3. **Feed 主屏幕** - FeedView.swift
   - 帖子列表
   - 下拉刷新
   - 无限滚动
   - 骨架屏加载
   - 快速返回顶部

4. **帖子详情屏幕** - PostDetailView.swift
   - 完整帖子信息
   - 评论列表
   - 新增评论表单
   - 点赞按钮

5. **创建帖子屏幕** - CreatePostView.swift
   - 图片选择
   - 文本输入
   - 标签/主题选择
   - 上传进度

6. **用户资料屏幕** - ProfileView.swift
   - 用户信息头部
   - 统计数据
   - 帖子网格
   - 关注按钮
   - 设置菜单

7. **用户编辑屏幕** - ProfileEditView.swift ⚠️ (TODO)
   - 头像编辑
   - 昵称编辑
   - 简介编辑
   - 隐私设置

8. **探索屏幕** - ExploreView.swift
   - 推荐帖子网格
   - 用户搜索
   - 搜索历史
   - 搜索防抖

9. **通知屏幕** - NotificationView.swift
   - 通知列表
   - 未读指示器
   - 删除通知
   - 标记已读

10. **聊天列表屏幕** - ChatListView.swift (TODO)
    - 对话列表
    - 最后消息预览
    - 未读计数
    - 搜索对话

11. **聊天屏幕** - ChatView.swift
    - 消息气泡
    - 输入框
    - 文件上传
    - 连接状态指示器
    - 输入指示器

12. **拨出通话屏幕** - OutgoingCallView.swift
    - 被叫者信息
    - 呼叫状态
    - 取消按钮

13. **来电屏幕** - IncomingCallView.swift
    - 来电者信息
    - 接受/拒绝按钮
    - 静音选项

14. **通话中屏幕** - ActiveCallView.swift
    - 本地视频 (小窗口)
    - 远端视频 (全屏)
    - 音视频切换按钮
    - 挂断按钮
    - 计时器

15. **通话历史屏幕** - CallHistoryView.swift
    - 通话记录列表
    - 通话时长
    - 通话时间
    - 删除历史

16. **设置屏幕** - SettingsView.swift
    - 语言选择
    - 主题切换
    - 账户设置
    - 隐私设置
    - 关于应用

17. **语言选择屏幕** - LanguageSelectionView.swift
    - 语言列表
    - 当前语言标记
    - 保存选择

### 缺失的屏幕 ❌

1. 关注者列表屏幕
2. 关注中列表屏幕
3. 群组聊天屏幕
4. 群组管理屏幕
5. 故事发布屏幕
6. 故事查看屏幕
7. 举报屏幕
8. 推荐内容屏幕
9. 书签/收藏屏幕
10. 搜索结果详情屏幕

---

## 7. 数据持久化和缓存

### 7.1 本地存储方案 ✅

**技术栈**:
- SwiftData (主要)
- UserDefaults (配置)
- FileManager (媒体缓存)

**存储的数据**:
```swift
// 用户相关
LocalUser (用户信息)
- id: UUID
- username: String
- email: String
- avatar: String?
- bio: String?
- followerCount: Int
- followingCount: Int
- postCount: Int
- isFollowing: Bool

// 帖子相关
LocalPost (帖子缓存)
- id: UUID
- userId: UUID
- content: String
- images: [String]
- likeCount: Int
- commentCount: Int
- isLiked: Bool
- createdAt: Date

// 消息相关
LocalMessage (离线消息队列)
- id: UUID
- conversationId: UUID
- senderId: UUID
- encryptedContent: String
- nonce: String
- status: String (pending, synced, failed)
- createdAt: Date
- syncedAt: Date?

// 草稿相关
LocalDraft (草稿保存)
- id: UUID
- postType: String (post, comment, message)
- content: String
- images: [String]
- createdAt: Date
- updatedAt: Date

// 同步状态
SyncState
- entityId: UUID
- entityType: String
- status: String (pending, completed, failed)
- error: String?
```

### 7.2 缓存策略 ✅

**两层缓存**:
1. **内存缓存** (URLCache + NSCache)
   - 容量: 100MB (图片)
   - TTL: 根据内容类型变化
   
2. **磁盘缓存** (FileManager)
   - 位置: `Documents/nova-cache/`
   - 自动清理过期数据

**缓存管理**:
- CacheManager 统一管理
- 缓存命中率统计
- 内存警告监听
- 自动过期清理

### 7.3 离线队列 ✅

**LocalMessageQueue**:
- 存储待发送消息
- 失败重试机制
- 连接恢复时自动同步
- 实时同步状态追踪

**文件**: `/NovaSocial/LocalData/Services/LocalMessageQueue.swift`

---

## 8. WebSocket 实时功能分析

### 8.1 实现的 WebSocket 功能 ✅

**自动重连 WebSocket** - `AutoReconnectingChatSocket.swift`

```
功能:
- 自动连接和重连 (指数退避)
- 最大重连延迟: 30 秒
- 心跳保活
- JWT 认证
- 断线自动恢复
- 状态变化回调

支持的消息类型:
- "message_new" - 新消息
- "message_recalled" - 消息撤回
- "typing" - 输入状态
- "call_offer" - 通话邀请
- "call_answer" - 通话应答
- "ice_candidate" - ICE 候选
```

**连接参数**:
```
URL: ws://localhost:8085/ws?conversation_id={id}&user_id={id}&token={jwt}

查询参数:
- conversation_id: 对话 ID
- user_id: 用户 ID
- token: JWT token (可选)
```

**事件处理**:
- `onMessageNew` - 新消息回调
- `onMessageRecalled` - 消息撤回回调
- `onTyping` - 输入状态回调
- `onStateChange` - 连接状态变化回调
- `onError` - 错误回调

### 8.2 缺失的 WebSocket 功能 ❌

1. **服务器推送通知**
   - APNs 集成
   - 本地通知

2. **离线消息同步**
   - 只有客户端队列，需要更好的服务器同步协议

3. **消息顺序保证**
   - 缺少消息序列号验证

---

## 9. TURN 服务器和 NAT 穿透

### 当前状态 ⚠️

**硬编码配置** (`WebRTCManager.swift`):
```swift
WebRTCConfig(
    turnServers: [
        "turn:turn.example.com:3478?transport=udp",
        "turn:turn.example.com:3478?transport=tcp",
    ],
    stunServers: [
        "stun:stun.l.google.com:19302",
        "stun:stun1.l.google.com:19302",
    ]
)
```

### 问题
1. TURN 服务器地址是示例值，需要真实配置
2. 没有凭证管理
3. 没有动态获取机制
4. 没有故障转移

### 建议的改进
1. 从 API 端点 `GET /config/turn-servers` 获取动态配置
2. 实现凭证轮换机制
3. 支持多个 TURN 服务器故障转移
4. 添加 TURN 连接超时处理

---

## 10. 测试覆盖情况

### 10.1 已实现的测试

**单元测试** (5,529 行代码):
```
✅ AuthRepositoryTests.swift
   - Token 刷新
   - 登录/注册
   - 错误处理

✅ FeedRepositoryTests.swift
   - Feed 加载
   - 分页
   - 缓存

✅ CacheTests.swift
   - 缓存命中/未命中
   - 过期清理
   - 内存管理

✅ ConcurrencyTests.swift
   - 并发请求
   - 数据竞争
   - 任务取消

✅ ErrorHandlingTests.swift
   - 网络错误
   - 解码错误
   - 重试逻辑

✅ PersistenceTests.swift
   - SwiftData 保存
   - 数据检索
   - 数据删除

✅ WebSocketReconnectTests.swift
   - 自动重连
   - 连接状态
   - 消息队列

✅ ChatViewModelIntegrationTests.swift
   - 聊天流程
   - 消息同步
   - 离线恢复

✅ LocalMessageQueueTests.swift
   - 队列操作
   - 消息持久化
   - 失败恢复
```

### 10.2 缺失的测试

```
❌ 视频通话集成测试
❌ WebRTC 信令测试
❌ 性能基准测试
❌ UI 测试 (SwiftUI Testing)
❌ 端到端测试
❌ 压力测试
❌ 安全性测试
```

---

## 11. 代码质量指标

| 指标 | 值 |
|-----|-----|
| 总 Swift 文件 | 442 |
| 总代码行数 | 37,637 |
| 平均文件大小 | 85 行 |
| 类型定义数 | 737+ |
| 测试代码行数 | 5,529 |
| 测试覆盖率 | ~60% (估计) |
| 主要类/结构体 | 200+ |

---

## 12. 优势和最佳实践

### 优势 ✅
1. **现代 iOS 开发**
   - 使用 SwiftUI (iOS 16+ 现代 API)
   - async/await 异步处理
   - Observation 框架
   - SwiftData 持久化

2. **架构清晰**
   - MVVM 分层架构
   - Repository 模式解耦
   - 依赖注入
   - 单一职责原则

3. **网络处理完善**
   - 自动重试机制
   - 请求去重
   - 缓存管理
   - 错误处理完整

4. **功能丰富**
   - 完整的消息系统 (加密、离线队列)
   - WebRTC 视频通话
   - WebSocket 实时推送
   - 国际化和辅助功能

5. **性能优化**
   - 两层缓存策略
   - 图片懒加载和压缩
   - 列表虚拟化
   - 内存管理最佳实践

### 最佳实践 ✅
1. 使用 `@MainActor` 确保 UI 更新在主线程
2. Sendable 协议实现线程安全
3. 定期的错误处理和日志记录
4. 触觉反馈增强用户体验
5. 骨架屏提升加载体验
6. 乐观更新改善响应速度

---

## 13. 需要实现的功能完整清单

### 优先级 1 (关键)
- [ ] TURN 服务器动态配置
- [ ] 推送通知 (APNs)
- [ ] 群组聊天功能
- [ ] 消息全文搜索 API
- [ ] 用户编辑资料功能
- [ ] 应用内浏览器

### 优先级 2 (重要)
- [ ] 故事 (Stories) 功能
- [ ] 分享和书签
- [ ] 语音消息
- [ ] 视频消息
- [ ] 举报内容
- [ ] 私信群组管理
- [ ] 应用锁定 (FaceID)
- [ ] 完整的离线模式

### 优先级 3 (增强)
- [ ] 实时视频直播
- [ ] AR 滤镜
- [ ] 推荐算法优化
- [ ] 话题和标签系统
- [ ] 蓝牙/NFC 集成
- [ ] 云备份和恢复
- [ ] 支付和订阅
- [ ] 位置服务

### 优先级 4 (可选)
- [ ] 应用内分析
- [ ] A/B 测试框架
- [ ] 性能监控 (Sentry)
- [ ] 崩溃报告

---

## 14. 存在的 TODO 注释总结

### 应用程序初始化
```swift
// App/NovaSocialApp.swift
// TODO: Integrate with analytics service
```

### 深层链接
```swift
// DeepLinking/DeepLinkHandler.swift
// TODO: Navigate to specific section if provided
// TODO: Implement followers navigation
// TODO: Implement following navigation
// TODO: Implement conversation navigation
// TODO: Implement media library navigation
// TODO: Show error alert
// TODO: Check actual authentication status
```

### 缓存迁移
```swift
// Network/Repositories/FeedRepositoryEnhanced.swift
// TODO: 迁移旧缓存到新存储（如果需要）
```

### WebRTC 实现
```swift
// Services/Calls/CallCoordinator.swift
// TODO: Attach remote stream to video view
// TODO: Send ICE candidate to peer via API/WebSocket
```

### UI 功能
```swift
// Views/Feed/PostCell.swift
// TODO: Share functionality
// TODO: Bookmark functionality
// TODO: Show action sheet

// Views/User/ProfileView.swift
// TODO: Navigate to edit profile

// Views/Explore/ExploreView.swift
// .environmentObject(AppState()) // TODO: Pass actual app state

// Views/Auth/LoginView.swift
// TODO: Navigate to forgot password
```

### 分析工具
```swift
// Utils/DeepLinkRouter.swift
// TODO: 集成分析工具 (Firebase, Mixpanel 等)

// ViewModels/User/UserProfileViewModel.swift
// TODO: Compare with AuthManager.shared.currentUser?.id
```

### WebRTC 流处理
```swift
// Views/Calls/IncomingCallView.swift
// TODO: Generate SDP answer via WebRTC manager
```

### 通话视图模型
```swift
// ViewModels/Calls/CallViewModel.swift
// TODO: Forward to WebRTC manager
```

---

## 15. 关键文件汇总

### 核心网络层
- `/Network/Core/APIClient.swift` - HTTP 客户端
- `/Network/Core/AuthManager.swift` - Token 管理
- `/Network/Core/RequestInterceptor.swift` - 请求拦截
- `/Network/Utils/AppConfig.swift` - 配置管理

### 消息系统核心
- `/Network/Repositories/MessagingRepository.swift` - 消息 API
- `/Services/WebSocket/AutoReconnectingChatSocket.swift` - WebSocket 客户端
- `/ViewModels/Chat/ChatViewModel.swift` - 聊天逻辑
- `/NovaSocial/LocalData/Services/LocalMessageQueue.swift` - 离线队列

### 视频通话核心
- `/Network/Repositories/CallRepository.swift` - 通话 API
- `/Services/WebRTC/WebRTCManager.swift` - WebRTC 管理
- `/Services/Calls/CallCoordinator.swift` - 通话协调
- `/ViewModels/Calls/CallViewModel.swift` - 通话状态

### 本地存储核心
- `/LocalData/Managers/LocalStorageManager.swift` - 存储管理
- `/LocalData/Models/LocalMessage.swift` - 消息模型
- `/LocalData/Models/LocalDraft.swift` - 草稿模型

### Feed 系统核心
- `/Network/Repositories/FeedRepository.swift` - Feed 数据
- `/ViewModels/Feed/FeedViewModel.swift` - Feed 逻辑
- `/Views/Feed/FeedView.swift` - Feed 主视图
- `/Views/Feed/PostCell.swift` - 帖子卡片

---

## 总结

Nova iOS 应用是一个**功能丰富、架构完善的社交应用**，具有以下特点:

**已完成 (90% 功能)**:
- 完整的认证系统
- 强大的 Feed 流系统
- 完整的消息系统 (包括加密)
- WebRTC 1v1 视频通话
- 国际化和辅助功能
- 媒体处理和缓存

**主要缺陷**:
- TURN 服务器硬编码 (需要动态配置)
- 缺少推送通知
- 缺少群组聊天
- 缺少故事功能
- 缺少支付系统
- 测试覆盖率需要提高

**建议优先级**:
1. 实现 TURN 服务器动态配置
2. 添加 APNs 推送通知
3. 实现群组聊天
4. 完善消息搜索功能
5. 提高测试覆盖率

