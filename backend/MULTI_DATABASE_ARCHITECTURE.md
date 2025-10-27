# Nova 多数据库架构设计方案

## 前言：Linus 式思考框架

在开始设计之前，让我先用我的方式问三个关键问题：

### 1. "这是真问题还是臆想出来的？"
**判断**：✅ **真问题**
- 5个独立数据库不是为了炫技，而是因为：
  - PostgreSQL 处理事务（ACID）
  - ClickHouse 处理海量分析（百亿级事件）
  - Elasticsearch 处理全文搜索（亿级文档）
  - Neo4j 处理社交图谱（千万节点复杂查询）
  - Milvus 处理向量搜索（深度学习推荐）
- 单一数据库无法同时满足这些场景的性能要求

### 2. "有更简单的方法吗？"
**答案**：❌ **没有**
- 简化方案会导致某个场景崩溃：
  - 用 PostgreSQL 做推荐算法？向量查询会拖垮数据库
  - 用 Elasticsearch 存事务数据？ACID 无法保证
  - 用 Neo4j 存所有数据？写入性能是灾难
- **但我们可以简化数据流**：
  - PostgreSQL 是唯一的真相源（Single Source of Truth）
  - 其他数据库都是"视图"（Materialized Views）
  - Kafka 是单一事件总线（不搞多个消息队列）

### 3. "会破坏什么吗？"
**风险点**：
- ⚠️ **最大风险**：数据一致性
  - PostgreSQL 写入成功，但 Elasticsearch 同步失败
  - Neo4j 关系图与 PostgreSQL 用户数据不同步
- **解决方案**：
  - PostgreSQL 为主（Master），其他为从（Slaves）
  - 所有写操作先写 PostgreSQL + Kafka，异步同步到其他库
  - 接受最终一致性（Eventual Consistency），但要有回滚机制

---

## 核心架构原则

### 数据流铁律
```text
        ┌─────────────┐
        │ PostgreSQL  │ ← 唯一真相源（Source of Truth）
        │  (Master)   │
        └──────┬──────┘
               │
               ├─────→ Kafka（事件总线）
               │
        ┌──────┴──────────────────────┐
        │                              │
        ▼                              ▼
 ┌─────────────┐              ┌──────────────┐
 │ ClickHouse  │              │ Elasticsearch│
 │  (Analytics)│              │   (Search)   │
 └─────────────┘              └──────────────┘
        │                              │
        │                              │
        ▼                              ▼
 ┌─────────────┐              ┌──────────────┐
 │   Milvus    │              │    Neo4j     │
 │  (Vectors)  │              │   (Graph)    │
 └─────────────┘              └──────────────┘
        │                              │
        └──────────────┬───────────────┘
                       ▼
                ┌──────────────┐
                │    Redis     │ ← Cache Layer
                │  (Cache)     │
                └──────────────┘
```

### 关键设计决策

| 决策 | 原因 | 权衡 |
|-----|------|------|
| PostgreSQL 为主 | ACID 保证，事务完整性 | 写入性能瓶颈（但可以接受） |
| Kafka 单一事件总线 | 统一数据流，避免复杂依赖 | 单点故障（需集群部署） |
| 最终一致性 | 性能优先，大部分场景能接受秒级延迟 | 读取可能看到旧数据（需业务侧兼容） |
| Redis 作为统一缓存 | 减轻数据库压力，加速读取 | 缓存失效需处理（TTL + 主动刷新） |

---

## 功能 1：实时通知系统

### 核心判断
✅ **值得做**：通知是社交平台的神经系统，必须实时且可靠。

### 关键洞察
- **数据结构**：通知是"事件 + 用户 + 状态"的三元组
- **复杂度**：去中心化推送（不走数据库查询，直接用 Kafka + WebSocket）
- **风险点**：通知丢失（需持久化到 PostgreSQL 作为兜底）

### 数据模型

