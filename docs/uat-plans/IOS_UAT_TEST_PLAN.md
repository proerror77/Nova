# 📋 iOS 应用 UAT 测试计划

**日期**: 2025-10-20
**范围**: Feed 功能 + 消息系统 + iOS 应用
**准备状态**: 🟢 **已完成与后端 API 集成**

---

## 📊 集成状态总结

### ✅ 后端 API 准备就绪

#### Feed Timeline API (Phase 3 Step 1 - 已合并 main)
```
✅ GET /api/v1/feed
   ├─ 查询参数: limit, offset, sort (recent|engagement)
   ├─ 性能: < 200ms (缓存命中), < 220ms (缓存未命中)
   ├─ Redis 缓存: 5 分钟 TTL
   └─ 返回: 分页 Feed 数据

✅ GET /api/v1/feed/timeline
   ├─ 快捷端点: 返回最近 20 个帖子
   ├─ 性能: < 200ms
   └─ 返回: Timeline 格式数据

✅ POST /api/v1/feed/refresh
   ├─ 功能: 清除用户 Redis 缓存
   ├─ 触发: 下拉刷新、新帖发布后
   └─ 返回: {"status": "refreshed"}
```

#### Messaging System API (Phase 2 Step 6 - 已合并 main)
```
✅ WebSocket /ws/messages
   ├─ 认证: JWT token
   ├─ 实时传输: Redis Pub/Sub
   └─ 功能: 消息流、输入指示、已读状态

✅ REST Endpoints
   ├─ GET /api/v1/conversations
   ├─ POST /api/v1/conversations
   ├─ GET /api/v1/conversations/{id}/messages
   ├─ POST /api/v1/messages
   ├─ PUT /api/v1/messages/{id}/read
   └─ DELETE /api/v1/messages/{id}
```

#### 认证系统 (Phase 1 - 完全集成)
```
✅ JWT 认证
   ├─ Token 有效期: 1 小时
   ├─ Refresh Token TTL: 7 天
   ├─ Token 存储: iOS Keychain
   └─ 自动续期: 在 Token 过期前 5 分钟

✅ OAuth 2.0 支持
   ├─ Apple Sign-In
   ├─ Google Sign-In
   └─ GitHub Sign-In
```

---

## ✅ iOS App 集成确认

### Network 层确认
```
📍 位置: nova/ios/NovaSocialApp/Network/

✅ APIClient 核心
   ├─ HTTP 客户端: URLSession
   ├─ 基础 URL: AppConfig.baseURL
   ├─ 自动重试: 指数退避
   └─ 请求超时: 30 秒

✅ Repositories 层
   ├─ FeedRepository: ✅ 已集成
   │  ├─ loadFeed(cursor, limit)
   │  ├─ refreshFeed()
   │  ├─ loadExploreFeed(page, limit)
   │  └─ 缓存策略: 内存 + SwiftData 本地存储
   │
   ├─ AuthRepository: ✅ 已集成
   │  ├─ login(credentials)
   │  ├─ refreshToken()
   │  ├─ logout()
   │  └─ Token 管理: Keychain 存储
   │
   ├─ MessageRepository: ⏳ 待验证
   │  ├─ loadConversations()
   │  ├─ sendMessage()
   │  ├─ markAsRead()
   │  └─ WebSocket 连接状态

✅ 服务层
   ├─ CacheManager: 缓存管理
   ├─ RequestDeduplicator: 请求去重
   ├─ NetworkMonitor: 网络连接监控
   ├─ PerformanceKit: 性能监测
   └─ RequestInterceptor: JWT 令牌注入

✅ 错误处理
   ├─ AppError 类型定义
   ├─ 自动重试机制
   ├─ 离线缓存降级
   └─ 用户友好错误消息
```

