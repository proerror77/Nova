# Nova Backend - 实现优先级与依赖关系完整规划

## 执行总结

**项目现状**: Phase 1 gRPC 迁移 66% 完成
- **已完成**: 3 个完整服务（messaging, auth, user）+ 4 个核心基础库
- **进行中**: 3 个服务（content, feed, streaming） 
- **未启动**: 4 个服务（search, notification, events, cdn）
- **总工作量**: 约 420-480 小时

---

## 1. 各服务完成度评估

### Phase 1A - 已完成 (✅)

#### messaging-service (100% - 871 LOC)
- **状态**: Phase 1A/1B 完成，Phase 1C (3.1-3.2) 实现中
- **实现**: 29 个 RPC 方法完整实现
- **特点**:
  - WebSocket 实时消息处理
  - E2E 加密与密钥交换
  - 消息离线队列管理
  - gRPC 指标集成（使用 RequestGuard）
  - 16 个集成测试通过
- **关键PR**: cc532675, 7f9bb68f, b8da1689, 43ce7147
- **后续**: WebSocket 事件兼容层、user_id 元数据提取

#### auth-service (95%)
- **状态**: gRPC 完整，HTTP 路由配置中
- **实现**: Register, Login, RefreshToken, Logout, ValidateToken
- **特点**: 
  - JWT 令牌管理
  - 2FA 支持
  - 会话管理
  - 审计日志
- **待完成**: OAuth2 集成、SAML 支持

#### user-service (85%)
- **状态**: gRPC 框架完成，部分方法实现
- **实现**: 用户资料、关系管理、偏好设置
- **特点**:
  - PostgreSQL + Redis 缓存
  - 用户社交图谱
  - CDC (Change Data Capture) 事件流
- **待完成**: 推荐用户算法优化、关系图谱查询优化

### Phase 1B - 进行中 (⏳)

#### content-service (75% - 571 LOC)
- **状态**: gRPC 框架完成，20 个方法大部分实现
- **实现**: 
  - CreatePost, GetPost, UpdatePost, DeletePost
  - GetComments, AddComment (部分)
  - 点赞/取赞系统
- **特点**:
  - 发布内容管理
  - 评论系统
  - 参与度追踪
- **待完成**: 
  - 视频关联操作 (POST_VIDEO_ASSOCIATION)
  - 评论分页和排序
  - 内容审核集成

#### feed-service (70% - 262 LOC)
- **状态**: gRPC 部分方法完成，推荐引擎框架建立
- **实现**:
  - GetFeed (缓存层完成)
  - RankPosts (框架就绪)
  - GetRecommendedCreators (部分)
- **特点**:
  - Redis 缓存（FeedCache）
  - 混合推荐算法（协同+内容特征）
  - A/B 测试框架
  - 向量搜索准备
- **待完成**:
  - ONNX 模型服务集成
  - Milvus 向量搜索
  - Kafka 事件消费者
  - JWT 轮换机制

#### streaming-service (65% - 195 LOC)
- **状态**: gRPC 方法框架完成，HTTP 路由待实现
- **实现**:
  - StartStream, StopStream
  - GetStreamStatus, GetStreamChat
- **特点**:
  - 直播流管理
  - 实时聊天
  - Redis 状态存储
- **待完成**:
  - HTTP 路由层实现
  - gRPC 方法完整实现
  - Redis 验证集成
  - 测试覆盖

#### media-service (60%)
- **状态**: gRPC 框架完成，大部分方法实现
- **实现**:
  - GetVideo, GetUserVideos, CreateVideo
  - 上传管理
  - 处理状态追踪
- **特点**:
  - S3 集成
  - 视频转码
  - CDN 路由
- **待完成**:
  - 处理优化
  - 缓存策略完善

### Phase 1C - 未启动 (❌)