#### 1.1 PostgreSQL（持久化存储）
```sql
-- 通知表（Source of Truth）
CREATE TABLE notifications (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id),
    type VARCHAR(50) NOT NULL, -- 'like', 'comment', 'follow', 'mention', 'message'
    actor_id BIGINT NOT NULL REFERENCES users(id), -- 谁触发的
    target_type VARCHAR(50), -- 'post', 'comment', 'user'
    target_id BIGINT,
    content JSONB, -- 额外数据 {"post_id": 123, "text": "..."}
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    read_at TIMESTAMPTZ
);

-- 索引（查询优化）
CREATE INDEX idx_notifications_user_unread ON notifications(user_id, is_read, created_at DESC);
CREATE INDEX idx_notifications_created ON notifications(created_at) WHERE NOT is_read;

-- 通知设置表（用户偏好）
CREATE TABLE notification_settings (
    user_id BIGINT PRIMARY KEY REFERENCES users(id),
    push_enabled BOOLEAN DEFAULT TRUE,
    email_enabled BOOLEAN DEFAULT TRUE,
    types_disabled TEXT[] DEFAULT '{}', -- ['like', 'follow']
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 设备推送 Token
CREATE TABLE push_tokens (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id),
    platform VARCHAR(20) NOT NULL, -- 'ios', 'android', 'web'
    token TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    last_used_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_push_tokens_user ON push_tokens(user_id);
```

#### 1.2 Redis（实时缓存）
```text
# 未读通知计数
notification:unread:{user_id} → 整数（TTL: 永久，主动更新）

# WebSocket 连接映射
ws:user:{user_id} → Set<connection_id>（TTL: 连接断开时删除）

# 推送 Token 缓存
push:tokens:{user_id} → List<token>（TTL: 1 小时）

# 最近通知快照（用户打开 App 时快速加载）
notification:recent:{user_id} → JSON 列表（TTL: 5 分钟）
```

#### 1.3 Kafka 事件流
```json
// Topic: notification.events
{
  "event_id": "uuid-v4",
  "type": "notification.created",
  "timestamp": 1704038400,
  "data": {
    "notification_id": 12345,
    "user_id": 67890,
    "type": "like",
    "actor_id": 11111,
    "target_type": "post",
    "target_id": 22222,
    "content": {
      "post_id": 22222,
      "actor_name": "Alice",
      "actor_avatar": "https://..."
    }
  }
}
```

#### 1.4 ClickHouse（分析统计）
```sql
-- 通知投递日志（用于分析推送效果）
CREATE TABLE notification_delivery_log (
    notification_id UInt64,
    user_id UInt64,
    type String,
    channel String, -- 'push', 'websocket', 'email'
    status String, -- 'sent', 'delivered', 'failed', 'opened'
    error_message String,
    created_at DateTime
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(created_at)
ORDER BY (user_id, created_at);
```

### 数据流架构

```text
用户 A 点赞用户 B 的帖子：

1. [API Server] 写入 PostgreSQL
   ↓
2. [API Server] 发送 Kafka 事件 "notification.created"
   ↓
3. [Notification Worker] 消费 Kafka
   ↓
   ├─→ [FCM/APNs] 发送推送通知（iOS/Android）
   │   └─→ [ClickHouse] 记录推送日志
   │
   ├─→ [WebSocket Server] 通过 Redis 查找用户 B 的活跃连接
   │   └─→ 实时推送通知（如果用户在线）
   │
   └─→ [Redis] 增加未读计数 notification:unread:67890
```

---

## 功能 2：私信系统

### 数据模型