### Views 层确认
```
📍 位置: nova/ios/NovaSocialApp/Views/

✅ Feed 相关 Views
   ├─ FeedView: 主 Feed 界面
   │  ├─ 支持下拉刷新
   │  ├─ 支持上拉加载更多 (cursor 分页)
   │  ├─ 离线模式显示缓存数据
   │  └─ 加载状态指示
   │
   ├─ PostDetailView: 帖子详情
   ├─ ExploreView: 探索页面
   └─ ProfileFeedView: 用户 Feed

✅ 消息相关 Views
   ├─ ConversationListView: 会话列表
   ├─ ChatView: 消息界面
   │  ├─ 消息气泡样式
   │  ├─ 输入框 (支持文本、图片、表情)
   │  ├─ 输入指示动画
   │  └─ 已读状态显示
   └─ CreateConversationView: 新建会话

✅ ViewModels 层
   ├─ FeedViewModel: Feed 数据管理
   │  ├─ @State isLoading
   │  ├─ @State posts: [Post]
   │  ├─ @State error: AppError?
   │  ├─ loadFeed()
   │  ├─ refreshFeed()
   │  └─ loadMore()
   │
   ├─ AuthViewModel: 认证状态管理
   │  ├─ @State isLoggedIn
   │  ├─ @State user: User?
   │  ├─ login()
   │  ├─ logout()
   │  └─ checkAuth()
   │
   └─ ChatViewModel: 消息状态管理
      ├─ @State messages: [Message]
      ├─ @State conversations: [Conversation]
      ├─ loadMessages()
      ├─ sendMessage()
      └─ markAsRead()
```

---

## 🧪 UAT 测试计划

### 测试环境设置

#### 前置条件
```bash
# 1. 后端环境
- ✅ Rust 后端服务运行 (主机: localhost:3000)
- ✅ PostgreSQL 数据库就绪
- ✅ Redis 缓存就绪 (localhost:6379)
- ✅ Feed Timeline MVP API 已部署
- ✅ Messaging System API 已部署

# 2. iOS 环境
- ✅ Xcode 15.0+
- ✅ iOS 17.0+ 模拟器或真机
- ✅ 网络连接: 可访问后端 API
- ✅ Keychain 权限: 已授予 (Token 存储)
```

#### 测试账户
```
账户 1: test-user-1@nova.local
  密码: TestPass123!
  用途: 主要测试用户 (Feed/Messages 发送者)

账户 2: test-user-2@nova.local
  密码: TestPass123!
  用途: 协作测试用户 (Messages 接收者)

账户 3: test-user-3@nova.local
  密码: TestPass123!
  用途: 性能测试用户 (大数据集)
```

---

## 🎯 测试场景 1: Feed 功能测试

### 场景 1.1: Feed 加载与显示

**目标**: 验证 iOS 应用能正确加载和显示 Feed

| # | 测试步骤 | 预期结果 | 实际结果 | 状态 |
|---|---------|--------|--------|------|
| 1.1.1 | 启动应用 → 登录 (test-user-1) | ✅ 成功登录，进入 Feed 页面 | | ⏳ |
| 1.1.2 | 观察 Feed 初始加载 | ✅ 显示最多 20 条帖子，< 2 秒加载完成 | | ⏳ |
| 1.1.3 | 检查帖子显示内容 | ✅ 显示: 用户头像、用户名、内容、时间戳、点赞数、评论数 | | ⏳ |
| 1.1.4 | 检查帖子排序 | ✅ 按时间倒序 (最新优先) | | ⏳ |
| 1.1.5 | 启用飞行模式，查看离线显示 | ✅ 显示缓存的帖子，提示"离线模式" | | ⏳ |
| 1.1.6 | 关闭飞行模式，刷新 Feed | ✅ 重新连接，自动或手动刷新后更新 | | ⏳ |

**API 调用验证**:
```
✅ 第一步登录
   - 端点: POST /auth/login
   - 验证: Keychain 中存储 JWT token

✅ 第一步加载 Feed
   - 端点: GET /api/v1/feed?limit=20&sort=recent
   - 验证: 响应时间 < 200ms (缓存命中) 或 < 220ms (缓存未命中)
   - 验证: HTTP 200, Content-Type: application/json

✅ 离线缓存
   - 验证: 缓存存储在 SwiftData (CoreData)
   - 验证: 离线时能加载缓存数据
```

---

### 场景 1.2: 分页与加载更多

