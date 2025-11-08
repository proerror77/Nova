# Phase 1B 完整实现计划 - gRPC 迁移和服务完善

**生成时间**: 2025-11-06
**分支**: feature/phase1-grpc-migration
**目标**: 完成所有未实现的 gRPC 方法和服务功能

---

## 📊 项目现状总览

### 完成度评估

| 服务 | 完成度 | 关键缺口 | 优先级 |
|------|--------|--------|--------|
| messaging-service | 60% | gRPC 方法、user_id 提取 | 🔴 P1 |
| notification-service | 15% | CRUD、Kafka 批处理 | 🔴 P1 |
| events-service | 5% | Outbox、事件发布 | 🔴 P1 |
| search-service | 10% | 全文/用户/建议搜索 | 🟡 P2 |
| feed-service | 50% | 推荐算法、缓存失效 | 🟡 P2 |
| streaming-service | 25% | HTTP路由、直播操作 | 🟡 P2 |
| cdn-service | 5% | URL生成、资产管理 | 🟢 P3 |

### 工作量估算

- **总工作量**: 290-330 小时
- **推荐周期**: 4-6 周 (取决于并行度)
- **关键路径**: events-service → notification-service → search-service → feed-service

---

## 🔴 Phase 1B 关键路径 (第一阶段 - 2 周)

### Week 1: 基础架构和 Events 系统

#### Task 1.1: 完善 Outbox 模式 (16h)
**目标**: 建立跨服务事件一致性基础

```rust
// backend/libs/event-schema/src/lib.rs - 扩展支持

1. 定义统一的 OutboxEvent 结构
   ├─ event_id: UUID
   ├─ aggregate_id: UUID
   ├─ event_type: String
   ├─ payload: serde_json::Value
   ├─ created_at: DateTime
   └─ published_at: Option<DateTime>

2. 扩展 Kafka 事件协议
   ├─ MessageCreated (messaging-service → notification/search)
   ├─ MessageEdited (消息编辑)
   ├─ MessageDeleted (消息删除)
   ├─ ReactionAdded (reactions 统一事件)
   ├─ FollowAdded (关注事件)
   └─ PostCreated/Updated/Deleted (内容变更)

3. 事件优先级和重试策略
   ├─ Priority enum: Critical/High/Normal/Low
   ├─ Retry 配置: max_retries, backoff_policy
   └─ TTL: 事件过期处理
```

**受影响文件**:
- `backend/libs/event-schema/src/lib.rs` (新增 Outbox 模型)
- `backend/libs/event-schema/src/events.rs` (事件定义)

**成功标准**:
- ✅ 所有 7 个服务共用一套事件协议
- ✅ 支持事件重放和幂等性
- ✅ 包含 500+ 行设计文档

---

#### Task 1.2: 实现 events-service 核心 (32h)
**目标**: 完成事件发布/订阅系统

```rust
// backend/events-service/src/grpc.rs (第 31-124 行)

实现 EventsService for EventsServiceImpl:

  1. PublishEvent (核心)
     ├─ 输入: event_type, payload, correlation_id
     ├─ 步骤:
     │  ├─ 验证 event_schema
     │  ├─ 保存到 PostgreSQL outbox 表
     │  ├─ 发布到 Kafka topic
     │  └─ 返回 event_id
     └─ 错误处理: Schema 验证失败, Kafka 发送失败

  2. SubscribeToEvents
     ├─ 输入: event_types (filter)
     ├─ 返回: stream of Event
     └─ 实现: 连接到 Kafka consumer group

  3. GetEventSchema
     ├─ 输入: event_type
     ├─ 返回: JSON Schema
     └─ 缓存: Redis TTL 1 小时

  4. GetOutboxStatus
     ├─ 列出未发布的 outbox 记录
     ├─ 用于监控和重试
     └─ 分页: limit=100, offset

  5. ReplayEvents (事件重放)
     ├─ 输入: from_timestamp, event_types
     ├─ 用于服务恢复
     └─ 验证: 仅允许管理员调用

实现 Outbox Publisher 后台任务:

  1. 定时扫描 PostgreSQL outbox 表
     ├─ 查询: published_at IS NULL
     ├─ 批量大小: 100 条
     └─ 扫描间隔: 1 秒

  2. 发布到 Kafka
     ├─ Topic: nova_events_{event_type}
     ├─ Key: aggregate_id (确保顺序)
     └─ 重试: exponential backoff, max 3 次

  3. 更新发布时间戳
     └─ 确保幂等性 (UPDATE ... WHERE published_at IS NULL)

实现 Kafka Schema Registry 集成:
  ├─ Avro 或 JSON Schema
  ├─ 模式版本控制
  └─ 向后兼容验证
```

**受影响文件**:
- `backend/events-service/src/grpc.rs` (gRPC 实现)
- `backend/events-service/src/services/mod.rs` (业务逻辑)
- `backend/events-service/src/services/outbox.rs` (新增 - Outbox 后台任务)
- `backend/events-service/src/db/migrations.sql` (events 和 outbox 表)