#### search-service (5% - 91 LOC)
- **状态**: 所有 10 个方法为 `Status::unimplemented`
- **需要实现**:
  - FullTextSearch (全文搜索)
  - SearchPosts, SearchUsers, SearchHashtags
  - GetPostsByHashtag, GetTrendingHashtags
  - SaveSearchQuery, GetSearchSuggestions
  - GetSearchHistory, ClearSearchHistory
- **依赖**:
  - PostgreSQL FTS (全文搜索)
  - Redis 搜索缓存
  - Elasticsearch (可选, 大规模)
- **工作量**: 60-80 小时
- **优先级**: ⚠️ 高（Feed 依赖搜索建议）

#### notification-service (15% - 128 LOC)
- **状态**: 13 个方法为 stub
- **需要实现**:
  - GetNotifications, GetNotification
  - CreateNotification, UpdateNotification, DeleteNotification
  - MarkAsRead, MarkAllAsRead
  - GetNotificationSettings, UpdateNotificationSettings
  - SendPushNotification (APNs/FCM 集成)
  - GetNotificationStats
- **依赖**:
  - PostgreSQL 通知表
  - Redis 实时通知缓存
  - Kafka (批处理消费)
  - APNs/FCM SDK
- **工作量**: 80-100 小时
- **优先级**: ⚠️ 高（用户体验关键）

#### events-service (10% - 127 LOC)
- **状态**: 14 个方法为 stub
- **需要实现**:
  - PublishEvent, PublishEvents (批量)
  - GetEvent, ListEvents
  - GetEventSchema, ValidateEvent
  - CreateEventSchema, UpdateEventSchema
  - SubscribeToEvent, UnsubscribeFromEvent
  - GetSubscriptions
  - Outbox 模式实现
- **依赖**:
  - PostgreSQL 事件表 + Outbox 表
  - Kafka 发布/订阅
  - Schema 版本管理
  - CDC 集成
- **工作量**: 100-120 小时
- **优先级**: 🔴 关键（所有服务的事件基础）

#### cdn-service (10% - 107 LOC)
- **状态**: 12 个方法为 stub
- **需要实现**:
  - GenerateCdnUrl (URL 生成)
  - GetCdnAsset, RegisterCdnAsset
  - ListCdnAssets, DeleteCdnAsset
  - InvalidateCdnCache, GetCacheStatus
  - GetCdnMetrics, GetAssetMetrics
  - UpdateAssetMetadata
  - CheckAssetHealth
- **依赖**:
  - PostgreSQL 资产表
  - Redis 缓存元数据
  - CloudFront/Cloudflare API
  - S3 后端
- **工作量**: 50-70 小时
- **优先级**: 中等（媒体交付优化）

---

## 2. 关键依赖关系图

```
┌─────────────────────────────────────────────────────────────────┐
│                    数据库 (PostgreSQL)                           │
│     ┌─────────────┬──────────┬────────────┬────────────┐        │
│     ▼             ▼          ▼            ▼            ▼        │
│  users      conversations messages   posts/videos  notifications
│  │           │              │           │              │
└──┼───────────┼──────────────┼───────────┼──────────────┘
   │           │              │           │              
┌──┴───────────┴──────────────┴───────────┴──────────────┐
│           事件基础设施 (events-service)                 │
│  - Event 发布/订阅                                     │
│  - Outbox 模式 (CDC 可靠性)                            │
│  - Schema 验证                                         │
│  - Kafka 集成                                          │
└──┬──────────────┬──────────────┬──────────────┬─────────┘
   │              │              │              │
   ▼              ▼              ▼              ▼
auth-svc    messaging-svc  content-svc   notification-svc
(✅)         (✅)           (⏳)          (❌)
   │              │              │              │
   ▼              ▼              ▼              ▼
user-svc     feed-svc      search-svc     cdn-svc
(85%)        (70%)         (5%)           (10%)
   │              │
   └──────────────┴─────────────────────┐
                                        ▼
                              streaming-service
                                   (65%)
```

### 依赖关系详解