**目标**: 验证 Cursor 分页机制

| # | 测试步骤 | 预期结果 | 实际结果 | 状态 |
|---|---------|--------|--------|------|
| 1.2.1 | 向下滚动 Feed，到达底部 | ✅ 显示加载指示 | | ⏳ |
| 1.2.2 | 继续滚动或等待自动加载 | ✅ 加载下一页数据 (20 条)，新数据追加到底部 | | ⏳ |
| 1.2.3 | 重复 2-3 次 | ✅ 每次加载新的数据，无重复 | | ⏳ |
| 1.2.4 | 检查总加载时间 | ✅ 每页加载 < 500ms | | ⏳ |
| 1.2.5 | 加载所有数据后向下滚动 | ✅ 到达底部时显示"已加载全部"或停止加载 | | ⏳ |

**API 调用验证**:
```
✅ 分页请求
   - 第一页: GET /api/v1/feed?limit=20&sort=recent
   - 返回: Base64 encoded cursor (例: "MTAw")

✅ 第二页: GET /api/v1/feed?limit=20&sort=recent&cursor=MTAw
   - 验证: 返回不同的数据集
   - 验证: 新 cursor 用于下一页加载

✅ 缓存验证
   - 第二页首次加载: 缓存未命中 (~200ms)
   - 第二页后续加载: 缓存命中 (~50ms)
```

---

### 场景 1.3: 刷新与缓存无效化

**目标**: 验证下拉刷新和缓存清理

| # | 测试步骤 | 预期结果 | 实际结果 | 状态 |
|---|---------|--------|--------|------|
| 1.3.1 | 在 Feed 页面下拉 (下拉刷新手势) | ✅ 显示刷新指示动画 | | ⏳ |
| 1.3.2 | 保持下拉至一定距离 | ✅ 提示"释放以刷新" | | ⏳ |
| 1.3.3 | 释放屏幕 | ✅ 显示加载动画，从服务器重新加载最新数据 | | ⏳ |
| 1.3.4 | 加载完成 | ✅ 数据更新，刷新动画消失，新帖子显示在顶部 | | ⏳ |
| 1.3.5 | 快速连续下拉刷新 3 次 | ✅ 第二、三次请求被去重，仅一个请求发送 | | ⏳ |
| 1.3.6 | 创建新帖子后自动刷新 | ✅ Feed 自动刷新，新帖子显示在顶部 | | ⏳ |

**API 调用验证**:
```
✅ 刷新请求流程
   1. POST /api/v1/feed/refresh (清除缓存)
      - 返回: {"status": "refreshed"}
      - 验证: 响应时间 < 100ms

   2. GET /api/v1/feed?limit=20&sort=recent (加载新数据)
      - 验证: 缓存未命中，响应时间 < 220ms
      - 验证: 数据是最新内容

✅ 去重验证
   - 快速连续 3 个相同请求
   - 验证: 仅发送 1 个网络请求
   - 其他 2 个请求等待第一个响应
```

---

### 场景 1.4: 排序选项

**目标**: 验证不同排序算法

| # | 测试步骤 | 预期结果 | 实际结果 | 状态 |
|---|---------|--------|--------|------|
| 1.4.1 | 查找"排序"或"筛选"按钮 | ✅ 找到排序选项 (Recent/Engagement) | | ⏳ |
| 1.4.2 | 选择"Recent" (按时间) | ✅ Feed 按创建时间倒序排列 (最新优先) | | ⏳ |
| 1.4.3 | 选择"Engagement" (按热度) | ✅ Feed 按点赞数和时间衰减综合排序 | | ⏳ |
| 1.4.4 | 查看排序切换后的结果顺序 | ✅ 顺序改变，新排序算法生效 | | ⏳ |
| 1.4.5 | 在两种排序间切换多次 | ✅ 每次切换立即更新排序 | | ⏳ |