**数据库变更**:
```sql
-- 1. Outbox 表 (所有服务使用)
CREATE TABLE outbox_events (
    id UUID PRIMARY KEY,
    aggregate_id UUID NOT NULL,
    event_type VARCHAR(255) NOT NULL,
    payload JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    published_at TIMESTAMPTZ,
    retry_count INT DEFAULT 0,
    last_error TEXT,
    INDEX idx_unpublished (published_at, created_at)
);

-- 2. Event Schema 注册表
CREATE TABLE event_schemas (
    event_type VARCHAR(255) PRIMARY KEY,
    schema_version INT NOT NULL,
    schema_definition JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(event_type, schema_version)
);

-- 3. Kafka Topic 元数据
CREATE TABLE kafka_topics (
    topic_name VARCHAR(255) PRIMARY KEY,
    event_type VARCHAR(255) NOT NULL,
    partition_count INT DEFAULT 3,
    replication_factor INT DEFAULT 2,
    created_at TIMESTAMPTZ DEFAULT now()
);
```

**成功标准**:
- ✅ PublishEvent 延迟 < 100ms
- ✅ Outbox 发布成功率 > 99.99%
- ✅ 支持事件重放
- ✅ Kafka schema 版本控制正常工作

---

#### Task 1.3: 更新 messaging-service gRPC (24h)
**目标**: 提取 user_id 并完成消息基础操作

```rust
// backend/messaging-service/src/grpc/mod.rs (第 292 行、382-778 行)

问题 1: user_id 提取 (第 292 行)

当前:
  let request = request.into_inner();
  // user_id 未提取

解决:
  use tonic::metadata::MetadataMap;

  fn extract_user_id(metadata: &MetadataMap) -> Result<Uuid, Status> {
      metadata
          .get("x-user-id")
          .and_then(|v| v.to_str().ok())
          .and_then(|s| Uuid::parse_str(s).ok())
          .ok_or_else(|| Status::unauthenticated("Missing x-user-id"))
  }

  // 在每个 RPC 开始处调用:
  let user_id = extract_user_id(request.metadata())?;

问题 2: gRPC 方法实现

需要实现的核心方法 (按优先级):

【高优先级 - Week 1】
1. SendMessage
   ├─ 输入: recipient_id, content, attachment_ids
   ├─ 步骤:
   │  ├─ 验证 recipient 存在
   │  ├─ 检查是否被阻止
   │  ├─ 保存到 conversations 和 messages 表
   │  ├─ 发布 MessageCreated 事件
   │  └─ 返回 message_id
   └─ 错误: recipient_not_found, blocked, rate_limited

2. GetConversation
   ├─ 输入: conversation_id, limit=50, offset=0
   ├─ 返回: 分页消息列表
   ├─ 缓存: Redis, TTL 5 分钟
   └─ 排序: created_at DESC

3. ListConversations
   ├─ 输入: user_id, limit=20, offset=0
   ├─ 返回: 用户的所有对话
   └─ 排序: last_message_at DESC (最近优先)

【中优先级 - Week 1-2】
4. EditMessage
   ├─ 验证: 仅原作者可编辑
   ├─ 时间限制: 编辑时间 < 24 小时
   ├─ 发布: MessageEdited 事件
   └─ 返回: 更新后的消息

5. DeleteMessage
   ├─ 验证: 仅原作者或管理员
   ├─ 发布: MessageDeleted 事件
   └─ 软删除: is_deleted flag

6. AddReaction
   ├─ 输入: message_id, emoji
   ├─ 验证: emoji 在允许列表
   ├─ 发布: ReactionAdded 事件
   └─ 统一事件流处理

【低优先级 - Week 2】
7. GetReactions
8. RemoveReaction
9. MarkAsRead
10. CreateGroup
11. AddGroupMember
12. RemoveGroupMember

其他未实现的 gRPC 方法:
├─ GetMessageHistory (已部分实现)
├─ GetMessageById
├─ SearchMessages
├─ SetTypingIndicator
├─ GetTypingIndicators
├─ SetReadReceipt
├─ GetUnreadCount
├─ CreateConversation
├─ UpdateConversation
├─ DeleteConversation
├─ UploadAttachment
├─ GetAttachment
├─ DeleteAttachment
├─ GetE2EEncryptionKey
├─ RotateE2EEncryptionKey
├─ SetPushToken
├─ GetOfflineMessages
├─ AckOfflineMessage
└─ BroadcastMessage
```

**受影响文件**:
- `backend/messaging-service/src/grpc/mod.rs`
- `backend/messaging-service/src/services/message_service.rs` (新增)
- `backend/messaging-service/src/db/queries.rs` (SQL 查询)