| 服务 | 依赖 | 类型 | 优先级 | 备注 |
|------|------|------|--------|------|
| **events-service** | PostgreSQL, Kafka | 基础设施 | 🔴 必须 | 所有服务依赖其事件系统 |
| **search-service** | PostgreSQL FTS, Redis | 数据 | ⚠️ 高 | Feed 推荐依赖搜索建议 |
| **notification-service** | PostgreSQL, Redis, Kafka, APNs/FCM | 基础设施 | ⚠️ 高 | 用户体验关键 |
| **cdn-service** | PostgreSQL, Redis, CloudFront/S3 | 基础设施 | 中 | 媒体交付优化 |
| **feed-service** | content-svc, user-svc, search-svc, PostgreSQL, Redis | 业务 | ⚠️ 高 | 核心产品功能 |
| **streaming-service** | events-svc, notification-svc, Redis | 业务 | 中 | 附加功能 |

---

## 3. 推荐实现顺序

### 第1阶段 (Week 1-2, 80-100小时) - 基础事件系统
**目标**: 建立跨服务通信基础

1. **events-service** (100-120h)
   - PostgreSQL Outbox 表 + 索引
   - Kafka 发布/订阅实现
   - Event Schema 版本管理
   - CDC 集成验证
   - 10 个 RPC 方法完整实现
   - 集成测试 (20+ 用例)
   
   **产出**: 
   - 事件发布/订阅 gRPC 服务
   - Schema 验证框架
   - Outbox 可靠性保证
   
   **前置条件**: Kafka 集群就绪，PostgreSQL 中间件扩展

---

### 第2阶段 (Week 3-4, 100-120小时) - 核心消费者

2. **notification-service** (80-100h)
   - PostgreSQL 通知表 (notifications, notification_settings, notification_history)
   - Redis 实时通知缓存
   - Kafka 批处理消费 (events-service → notifications)
   - APNs/FCM 推送集成
   - 13 个 RPC 方法实现
   
   **产出**:
   - 完整 CRUD 操作
   - 实时推送系统
   - 设置管理
   
   **前置条件**: events-service ✅, APNs/FCM 凭证

3. **search-service** (60-80h)
   - PostgreSQL 全文搜索索引 (GIN)
   - Redis 搜索结果缓存
   - 搜索历史追踪
   - 10 个 RPC 方法实现
   - 性能优化 (响应 < 500ms)
   
   **产出**:
   - 全文搜索引擎
   - 搜索建议系统
   - 热搜追踪
   
   **前置条件**: PostgreSQL FTS 配置

---

### 第3阶段 (Week 5-6, 120-160小时) - 内容推荐

4. **content-service 完善** (40-50h)
   - 剩余的评论系统完整性
   - POST_VIDEO_ASSOCIATION 迁移
   - 内容审核钩子
   - 2 个 RPC 方法完成
   
   **产出**:
   - 完整 CRUD
   - 评论分页
   
   **前置条件**: video-service ✅

5. **feed-service 完整实现** (80-100h)
   - ONNX 模型服务 (PyTorch → TensorRT)
   - Milvus 向量搜索集成
   - Kafka 事件消费 (posts, users, follows)
   - 协同过滤 + 内容特征混合排序
   - A/B 测试框架完成
   - JWT 轮换机制
   - 3 个 RPC 方法完整 + 缓存优化
   
   **产出**:
   - 端到端个性化推荐
   - 向量相似度排序
   - 实验框架
   
   **前置条件**: content-svc ✅, search-svc ✅, Milvus ✅, ONNX 模型就绪

---

### 第4阶段 (Week 7-8, 100-120小时) - 辅助服务

6. **cdn-service** (50-70h)
   - PostgreSQL 资产表 (cdn_assets, cdn_cache_status)
   - Redis 元数据缓存
   - CloudFront/Cloudflare API 集成
   - 12 个 RPC 方法实现
   - 缓存失效策略
   
   **产出**:
   - URL 生成引擎
   - 缓存管理
   - 指标追踪
   
   **前置条件**: media-service ✅, CDN 账户配置