**API 调用验证**:
```
✅ Recent 排序
   - GET /api/v1/feed?limit=20&sort=recent
   - 数据按 created_at DESC 排列
   - 最新的帖子在最前面

✅ Engagement 排序
   - GET /api/v1/feed?limit=20&sort=engagement
   - Score = (likes × 0.7) + (time_decay × 100 × 0.3)
   - 时间衰减: e^(-hours_old / 24)
   - 高点赞、最近发布的帖子靠前

✅ 缓存分离
   - 不同排序缓存键不同
   - recent 缓存: feed:timeline:user:{id}:limit:20:sort:recent
   - engagement 缓存: feed:timeline:user:{id}:limit:20:sort:engagement
```

---

### 场景 1.5: 性能测试

**目标**: 验证性能指标

| # | 测试步骤 | 预期结果 | 实际结果 | 状态 |
|---|---------|--------|--------|------|
| 1.5.1 | 首次打开 App，加载 Feed | ✅ 首屏加载时间 < 2 秒 | | ⏳ |
| 1.5.2 | 下拉刷新 | ✅ 刷新完成时间 < 500ms (缓存命中), < 1s (缓存未命中) | | ⏳ |
| 1.5.3 | 加载下一页 | ✅ 页面加载时间 < 500ms | | ⏳ |
| 1.5.4 | 快速滚动 Feed | ✅ 滚动帧率 ≥ 60 FPS，无卡顿 | | ⏳ |
| 1.5.5 | 内存占用 | ✅ 稳定在 < 150MB (iPhone 上) | | ⏳ |
| 1.5.6 | 电池消耗 (30 分钟连续使用) | ✅ 电池消耗 < 5% | | ⏳ |

**性能监测方法**:
```
✅ 使用 PerformanceKit
   - PerformanceTimer: 记录 API 响应时间
   - NetworkMonitor: 监控网络连接
   - PerformanceMetrics: 收集性能数据

✅ Xcode 工具
   - Instruments > Network
   - Instruments > Memory
   - Instruments > Core Animation (FPS)
   - Xcode > Debug > View Hierarchy (UI 性能)
```

---

## 🎯 测试场景 2: 消息系统测试

### 场景 2.1: 会话列表与加载

**目标**: 验证消息系统基本功能

| # | 测试步骤 | 预期结果 | 实际结果 | 状态 |
|---|---------|--------|--------|------|
| 2.1.1 | 进入"消息"标签页 | ✅ 显示会话列表，或"暂无会话"提示 | | ⏳ |
| 2.1.2 | 从 Profile 页面发起新消息 | ✅ 打开 ChatView，显示该用户的会话 | | ⏳ |
| 2.1.3 | 查看已有会话 | ✅ 显示: 用户头像、用户名、最后一条消息预览、时间戳 | | ⏳ |
| 2.1.4 | 点击会话进入 | ✅ 加载消息历史，显示所有消息 | | ⏳ |
| 2.1.5 | 向下滚动历史消息 | ✅ 加载更早的消息 (分页) | | ⏳ |

**API 调用验证**:
```
✅ 获取会话列表
   - GET /api/v1/conversations
   - 返回: [{id, user, lastMessage, timestamp}, ...]
   - 验证: 按最后更新时间排序

✅ 获取消息历史
   - GET /api/v1/conversations/{id}/messages?limit=50
   - 返回: [Message{id, content, sender, timestamp}, ...]
   - 验证: 按时间倒序排列

✅ 分页加载
   - GET /api/v1/conversations/{id}/messages?limit=50&cursor=xxx
   - 验证: 加载更早的消息
```

---

### 场景 2.2: 实时消息接收与发送

**目标**: 验证 WebSocket 实时通信

| # | 测试步骤 | 预期结果 | 实际结果 | 状态 |
|---|---------|--------|--------|------|
| 2.2.1 | 打开 ChatView | ✅ 建立 WebSocket 连接，显示连接状态 | | ⏳ |
| 2.2.2 | 输入消息，点击发送 | ✅ 消息立即显示在聊天窗口 (本地) | | ⏳ |
| 2.2.3 | 观察消息发送 | ✅ 显示"发送中"状态，完成后显示"已发送" | | ⏳ |
| 2.2.4 | 从另一设备/账户发送消息到当前用户 | ✅ 消息实时显示在 ChatView，无延迟 | | ⏳ |
| 2.2.5 | 查看已读状态 | ✅ 对方消息下方显示"已读"或时间戳 | | ⏳ |
| 2.2.6 | 当前用户查看对方消息时 | ✅ 消息自动标记为"已读"，对方可看到 | | ⏳ |