**成功标准**:
- ✅ 所有消息 CRUD 操作完成
- ✅ 事件发布成功
- ✅ user_id 正确提取
- ✅ 响应延迟 < 200ms (P95)

---

### Week 2: Notification 和 Search 系统

#### Task 2.1: 实现 notification-service (24h)
**目标**: 完成通知的 CRUD 和 Kafka 消费

```rust
// backend/notification-service/src/grpc.rs (第 31-125 行)

实现 NotificationService:

【核心 CRUD 操作】
1. CreateNotification
   ├─ 输入: user_id, title, body, type, data
   ├─ 保存到 notifications 表
   ├─ 获取用户的 FCM/APNs tokens
   ├─ 立即发送推送
   └─ 返回: notification_id

2. GetNotification
   ├─ 输入: notification_id
   ├─ 验证: 仅用户自己可读
   └─ 返回: notification 详情

3. ListNotifications
   ├─ 输入: user_id, limit=50, offset=0
   ├─ 过滤: is_read (boolean)
   ├─ 排序: created_at DESC
   └─ 返回: 分页列表

4. MarkAsRead
   ├─ 输入: notification_id
   ├─ 更新: is_read = true, read_at = now()
   └─ 发布: NotificationRead 事件

5. MarkAllAsRead
   ├─ 输入: user_id
   ├─ 批量更新
   └─ 返回: 更新数量

6. DeleteNotification
   ├─ 软删除: is_deleted = true
   └─ 保留历史记录

【推送令牌管理】
7. RegisterPushToken
   ├─ 输入: user_id, token, type(FCM/APNs), device_id
   ├─ 保存到 push_tokens 表
   ├─ 验证令牌有效性
   └─ 返回: token_id

8. UnregisterPushToken
   ├─ 输入: token
   └─ 删除令牌

【统计和分析】
9. GetNotificationStats
   ├─ 输入: user_id, date_range
   ├─ 返回:
   │  ├─ total_count
   │  ├─ read_count
   │  ├─ unread_count
   │  ├─ delivery_success_rate
   │  └─ by_type (breakdown)
   └─ 缓存: Redis, TTL 1 小时

【Kafka 消费实现】
在 src/services/kafka_consumer.rs (第 101-107 行):

1. 订阅事件 Kafka topics
   ├─ MessageCreated → 创建 mention 通知
   ├─ FollowAdded → 创建 follow 通知
   ├─ CommentCreated → 创建 reply 通知
   ├─ PostLiked → 创建 like 通知
   └─ ReplyLiked → 创建 reply_like 通知

2. 批处理逻辑
   ├─ 缓冲大小: 100 条通知
   ├─ 刷新间隔: 5 秒
   ├─ 实现:
   │  ├─ 收集事件到内存 buffer
   │  ├─ 触发条件: size >= 100 OR elapsed >= 5s
   │  ├─ 批量插入 PostgreSQL
   │  ├─ 获取受影响用户的推送令牌
   │  ├─ 批量发送到 FCM/APNs
   │  └─ 更新发送状态
   └─ 重试: 失败重试 3 次

3. 去重逻辑
   ├─ 同一用户相同事件在 1 分钟内合并
   ├─ 使用 Redis: user_id:event_type:timestamp
   └─ TTL: 2 分钟

4. 优先级处理
   ├─ Critical: 直播开始、紧急提醒 (立即发送)
   ├─ High: 新消息、评论 (5 秒内)
   └─ Normal: 赞、关注 (15 秒内)

【监控和错误处理】
5. 推送失败处理
   ├─ FCM 4xx 错误: 删除无效令牌
   ├─ FCM 5xx 错误: 重试
   ├─ APNs 失败: 记录日志, 稍后重试
   └─ 记录: push_delivery_logs 表
```

**受影响文件**:
- `backend/notification-service/src/grpc.rs`
- `backend/notification-service/src/services/kafka_consumer.rs`
- `backend/notification-service/src/services/push_sender.rs` (新增)
- `backend/notification-service/src/db/migrations.sql`

**数据库变更**:
```sql
CREATE TABLE notifications (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL,
    title VARCHAR(255) NOT NULL,
    body TEXT,
    notification_type VARCHAR(50) NOT NULL,
    data JSONB,
    is_read BOOLEAN DEFAULT FALSE,
    read_at TIMESTAMPTZ,
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT now(),
    INDEX idx_user_unread (user_id, is_read)
);

CREATE TABLE push_tokens (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL,
    token VARCHAR(1000) NOT NULL,
    token_type ENUM('FCM', 'APNs') NOT NULL,
    device_id VARCHAR(255),
    is_valid BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id, token, token_type)
);

CREATE TABLE push_delivery_logs (
    id UUID PRIMARY KEY,
    notification_id UUID NOT NULL,
    token_id UUID NOT NULL,
    status ENUM('pending', 'success', 'failed') NOT NULL,
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    INDEX idx_notification (notification_id)
);
```