7. **streaming-service 完善** (50-70h)
   - HTTP 路由层完整实现
   - gRPC 方法完整 + Redis 验证
   - 直播事件集成 (events-service)
   - 3 个 RPC 方法完整
   - 集成测试
   
   **产出**:
   - 完整直播系统
   - 实时聊天
   - 状态管理
   
   **前置条件**: events-svc ✅, notification-svc ✅

---

## 4. 每个模块工作量估算 (单位: 小时)

### 按复杂度分类

#### 🟢 简单 (40-60h)
- **cdn-service** URL 生成 + 缓存管理: 50h
  - PostgreSQL 表设计: 5h
  - CloudFront 集成: 20h
  - 缓存失效逻辑: 15h
  - 指标 + 测试: 10h

#### 🟡 中等 (60-100h)
- **search-service** 全文搜索: 70h
  - PostgreSQL FTS 索引: 15h
  - 搜索API实现: 30h
  - 缓存 + 分页: 15h
  - 性能优化 + 测试: 10h

- **notification-service** CRUD: 80h
  - PostgreSQL 表 + 索引: 10h
  - Redis 缓存: 15h
  - CRUD API: 25h
  - APNs/FCM 集成: 20h
  - Kafka 消费: 10h

- **streaming-service** HTTP + gRPC: 65h
  - HTTP 路由: 20h
  - gRPC 方法: 20h
  - Redis 状态: 15h
  - 测试: 10h

#### 🔴 复杂 (80-120h)
- **events-service** 事件系统: 110h
  - PostgreSQL Outbox: 20h
  - Kafka 集成: 25h
  - Schema 管理: 20h
  - CDC 集成: 20h
  - 测试 + 优化: 25h

- **feed-service** 推荐引擎: 100h
  - ONNX 模型服务: 30h
  - Milvus 集成: 25h
  - Kafka 消费: 15h
  - 混合排序算法: 20h
  - A/B 测试: 10h

- **content-service** 完善: 45h
  - 评论系统完整: 20h
  - VIDEO_ASSOCIATION: 15h
  - 审核集成: 10h

### 总工作量分布

```
events-service       ████████████ 110h (22%)
feed-service         ███████████  100h (20%)
notification-service ██████████   80h  (16%)
search-service       ███████      70h  (14%)
streaming-service    ██████       65h  (13%)
cdn-service          ██████       50h  (10%)
content-service (完善) ████       45h  (9%)
──────────────────────────────────────────
总计                              520h
```

**时间估算**: 4-6 周，1 个高级工程师 + 1 个中级工程师

---

## 5. 风险点与前置条件

### 🔴 关键风险

#### 1. 数据库架构一致性
- **风险**: 7 个服务不同的数据模型可能冲突
- **缓解**: 
  - ✅ 统一 UUID 标识符规范
  - ⏳ 建立数据所有权 (DDD 概念)
  - ⏳ 跨服务数据一致性测试

#### 2. Kafka 可靠性
- **风险**: 事件丢失或重复处理
- **缓解**:
  - 实现 Outbox 模式 (PostgreSQL)
  - 幂等消费者设计
  - 死信队列处理

#### 3. 推荐算法性能
- **风险**: ONNX 模型 P95 延迟 > 500ms
- **缓解**:
  - 模型量化 (int8)
  - 批量推理 (batch size=32)
  - Redis 缓存预热

#### 4. 跨服务数据一致性
- **风险**: Feed 排序与搜索结果不同步
- **缓解**:
  - CDC 延迟监控 (目标: < 30s)
  - ClickHouse 同步验证
  - 最终一致性测试框架

