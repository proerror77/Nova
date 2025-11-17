# iOS-API 集成快速参考表

## 页面功能 → API映射

```
┌─────────────┬──────────────────┬──────────────────────────┬───────────┐
│ 页面        │ 功能             │ 需要的API                │ 状态      │
├─────────────┼──────────────────┼──────────────────────────┼───────────┤
│ Home        │ Feed加载         │ SocialService.GetUserFeed│ ❌未实现  │
│             │ Explore加载      │ SocialService.GetExplore │ ❌未实现  │
├─────────────┼──────────────────┼──────────────────────────┼───────────┤
│ Chat        │ 对话列表         │ CommunicationService.Lst │ ❌未实现  │
│             │ 发送消息         │ CommunicationService.Snd │ ❌未实现  │
│             │ 实时消息         │ CommunicationService.Strm│ ❌未实现  │
├─────────────┼──────────────────┼──────────────────────────┼───────────┤
│ Search      │ 执行搜索         │ SearchService.SearchAll  │ ❌未实现  │
│             │ 搜索建议         │ SearchService.GetSuggest │ ❌未实现  │
├─────────────┼──────────────────┼──────────────────────────┼───────────┤
│ Notif       │ 加载通知         │ CommunicationService.Get │ ❌未实现  │
│             │ 标记已读         │ CommunicationService.Mrk │ ❌未实现  │
├─────────────┼──────────────────┼──────────────────────────┼───────────┤
│ Profile     │ 获取用户资料     │ UserService.GetUser      │ ⚠️存在未调│
│             │ 获取用户帖子     │ ContentService.GetUserPst│ ✓存在已调│
│             │ 获取保存的帖子   │ ContentService.GetUserBkm│ ✓存在已调│
│             │ 获取点赞的帖子   │ ???(缺失API)            │ ❌无法实现│
│             │ 更新头像         │ MediaService.Upload +    │ ⚠️框架未│
│             │                  │ UserService.UpdateProfile│   完整  │
│             │ 关注用户         │ SocialService.Follow     │ ✓存在   │
├─────────────┼──────────────────┼──────────────────────────┼───────────┤
│ CreatePost  │ 创建帖子         │ ContentService.CreatePost│ ⚠️框架未│
│             │ 上传图片         │ MediaService.Upload      │   实现  │
├─────────────┼──────────────────┼──────────────────────────┼───────────┤
│ Settings    │ 加载设置         │ UserService.GetSettings  │ ⚠️框架未│
│             │ 保存设置         │ UserService.UpdateSettings│   实现  │
│             │ 登出             │ IdentityService.Logout   │ ❌缺失API│
│             │ 删除账户         │ IdentityService.Delete   │ ❌缺失API│
└─────────────┴──────────────────┴──────────────────────────┴───────────┘
```

## 后端API完整度分析

```
✅ 已完全实现（无需iOS调用）
   - SocialService: FollowUser, UnfollowUser, LikeContent, UnlikeContent
   - ContentService: CreateComment, GetComments, UpdateComment, DeleteComment
   - MediaService: InitiateUpload, CompleteUpload, GenerateThumbnail
   - UserService: SearchUsers, VerifyUser, BanUser

⚠️ 已实现但未在iOS调用（框架存在，代码未完成）
   - ContentService.CreatePost (有框架，未实现媒体上传)
   - UserService.GetSettings/UpdateSettings (有proto, 未调用)
   - MediaService整套 (有proto, 上传逻辑未实现)

❌ 关键缺失（无对应API，需后端开发）
   - SocialService.GetUserLikes(user_id) → [Post] (获取用户点赞的帖子)
   - IdentityService.Logout (登出)
   - IdentityService.DeleteAccount (删除账户)
```

## 优先级执行计划

### 周1: 核心通讯
```
Day 1-2: HomeViewModel.loadFeed()
         关键: SocialService.GetUserFeed调用 + cursor分页

Day 3-4: ChatViewModel.loadConversations() + sendMessage()  
         关键: 消息状态机 (SENDING→SENT→DELIVERED→READ)

Day 5:   NotificationViewModel.loadNotifications()
         关键: 过滤unread_only + 错误处理
```

### 周2: 实时交互
```
Day 1-2: 实时消息推送 (StreamMessages或轮询)
Day 3-4: 通知标记已读 (MarkNotificationRead)
Day 5:   Push Token注册 (RegisterPushToken for APNs)
```