**成功标准**:
- ✅ Kafka 消费延迟 < 10 秒
- ✅ 推送发送成功率 > 99%
- ✅ 批处理吞吐量 > 1000 通知/秒
- ✅ 无重复通知

---

#### Task 2.2: 实现 search-service (20h)
**目标**: 完成全文搜索和用户发现功能

```rust
// backend/search-service/src/grpc.rs (第 25-88 行)

实现 SearchService:

【全文搜索】
1. FullTextSearch
   ├─ 输入: query, type(all|posts|users), limit=20, offset=0
   ├─ 搜索: Elasticsearch
   │  ├─ Posts: title, content, tags
   │  ├─ Users: username, display_name, bio
   │  ├─ Comments: content
   │  └─ Boost: 新鲜度、热度、相关性
   ├─ 排序: _score, created_at DESC
   └─ 返回: SearchResult[]

2. SearchPosts
   ├─ 输入: query, filters (hashtags, author_id, date_range), limit=50
   ├─ Elasticsearch 查询
   ├─ 过滤: 已发布、非隐藏、用户未被阻止
   └─ 返回: post_id, title, excerpt, author, likes_count

3. SearchUsers
   ├─ 输入: query, filters (location, interests), limit=20
   ├─ Elasticsearch 查询
   ├─ 过滤: 公开账户、不是私密关注
   └─ 返回: user_id, username, avatar_url, is_following

【搜索建议和自动完成】
4. GetSearchSuggestions
   ├─ 输入: prefix (最少 2 个字符)
   ├─ 缓存: Redis sorted set
   │  ├─ Key: search_suggestions:{prefix}
   │  ├─ Score: 热搜排名
   │  ├─ TTL: 24 小时
   │  └─ 大小限制: top 100
   ├─ 返回: 10 条建议
   └─ 格式: [{ text, type(post|user|hashtag), popularity }]

5. GetTrendingSearches
   ├─ 输入: time_range (1h|24h|7d), limit=20
   ├─ 数据来源: ClickHouse (搜索分析表)
   │  ├─ 聚合: count(searches) by query
   │  ├─ 去重: 同一用户相同查询在 5 分钟内计数 1 次
   │  └─ 过滤: 垃圾查询
   ├─ 缓存: Redis, TTL 1 小时
   └─ 返回: [{ query, search_count, trend }]

【热搜和标签】
6. GetTrendingHashtags
   ├─ 输入: limit=20, country (optional)
   ├─ 数据来源: ClickHouse
   │  ├─ 时间范围: 过去 24 小时
   │  ├─ 聚合: count(uses) by hashtag
   │  └─ 排序: 使用量 > 增长率
   ├─ 缓存: Redis, TTL 1 小时
   └─ 返回: [{ hashtag, usage_count, trend_score }]

【搜索分析】
7. LogSearchEvent (异步)
   ├─ 输入: user_id, query, results_count, clicked_result (optional)
   ├─ 发送到 Kafka: search_events topic
   ├─ 最终写入: ClickHouse (search_analytics 表)
   └─ 字段:
      ├─ timestamp
      ├─ user_id
      ├─ query
      ├─ results_count
      ├─ clicked_type (post|user|hashtag|none)
      ├─ clicked_id
      └─ session_id

8. GetSearchAnalytics (仅管理员)
   ├─ 输入: date_range, limit_queries=100
   ├─ 返回:
   │  ├─ total_searches
   │  ├─ unique_users
   │  ├─ avg_results_count
   │  ├─ click_through_rate
   │  ├─ top_queries [query, count, ctr]
   │  ├─ zero_results_queries
   │  └─ trending_up [query, previous_rank, current_rank]
   └─ 数据来源: ClickHouse

【索引维护】
9. RebuildSearchIndex (仅管理员)
   ├─ 后台任务
   ├─ 重建 Elasticsearch 索引
   ├─ 步骤:
   │  ├─ 创建新索引
   │  ├─ 从 PostgreSQL 全量读取
   │  ├─ 批量写入 Elasticsearch
   │  ├─ 删除旧索引
   │  └─ 更新别名
   └─ 时间: 凌晨 2-4 点

10. SyncSearchIndex (增量同步)
    ├─ Kafka 消费: content_changes topic
    ├─ 事件: PostCreated, PostEdited, PostDeleted, UserUpdated
    ├─ 延迟: < 5 秒
    └─ 重试: exponential backoff, max 3 次

【错误处理和降级】
- Elasticsearch 不可用:
  ├─ 缓存 Elasticsearch 响应 (Redis)
  ├─ TTL: 24 小时
  └─ 返回缓存结果
- 搜索超时: 返回 partial results
```

**受影响文件**:
- `backend/search-service/src/grpc.rs`
- `backend/search-service/src/services/elasticsearch.rs` (新增)
- `backend/search-service/src/services/clickhouse.rs` (新增)
- `backend/search-service/src/db/migrations.sql`