#### 2.1 PostgreSQL（主存储）
```sql
-- 会话表（两人之间的聊天）
CREATE TABLE conversations (
    id BIGSERIAL PRIMARY KEY,
    participant1_id BIGINT NOT NULL REFERENCES users(id),
    participant2_id BIGINT NOT NULL REFERENCES users(id),
    last_message_id BIGINT,
    last_message_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT participants_order CHECK (participant1_id < participant2_id),
    UNIQUE(participant1_id, participant2_id)
);
CREATE INDEX idx_conversations_p1 ON conversations(participant1_id, last_message_at DESC);
CREATE INDEX idx_conversations_p2 ON conversations(participant2_id, last_message_at DESC);

-- 消息表（核心数据）
CREATE TABLE messages (
    id BIGSERIAL PRIMARY KEY,
    conversation_id BIGINT NOT NULL REFERENCES conversations(id),
    sender_id BIGINT NOT NULL REFERENCES users(id),
    content TEXT NOT NULL,
    message_type VARCHAR(20) DEFAULT 'text', -- 'text', 'image', 'video', 'file'
    metadata JSONB, -- {"file_url": "...", "thumbnail": "..."}
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_messages_conversation ON messages(conversation_id, created_at DESC);
CREATE INDEX idx_messages_sender ON messages(sender_id, created_at DESC);

-- 消息已读状态
CREATE TABLE message_read_status (
    user_id BIGINT NOT NULL REFERENCES users(id),
    conversation_id BIGINT NOT NULL REFERENCES conversations(id),
    last_read_message_id BIGINT NOT NULL,
    last_read_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, conversation_id)
);
```

#### 2.2 Elasticsearch（消息搜索）
```json
// Index: messages
{
  "mappings": {
    "properties": {
      "message_id": { "type": "long" },
      "conversation_id": { "type": "long" },
      "sender_id": { "type": "long" },
      "content": { "type": "text", "analyzer": "ik_max_word" },
      "message_type": { "type": "keyword" },
      "is_deleted": { "type": "boolean" },
      "created_at": { "type": "date" }
    }
  }
}
```

#### 2.3 Redis（实时状态）
```text
# 用户在线状态
user:online:{user_id} → "1"（TTL: 5 分钟，心跳刷新）

# 会话未读数
conversation:unread:{user_id}:{conversation_id} → 整数

# 正在输入状态
conversation:typing:{conversation_id} → Set<user_id>（TTL: 3 秒）

# 最近会话列表缓存
user:conversations:{user_id} → JSON 列表（TTL: 1 分钟）
```

---

## 功能 3：视频直播

### 数据模型

#### 3.1 PostgreSQL（元数据）
```sql
-- 直播流表
CREATE TABLE live_streams (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id),
    title VARCHAR(255) NOT NULL,
    description TEXT,
    thumbnail_url TEXT,
    rtmp_url TEXT NOT NULL, -- 推流地址
    hls_url TEXT, -- 播放地址
    status VARCHAR(20) DEFAULT 'preparing', -- 'preparing', 'live', 'ended'
    viewer_count INT DEFAULT 0,
    peak_viewer_count INT DEFAULT 0,
    started_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_live_streams_status ON live_streams(status, started_at DESC);
```

#### 3.2 Redis（实时状态）
```text
# 直播间在线观众集合
stream:viewers:{stream_id} → Set<user_id>

# 直播间观众数
stream:viewer_count:{stream_id} → 整数

# 直播间弹幕列表
stream:comments:{stream_id} → List<JSON>（LTRIM 保持 100 条）
```

---

## 功能 4：社交图谱优化

### 数据模型

#### 4.1 PostgreSQL（主存储）
```sql
-- 关注关系表（Source of Truth）
CREATE TABLE follows (
    id BIGSERIAL PRIMARY KEY,
    follower_id BIGINT NOT NULL REFERENCES users(id),
    followee_id BIGINT NOT NULL REFERENCES users(id),
    status VARCHAR(20) DEFAULT 'active', -- 'active', 'blocked', 'muted'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(follower_id, followee_id)
);
CREATE INDEX idx_follows_follower ON follows(follower_id, created_at DESC);
CREATE INDEX idx_follows_followee ON follows(followee_id, created_at DESC);

-- 用户统计表
CREATE TABLE user_stats (
    user_id BIGINT PRIMARY KEY REFERENCES users(id),
    follower_count INT DEFAULT 0,
    following_count INT DEFAULT 0,
    post_count INT DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

#### 4.2 Neo4j（图查询）
```cypher
-- 用户节点
CREATE (u:User {
  id: 12345,
  username: "alice",
  avatar_url: "https://...",
  bio: "Hello!",
  created_at: 1704038400
})