### ⚠️ 中等风险

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| PostgreSQL 连接池耗尽 | 服务超时 | 连接池监控 + 动态调整 |
| Redis 缓存穿透 | 数据库 CPU 尖峰 | 布隆过滤器 + 缓存预热 |
| Kafka partition rebalance | 消息处理延迟 | 消费者群组配置优化 |
| JWT 过期导致服务调用失败 | 用户请求失败 | 自动轮换机制 |
| 向量搜索冷启动 | Feed 推荐慢 | 离线模型预热 |

### 📋 前置条件清单

```
基础设施:
  ☑️ PostgreSQL 14+ (66 migrations 已完成)
  ☑️ Redis 7+ (连接池、缓存策略)
  ☑️ Kafka 3.0+ (5 个主题已创建)
  ☐ Milvus 2.3+ (向量搜索) - 需要部署
  ☐ ClickHouse (Feed 排序分析) - 待确认
  
外部服务:
  ☑️ JWT 密钥对 (crypto-core 已集成)
  ☐ APNs 凭证 (iOS 推送)
  ☐ FCM 凭证 (Android 推送)
  ☐ CloudFront/Cloudflare API 密钥
  ☐ ONNX 模型文件 (PyTorch 转换)
  
依赖库:
  ☑️ grpc-metrics (RED 指标)
  ☑️ grpc-clients (统一客户端)
  ☑️ crypto-core (JWT/加密)
  ☑️ redis-utils (连接池)
  ☑️ actix-middleware (HTTP 中间件)
  ☑️ error-handling (统一错误)
  
开发工具:
  ☑️ sqlx-cli (数据库迁移)
  ☑️ cargo 1.76+
  ☑️ Docker & Docker Compose
  ☐ ONNX Runtime (推荐模型)
  ☐ gRPC 压力测试工具 (ghz)
```

---

## 6. 实现检查清单 (按优先级)

### Phase 1: events-service 基础 (Week 1-2)

- [ ] PostgreSQL Outbox 表创建 (迁移 053)
- [ ] Kafka Topic 主题配置验证
- [ ] Event Schema 原型定义
- [ ] PublishEvent RPC 实现 + 测试
- [ ] PublishEvents (批量) 实现 + 性能测试
- [ ] SubscribeToEvent / UnsubscribeFromEvent
- [ ] CDC Consumer 验证
- [ ] Prometheus 指标验证

### Phase 2: notification-service (Week 3-4)

- [ ] PostgreSQL notifications 表
- [ ] GetNotifications 分页实现
- [ ] CreateNotification 持久化
- [ ] MarkAsRead 批量更新优化
- [ ] Kafka 消费者集成 (events → notifications)
- [ ] APNs 推送集成
- [ ] Redis 缓存 (user:notifications:unread)
- [ ] 集成测试 (15+ 用例)

### Phase 3: search-service (Week 3-4)

- [ ] PostgreSQL GIN 索引 (posts.content, users.username)
- [ ] FullTextSearch 查询优化
- [ ] SearchUsers 实现 (用户名/简介)
- [ ] SearchPosts 实现 (内容 + 标签)
- [ ] GetSearchSuggestions (Redis 缓存)
- [ ] GetSearchHistory + 清除
- [ ] 性能基准测试 (< 500ms P95)
- [ ] 集成测试 (10+ 用例)

### Phase 4: feed-service 完善 (Week 5-6)

- [ ] Milvus 集群部署验证
- [ ] ONNX 模型加载 (TensorRT)
- [ ] 向量嵌入生成 (PostEmbedding)
- [ ] Kafka 消费 posts/users/follows 事件
- [ ] 混合排序算法 (协同 + 内容)
- [ ] A/B 测试框架 (variant 分配)
- [ ] JWT 轮换机制 (gRPC 客户端)
- [ ] 缓存预热脚本
- [ ] 性能测试 (1000 QPS)

### Phase 5: cdn-service (Week 7)

