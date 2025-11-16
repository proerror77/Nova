# Nova Social iOS - 前端UI与Backend API集成分析报告

**生成时间**: 2025-11-15  
**分析范围**: iOS Features目录 vs Backend Proto V2服务定义

---

## 第一部分：iOS UI页面清单

### 1. **Home Feature** - 主页/信息流
**路径**: `/Features/Home/`

| 组件 | 功能 | 状态 |
|------|------|------|
| HomeView | 显示三个Tab: Feed/Explore/Trending | UI完成 |
| HomeViewModel | 加载信息流、管理导航状态 | **未实现** |

**ViewModel中的TODO**:
- Line 43: `loadFeed()` - 从后端加载信息流（空实现）

**关联API需求**:
- SocialService.GetUserFeed - 获取用户信息流
- SocialService.GetExploreFeed - 获取探索页信息流

---

### 2. **CreatePost Feature** - 发布新帖子
**路径**: `/Features/CreatePost/`

| 组件 | 功能 | 状态 |
|------|------|------|
| NewPostView | 文本输入、图片添加/移除 | UI完成 |
| CreatePostViewModel | 上传管理、创建帖子 | **部分实现** |

**ViewModel中的TODO**:
- Line 44-45: `createPost()` 
  - 图片上传流程（缺失）
  - 帖子创建（框架存在但未调用API）

**关联API需求**:
- MediaService.InitiateUpload / CompleteUpload - 上传图片
- ContentService.CreatePost - 创建帖子

---

### 3. **Chat Feature** - 即时消息
**路径**: `/Features/Chat/`

| 组件 | 功能 | 状态 |
|------|------|------|
| ChatView | 显示对话列表、选中对话 | UI完成 |
| ChatViewModel | 管理对话、发送消息 | **未实现** |

**ViewModel中的TODO**:
- Line 32: `loadConversations()` - 加载对话列表
- Line 44: `sendMessage()` - 发送消息

**关联API需求**:
- CommunicationService.ListConversations - 获取对话列表
- CommunicationService.SendMessage - 发送消息
- CommunicationService.StreamMessages - 实时消息推送

**数据模型缺陷**:
- Conversation定义在ViewModel内（应在Shared/Models）

---

### 4. **Profile Feature** - 用户资料
**路径**: `/Features/Profile/`

| 组件 | 功能 | 状态 |
|------|------|------|
| ProfileView | 显示用户信息、三个Tab (Posts/Saved/Liked) | UI完成 |
| ProfileViewModel | 加载资料、关注、点赞等社交操作 | **部分实现** |

**ViewModel中的TODO**:
- Line 44-46: `loadUserProfile()` 
  - 缺少获取用户资料的API调用
  - 需要单独的UserProfileService（用户信息不由GraphService管理）
  
- Line 74-77: `loadContent(for: .liked)`
  - 获取用户点赞过的帖子功能**完全缺失**
  - SocialService只提供"谁点赞了某个帖子"，不提供"用户点赞了哪些帖子"
  
- Line 100-107: `uploadAvatar()`
  - 头像上传后无法更新到服务器
  - 需要UserService.UpdateProfile支持

- Line 121/133: `followUser()` / `unfollowUser()` 后
  - 缺少重新加载关注者数量

**关联API需求**:
- UserService.GetUser - 获取用户资料（**缺失**）
- UserService.UpdateProfile - 更新资料
- ContentService.GetUserPosts - 获取用户帖子 ✓ 已有
- ContentService.GetUserBookmarks - 获取用户保存的帖子 ✓ 已有
- **缺失**: 获取用户点赞的帖子
- SocialService.FollowUser / UnfollowUser - 关注/取消关注 ✓ 已有
- MediaService.UploadImage - 上传图片 ✓ 已有

---

### 5. **Search Feature** - 搜索
**路径**: `/Features/Search/`

| 组件 | 功能 | 状态 |
|------|------|------|
| SearchView | 搜索输入、显示结果 | UI完成 |
| SearchViewModel | 执行搜索、清除结果 | **未实现** |

**ViewModel中的TODO**:
- Line 42: `performSearch()` - 执行搜索（空实现）

**关联API需求**:
- SearchService.SearchAll - 全文搜索（内容、用户、标签）
- SearchService.GetSearchSuggestions - 搜索建议
- SearchService.GetTrendingTopics - 热门话题

**数据模型缺陷**:
- SearchResult定义在ViewModel内（应在Shared/Models）

---

### 6. **Notifications Feature** - 通知
**路径**: `/Features/Notifications/`