**API 调用验证**:
```
✅ WebSocket 连接
   - URL: ws://localhost:3000/ws/messages
   - 认证: 在 query 或 header 中传递 JWT token
   - 验证: 连接成功 (WS 1.1 101 Switching Protocols)

✅ 发送消息
   - POST /api/v1/messages
   - Body: {conversationId, content, type}
   - 验证: 返回 Message{id, content, timestamp, status}

✅ 消息接收 (WebSocket 事件)
   - 事件类型: "message"
   - 内容: {id, conversationId, sender, content, timestamp}
   - 触发: 1. 本地消息发送成功 2. 远端消息到达

✅ 已读状态
   - PUT /api/v1/messages/{id}/read
   - 验证: 返回 {id, readAt, status}
   - 触发时机: 用户查看消息 500ms 后

✅ 输入指示
   - WebSocket 事件: "typing"
   - 触发时机: 用户开始输入
   - 显示: 对方看到"正在输入..."
```

---

### 场景 2.3: WebSocket 重连与离线恢复

**目标**: 验证网络断线恢复

| # | 测试步骤 | 预期结果 | 实际结果 | 状态 |
|---|---------|--------|--------|------|
| 2.3.1 | 打开 ChatView，建立连接 | ✅ WebSocket 已连接 | | ⏳ |
| 2.3.2 | 启用飞行模式 (模拟网络中断) | ✅ WebSocket 断开，显示"离线"状态 | | ⏳ |
| 2.3.3 | 尝试发送消息 | ✅ 消息缓存本地，显示"待发送"状态 | | ⏳ |
| 2.3.4 | 关闭飞行模式，恢复网络 | ✅ 自动重连 WebSocket，显示"已连接" | | ⏳ |
| 2.3.5 | 观察缓存消息发送 | ✅ 本地缓存消息自动发送，更新为"已发送" | | ⏳ |
| 2.3.6 | 加载消息历史 | ✅ 同步服务器最新消息 (无重复、无遗漏) | | ⏳ |

**API 调用验证**:
```
✅ 重连机制
   - 网络恢复后自动重连 WebSocket
   - 重连间隔: 指数退避 (1s, 2s, 4s, 最多 30s)
   - 最大重试次数: 10 次

✅ 离线消息缓存
   - 本地存储: SwiftData / CoreData
   - 容量: 最多 500 条消息
   - 重连后同步: 批量发送或单个发送

✅ 消息顺序保证
   - 离线发送的消息保持顺序
   - 服务器端合并时保持时间戳顺序
```

---

### 场景 2.4: 消息加密与安全

**目标**: 验证端到端加密

| # | 测试步骤 | 预期结果 | 实际结果 | 状态 |
|---|---------|--------|--------|------|
| 2.4.1 | 打开 ChatView | ✅ 显示加密指示 (锁定图标或"加密"标签) | | ⏳ |
| 2.4.2 | 发送消息 | ✅ 消息内容在客户端加密后发送 | | ⏳ |
| 2.4.3 | 服务器端查看消息 (使用工具/数据库) | ✅ 消息为加密格式，不可读 | | ⏳ |
| 2.4.4 | 对方接收消息 | ✅ 在客户端解密，正确显示原文 | | ⏳ |
| 2.4.5 | 切换会话，再返回 | ✅ 历史消息正确解密，内容完整 | | ⏳ |

**加密验证方法**:
```
✅ 加密检查
   - 使用 Charles / Burp Suite 拦截 API 流量
   - 检查: POST /api/v1/messages 中 content 字段是否加密
   - 验证: Base64 or Hex 格式的加密数据

✅ Keychain 验证
   - 确认加密密钥存储在 Keychain (安全)
   - 不存储在 UserDefaults (不安全)
```

---