**Elasticsearch 索引定义**:
```json
{
  "posts_index": {
    "mappings": {
      "properties": {
        "id": { "type": "keyword" },
        "title": { "type": "text", "analyzer": "standard", "boost": 2 },
        "content": { "type": "text", "analyzer": "standard" },
        "author_id": { "type": "keyword" },
        "tags": { "type": "keyword" },
        "created_at": { "type": "date" },
        "likes_count": { "type": "integer" },
        "comments_count": { "type": "integer" }
      }
    }
  }
}
```

**ClickHouse 表定义**:
```sql
CREATE TABLE search_analytics (
    timestamp DateTime,
    user_id UUID,
    query String,
    results_count UInt32,
    clicked_type Enum('post', 'user', 'hashtag', 'none'),
    clicked_id Nullable(UUID),
    session_id UUID
) ENGINE = MergeTree()
ORDER BY (timestamp, user_id);
```

**成功标准**:
- ✅ 搜索延迟 < 500ms (P95)
- ✅ 索引最新性 < 5 秒
- ✅ 搜索精度 > 95%
- ✅ 支持 10k+ 并发搜索

---

## 🟡 Phase 1B 可选优化 (第二阶段 - Week 3-4)

### Task 3.1: 完成 feed-service 推荐算法 (24h)

```rust
// backend/feed-service/src/services/recommendation_v2/

需要完成的模块:

1. collaborative_filtering.rs (第 83 行)
   ├─ UserCollaborativeFilter trait
   ├─ 输入: user_id, user_history, k=50
   ├─ 算法:
   │  ├─ 1. 计算用户相似度 (cosine similarity)
   │  ├─ 2. 找到 k 个最相似用户
   │  ├─ 3. 推荐他们喜欢但当前用户没看过的内容
   │  └─ 4. 按评分排序
   ├─ 数据来源: PostgreSQL user_interactions 表
   ├─ 缓存: Redis, TTL 6 小时
   └─ 返回: Vec<(post_id, score)>

2. content_based.rs (第 49, 67 行)
   ├─ ContentBasedFilter trait
   ├─ 特征提取:
   │  ├─ Post 特征: category, tags, sentiment, freshness
   │  ├─ User 特征: interests, preferences, reading_level
   │  └─ 交叉: category_affinity, tag_affinity
   ├─ 相似度计算: cosine similarity on features
   ├─ 缓存: Redis, TTL 3 小时
   └─ 返回: Vec<(post_id, score)>

3. onnx_serving.rs (第 81 行)
   ├─ ONNX 推理引擎初始化
   ├─ 步骤:
   │  ├─ 下载 ONNX 模型 (s3://models/feed-ranking-v2.onnx)
   │  ├─ 初始化 ONNX Runtime
   │  ├─ 加载 feature scaler (标准化参数)
   │  └─ 预热缓存
   ├─ 输入特征:
   │  ├─ user_engagement_features (10 维)
   │  ├─ post_features (15 维)
   │  └─ context_features (5 维)
   ├─ 输出: ranking_score (0-1)
   └─ 吞吐量: > 10k predictions/sec

4. ab_testing.rs (第 76, 135, 149, 157 行)
   ├─ 实验分配逻辑:
   │  ├─ hash(user_id) % 100 < experiment.traffic_allocation
   │  ├─ 返回: experiment_id, control_flag
   │  └─ 缓存: 用户实验分配 (Redis)
   ├─ 指标记录:
   │  ├─ engagement_duration
   │  ├─ click_count
   │  ├─ like_count
   │  ├─ share_count
   │  └─ completion_rate
   └─ 统计分析:
      ├─ A/B 对比 (t-test)
      ├─ 显著性判定 (p-value < 0.05)
      ├─ 改进幅度计算

5. hybrid_ranker.rs (第 192, 279 行)
   ├─ 混合排序器结合:
   │  ├─ collaborative_filtering 权重: 0.4
   │  ├─ content_based 权重: 0.3
   │  ├─ onnx_ranking 权重: 0.2
   │  └─ freshness_boost 权重: 0.1
   ├─ 最终排序:
   │  ├─ 去除已读内容
   │  ├─ 应用用户屏蔽名单
   │  ├─ 应用广告投放限制
   │  ├─ 应用多样性约束 (不超过 20% 同一作者)
   │  └─ 应用新鲜度衰减
   └─ 返回: top 100 posts

6. mod.rs (第 572, 577 行)
   ├─ Redis 缓存集成
   ├─ ClickHouse 写入
   │  ├─ 记录: user_id, recommended_posts, scores, experiment_id
   │  ├─ 用途: 离线分析和模型改进
   │  └─ 分区: by date
   └─ 监控:
      ├─ 推荐延迟 (目标 < 200ms)
      ├─ 缓存命中率 (目标 > 90%)
      └─ 多样性指标

【实验配置同步】
├─ Kafka 消费: experiments_config topic
├─ 实时更新实验配置
└─ 不需要服务重启
```