| 组件 | 功能 | 状态 |
|------|------|------|
| NotificationView | 显示通知列表 | UI完成 |
| NotificationViewModel | 加载/标记通知 | **未实现** |

**ViewModel中的TODO**:
- Line 41: `loadNotifications()` - 加载通知
- Line 49: `markAsRead()` - 标记单个通知为已读
- Line 53: `markAllAsRead()` - 标记全部已读

**关联API需求**:
- CommunicationService.GetNotifications - 获取通知列表
- CommunicationService.MarkNotificationRead - 标记已读
- CommunicationService.MarkAllNotificationsRead - 全部标记已读

**数据模型缺陷**:
- NotificationItem定义在ViewModel内（应在Shared/Models）

---

### 7. **Settings Feature** - 设置
**路径**: `/Features/Settings/`

| 组件 | 功能 | 状态 |
|------|------|------|
| SettingsView | 显示设置选项 | UI完成 |
| SettingsViewModel | 管理设置、登出、删除账户 | **未实现** |

**ViewModel中的TODO**:
- Line 39: `loadSettings()` - 从UserDefaults或后端加载设置
- Line 43: `saveSettings()` - 保存设置到本地和后端
- Line 47: `logout()` - 登出逻辑
- Line 51: `deleteAccount()` - 删除账户

**关联API需求**:
- UserService.GetSettings - 获取用户设置
- UserService.UpdateSettings - 更新设置
- CommunicationService.UpdateNotificationPreferences - 更新通知偏好
- **缺失**: 登出/删除账户API（应在IdentityService）

---

### 8. **Media Feature** - 媒体处理
**路径**: `/Features/Media/`

| 组件 | 功能 | 状态 |
|------|------|------|
| CameraScreen | 拍照、切换摄像头、闪光灯 | UI完成 |
| VideoScreen | 录制视频 | UI完成 |
| PhotoPickerView | 从相册选择图片 | UI完成 |
| MediaViewModel | 相机操作、上传媒体 | **部分实现** |

**ViewModel中的TODO**:
- Line 56: `capturePhoto()` - 拍照（空实现）
- Line 61: `startRecording()` - 开始录制（空实现）
- Line 66: `stopRecording()` - 停止录制（空实现）

**已实现**:
- Line 71-84: `uploadMedia()` - 上传图片 ✓

**关联API需求**:
- MediaService.InitiateUpload - 初始化上传
- MediaService.CompleteUpload - 完成上传
- MediaService.TranscodeVideo - 转码视频

---

## 第二部分：Backend API服务清单（Proto V2）

### 核心7个微服务

#### 1. **ContentService** - 内容管理
```
主要RPC:
✓ CreatePost / GetPost / UpdatePost / DeletePost
✓ CreateComment / GetComments / UpdateComment / DeleteComment
✓ CreateArticle / GetArticle / UpdateArticle / DeleteArticle
✓ ReportContent / ModerateContent
✓ GetContentVersions

iOS需要的: CreatePost, GetUserPosts, UpdatePost, DeletePost, GetComments, CreateComment
```

#### 2. **SocialService** - 社交关系与互动
```
主要RPC:
✓ FollowUser / UnfollowUser / BlockUser / UnblockUser
✓ GetFollowers / GetFollowing / GetRelationship
✓ LikeContent / UnlikeContent / ShareContent / GetContentLikes
✓ GetUserFeed / GetExploreFeed / RefreshFeed

iOS需要的: FollowUser, UnfollowUser, LikeContent, UnlikeContent, GetUserFeed, GetExploreFeed
```

#### 3. **CommunicationService** - 消息与通知
```
主要RPC:
✓ CreateConversation / GetConversation / ListConversations / DeleteConversation
✓ SendMessage / GetMessages / MarkMessageRead / DeleteMessage / EditMessage
✓ StreamMessages (WebSocket替代方案)
✓ SendNotification / GetNotifications / MarkNotificationRead / MarkAllNotificationsRead
✓ RegisterPushToken / UnregisterPushToken
✓ GetNotificationPreferences / UpdateNotificationPreferences

iOS需要的: CreateConversation, ListConversations, SendMessage, GetMessages, MarkMessageRead,
           GetNotifications, MarkNotificationRead, MarkAllNotificationsRead,
           RegisterPushToken, UpdateNotificationPreferences
```

#### 4. **UserService** - 用户资料与设置
```
主要RPC:
✓ GetUser / GetUsersByIds / GetUserByUsername
✓ UpdateProfile / DeleteUser
✓ GetSettings / UpdateSettings
✓ SearchUsers
✓ VerifyUser / UnverifyUser
✓ BanUser / UnbanUser

iOS需要的: GetUser, UpdateProfile, GetSettings, UpdateSettings, SearchUsers
```