-- 关注关系
CREATE (u1:User {id: 111})-[:FOLLOWS {created_at: 1704038400}]->(u2:User {id: 222})

-- 关键查询：二度人脉（朋友的朋友）
MATCH (me:User {id: 111})-[:FOLLOWS]->(friend)-[:FOLLOWS]->(recommended)
WHERE NOT (me)-[:FOLLOWS]->(recommended) AND me <> recommended
RETURN recommended.id, recommended.username
ORDER BY COUNT(friend) DESC
LIMIT 20
```

#### 4.3 Redis（缓存）
```text
# 关注列表
user:following:{user_id} → Set<followee_id>

# 粉丝列表
user:followers:{user_id} → Set<follower_id>

# 推荐关注列表
user:recommended:{user_id} → List<user_id>（TTL: 1 小时）
```

---

## 功能 5：推荐算法 v2.0（完整示例）

### 完整架构图

```text
用户行为
  ↓
PostgreSQL (user_interactions)
  ↓
Kafka (user.behavior.events)
  ↓
┌─────────────┬──────────────┬──────────────┐
│ ClickHouse  │   Neo4j      │ Elasticsearch│
│ (analytics) │  (graph)     │   (search)   │
└─────────────┴──────────────┴──────────────┘
  ↓
PyTorch Training
  ↓
Milvus (256-dim embeddings)
  ↓
Redis (cached recommendations)
  ↓