**受影响文件**:
- `backend/feed-service/src/services/recommendation_v2/collaborative_filtering.rs`
- `backend/feed-service/src/services/recommendation_v2/content_based.rs`
- `backend/feed-service/src/services/recommendation_v2/onnx_serving.rs`
- `backend/feed-service/src/services/recommendation_v2/ab_testing.rs`
- `backend/feed-service/src/services/recommendation_v2/hybrid_ranker.rs`
- `backend/feed-service/src/services/recommendation_v2/mod.rs`

**成功标准**:
- ✅ 推荐延迟 < 200ms (P95)
- ✅ 缓存命中率 > 90%
- ✅ ONNX 推理吞吐量 > 10k/sec
- ✅ A/B 测试统计显著性

---

### Task 3.2: 完成 streaming-service 直播功能 (20h)

```rust
// backend/streaming-service/src/grpc.rs (第 54-183 行)

实现 StreamingService:

【直播生命周期】
1. StartStream
   ├─ 输入: title, description, preview_image, is_private
   ├─ 步骤:
   │  ├─ 创建 stream record (status=starting)
   │  ├─ 生成 RTMP 推流 URL
   │  ├─ 生成 HLS 播放 URL
   │  ├─ 关联 Redis 直播状态
   │  └─ 发布 StreamStarted 事件
   ├─ 返回: stream_id, rtmp_url, hls_url
   └─ 验证: 仅认证用户, rate limit 10/天

2. EndStream
   ├─ 输入: stream_id
   ├─ 步骤:
   │  ├─ 更新 status = 'ended'
   │  ├─ 记录最终统计 (viewers, duration, likes)
   │  ├─ 生成回放 (HLS 存档)
   │  ├─ 通知所有观众
   │  └─ 发布 StreamEnded 事件
   └─ 返回: final_stats

3. GetStreamStatus
   ├─ 输入: stream_id
   ├─ 返回: {status, viewer_count, likes_count, comments_count}
   └─ 缓存: Redis, TTL 5 秒

【观众和交互】
4. JoinStream
   ├─ 输入: stream_id, user_id
   ├─ 步骤:
   │  ├─ 验证流在线
   │  ├─ 检查私密权限
   │  ├─ 记录观众 (Redis set)
   │  ├─ 发送 joined 消息给其他观众
   │  └─ 增加观看计数
   ├─ 返回: viewer_token (用于 WebSocket)
   └─ 权限: public/followers_only/invite_only

5. LeaveStream
   ├─ 从 Redis set 移除观众
   ├─ 广播 left 消息
   └─ 更新观众计数

6. GetStreamManifest
   ├─ 输入: stream_id
   ├─ 返回: HLS manifest (.m3u8)
   └─ 格式: #EXTM3U, #EXT-X-VERSION, #EXT-X-TARGETDURATION

7. GetStreamProfile
   ├─ 输入: stream_id, quality(auto|720p|480p|360p|240p)
   ├─ 返回: 对应质量的 HLS URL
   └─ 自适应: 根据带宽推荐

【直播消息】
8. SendStreamMessage (WebSocket 后端)
   ├─ 输入: stream_id, message, user_id
   ├─ 广播给: 所有连接的观众
   ├─ 限制: rate limit 1 msg/sec per user
   ├─ 记录: Redis 消息历史 (最近 100 条)
   └─ 过滤: 违禁内容、垃圾消息

9. GetStreamMessages
   ├─ 输入: stream_id, limit=50
   ├─ 返回: 最近消息列表
   └─ 缓存: Redis

【点赞和交互】
10. LikeStream
    ├─ 输入: stream_id
    ├─ 去重: 同一用户在 5 秒内只计数 1 次
    ├─ 实现: Redis bitmap (user_id as bit)
    └─ 更新计数: Redis INCR

11. GetStreamLikes
    ├─ 返回: 点赞总数
    └─ 缓存: Redis, TTL 2 秒

【分析和监控】
12. GetStreamAnalytics
    ├─ 输入: stream_id
    ├─ 返回:
    │  ├─ peak_viewers (最高并发)
    │  ├─ total_viewers (不重复观众数)
    │  ├─ avg_watch_duration (平均观看时长)
    │  ├─ like_count
    │  ├─ message_count
    │  ├─ engagement_rate
    │  └─ by_region (按地区分布)
    └─ 数据来源: ClickHouse

【技术需求】
- Nginx RTMP 模块: 负责 RTMP 推流和 HLS 转码
- Redis: 直播状态、观众列表、消息历史
- ClickHouse: 分析数据
- WebSocket: 实时消息和交互

【HTTP 路由】(第 200 行)
在 src/main.rs:
  ├─ GET /streams/{stream_id}/manifest.m3u8 → HLS manifest
  ├─ GET /streams/{stream_id}/video_{quality}_{segment}.ts → HLS 分段
  ├─ POST /rtmp/auth → 验证推流者身份
  └─ POST /api/streams/create → 创建直播
```