#### 5. **SearchService** - 全文搜索与发现
```
主要RPC:
✓ SearchContent / SearchUsers / SearchHashtags / SearchAll
✓ GetSearchSuggestions / GetTrendingTopics
✓ IndexContent / IndexUser / RemoveFromIndex (内部)
✓ RebuildIndex / GetIndexStats (管理)

iOS需要的: SearchContent, SearchUsers, SearchHashtags, SearchAll, GetSearchSuggestions, GetTrendingTopics
```

#### 6. **MediaService** - 媒体处理
```
主要RPC:
✓ InitiateUpload / CompleteUpload / CancelUpload
✓ GetMedia / GetMediaByIds / GetUserMedia
✓ GenerateThumbnail / TranscodeVideo / GetTranscodeStatus
✓ GetStreamingUrl / GetDownloadUrl
✓ DeleteMedia / BulkDeleteMedia

iOS需要的: InitiateUpload, CompleteUpload, GetMedia, TranscodeVideo, GetStreamingUrl,
           GetDownloadUrl, DeleteMedia
```

#### 7. **EventsService** - 事件总线
```
主要RPC:
✓ PublishEvent / PublishBatch
✓ Subscribe / CreateSubscription / DeleteSubscription / ListSubscriptions
✓ GetEventHistory / ReplayEvents
✓ GetDeadLetterQueue / RetryDeadLetter / DiscardDeadLetter
✓ GetEventMetrics

iOS使用场景: 订阅实时消息事件（StreamMessages仅返回gRPC流）
```

---

## 第三部分：集成状态矩阵

### 按优先级分类

#### **P0 - 关键缺失（应立即实现）**

| 页面 | 功能 | API | 状态 | 影响 | 难度 |
|------|------|-----|------|------|------|
| Home | 加载信息流 | SocialService.GetUserFeed | ❌ 未实现 | 核心功能 | 中 |
| Chat | 列表/消息 | CommunicationService.ListConversations/SendMessage | ❌ 未实现 | 核心功能 | 中 |
| Search | 执行搜索 | SearchService.SearchAll | ❌ 未实现 | 核心功能 | 低 |
| Notifications | 加载通知 | CommunicationService.GetNotifications | ❌ 未实现 | 核心功能 | 低 |
| Profile | 获取用户资料 | **UserService.GetUser不在iOS使用** | ⚠️ API存在但未调用 | 核心信息 | 低 |

#### **P1 - 高优先级（实现完整功能）**

| 页面 | 功能 | API | 状态 | 影响 | 难度 |
|------|------|-----|------|------|------|
| CreatePost | 上传图片 | MediaService.InitiateUpload/CompleteUpload | ⚠️ 框架存在，未调用 | 用户生成内容 | 中 |
| Profile | 获取用户点赞的帖子 | **缺失API** | ❌ 无法实现 | 用户资料完整性 | 高 |
| Profile | 更新头像 | UserService.UpdateProfile不支持媒体 | ❌ 无法同步 | 用户体验 | 中 |
| Settings | 设置保存/同步 | UserService.UpdateSettings | ⚠️ 框架存在，未调用 | 用户体验 | 低 |
| Media | 本地拍照/录制 | 需要本地实现 | ⚠️ 框架存在 | 用户体验 | 高 |

#### **P2 - 非关键（增强功能）**

| 页面 | 功能 | API | 状态 |
|------|------|-----|------|
| Profile | 更新关注者数 | SocialService.GetRelationship | ✓ API存在，需调用 |
| Notifications | 标记已读 | CommunicationService.MarkNotificationRead | ✓ API存在 |
| Settings | 登出/删除账户 | **缺失API** | ❌ 需在IdentityService添加 |

---

## 第四部分：API集成优先级路线图

### **阶段1: 核心信息流（第1-2周）**

**目标**: 完成Home、Chat、Notifications基础功能

```
Week 1:
  ✅ Day 1-2: HomeViewModel.loadFeed() 
     - SocialService.GetUserFeed with FEED_ALGORITHM_CHRONOLOGICAL
     - 实现分页逻辑
  
  ✅ Day 3-4: ChatViewModel.loadConversations() + sendMessage()
     - CommunicationService.ListConversations
     - CommunicationService.SendMessage
     - 处理消息状态机（SENDING → SENT → DELIVERED → READ）
  
  ✅ Day 5: NotificationViewModel.loadNotifications()
     - CommunicationService.GetNotifications
     - 实现unread_only过滤

Week 2:
  ✅ Day 1-2: 实时消息处理
     - CommunicationService.StreamMessages (如果选择gRPC)
     - 或实现轮询方案
  
  ✅ Day 3-4: 通知标记已读
     - CommunicationService.MarkNotificationRead/MarkAllNotificationsRead
  
  ✅ Day 5: 测试 + Push Token注册
     - CommunicationService.RegisterPushToken (APNs)
```