API Response
```

### 5.1 PostgreSQL（用户行为）
```sql
CREATE TABLE user_interactions (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id),
    target_type VARCHAR(50) NOT NULL, -- 'post', 'user', 'tag'
    target_id BIGINT NOT NULL,
    interaction_type VARCHAR(50) NOT NULL, -- 'view', 'like', 'comment', 'share'
    interaction_value FLOAT, -- 权重
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_interactions_user ON user_interactions(user_id, created_at DESC);
```

### 5.2 ClickHouse（分析数据）
```sql
-- 用户行为事件流
CREATE TABLE user_behavior_events (
    user_id UInt64,
    target_type String,
    target_id UInt64,
    interaction_type String,
    interaction_value Float32,
    created_at DateTime
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(created_at)
ORDER BY (user_id, created_at);

-- 训练数据
CREATE TABLE ml_training_data (
    user_id UInt64,
    item_id UInt64,
    label Float32, -- 1=正样本，0=负样本
    features String, -- JSON
    date Date
) ENGINE = MergeTree()
PARTITION BY date
ORDER BY (user_id, date);
```

### 5.3 Milvus（向量搜索）
```python
# 用户 Embedding Collection
from pymilvus import Collection, FieldSchema, CollectionSchema, DataType

user_fields = [
    FieldSchema(name="user_id", dtype=DataType.INT64, is_primary=True),
    FieldSchema(name="embedding", dtype=DataType.FLOAT_VECTOR, dim=256),
    FieldSchema(name="model_version", dtype=DataType.VARCHAR, max_length=50),
    FieldSchema(name="updated_at", dtype=DataType.INT64)
]

user_schema = CollectionSchema(fields=user_fields, description="User embeddings")
user_collection = Collection(name="user_embeddings", schema=user_schema)

# 创建 HNSW 索引（快速 ANN 搜索）
index_params = {
    "metric_type": "COSINE",
    "index_type": "HNSW",
    "params": {"M": 16, "efConstruction": 200}
}
user_collection.create_index(field_name="embedding", index_params=index_params)
```

### 5.4 Redis（推荐缓存）
```text
# 用户推荐列表
recommendation:user:{user_id} → JSON 列表（TTL: 1 小时）
[
  {"item_id": 123, "score": 0.95},
  {"item_id": 456, "score": 0.89},
  ...
]

# 用户 Embedding 缓存
embedding:user:{user_id} → Binary（TTL: 6 小时）

# 热门推荐（冷启动）
recommendation:trending → JSON 列表（TTL: 10 分钟）
```

### 5.5 数据流

#### 离线训练（每日凌晨）
```text
1. Spark Job: ClickHouse → 训练数据
2. PyTorch: 训练 Two-Tower DNN
3. Embedding Export: 生成所有用户/内容向量
4. Milvus Bulk Insert: 批量导入向量
```

#### 在线推理（实时）
```text
1. Milvus: 查询用户向量（< 50ms）
2. Neo4j: 协同过滤（< 100ms）
3. Elasticsearch: 内容过滤（< 50ms）
4. Score Fusion: 融合多路召回
5. Redis: 缓存结果（TTL: 1 小时）
```

---

## 全局 Kafka 事件架构

### 核心 Topics

```text
1. user.events（用户行为）
   - 分区：16（按 user_id hash）
   - 保留期：7 天
   - 消费者：ClickHouse, Recommendation

2. notification.events（通知）
   - 分区：8
   - 保留期：3 天
   - 消费者：Push, WebSocket

3. message.events（私信）
   - 分区：16（按 conversation_id hash）
   - 保留期：30 天
   - 消费者：Elasticsearch, Archive

4. live.events（直播）
   - 分区：4
   - 保留期：1 天
   - 消费者：Analytics

5. social.events（关注）
   - 分区：8
   - 保留期：7 天
   - 消费者：Neo4j, Redis

6. recommendation.training（训练数据）
   - 分区：32
   - 保留期：90 天
   - 消费者：Spark, ClickHouse
```

---

## 实施清单（按依赖顺序）

### Phase 1: 基础设施（Week 1-2）
- [ ] 部署 Kafka 集群（3 节点 + Zookeeper）
- [ ] 部署 PostgreSQL 主从集群
- [ ] 部署 Redis 集群
- [ ] 配置 Kafka Connect CDC

### Phase 2: 数据库部署（Week 3-4）
- [ ] 部署 ClickHouse 集群
- [ ] 部署 Elasticsearch 集群
- [ ] 部署 Neo4j 集群
- [ ] 部署 Milvus 集群

### Phase 3: Schema 初始化（Week 5）
- [ ] 创建 PostgreSQL 所有表
- [ ] 创建 ClickHouse 表和 MV
- [ ] 配置 Elasticsearch 索引
- [ ] 初始化 Neo4j 索引

### Phase 4: 数据同步管道（Week 6-7）
- [ ] Kafka → ClickHouse Sink
- [ ] Kafka → Elasticsearch Sink
- [ ] Kafka → Neo4j Sync Worker
- [ ] PostgreSQL → Milvus ETL

### Phase 5: 业务功能（Week 8-12）
- [ ] 功能 1：实时通知
- [ ] 功能 2：私信系统
- [ ] 功能 3：视频直播
- [ ] 功能 4：社交图谱
- [ ] 功能 5：推荐算法

### Phase 6: 监控和测试（Week 13-14）
- [ ] Prometheus + Grafana 监控
- [ ] 数据一致性测试
- [ ] 性能压测（100 万 QPS）

### Phase 7: 上线（Week 15-16）
- [ ] 灰度发布（10% 流量）
- [ ] 全量上线
- [ ] 性能调优

---

## 性能目标

| 指标 | 目标 |
|-----|------|
| 推荐延迟 P95 | < 200ms |
| Milvus ANN P99 | < 50ms |
| 缓存命中率 | > 80% |
| 模型 AUC | > 0.85 |
| 用户 CTR | > 5% |

---

## 最后的话

这份架构设计遵循三个核心原则：

1. ✅ **解决真问题**：社交平台的核心痛点
2. ✅ **尽可能简化**：PostgreSQL 为主，其他为从
3. ✅ **向后兼容**：任何数据库故障都能降级

**Remember**: "Bad programmers worry about the code. Good programmers worry about data structures."