### 场景 2.5: 多设备消息同步

**目标**: 验证跨设备消息同步

| # | 测试步骤 | 预期结果 | 实际结果 | 状态 |
|---|---------|--------|--------|------|
| 2.5.1 | 在设备 A 上发送消息 | ✅ 消息显示在设备 A 的 ChatView | | ⏳ |
| 2.5.2 | 在设备 B 上查看 | ✅ 同一会话中看到来自设备 A 的消息 | | ⏳ |
| 2.5.3 | 在设备 B 上标记已读 | ✅ 已读状态在设备 A 上也显示 | | ⏳ |
| 2.5.4 | 在设备 B 上删除消息 | ✅ 消息在设备 A 上也被删除 (同步) | | ⏳ |

**API 调用验证**:
```
✅ 消息同步
   - WebSocket 广播: 消息发送时广播给所有活跃连接
   - 已读同步: PUT /api/v1/messages/{id}/read 广播给所有设备
   - 删除同步: DELETE /api/v1/messages/{id} 广播给所有设备

✅ 连接管理
   - 每个设备标识: device_id (UUID)
   - 本用户多设备连接: 允许多个 WebSocket 连接
   - 消息广播: 排除发送者自己的连接
```

---

## 🎯 测试场景 3: iOS 应用整体测试

### 场景 3.1: 应用启动与初始化

**目标**: 验证应用冷启动流程

| # | 测试步骤 | 预期结果 | 实际结果 | 状态 |
|---|---------|--------|--------|------|
| 3.1.1 | 完全关闭应用，从 App Store 或本地重新安装 | ✅ 安装成功，无错误 | | ⏳ |
| 3.1.2 | 启动应用 | ✅ 显示启动屏幕，加载 < 3 秒 | | ⏳ |
| 3.1.3 | 如果未登录，显示登录页 | ✅ 登录界面正确显示 | | ⏳ |
| 3.1.4 | 完成登录 | ✅ 进入主页 (Feed 页面)，< 5 秒 | | ⏳ |
| 3.1.5 | 检查本地数据完整性 | ✅ 缓存、Token、User Info 都正确存储 | | ⏳ |

---

### 场景 3.2: 应用后台与恢复

**目标**: 验证应用生命周期管理

| # | 测试步骤 | 预期结果 | 实际结果 | 状态 |
|---|---------|--------|--------|------|
| 3.2.1 | 应用运行中，按 Home 键进入后台 | ✅ 应用正常进入后台，资源释放 | | ⏳ |
| 3.2.2 | 等待 2 分钟 | ✅ 应用在后台保持连接 (WebSocket) 或断开 (可配置) | | ⏳ |
| 3.2.3 | 从后台返回前台 | ✅ 应用立即恢复，显示当前页面 | | ⏳ |
| 3.2.4 | 查看 Feed 或消息 | ✅ 显示最新数据，如有新消息会更新 | | ⏳ |
| 3.2.5 | 内存占用 | ✅ 后台内存占用 < 50MB | | ⏳ |

---

### 场景 3.3: 响应式设计与方向切换

**目标**: 验证不同屏幕尺寸适配

| # | 测试步骤 | 预期结果 | 实际结果 | 状态 |
|---|---------|--------|--------|------|
| 3.3.1 | 在竖屏模式查看 Feed | ✅ 布局正确，内容完整可读 | | ⏳ |
| 3.3.2 | 旋转屏幕到横屏模式 | ✅ 布局自动调整，数据保留 | | ⏳ |
| 3.3.3 | 在横屏查看内容 | ✅ 充分利用宽屏空间，无拉伸变形 | | ⏳ |
| 3.3.4 | 快速连续旋转屏幕 | ✅ 无崩溃，布局稳定切换 | | ⏳ |
| 3.3.5 | 在 iPad 上测试 | ✅ 适配平板尺寸，分栏布局 (如适用) | | ⏳ |

---

### 场景 3.4: 错误处理与异常恢复

**目标**: 验证异常情况处理