### **阶段2: 用户互动（第3-4周）**

**目标**: 完成Post创建、搜索、个人资料

```
Week 3:
  ✅ Day 1-2: Search.performSearch()
     - SearchService.SearchAll
     - 处理SearchResult去重（内容/用户/标签混合结果）
  
  ✅ Day 3: ProfileViewModel.loadUserProfile()
     - UserService.GetUser（目前缺失，需添加！）
     - 或改用ContentService.GetUserPosts获取基本信息
  
  ✅ Day 4-5: CreatePost.createPost()
     - 图片上传流程: MediaService.InitiateUpload → CompleteUpload
     - ContentService.CreatePost with media_ids

Week 4:
  ✅ Day 1-2: Profile.uploadAvatar()
     - MediaService.UploadImage (目前)
     - 需要UserService.UpdateProfile支持avatar_url字段更新
  
  ✅ Day 3-4: 获取用户点赞的帖子
     - **BLOCKER**: 无对应API，需后端开发
     - 临时方案: 在Profile中隐藏"Liked"Tab或显示"Coming Soon"
  
  ✅ Day 5: Settings同步
     - UserService.GetSettings / UpdateSettings
```

### **阶段3: 增强功能（第5周+）**

```
✅ 评论系统: ContentService.CreateComment/GetComments
✅ 实时输入状态: CommunicationService支持TYPING事件
✅ 视频转码: MediaService.TranscodeVideo + GetStreamingUrl
✅ 高级搜索过滤: SearchService.SearchContent with SearchFilter
✅ 用户关系图: SocialService.GetFollowers/GetFollowing
```

---

## 第五部分：发现的问题与建议

### **🔴 BLOCKER级别问题**

#### 1. **缺失API: 获取用户点赞的帖子**
```
Issue: ProfileViewModel无法实现"Liked Posts" Tab
Root Cause: SocialService.GetContentLikes返回"用户ID列表"而非"帖子列表"
           无反向关系查询

Solution Options:
  A) 后端新增: SocialService.GetUserLikes(user_id) → [Post]
  B) 后端新增: ContentService.SearchUserLikes(user_id) + 分页
  C) iOS临时: 隐藏"Liked" Tab或显示"Coming Soon"

Impact: 用户无法查看自己点赞过的帖子，影响个人资料完整性
```

#### 2. **缺失API: 登出与账户删除**
```
Issue: SettingsViewModel.logout() 和 deleteAccount() 无法实现
Root Cause: 无IdentityService定义

Solution: 需在proto/services_v2/中新增identity_service.proto
  rpc Logout(LogoutRequest) returns (google.protobuf.Empty)
  rpc DeleteAccount(DeleteAccountRequest) returns (google.protobuf.Empty)
  rpc ChangePassword(ChangePasswordRequest) returns (google.protobuf.Empty)

Impact: 用户无法登出或管理账户
```

#### 3. **UserService缺失Profile获取**
```
Issue: ProfileViewModel.loadUserProfile()使用的"UserProfile"数据模型
      在任何地方都没有对应的API调用
Root Cause: iOS定义了UserProfile结构，但后端GetUser API从未调用

Current Code: 
  guard let userProfile = userProfile else { return }
  // userProfile永远为nil（仅在mock/preview中设置）

Solution: ProfileViewModel需调用
  UserService.GetUser(userId) → User proto
  映射User proto到UserProfile Swift结构

Impact: 用户资料页显示mock数据，无法加载真实用户信息
```

### **🟡 HIGH优先级问题**

#### 1. **数据模型分散定义**
```
问题: SearchResult、Conversation、NotificationItem在ViewModel内定义

影响:
  - 代码重复
  - 模型不一致
  - 难以跨Feature共享

建议:
  /iOS/NovaSocial/Shared/Models/
    ├── SearchResult.swift
    ├── Conversation.swift
    ├── NotificationItem.swift
    └── ... (统一管理)
```