**受影响文件**:
- `backend/streaming-service/src/grpc.rs`
- `backend/streaming-service/src/main.rs` (HTTP 路由)
- `backend/streaming-service/src/services/streaming/repository.rs` (数据库操作)
- `backend/streaming-service/src/services/streaming/redis_counter.rs` (Redis 统计)

**Redis 数据结构**:
```
stream:{stream_id}:status → HSET (status, title, viewer_count)
stream:{stream_id}:viewers → SET (user_id1, user_id2, ...)
stream:{stream_id}:messages → LIST (message objects, max 100)
stream:{stream_id}:likes → BITMAP (user_id bits)
```

**成功标准**:
- ✅ 支持 10k+ 并发观众
- ✅ 消息延迟 < 1 秒
- ✅ HLS 转码延迟 < 10 秒
- ✅ 播放起动时间 < 3 秒

---

### Task 3.3: 完成 cdn-service (12h)

```rust
// backend/cdn-service/src/grpc.rs (第 25-104 行)

实现 CDNService:

【URL 生成和管理】
1. GenerateAssetUrl
   ├─ 输入: asset_id, quality, format(jpeg|webp|avif), expiry
   ├─ 步骤:
   │  ├─ 验证资产存在且为公开
   │  ├─ 生成签名 URL (SHA256 HMAC)
   │  ├─ 包含过期时间戳
   │  └─ 支持格式转换参数
   ├─ 返回: 公开 CDN URL
   └─ 示例: https://cdn.nova.app/image.jpeg?sig=xxx&expires=1730956800

2. GetAssetInfo
   ├─ 输入: asset_id
   ├─ 返回:
   │  ├─ size
   │  ├─ mime_type
   │  ├─ dimensions (if image)
   │  ├─ duration (if video)
   │  ├─ available_qualities
   │  ├─ uploaded_by
   │  └─ created_at
   └─ 缓存: Redis, TTL 24 小时

【资产管理】
3. UploadAsset (预签名 URL)
   ├─ 输入: content_type, size_bytes, metadata
   ├─ 步骤:
   │  ├─ 创建 asset record (status=pending)
   │  ├─ 生成预签名上传 URL (S3)
   │  ├─ 返回 upload 信息
   │  └─ 设置 webhook 处理上传完成
   ├─ 返回: upload_url, asset_id, expires_at
   └─ 权限: 仅认证用户

4. DeleteAsset
   ├─ 输入: asset_id
   ├─ 验证: 仅所有者或管理员
   ├─ 步骤:
   │  ├─ 删除 PostgreSQL 记录
   │  ├─ 删除 S3 对象
   │  ├─ 清除 CDN 缓存
   │  └─ 发布 AssetDeleted 事件
   └─ 返回: success

5. ListAssets
   ├─ 输入: user_id, limit=50, offset=0
   ├─ 返回: 用户的所有资产
   └─ 排序: created_at DESC

【缓存和优化】
6. InvalidateCacheForAsset
   ├─ 输入: asset_id
   ├─ 步骤:
   │  ├─ 调用 CDN API (Cloudflare/AWS CloudFront)
   │  ├─ 清除所有变体 (qualities)
   │  └─ 立即生效
   ├─ 返回: invalidation_id
   └─ 异步: 不阻塞请求

7. GetCacheStatus
   ├─ 返回: CDN 缓存统计
   │  ├─ total_cached_assets
   │  ├─ cache_size_gb
   │  ├─ hit_rate (今日)
   │  └─ bandwidth_saved
   └─ 缓存: Redis, TTL 1 小时

【性能和指标】
8. GetAssetMetrics
   ├─ 输入: asset_id, time_range(1h|24h|7d)
   ├─ 返回:
   │  ├─ bandwidth_usage_bytes
   │  ├─ download_count
   │  ├─ avg_latency_ms
   │  ├─ cache_hit_rate
   │  └─ top_regions
   └─ 数据来源: ClickHouse

9. GetCDNMetrics (仅管理员)
   ├─ 返回:
   │  ├─ total_bandwidth_gb
   │  ├─ total_requests
   │  ├─ cache_hit_rate
   │  ├─ peak_concurrent_downloads
   │  └─ cost_estimate
   └─ 时间粒度: hourly

【图像处理】
10. ProcessImage
    ├─ 输入: asset_id, transformations
    │  ├─ resize (width, height)
    │  ├─ crop (x, y, width, height)
    │  ├─ quality (1-100)
    │  ├─ format (jpeg|webp|avif)
    │  └─ filter (blur, grayscale, etc.)
    ├─ 处理: 在边缘节点进行 (Cloudflare Workers)
    ├─ 缓存: 处理结果
    └─ 返回: 新的 CDN URL

【可用性和高可用】
11. GetAssetStatus
    ├─ 检查资产在全球 CDN 节点的可用性
    ├─ 返回: 按地区的可用性状态
    └─ 用途: 诊断和监控

12. VerifyAssetIntegrity
    ├─ 输入: asset_id
    ├─ 验证: S3 和 CDN 数据一致性
    ├─ 步骤:
    │  ├─ 计算 S3 对象的 MD5
    │  ├─ 从多个 CDN 节点检查
    │  └─ 不一致时触发重新上传
    └─ 返回: integrity_status
```