| # | 测试步骤 | 预期结果 | 实际结果 | 状态 |
|---|---------|--------|--------|------|
| 3.4.1 | 后端服务宕机时打开应用 | ✅ 显示错误提示: "无法连接到服务器"，提供重试选项 | | ⏳ |
| 3.4.2 | 点击重试 | ✅ 重试连接，若服务恢复则加载数据 | | ⏳ |
| 3.4.3 | 登录时输入错误密码 | ✅ 显示"用户名或密码错误"，允许重试 | | ⏳ |
| 3.4.4 | 超时的 API 请求 | ✅ 显示"请求超时"，提供重试或返回选项 | | ⏳ |
| 3.4.5 | 中途应用崩溃 (故意杀死进程) | ✅ 重启应用，恢复到崩溃前的页面和状态 | | ⏳ |

---

### 场景 3.5: 辅助功能与无障碍

**目标**: 验证 WCAG 2.1 合规性

| # | 测试步骤 | 预期结果 | 实际结果 | 状态 |
|---|---------|--------|--------|------|
| 3.5.1 | 启用 VoiceOver (无障碍阅读) | ✅ 所有按钮、文本都能被 VoiceOver 正确读取 | | ⏳ |
| 3.5.2 | 使用 VoiceOver 导航应用 | ✅ 逻辑顺序清晰，能访问所有功能 | | ⏳ |
| 3.5.3 | 启用字体放大 | ✅ 文本自动放大，布局正确调整 | | ⏳ |
| 3.5.4 | 启用高对比度模式 | ✅ 颜色对比满足 WCAG AA (≥ 4.5:1)，文本清晰可读 | | ⏳ |
| 3.5.5 | 使用深色模式 | ✅ UI 自动切换到深色，颜色方案协调 | | ⏳ |
| 3.5.6 | 测试键盘导航 | ✅ 使用 Tab/Shift+Tab 可访问所有交互元素 | | ⏳ |

---

### 场景 3.6: 国际化与本地化

**目标**: 验证多语言支持

| # | 测试步骤 | 预期结果 | 实际结果 | 状态 |
|---|---------|--------|--------|------|
| 3.6.1 | 设置系统语言为简体中文 | ✅ 应用界面显示简体中文 | | ⏳ |
| 3.6.2 | 设置系统语言为英文 | ✅ 应用界面切换到英文 | | ⏳ |
| 3.6.3 | 设置系统语言为其他语言 (日文/西班牙文等) | ✅ 应用显示相应语言 (如支持)，或回退到英文 | | ⏳ |
| 3.6.4 | 在不同语言间快速切换 | ✅ 应用无崩溃，语言立即切换 | | ⏳ |
| 3.6.5 | 查看时间格式 | ✅ 时间戳按系统区域设置格式化 (如 24/12 小时制) | | ⏳ |

---

## 📊 测试数据与清单

### 必要的测试数据

#### Feed 测试数据
```
创建者: test-user-1
发布内容:
  - 纯文本帖子 (5 条)
  - 含单张图片的帖子 (3 条)
  - 含多张图片的帖子 (2 条)
  - 含视频的帖子 (2 条)
  - 热门帖子 (> 1000 赞) (1 条)

点赞分布:
  - 0-10 赞 (4 条)
  - 10-100 赞 (4 条)
  - 100-1000 赞 (2 条)
  - > 1000 赞 (1 条)

时间分布:
  - 今天 (5 条)
  - 昨天 (3 条)
  - 1-7 天前 (4 条)
  - 7-30 天前 (2 条)
```

#### 消息测试数据
```
会话 1: test-user-1 ↔ test-user-2
  消息数量: 50+ 条
  内容类型: 文本、图片、文件
  时间跨度: 7 天

会话 2: test-user-1 ↔ test-user-3
  消息数量: 10+ 条
  内容类型: 纯文本
  时间跨度: 1 天

消息状态:
  - 已发送未读 (10+ 条)
  - 已发送已读 (40+ 条)
```

---

## ✅ 测试完成检查清单

### Feed 功能
- [ ] 基本加载与显示
- [ ] 分页与无限滚动
- [ ] 下拉刷新
- [ ] 排序选项 (Recent/Engagement)
- [ ] 缓存验证
- [ ] 离线支持
- [ ] 性能指标
- [ ] 错误处理