- [ ] PostgreSQL cdn_assets 表
- [ ] CloudFront 分布设置验证
- [ ] GenerateCdnUrl 实现 (签名 URL)
- [ ] InvalidateCdnCache 集成
- [ ] GetCdnMetrics (CloudWatch)
- [ ] 资产健康检查
- [ ] 集成测试

### Phase 6: streaming-service (Week 7-8)

- [ ] HTTP 路由完整实现
- [ ] StartStream gRPC + Redis 状态
- [ ] GetStreamChat (分页)
- [ ] events-service 事件集成
- [ ] notification-service 推送集成
- [ ] 实时聊天 WebSocket
- [ ] 集成测试 (8+ 用例)

---

## 7. 跨服务集成验证

### 数据流验证

```
User Action        Event Flow           Notification Flow       Feed Update
─────────────────────────────────────────────────────────────────────────

用户点赞 Post   →  content-svc  →  events-svc  →  notification-svc  →  Feed 重排序
                   (PostLiked)     (publish)      (createNotif)       (redis清除)
                                   ↓ Kafka
                              notification-svc
                              (send APNs/FCM)

用户搜索话题    →  search-svc  →  (PostgreSQL FTS)  →  Feed 建议话题
                   (SearchHashtag)  (cache Redis)      (ranked posts)

用户关注        →  user-svc  →  events-svc  →  feed-svc  →  用户 Feed 重建
                   (FollowUser)  (UserFollowed) (invalidate) (Milvus 排序)
                                (Kafka)
```

### 集成测试场景 (30+ 用例)

1. **单个服务 CRUD** (8 用例)
   - CreateNotification → 验证 PostgreSQL + Redis
   - GetNotifications 分页 → 验证排序
   - MarkAsRead → 验证原子性

2. **跨服务事件** (10 用例)
   - Post 创建 → events-svc → notification-svc → APNs
   - User Follow → 验证 CDC → feed-svc 缓存清除
   - Search Query → redis 缓存 + 热搜更新

3. **性能测试** (8 用例)
   - Feed 排序 P95 < 500ms (1000 QPS)
   - 搜索建议 P95 < 200ms
   - 通知推送吞吐量 > 10k/s

4. **故障恢复** (4 用例)
   - Kafka broker 宕机 → consumer lag 恢复
   - Redis 连接断开 → 自动降级到 PostgreSQL
   - 模型推理超时 → 降级到规则排序

---

## 8. 成功指标 (KPI)

### 功能完成度
- [ ] 7 个服务 gRPC 方法 100% 实现 (194 个方法)
- [ ] 集成测试覆盖率 > 80%
- [ ] E2E 场景覆盖 (10+ 用户旅程)

### 性能指标
- [ ] API P95 延迟: < 500ms
- [ ] Feed 排序 P99: < 800ms
- [ ] 搜索建议: < 200ms
- [ ] 推送吞吐量: > 10k/s
- [ ] CDC 延迟: < 30s

### 可靠性
- [ ] 错误率: < 0.1%
- [ ] Kafka 消息幸存率: > 99.99%
- [ ] 服务可用性: > 99.5%
- [ ] 数据一致性: < 1 分钟偏差

### 可观测性
- [ ] Prometheus RED 指标覆盖 100%
- [ ] 分布式追踪 (Jaeger) 样本率 1%
- [ ] 日志结构化 (JSON) 覆盖 100%

---

## 9. 学习资源与参考

### 架构
- Redis 缓存设计: `backend/feed-service/src/cache.rs`
- 数据库迁移: `backend/migrations/`
- gRPC 指标: `backend/libs/grpc-metrics/`
- 事件驱动: `backend/proto/services/events_service.proto`

### 已有实现
- messaging-service 完整示例: 29 个 RPC 方法
- auth-service JWT: `crypto-core` 库
- user-service CDC: `user-service/src/services/cdc/`
- feed-service 缓存: `FeedCache` 实现

---

**版本**: 1.0 (2025-11-06)
**作者**: Nova Architecture Team
**状态**: 待执行