### 周3: 搜索与发现
```
Day 1-2: SearchViewModel.performSearch()
         SearchService.SearchAll + 处理混合结果类型

Day 3:   ProfileViewModel.loadUserProfile()
         **需确认**: UserService.GetUser是否已实现？

Day 4-5: GetSearchSuggestions + GetTrendingTopics
```

### 周4: 内容创建与编辑
```
Day 1-2: CreatePost.createPost()
         - MediaService.InitiateUpload → CompleteUpload
         - ContentService.CreatePost with media_ids

Day 3-4: Profile.uploadAvatar()  
         **BLOCKER**: UserService.UpdateProfile需支持avatar_url

Day 5:   Settings同步 (UserService.UpdateSettings)
```

## 关键发现（Linus观点）

### 🔴 数据结构问题 - "坏品味"
```
当前糟糕的地方:

1. 数据模型分散定义
   Conversation在ChatViewModel内
   SearchResult在SearchViewModel内  
   NotificationItem在NotificationViewModel内
   
   这就是典型的"随处可见的特殊情况"
   
   解决方案: 统一到 Shared/Models/
   这样就消除了3个特殊情况

2. ViewModel直接创建Service实例
   private let contentService = ContentService()
   
   问题: 无法mock测试, 无法配置
   解决方案: 依赖注入 + Protocol定义
   
3. 错误处理缺失
   90%的代码框架是空的(仅isLoading标记)
   没有errorMessage显示
   
   Linus说过: "你需要的仅仅是一个正确的错误处理"
   建议: 统一的Error类型 + 重试机制
```

### 🟡 API设计问题 - "破坏用户空间"
```
后端设计缺陷（与"Never break userspace"相反）:

1. GetContentLikes(postId) → [UserId]
   但iOS需要: GetUserLikes(userId) → [Post]
   这是反向查询,目前无法实现!
   
   iOS最终会被迫: 逐个Post查询喜欢者列表
   导致N+1查询问题
   
   解决: 在SocialService添加GetUserLikes RPC

2. 登出没有API
   当前: 如何登出用户?
   答: 无法登出! (IdentityService缺失)
   
   这违反了基本的安全原则
   需要立即添加IdentityService

3. UpdateProfile缺少avatar_url支持?
   需要验证: UserService.UpdateProfile是否支持
   如果不支持,需添加google.protobuf.StringValue avatar_url
```

### ✅ 已做得好的地方
```
1. Proto定义清晰
   - 所有enums定义明确
   - 消息结构设计合理
   - 事件驱动架构正确

2. Service边界清晰
   - ContentService负责内容
   - SocialService负责关系
   - CommunicationService负责消息
   - MediaService处理媒体
   
   这就是"好品味"的表现:
   每个Service只做一件事,做得很好

3. iOS UI框架完整
   - 所有View都有对应ViewModel
   - 数据绑定正确(@Published)
   - Navigation state管理清晰
```

## 立即行动清单

### 后端(优先级排序)
- [ ] 确认UserService.GetUser是否实现
- [ ] 确认UserService.UpdateProfile支持avatar_url
- [ ] 添加SocialService.GetUserLikes(userId) → [Post]
- [ ] 新建IdentityService.proto
  - [ ] Logout RPC
  - [ ] DeleteAccount RPC  
  - [ ] ChangePassword RPC

### iOS(优先级排序)
- [ ] 提取共享数据模型到Shared/Models/
- [ ] 添加gRPC客户端框架(如有必要)
- [ ] 实现HomeViewModel.loadFeed()
- [ ] 实现ChatViewModel核心功能
- [ ] 实现NotificationViewModel核心功能
- [ ] 实现SearchViewModel.performSearch()
- [ ] 修复ProfileViewModel (依赖后端修复)
- [ ] 完成CreatePost图片上传流程
- [ ] 完成Settings同步逻辑

## 技术债务排序

```
高优先级技术债:
  1. 缺少API层(gRPC客户端框架)
  2. 错误处理不完善  
  3. 数据模型分散定义
  4. 缺少ViewModel测试框架
  5. 没有网络重试逻辑

中优先级:
  6. 离线支持(缓存)
  7. 性能优化(N+1查询)
  8. 日志系统(tracing)

低优先级:
  9. 代码注释补充
  10. 单元测试覆盖
```