#### 2. **缺失API层**
```
问题: 没有gRPC客户端代码框架（iOS側）

当前: ViewModels直接创建Service()
  private let contentService = ContentService()

建议:
  1) 使用swift-protobuf生成的代码
  2) 创建Service层包装API调用
  3) 实现Error handling + Retry逻辑
  4) 添加超时配置

Example:
  class ContentAPIClient {
    private let channel: GRPCChannel
    private let client: Nova_Content_V1_ContentServiceClient
    
    func createPost(_ req: CreatePostRequest) async throws -> Post
  }
```

#### 3. **实时消息处理不完善**
```
问题: ChatViewModel.sendMessage()没有消息状态机

建议:
  Message状态流: SENDING → SENT → DELIVERED → READ
  
  enum MessageStatus {
    case sending(progress: Double)
    case sent(timestamp: Date)
    case delivered(timestamp: Date)
    case read(timestamp: Date)
    case failed(error: Error)
  }
  
  CommunicationService需提供:
    1) StreamMessages用于DELIVERED/READ更新
    2) 或轮询GetMessages获取最新状态
```

### **🟢 优化建议**

#### 1. **图片上传优化**
```
当前流程:
  1. MediaService.InitiateUpload
  2. (手动通过presigned_url上传到S3)
  3. MediaService.CompleteUpload

建议:
  - 添加上传进度反馈
  - 实现断点续传
  - 并行上传多张图片
  - 失败重试机制

Code:
  @Published var uploadProgress: Double = 0.0  // ✓ 已有
  // 需实现具体逻辑
```

#### 2. **搜索体验**
```
建议:
  - 搜索建议: SearchService.GetSearchSuggestions (已有API)
  - 搜索历史: 本地存储(SQLite/Core Data)
  - 热门话题: SearchService.GetTrendingTopics (已有API)
  - 实时搜索: 输入延迟后触发
```

#### 3. **推送通知**
```
需实现:
  1) AppDelegate中处理APNs令牌
  2) CommunicationService.RegisterPushToken(user_id, token, APNS)
  3) 前台收到通知时的本地处理
  4) 深链接导航(action_url处理)
```

---

## 第六部分：API集成检查清单

### 必须实现（Week 1-2）

- [ ] **HomeViewModel.loadFeed()**
  - [ ] SocialService.GetUserFeed调用
  - [ ] 分页逻辑(cursor-based)
  - [ ] 错误处理
  - [ ] Loading状态管理

- [ ] **ChatViewModel**
  - [ ] ListConversations调用
  - [ ] SendMessage调用
  - [ ] 消息状态管理
  - [ ] 实时更新机制

- [ ] **NotificationViewModel**
  - [ ] GetNotifications调用
  - [ ] MarkNotificationRead调用
  - [ ] MarkAllNotificationsRead调用

### 需要后端支持

- [ ] **UserService扩展**
  - [ ] AddAPI: GetUserLikes → 获取用户点赞的帖子 (Profile.liked用)
  - [ ] Verify: UpdateProfile是否支持avatar_url同步
  - [ ] Test: UpdateSettings完整功能

- [ ] **IdentityService新增** (目前缺失)
  - [ ] Logout RPC
  - [ ] DeleteAccount RPC
  - [ ] ChangePassword RPC

### 数据模型同步

- [ ] 创建`Shared/Models/`统一管理数据模型
- [ ] 从ViewModels中提取`SearchResult`, `Conversation`, `NotificationItem`
- [ ] 与Proto message保持对齐

### gRPC客户端框架

- [ ] 生成Swift代码(from .proto files)
- [ ] 创建API client layer (ContentAPIClient, SocialAPIClient等)
- [ ] 实现通用Error handling
- [ ] 配置超时 & 重试策略

---

## 总结

### 当前状况
- ✅ 所有iOS UI Views已完成
- ✅ 数据模型框架已定义  
- ❌ 90%的API调用代码为空实现（仅框架）
- ❌ 缺少2个关键后端API

### 推荐行动
1. **立即**: 后端实现`GetUserLikes` API (影响Profile功能)
2. **立即**: 后端添加`IdentityService` (影响Settings功能)
3. **本周**: 完成Home/Chat/Notifications的API集成（Week 1-2）
4. **下周**: 完成Profile/Search/CreatePost的API集成（Week 3-4）
5. **持续**: 完善错误处理、网络恢复、离线支持

### 集成难度评估
- 🟢 简单(SearchService): 数据模型简单，无状态机
- 🟡 中等(ContentService/SocialService): 涉及多个RPC、状态跟踪
- 🔴 复杂(CommunicationService): 实时性、消息状态机、推送通知

---

**分析完成** - 可立即开始API集成工作