**受影响文件**:
- `backend/cdn-service/src/grpc.rs`
- `backend/cdn-service/src/services/cdn_provider.rs` (新增)
- `backend/cdn-service/src/services/image_processor.rs` (新增)

**成功标准**:
- ✅ 生成 URL 延迟 < 50ms
- ✅ CDN 缓存命中率 > 95%
- ✅ 图像处理延迟 < 1 秒
- ✅ 支持全球 200+ 边缘节点

---

## 🟢 Phase 1B 集成和测试 (Week 4+)

### Task 4.1: 跨服务集成测试 (16h)

```rust
【测试矩阵】
1. messaging-service + notification-service
   ├─ 发送消息 → 触发 mention 通知
   ├─ 编辑消息 → 更新通知内容
   └─ 删除消息 → 删除相关通知

2. events-service + 所有服务
   ├─ 验证 Outbox 正确发布
   ├─ 验证 Kafka 消费成功
   └─ 验证幂等性 (重复消息)

3. search-service + content-service
   ├─ 创建内容 → 索引同步 (< 5 秒)
   ├─ 编辑内容 → 索引更新
   └─ 删除内容 → 索引移除

4. feed-service + recommendation engines
   ├─ 推荐精度 > 95%
   ├─ 多样性约束生效
   └─ A/B 测试统计

5. 端到端用户场景
   ├─ 用户注册 → 收到欢迎通知
   ├─ 用户发布 → 出现在 feed 和 search
   ├─ 用户互动 → 触发推荐和通知
   └─ 直播 → 实时消息和推荐
```

---

## 📝 依赖关系和顺序

```
Week 1:
  ├─ Task 1.1: Outbox 模式 (基础)
  │   └─ Task 1.2: events-service (阻塞点)
  │       ├─ Task 2.1: notification-service
  │       ├─ Task 2.2: search-service
  │       └─ Task 3.1: feed-service
  └─ Task 1.3: messaging-service (并行)

Week 2:
  ├─ Task 2.1: notification-service
  └─ Task 2.2: search-service

Week 3-4:
  ├─ Task 3.1: feed-service 推荐
  ├─ Task 3.2: streaming-service
  ├─ Task 3.3: cdn-service
  └─ Task 4.1: 集成测试
```

---

## ⚠️ 风险点和缓解

| 风险 | 概率 | 影响 | 缓解 |
|------|------|------|------|
| Kafka 延迟导致数据不一致 | 30% | 高 | Outbox 模式 + 重试逻辑 |
| 跨服务网络分区 | 20% | 中 | Circuit breaker + 本地缓存 |
| ONNX 模型精度问题 | 25% | 中 | A/B 测试 + 回退到基础算法 |
| PostgreSQL 性能瓶颈 | 15% | 高 | 索引优化 + 读副本 |
| CDN 边缘节点延迟 | 10% | 低 | 多 CDN 提供商 + 地理分布 |

---

## 📊 成功标准

### 功能完成
- ✅ 所有 7 个服务的关键路径完成
- ✅ 所有 gRPC 方法实现 (非 TODO)
- ✅ Outbox 和事件流生效

### 性能目标
- ✅ 平均延迟 < 200ms (P95 < 500ms)
- ✅ 吞吐量 > 5000 req/sec
- ✅ 可用性 > 99.9%

### 质量目标
- ✅ 单元测试覆盖率 > 85%
- ✅ 集成测试覆盖主要流程
- ✅ 无 P1 级别 bug
- ✅ 安全审计通过

---

## 📅 时间线

| 阶段 | 周期 | 关键交付 |
|------|------|---------|
| Phase 1B.1 | Week 1 | events-service, Outbox 模式 |
| Phase 1B.2 | Week 2 | notification, search 基础功能 |
| Phase 1B.3 | Week 3 | feed 推荐, streaming 直播 |
| Phase 1B.4 | Week 4+ | cdn, 集成测试, 性能优化 |

---

## 🚀 开始执行

优先级: **立即启动 Task 1.1 和 Task 1.2**

建议:
1. 分配 2-3 名工程师到 events-service (关键路径)
2. 并行启动 messaging-service 改进
3. Week 2 后期启动 notification 和 search
4. 每日同步进度, 及时识别阻塞点