### 消息系统
- [ ] 会话列表加载
- [ ] 实时消息接收
- [ ] 消息发送
- [ ] 已读状态同步
- [ ] WebSocket 重连
- [ ] 离线消息缓存
- [ ] 消息加密
- [ ] 多设备同步

### iOS 应用
- [ ] 应用启动与初始化
- [ ] 后台与恢复
- [ ] 屏幕适配与旋转
- [ ] 错误处理与恢复
- [ ] 辅助功能
- [ ] 国际化

### API 端点验证
- [ ] `GET /api/v1/feed` 正确返回
- [ ] `GET /api/v1/feed/timeline` 正确返回
- [ ] `POST /api/v1/feed/refresh` 正确执行
- [ ] `GET /api/v1/conversations` 正确返回
- [ ] `POST /api/v1/messages` 正确发送
- [ ] `PUT /api/v1/messages/{id}/read` 正确更新
- [ ] WebSocket `/ws/messages` 正常连接

### 性能指标
- [ ] Feed 首屏加载 < 2 秒
- [ ] API 响应 < 200ms (缓存), < 220ms (无缓存)
- [ ] 消息实时延迟 < 100ms
- [ ] 内存占用 < 150MB
- [ ] 帧率 ≥ 60 FPS

---

## 🚀 UAT 执行计划

### 第一天 (Today - 2025-10-20)
```
上午:
  - [ ] 环境验证 (后端 API, iOS 编译)
  - [ ] 场景 1.1-1.2 (Feed 加载与分页)
  - [ ] 场景 2.1 (消息列表)

下午:
  - [ ] 场景 1.3-1.5 (Feed 刷新和性能)
  - [ ] 场景 2.2-2.3 (消息发送和重连)
```

### 第二天
```
上午:
  - [ ] 场景 2.4-2.5 (消息加密和多设备)
  - [ ] 场景 3.1-3.3 (应用整体功能)

下午:
  - [ ] 场景 3.4-3.6 (错误处理和无障碍)
  - [ ] 性能回归测试
  - [ ] 问题分类和优先级评估
```

### 第三天
```
全天:
  - [ ] 问题修复和回测
  - [ ] 最终验证清单
  - [ ] UAT 报告生成
```

---

## 📝 问题追踪模板

当发现问题时，使用以下格式记录:

```
【问题 ID】: UAT-001
【严重级别】: 🔴 Critical / 🟡 High / 🟢 Medium / 🔵 Low
【类别】: Feed / Messaging / iOS App / Performance
【标题】: [简洁描述问题]
【步骤】:
  1. ...
  2. ...
  3. ...
【预期结果】: 应该...
【实际结果】: 实际上...
【环境】: iOS 17.0+, iPhone 14 Pro, 网络: WiFi
【附件】: 截图/视频/日志
【根本原因】: [分析如果有的话]
【建议】: [修复建议]
【状态】: 🟢 开启 / 🟡 进行中 / 🔵 待测试 / 🟢 已关闭
```

---

## 📞 快速参考

### 后端 API 服务状态查询
```bash
# 检查后端健康状态
curl -X GET http://localhost:3000/health

# 检查 Redis 连接
redis-cli ping  # 应返回 PONG

# 检查数据库连接
psql -U nova -d nova_db -c "SELECT version();"
```

### iOS 调试技巧
```bash
# 查看实时日志
xcrun simctl spawn booted log stream --predicate 'eventMessage contains "Nova"'

# 查看 Network 流量 (使用 Proxyman/Charles)
# 配置代理: 应用 → 设置 → WiFi → 配置代理

# 性能分析
# Xcode → Debug → Instruments → 选择 Network/Memory/Core Animation
```

---

**May the Force be with you.**

*iOS UAT 测试计划已完成。准备执行三天 UAT 周期。*

---

*准备时间*: 2025-10-20
*状态*: ✅ **就绪执行**
*预期完成*: 2025-10-22
*质量目标*: 🌟 **生产级别**
