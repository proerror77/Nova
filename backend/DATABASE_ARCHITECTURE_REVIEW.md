# Nova 数据库架构深度评估报告

**评估日期**: 2025-11-24
**评估范围**: 全部 12 个微服务 + 共享基础设施
**评估人**: Linus (Database Architect)
**严重性**: 🔴 **P0 - 生产环境风险**

---

## 执行摘要 (Executive Summary)

### 核心发现

Nova 的数据库架构处于 **"微服务拆分未完成"** 的危险状态：

1. **数据所有权混乱** - 159 个全局 migrations vs 服务独立 migrations
2. **重复 schema 定义** - `likes`/`comments`/`shares` 在 3 个地方重复创建
3. **跨服务强依赖** - PostgreSQL 外键引用跨服务边界
4. **技术选型不一致** - 同一数据在 PostgreSQL + ClickHouse + Neo4j 中重复存储
5. **迁移策略缺失** - 120+ pending migrations 未应用，未知生产状态

**影响**: 数据一致性风险、无法独立部署服务、扩展性瓶颈

---

## 1. 数据库技术栈分布

### 1.1 已使用技术

| 数据库类型 | 用途 | 服务 | 评估 |
|-----------|------|------|------|
| **PostgreSQL** | OLTP 主存储 | 所有服务 (12个) | ✅ 正确选型 |
| **Redis** | 缓存 + Session | 所有服务 (12个) | ✅ 正确使用 |
| **ClickHouse** | OLAP 分析 | analytics-service, feed-service, search-service | ⚠️ 部分重复 |
| **Neo4j** | 图关系 | graph-service | ❌ **未实际使用** |
| **Elasticsearch** | 全文搜索 | search-service | ✅ 正确选型 |

### 1.2 技术选型问题

#### ❌ **Neo4j 问题**
- **现状**: `graph-service` 声明使用 Neo4j，但实际只有 migration 脚本，无运行时代码
- **问题**:
  - 社交关系存储在 PostgreSQL `user_relationships` 表
  - Neo4j 仅在 `migrations/migrate_follows_to_neo4j.rs` 中被引用（迁移工具）
  - 生产环境未部署 Neo4j 实例
- **建议**:
  - **短期**: 删除 graph-service，合并到 social-service
  - **长期**: 如需图算法（推荐/发现），考虑 PostgreSQL + pgvector 或 ClickHouse

#### ⚠️ **ClickHouse 重复**
- **问题**:
  - `feed-service` 和 `analytics-service` 都有独立 ClickHouse schema
  - CDC 数据（posts/likes/comments）在两处重复定义
  - `feature-store` 也有独立 ClickHouse schema（`features` 表）
- **建议**:
  - 统一 ClickHouse schema 到 `analytics-service`
  - 其他服务通过 gRPC 调用 analytics-service 获取分析数据

---

## 2. 服务级数据库架构分析

### 2.1 Identity Service (认证服务)

**数据库**: PostgreSQL
**Schema 文件**: `identity-service/migrations/001_create_identity_tables.sql`

#### 表结构
```
users                     ✅ 核心用户表 (email, password_hash, 认证状态)
sessions                  ✅ 活跃会话
refresh_tokens            ✅ JWT refresh tokens
password_reset_tokens     ✅ 密码重置
email_verification_tokens ✅ 邮箱验证
security_audit_log        ✅ 安全审计
outbox_events             ✅ Transactional Outbox
invite_codes              ✅ 邀请码
user_channels             ⚠️ Channel 订阅 (应该在 content-service)
```

#### 架构问题
1. **❌ 数据边界泄漏**: `user_channels` 表引用 content-service 的 `channel_id`，违反服务边界
2. **✅ 好设计**: Outbox pattern 正确实现，所有 token 表都有过期机制
3. **⚠️ Session 冗余**: `sessions` 表存储大量设备元数据（device_id, os_name, browser_name），应拆分到 `devices` 表

**推荐改进**:
```sql
-- 移除跨服务引用
DROP TABLE user_channels;  -- 移动到 content-service

-- 设备表独立
CREATE TABLE devices (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES users(id),
  device_id VARCHAR(255) UNIQUE,
  device_name VARCHAR(255),
  device_type VARCHAR(100),
  last_seen_at TIMESTAMPTZ
);

ALTER TABLE sessions DROP COLUMN device_name, DROP COLUMN device_type, ...;
ALTER TABLE sessions ADD COLUMN device_id UUID REFERENCES devices(id);
```

---

### 2.2 Content Service (内容服务)

**数据库**: PostgreSQL
**Schema 文件**: `content-service/migrations/20241107_create_content_tables.sql`

#### 表结构
```
posts         ✅ 帖子主表 (content, media_key, user_id)
comments      ✅ 评论 (post_id, user_id, content)
likes         ❌ 重复定义 (也在 social-service)
bookmarks     ❌ 重复定义 (也在 social-service)
shares        ❌ 重复定义 (也在 social-service)
```

#### 架构问题
1. **❌ 致命问题**: `likes`/`bookmarks`/`shares` 表与 social-service 完全重复
   - **当前状态**: 两个服务都有独立的 `likes` 表
   - **风险**: 数据不一致、双写问题
   - **影响**: 点赞数据可能分散在两个数据库

2. **❌ 外键缺失**: `posts.user_id` 没有外键约束，无法保证引用完整性

**推荐改进**:
```sql
-- ❌ 删除重复表 (保留在 social-service)
DROP TABLE likes;
DROP TABLE bookmarks;
DROP TABLE shares;

-- ✅ 仅保留内容核心表
-- posts 和 comments 归 content-service 所有
```

---

### 2.3 Social Service (社交服务)

**数据库**: PostgreSQL
**Schema 文件**: `social-service/migrations/002_create_social_tables.sql`

#### 表结构
```
likes               ✅ 点赞 (post_id, user_id, UNIQUE约束)
shares              ✅ 分享 (post_id, user_id, share_type)
comments            ❌ 重复定义 (也在 content-service)
comment_likes       ✅ 评论点赞
post_counters       ✅ 帖子计数缓存 (like_count, comment_count)
processed_events    ✅ 幂等消费者
```

#### 架构问题
1. **❌ Comments 冲突**:
   - content-service 有 `comments` 表
   - social-service 也有 `comments` 表（带 like_count/reply_count 列）
   - **决策**: Comments 应该在 content-service，social-service 通过事件同步计数

2. **✅ 好设计**:
   - 触发器自动维护 `post_counters` (increment/decrement)
   - `processed_events` 防止重复处理
   - `UNIQUE (post_id, user_id)` 防止重复点赞

3. **⚠️ 性能风险**:
   - 触发器在每次 INSERT/DELETE 时更新计数器
   - 高并发下可能导致锁竞争
   - 建议：异步更新 + Redis 缓存

**推荐改进**:
```sql
-- ❌ 删除 comments 表 (归 content-service 所有)
DROP TABLE comments CASCADE;
DROP TABLE comment_likes;  -- 或移动到 content-service

-- ✅ 保留社交互动表
-- likes, shares, post_counters 归 social-service 所有

-- ⚠️ 考虑异步计数器更新
-- 选项 1: 移除触发器，通过 Kafka 事件异步更新
-- 选项 2: 使用 PostgreSQL LISTEN/NOTIFY + 后台 worker
```

---

### 2.4 Realtime Chat Service (实时聊天)

**数据库**: PostgreSQL
**Schema 文件**: `realtime-chat-service/migrations/0004_create_messages.sql`

#### 表结构
```
conversations           ✅ 会话 (type: direct/group/channel)
conversation_members    ✅ 会话成员
messages                ✅ 消息 (加密存储)
message_reactions       ✅ 消息表情
message_attachments     ✅ 附件
message_recalls         ✅ 消息撤回
```

#### 架构问题
1. **✅ 好设计**:
   - 端到端加密 (`content_encrypted`, `content_nonce`)
   - `idempotency_key` 防止重复消息
   - `sequence_number` 保证消息顺序

2. **❌ 缺失索引**:
   - `messages.conversation_id` 无复合索引
   - 高频查询 `WHERE conversation_id = ? ORDER BY sequence_number DESC LIMIT 50` 效率低

3. **⚠️ 软删除不一致**:
   - `messages.deleted_at` 使用 TIMESTAMPTZ
   - 其他服务使用 `is_deleted BOOLEAN`

**推荐改进**:
```sql
-- ✅ 添加性能关键索引
CREATE INDEX idx_messages_conversation_seq
  ON messages(conversation_id, sequence_number DESC)
  WHERE deleted_at IS NULL;

-- ✅ 分区优化 (按时间分区，历史消息归档)
CREATE TABLE messages_2025_01 PARTITION OF messages
  FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');
```

---

### 2.5 Notification Service (通知服务)

**数据库**: PostgreSQL
**Schema 文件**: `notification-service/migrations/001_initial_schema.sql`

#### 表结构
```
notifications             ✅ 通知主表
push_tokens               ✅ 推送 token (FCM/APNs)
push_delivery_logs        ✅ 推送投递日志
notification_preferences  ✅ 用户通知偏好
notification_dedup        ✅ 1分钟去重窗口
```

#### 架构问题
1. **✅ 好设计**:
   - `notification_dedup` 防止通知轰炸
   - `push_delivery_logs` 追踪投递状态
   - `priority` 和 `status` 枚举值清晰

2. **⚠️ 索引不足**:
   - `notifications(user_id, is_read, created_at)` 需要复合索引
   - `push_tokens` 缺少 `(user_id, is_valid, last_used_at)` 索引

3. **⚠️ 数据保留策略缺失**:
   - `push_delivery_logs` 会无限增长
   - `notification_dedup` 虽然有 TTL，但依赖手动清理

**推荐改进**:
```sql
-- ✅ 添加复合索引
CREATE INDEX idx_notifications_user_read_time
  ON notifications(user_id, is_read, created_at DESC);

-- ✅ 数据保留策略
-- 选项 1: TimescaleDB 自动分区 + retention
SELECT add_retention_policy('push_delivery_logs', INTERVAL '30 days');

-- 选项 2: PostgreSQL 原生分区 + cron job
CREATE TABLE push_delivery_logs_old PARTITION OF push_delivery_logs
  FOR VALUES FROM (MINVALUE) TO ('2025-01-01');
```

---

### 2.6 Feed Service (推荐服务)

**数据库**: PostgreSQL + ClickHouse
**Schema 文件**: `feed-service/migrations/20241107_create_experiment_tables.sql`

#### 表结构 (PostgreSQL)
```
experiments              ✅ A/B 实验配置
experiment_assignments   ✅ 用户实验分组
experiment_metrics       ✅ 实验指标
```

#### 表结构 (ClickHouse)
```
feed_candidates_followees  ✅ 关注用户候选
feed_candidates_trending   ✅ 热门内容候选
feed_candidates_affinity   ✅ 兴趣亲和度候选
posts_cdc                  ⚠️ 与 analytics-service 重复
likes_cdc                  ⚠️ 与 analytics-service 重复
comments_cdc               ⚠️ 与 analytics-service 重复
```

#### 架构问题
1. **❌ ClickHouse Schema 重复**:
   - `posts_cdc`, `likes_cdc`, `comments_cdc` 在 `analytics-service` 和 `feed-service` 都有
   - CDC 数据应该集中管理

2. **✅ 好设计**:
   - `feed_candidates_*` 预计算推荐候选
   - `ReplacingMergeTree` 支持 upsert
   - 按月分区 (`PARTITION BY toYYYYMM`)

3. **⚠️ 实验表设计问题**:
   - `experiment_metrics.metric_value NUMERIC` 太宽泛
   - 应该拆分为多列（impression_count, click_count, dwell_time）

**推荐改进**:
```sql
-- ❌ 删除重复的 CDC 表 (统一到 analytics-service)
DROP TABLE posts_cdc;
DROP TABLE likes_cdc;
DROP TABLE comments_cdc;

-- ✅ Feed 服务通过 gRPC 调用 analytics-service 获取数据
-- 或者通过 Kafka 订阅 CDC 事件
```

---

### 2.7 Analytics Service (分析服务)

**数据库**: ClickHouse
**Schema 文件**: `analytics-service/migrations/001_create_outbox_tables.sql`

#### 表结构 (ClickHouse)
```
outbox_events         ⚠️ 为什么在 ClickHouse？
event_schemas         ⚠️ 应该在 PostgreSQL
kafka_topics          ⚠️ 应该在 PostgreSQL
domain_events         ✅ 事件溯源存储
event_subscriptions   ⚠️ 应该在 PostgreSQL
```

#### 架构问题
1. **❌ 致命错误**:
   - Outbox pattern 的 `outbox_events` 表放在 ClickHouse
   - **问题**: ClickHouse 不支持事务性写入，无法保证 exactly-once
   - **正确做法**: Outbox 表必须在 PostgreSQL

2. **❌ 配置表放错位置**:
   - `event_schemas`, `kafka_topics`, `event_subscriptions` 是配置数据
   - ClickHouse 不适合频繁更新的配置数据
   - 应该在 PostgreSQL

3. **✅ domain_events 正确**:
   - 事件溯源历史适合 ClickHouse
   - `sequence_number` 保证全局顺序

**推荐改进**:
```sql
-- ❌ 将配置表移动到 PostgreSQL
-- 在 analytics-service 的 PostgreSQL 数据库中创建:
CREATE TABLE event_schemas (...);
CREATE TABLE kafka_topics (...);
CREATE TABLE event_subscriptions (...);

-- ❌ Outbox 表移动到 PostgreSQL
-- 使用 PostgreSQL LISTEN/NOTIFY 或 Debezium CDC

-- ✅ ClickHouse 仅保留只读分析表
-- domain_events, posts_cdc, likes_cdc 等
```

---

### 2.8 Search Service (搜索服务)

**数据库**: PostgreSQL + Elasticsearch + ClickHouse
**Schema 文件**: `search-service/migrations/002_create_search_tables.sql`

#### 表结构 (PostgreSQL)
```
search_event_logs    ⚠️ 应该在 ClickHouse
search_suggestions   ✅ 自动完成缓存
trending_queries     ✅ 热搜缓存
```

#### 架构问题
1. **❌ 日志表放错位置**:
   - `search_event_logs` 是高频写入的日志数据
   - PostgreSQL 不适合此场景
   - 应该直接写入 ClickHouse

2. **✅ 缓存表设计正确**:
   - `search_suggestions` 预计算自动完成
   - `trending_queries` 缓存热搜（避免频繁查询 ClickHouse）

3. **❌ 索引语法错误**:
   ```sql
   CREATE TABLE search_event_logs (
     ...
     INDEX idx_search_user (user_id),  -- ❌ 错误：PostgreSQL 不支持表内 INDEX
   ```

**推荐改进**:
```sql
-- ❌ 删除 PostgreSQL 日志表
DROP TABLE search_event_logs;

-- ✅ 直接写入 ClickHouse
CREATE TABLE search_event_logs (
  event_id UUID,
  user_id String,
  query String,
  results_count UInt32,
  clicked_type String,
  clicked_id String,
  session_id String,
  event_time DateTime DEFAULT now()
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (user_id, event_time)
TTL event_time + INTERVAL 90 DAY;

-- ✅ 修复索引语法
CREATE INDEX idx_suggestions_prefix ON search_suggestions(query_prefix);
```

---

### 2.9 Trust & Safety Service (信任与安全)

**数据库**: PostgreSQL
**Schema 文件**: `trust-safety-service/migrations/001_create_moderation_logs.sql`

#### 表结构
```
moderation_logs  ✅ 审核日志
appeals          ✅ 申诉记录
```

#### 架构问题
1. **✅ 设计简洁**:
   - `moderation_logs` 存储审核决策
   - `violations TEXT[]` 使用 PostgreSQL 数组

2. **⚠️ 缺失关键功能**:
   - 无 `content_hashes` 表（去重检测）
   - 无 `banned_users` 表（封禁管理）
   - 无 `auto_mod_rules` 表（规则引擎）

3. **⚠️ 日志膨胀风险**:
   - `moderation_logs` 会无限增长
   - 需要数据保留策略

**推荐改进**:
```sql
-- ✅ 添加内容哈希表 (检测重复违规内容)
CREATE TABLE content_hashes (
  hash_value BYTEA PRIMARY KEY,
  first_seen_at TIMESTAMPTZ NOT NULL,
  violation_count INT DEFAULT 0,
  is_blocked BOOLEAN DEFAULT FALSE
);

-- ✅ 添加封禁管理
CREATE TABLE banned_users (
  user_id UUID PRIMARY KEY,
  banned_at TIMESTAMPTZ NOT NULL,
  banned_until TIMESTAMPTZ,
  reason TEXT NOT NULL,
  banned_by UUID  -- 操作者
);

-- ✅ 数据保留策略 (保留 1 年)
CREATE TABLE moderation_logs_old PARTITION OF moderation_logs
  FOR VALUES FROM (MINVALUE) TO ('2024-01-01');
```

---

### 2.10 User Service (用户服务)

**数据库**: PostgreSQL
**Schema 文件**: `user-service/migrations/052_user_core_tables.sql`

#### 表结构
```
user_profiles       ✅ 用户资料 (display_name, bio, avatar_url)
user_settings       ✅ 用户设置
user_relationships  ✅ 关注关系 (follower_id, followee_id)
```

#### 架构问题
1. **❌ 数据所有权冲突**:
   - `user_profiles.id` 引用 `users(id)` 外键
   - `users` 表在 `identity-service`
   - **问题**: 跨服务外键依赖

2. **❌ 关注关系重复**:
   - `user_relationships` 存储在 user-service
   - `follows_cdc` 存储在 ClickHouse (analytics-service)
   - graph-service 声称要使用 Neo4j (但未实现)

3. **⚠️ user_profiles 设计问题**:
   - `follower_count`, `following_count`, `post_count` 冗余字段
   - 应该通过事件异步更新，或通过 API 聚合查询

**推荐改进**:
```sql
-- ❌ 移除跨服务外键
ALTER TABLE user_profiles DROP CONSTRAINT fk_user_profiles_user;

-- ✅ 使用逻辑外键 (通过事件验证)
-- identity-service 在创建用户时发送 UserCreated 事件
-- user-service 监听事件，创建对应的 user_profiles 记录

-- ⚠️ 计数器异步更新
-- 移除 follower_count, following_count, post_count 列
-- 通过 Redis 缓存 + 事件同步
```

---

### 2.11 Media Service (媒体服务)

**数据库**: 无独立 schema
**依赖**: Redis (缓存), ClickHouse (访问日志)

#### 架构问题
1. **❌ 缺失元数据表**:
   - 媒体文件元数据存储在哪里？
   - S3 路径、文件大小、MIME 类型、访问权限
   - 当前可能通过 content-service 的 `posts.media_key` 引用

2. **⚠️ 无上传状态追踪**:
   - 分片上传、断点续传需要状态表

**推荐设计**:
```sql
-- ✅ 创建 media-service 独立 schema
CREATE TABLE media_objects (
  id UUID PRIMARY KEY,
  owner_id UUID NOT NULL,  -- 逻辑外键到 identity-service
  storage_key TEXT NOT NULL,  -- S3 key
  mime_type VARCHAR(100) NOT NULL,
  file_size BIGINT NOT NULL,
  width INT,
  height INT,
  duration INT,  -- 视频时长(秒)
  upload_status VARCHAR(20) NOT NULL,  -- pending/processing/completed/failed
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE upload_sessions (
  id UUID PRIMARY KEY,
  media_id UUID REFERENCES media_objects(id),
  chunk_size INT NOT NULL,
  total_chunks INT NOT NULL,
  uploaded_chunks INT[] DEFAULT '{}',
  expires_at TIMESTAMPTZ NOT NULL
);
```

---

### 2.12 Ranking Service (排序服务)

**数据库**: 无独立 schema
**依赖**: Redis (特征缓存), feed-service (候选集)

#### 架构问题
1. **❌ 无独立数据存储**:
   - Ranking 模型参数存储在哪里？
   - A/B 测试模型版本如何管理？

2. **⚠️ 特征存储混乱**:
   - `feature-store` 有独立 ClickHouse schema
   - ranking-service 应该使用 feature-store

**推荐设计**:
```sql
-- ✅ 创建 ranking-service 配置表
CREATE TABLE ranking_models (
  id UUID PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  version VARCHAR(20) NOT NULL,
  model_type VARCHAR(50) NOT NULL,  -- lr/xgboost/dnn
  parameters JSONB NOT NULL,
  is_active BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (name, version)
);

CREATE TABLE ranking_features (
  feature_name VARCHAR(100) PRIMARY KEY,
  feature_type VARCHAR(20) NOT NULL,  -- user/post/context
  source_service VARCHAR(50) NOT NULL,  -- feed/analytics/social
  cache_ttl_seconds INT NOT NULL
);
```

---

## 3. 全局架构问题

### 3.1 数据所有权混乱

#### 问题：单体遗留 migrations

**发现**:
- `/Users/proerror/Documents/nova/backend/migrations/` 包含 120+ 全局 migrations
- 创建了 159 个表 (根据 `grep CREATE TABLE` 统计)
- 服务独立 migrations 与全局 migrations 冲突

**示例**:
```
migrations/001_initial_schema.sql      → 创建 users, sessions, refresh_tokens
identity-service/migrations/001_...    → 也创建 users, sessions, refresh_tokens

migrations/100_social_service_schema.sql  → 创建 likes, shares, comments
social-service/migrations/002_...         → 也创建 likes, shares, comments
```

**影响**:
- 无法确定哪个 migration 是 "source of truth"
- 生产环境可能运行了全局 migrations，服务独立 migrations 会失败
- 数据所有权不清晰

**解决方案**:
```bash
# ❌ 错误做法：同时保留两套 migrations
# ✅ 正确做法：

# 1. 确定生产环境已应用哪些 migrations
psql -h prod-db -c "SELECT * FROM schema_migrations ORDER BY version;"

# 2. 废弃全局 migrations
mv migrations/ migrations_deprecated/
echo "这些 migrations 已废弃，请使用服务独立 migrations" > migrations_deprecated/README.md

# 3. 每个服务创建完整的 schema baseline
# identity-service/migrations/000_baseline.sql
-- 此文件反映生产环境当前状态
CREATE TABLE IF NOT EXISTS users (...);
...

# 4. 后续新 migrations 基于 baseline 增量修改
# identity-service/migrations/001_add_totp.sql
ALTER TABLE users ADD COLUMN totp_secret VARCHAR(255);
```

---

### 3.2 表重复定义 (Data Duplication)

#### 重复创建的表

| 表名 | 创建次数 | 位置 | 问题 |
|------|---------|------|------|
| **likes** | 3次 | content-service, social-service, migrations/ | ❌ 数据分散 |
| **comments** | 3次 | content-service, social-service, migrations/ | ❌ 数据分散 |
| **shares** | 3次 | content-service, social-service, migrations/ | ❌ 数据分散 |
| **outbox_events** | 2次 | identity-service, analytics-service | ⚠️ 合理 (各自独立) |
| **search_suggestions** | 2次 | search-service, user-service | ❌ 冗余 |

#### 决策：谁拥有这些表？

```
✅ 正确分配：

content-service OWNS:
  - posts
  - comments (包括 comment_likes)

social-service OWNS:
  - likes
  - shares
  - bookmarks
  - post_counters

user-service OWNS:
  - user_profiles
  - user_settings

identity-service OWNS:
  - users (仅认证字段)
  - sessions
  - refresh_tokens
```

---

### 3.3 跨服务外键 (Cross-Service Foreign Keys)

#### 问题：强耦合依赖

**发现**:
```sql
-- user-service/migrations/052_user_core_tables.sql
CREATE TABLE user_profiles (
  id UUID PRIMARY KEY,
  ...
  CONSTRAINT fk_user_profiles_user FOREIGN KEY (id)
    REFERENCES users(id) ON DELETE CASCADE  -- ❌ users 在 identity-service!
);

-- realtime-chat-service/migrations/0004_create_messages.sql
CREATE TABLE messages (
  ...
  sender_id UUID REFERENCES users(id) ON DELETE CASCADE,  -- ❌ 跨服务外键
);
```

**影响**:
- user-service 无法独立部署（依赖 identity-service 的 users 表）
- 跨服务级联删除风险（DELETE user → CASCADE 删除 profiles）
- 数据库扩展性差（无法分库）

**解决方案**:
```sql
-- ❌ 删除物理外键
ALTER TABLE user_profiles DROP CONSTRAINT fk_user_profiles_user;

-- ✅ 使用逻辑外键 + 事件驱动
-- identity-service 在删除用户时发送 UserDeleted 事件
-- user-service 监听事件，删除对应的 user_profiles

-- ✅ 或者通过 API 验证
-- user-service 在创建 profile 前，调用 identity-service API 验证 user_id 存在
```

---

### 3.4 数据一致性风险

#### 问题：多处写入同一逻辑数据

**示例 1: Posts CDC**
```
content-service 写入 PostgreSQL posts 表
  ↓ (CDC)
ClickHouse posts_cdc (analytics-service)
  ↓ (读取)
feed-service 的 ClickHouse posts_cdc (重复?)
```

**示例 2: User Relationships**
```
user-service 写入 user_relationships (PostgreSQL)
graph-service 写入 Neo4j (未实现)
ClickHouse follows_cdc (analytics-service)
```

**影响**:
- 数据不一致风险
- 不清楚哪个是 "source of truth"

**解决方案**:
```
✅ Single Source of Truth 原则：

1. PostgreSQL = OLTP 写入源
   content-service writes to posts (PostgreSQL)

2. CDC → ClickHouse = OLAP 只读副本
   Debezium CDC → Kafka → ClickHouse posts_cdc

3. 其他服务只读 ClickHouse
   feed-service reads from ClickHouse (不维护自己的 posts_cdc)
```

---

### 3.5 ClickHouse Schema 分散

#### 问题：3 个地方定义 ClickHouse schema

| 位置 | 文件 | 内容 |
|------|------|------|
| **clickhouse/** | `init-db.sql` | posts_cdc, likes_cdc, comments_cdc, feed_candidates_* |
| **feature-store/** | `002_clickhouse_schema.sql` | features, feature_embeddings |
| **analytics-service/** | `001_create_outbox_tables.sql` | outbox_events (❌ 错误) |

**影响**:
- 无法确定 ClickHouse 的完整 schema
- 部署时不知道执行哪个 SQL 文件
- 缺乏版本控制

**解决方案**:
```bash
# ✅ 统一 ClickHouse schema 到一个位置
backend/
  clickhouse/
    migrations/
      001_cdc_tables.sql          # posts_cdc, likes_cdc, comments_cdc
      002_feed_candidates.sql     # feed_candidates_*
      003_feature_store.sql       # features, feature_embeddings
      004_analytics_events.sql    # domain_events

    README.md  # 说明每个 migration 的用途

# ✅ 使用 ClickHouse migration 工具
# 选项 1: clickhouse-migrations (Go)
# 选项 2: Flyway (支持 ClickHouse)
```

---

### 3.6 软删除不一致 (Soft Delete Inconsistency)

#### 问题：3 种不同的软删除实现

| 服务 | 实现 | 类型 |
|------|------|------|
| content-service | `deleted_at TIMESTAMPTZ` | ✅ 推荐 |
| social-service | `is_deleted BOOLEAN` | ⚠️ 可接受 |
| realtime-chat-service | `deleted_at TIMESTAMPTZ` | ✅ 推荐 |
| identity-service | `deleted_at TIMESTAMPTZ` | ✅ 推荐 |

**影响**:
- 查询不一致 (`WHERE deleted_at IS NULL` vs `WHERE is_deleted = FALSE`)
- 无法记录删除时间（`is_deleted` 方案）

**推荐标准**:
```sql
-- ✅ 统一使用 deleted_at
ALTER TABLE xxx ADD COLUMN deleted_at TIMESTAMPTZ;
CREATE INDEX idx_xxx_active ON xxx(id) WHERE deleted_at IS NULL;

-- ✅ 如果需要记录删除者
ALTER TABLE xxx ADD COLUMN deleted_by UUID;

-- ✅ 如果需要软删除原因
ALTER TABLE xxx ADD COLUMN deletion_reason TEXT;
```

---

## 4. 性能问题

### 4.1 缺失关键索引

#### content-service
```sql
-- ❌ 缺失索引
posts 表没有 (user_id, created_at DESC) 复合索引
  → 查询 "用户最近帖子" 效率低

-- ✅ 推荐
CREATE INDEX idx_posts_user_time ON posts(user_id, created_at DESC)
  WHERE deleted_at IS NULL;
```

#### social-service
```sql
-- ❌ 缺失索引
likes 表只有 (post_id) 和 (user_id) 单列索引
  → 查询 "某帖子的点赞列表" 需要排序

-- ✅ 推荐
CREATE INDEX idx_likes_post_time ON likes(post_id, created_at DESC);
```

#### notification-service
```sql
-- ❌ 缺失索引
notifications 缺少 (user_id, is_read, created_at) 三列索引
  → 查询 "未读通知列表" 效率低

-- ✅ 推荐
CREATE INDEX idx_notifications_user_unread
  ON notifications(user_id, created_at DESC)
  WHERE is_read = FALSE AND is_deleted = FALSE;
```

---

### 4.2 触发器性能风险

#### social-service 计数器触发器

**问题**:
```sql
-- 每次点赞都触发同步更新
CREATE TRIGGER trigger_increment_like_count
AFTER INSERT ON likes
FOR EACH ROW EXECUTE FUNCTION increment_like_count();

-- 高并发下导致锁竞争
-- 100个用户同时点赞同一帖子 → 100次 UPDATE post_counters
```

**解决方案**:
```sql
-- ✅ 选项 1: 异步更新 (推荐)
-- 1. 写入 likes 表
-- 2. 发送 Kafka 事件 LikeCreated
-- 3. Counter Updater 服务消费事件，批量更新 post_counters

-- ✅ 选项 2: 使用 Redis 缓存
-- 1. 点赞时 INCR redis_key
-- 2. 每 10 秒同步到 PostgreSQL post_counters

-- ✅ 选项 3: 使用 materialized view
CREATE MATERIALIZED VIEW post_counters AS
SELECT
  post_id,
  COUNT(*) AS like_count
FROM likes
WHERE created_at > NOW() - INTERVAL '90 days'
GROUP BY post_id;

-- 定时刷新 (每分钟)
REFRESH MATERIALIZED VIEW post_counters;
```

---

### 4.3 N+1 查询风险

#### 示例：获取帖子列表 + 作者信息

**当前设计**:
```rust
// ❌ N+1 查询
let posts = db.query("SELECT * FROM posts LIMIT 10").await?;
for post in posts {
  let user = db.query("SELECT * FROM users WHERE id = ?", post.user_id).await?;  // 10次查询!
}
```

**推荐**:
```sql
-- ✅ 单次 JOIN 查询
SELECT
  p.*,
  u.username,
  u.avatar_url
FROM posts p
LEFT JOIN users u ON u.id = p.user_id
WHERE p.deleted_at IS NULL
ORDER BY p.created_at DESC
LIMIT 10;

-- 但这是跨服务查询！正确做法：

-- ✅ 方案 1: user-service 提供批量查询 API
let user_ids: Vec<Uuid> = posts.iter().map(|p| p.user_id).collect();
let users = user_service_client.batch_get_users(user_ids).await?;

-- ✅ 方案 2: user_profiles 数据通过事件同步到 content-service
CREATE TABLE user_profiles_cache (
  user_id UUID PRIMARY KEY,
  username VARCHAR(50),
  avatar_url TEXT,
  updated_at TIMESTAMPTZ
);

-- content-service 监听 UserUpdated 事件，更新缓存
```

---

## 5. 推荐的数据架构

### 5.1 数据所有权 (Data Ownership)

```
┌─────────────────────────────────────────────────────────────┐
│                   Service Data Ownership                    │
└─────────────────────────────────────────────────────────────┘

identity-service (PostgreSQL):
  ✅ users (仅认证字段: email, password_hash, is_active)
  ✅ sessions, refresh_tokens
  ✅ security_audit_log
  ✅ outbox_events

user-service (PostgreSQL):
  ✅ user_profiles (display_name, bio, avatar_url)
  ✅ user_settings
  ✅ user_relationships (关注关系)

content-service (PostgreSQL):
  ✅ posts
  ✅ comments (包括 comment_likes)

social-service (PostgreSQL):
  ✅ likes
  ✅ shares
  ✅ bookmarks
  ✅ post_counters (缓存表)

notification-service (PostgreSQL):
  ✅ notifications
  ✅ push_tokens
  ✅ notification_preferences

realtime-chat-service (PostgreSQL):
  ✅ conversations
  ✅ messages (加密)

feed-service (PostgreSQL):
  ✅ experiments (A/B 测试配置)
  ✅ experiment_assignments

search-service (PostgreSQL):
  ✅ search_suggestions
  ✅ trending_queries

trust-safety-service (PostgreSQL):
  ✅ moderation_logs
  ✅ content_hashes
  ✅ banned_users

media-service (PostgreSQL):
  ✅ media_objects (新增)
  ✅ upload_sessions (新增)

analytics-service (ClickHouse):
  ✅ domain_events (事件溯源)
  ✅ posts_cdc, likes_cdc, comments_cdc (CDC 只读副本)
  ✅ feed_candidates_* (预计算推荐)

feature-store (ClickHouse):
  ✅ features, feature_embeddings

ranking-service (PostgreSQL):
  ✅ ranking_models (新增)
  ✅ ranking_features (新增)
```

---

### 5.2 数据流架构

```
┌──────────────────────────────────────────────────────────────────┐
│                      Data Flow Architecture                       │
└──────────────────────────────────────────────────────────────────┘

OLTP Write Path (事务性写入):
  User Action
    ↓
  Service (PostgreSQL)
    ↓ (atomic)
  [Business Table + outbox_events]
    ↓
  Outbox Publisher (每秒轮询)
    ↓
  Kafka Topic (nova-events-*)
    ↓
  Consumer Services (其他服务订阅)

OLAP Sync Path (分析同步):
  PostgreSQL (OLTP)
    ↓ (Debezium CDC)
  Kafka (CDC stream)
    ↓ (Kafka Connect)
  ClickHouse (OLAP)
    ↓ (materialized views)
  Pre-computed Aggregations

Cache Path (缓存层):
  Service Query
    ↓
  Redis (L1 cache, TTL 60s)
    ↓ (miss)
  PostgreSQL (L2 source)
    ↓
  Write-back to Redis
```

---

### 5.3 技术栈选型建议

| 用途 | 推荐技术 | 替代方案 | 不推荐 |
|------|---------|---------|--------|
| **OLTP** | PostgreSQL 14+ | CockroachDB (多区域) | ❌ MySQL (缺少 JSONB, CTE) |
| **缓存** | Redis 7.0+ | Valkey | ❌ Memcached (无数据结构) |
| **OLAP** | ClickHouse 23+ | Apache Druid | ❌ PostgreSQL (不适合) |
| **全文搜索** | Elasticsearch 8+ | Meilisearch | ❌ PostgreSQL `ts_vector` |
| **图关系** | PostgreSQL + pgvector | Neo4j (大规模时) | ❌ 当前未实现 |
| **时序数据** | ClickHouse | TimescaleDB | ❌ PostgreSQL 原生 |
| **消息队列** | Kafka | Redpanda | ❌ RabbitMQ (无 CDC) |
| **CDC** | Debezium | pg_logical | ❌ 手写 trigger |

---

## 6. 迁移路线图 (Migration Roadmap)

### Phase 1: 紧急修复 (1-2 周)

#### P0 Blockers
```sql
-- 1. 移除跨服务外键
ALTER TABLE user_profiles DROP CONSTRAINT fk_user_profiles_user;
ALTER TABLE messages DROP CONSTRAINT IF EXISTS fk_messages_sender;

-- 2. 修复 analytics-service outbox 错误
-- 将 outbox_events 从 ClickHouse 移动到 PostgreSQL

-- 3. 删除重复表定义
-- 在 content-service 中:
DROP TABLE likes;
DROP TABLE shares;
DROP TABLE bookmarks;
```

#### P1 High Priority
```sql
-- 4. 添加缺失的关键索引
CREATE INDEX idx_posts_user_time ON posts(user_id, created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_likes_post_time ON likes(post_id, created_at DESC);
CREATE INDEX idx_notifications_user_unread ON notifications(user_id, created_at DESC) WHERE is_read = FALSE;

-- 5. 统一软删除策略
-- 所有表改为使用 deleted_at TIMESTAMPTZ
```

---

### Phase 2: 架构清理 (2-4 周)

#### 服务边界明确
```bash
# 1. 废弃全局 migrations
mv migrations/ migrations_deprecated/

# 2. 每个服务创建 baseline migration
# identity-service/migrations/000_baseline.sql
# 反映生产环境当前状态

# 3. 删除 graph-service (未使用 Neo4j)
rm -rf graph-service/

# 4. 合并重复的 ClickHouse schema
mv clickhouse/init-db.sql clickhouse/migrations/001_cdc_tables.sql
mv feature-store/migrations/002_clickhouse_schema.sql clickhouse/migrations/003_feature_store.sql
```

#### 数据所有权转移
```sql
-- 5. 将 user_channels 从 identity-service 移动到 content-service
-- Step 1: content-service 创建表
CREATE TABLE user_channels (...);

-- Step 2: 数据迁移
INSERT INTO content_service.user_channels
SELECT * FROM identity_service.user_channels;

-- Step 3: 验证数据一致性
SELECT COUNT(*) FROM identity_service.user_channels;
SELECT COUNT(*) FROM content_service.user_channels;

-- Step 4: 删除旧表
DROP TABLE identity_service.user_channels;
```

---

### Phase 3: 性能优化 (4-6 周)

#### 异步计数器
```rust
// 1. 移除 social-service 的同步触发器
DROP TRIGGER trigger_increment_like_count ON likes;

// 2. 实现 Counter Updater 服务
// counter-updater/src/main.rs
#[tokio::main]
async fn main() {
    let consumer = KafkaConsumer::new("nova-events-social");

    loop {
        let events = consumer.poll().await?;

        // 批量更新计数器
        for batch in events.chunks(100) {
            update_counters_batch(batch).await?;
        }
    }
}
```

#### CDC Pipeline
```bash
# 3. 部署 Debezium CDC
docker run -d \
  --name debezium \
  -e BOOTSTRAP_SERVERS=kafka:9092 \
  -e GROUP_ID=1 \
  -e CONFIG_STORAGE_TOPIC=debezium_configs \
  debezium/connect:2.4

# 4. 配置 PostgreSQL → Kafka → ClickHouse
curl -X POST http://debezium:8083/connectors \
  -H "Content-Type: application/json" \
  -d @connectors/postgres-cdc.json
```

---

### Phase 4: 扩展性改进 (长期)

#### 多租户支持
```sql
-- 如果未来需要多租户隔离
ALTER TABLE posts ADD COLUMN tenant_id UUID;
CREATE INDEX idx_posts_tenant ON posts(tenant_id, created_at DESC);
```

#### 分库分表
```sql
-- 如果数据量超过单库容量 (1TB+)
-- 选项 1: Citus (PostgreSQL 扩展)
SELECT create_distributed_table('posts', 'user_id');

-- 选项 2: CockroachDB (原生分布式)
-- 选项 3: 应用层分片 (按 user_id % 8)
```

---

## 7. 监控与告警

### 7.1 数据库健康监控

```yaml
# Prometheus metrics
postgres_up{service="identity-service"}
postgres_connections_active{service="identity-service"}
postgres_replication_lag_seconds
postgres_deadlocks_total
postgres_table_bloat_bytes{table="posts"}

# ClickHouse metrics
clickhouse_query_duration_seconds{query_type="feed_candidates"}
clickhouse_disk_usage_percent
clickhouse_part_count{table="posts_cdc"}

# Redis metrics
redis_connected_clients
redis_memory_used_bytes
redis_evicted_keys_total
```

### 7.2 推荐告警规则

```yaml
# 1. 连接池耗尽
- alert: PostgreSQLConnectionPoolExhausted
  expr: postgres_connections_active / postgres_max_connections > 0.8
  for: 5m
  annotations:
    summary: "PostgreSQL connection pool usage > 80%"

# 2. 复制延迟
- alert: PostgreSQLReplicationLag
  expr: postgres_replication_lag_seconds > 60
  for: 2m
  annotations:
    summary: "PostgreSQL replication lag > 1 minute"

# 3. 慢查询
- alert: SlowQueryDetected
  expr: postgres_query_duration_seconds{quantile="0.99"} > 5
  for: 10m
  annotations:
    summary: "P99 query latency > 5 seconds"

# 4. ClickHouse 分区膨胀
- alert: ClickHousePartCountHigh
  expr: clickhouse_part_count > 1000
  for: 1h
  annotations:
    summary: "ClickHouse table has >1000 parts, needs OPTIMIZE"
```

---

## 8. 总结与行动项

### 8.1 关键问题总结

| 问题 | 严重性 | 影响 | 优先级 |
|------|--------|------|--------|
| 跨服务外键依赖 | 🔴 P0 | 无法独立部署 | 立即修复 |
| 表重复定义 (likes/comments) | 🔴 P0 | 数据一致性风险 | 1 周内 |
| Analytics outbox 在 ClickHouse | 🔴 P0 | 无法保证事务性 | 1 周内 |
| 全局 migrations 冲突 | 🟡 P1 | 部署混乱 | 2 周内 |
| ClickHouse schema 分散 | 🟡 P1 | 维护困难 | 2 周内 |
| 缺失关键索引 | 🟡 P1 | 性能问题 | 2 周内 |
| 触发器性能风险 | 🟢 P2 | 高并发瓶颈 | 1 月内 |
| 软删除不一致 | 🟢 P2 | 查询不统一 | 1 月内 |
| Neo4j 未实现 | 🟢 P3 | 资源浪费 | 2 月内 |

---

### 8.2 立即行动项 (This Week)

```bash
# 1. 修复 P0 问题
cd /Users/proerror/Documents/nova/backend

# 删除跨服务外键
psql -f scripts/remove_cross_service_fks.sql

# 删除重复表
psql -f scripts/remove_duplicate_tables.sql

# 2. 添加缺失索引
psql -f scripts/add_critical_indexes.sql

# 3. 创建 baseline migrations
for service in identity-service user-service content-service social-service; do
  cd $service/migrations
  pg_dump --schema-only > 000_baseline.sql
done
```

---

### 8.3 长期改进建议

1. **统一 schema migration 工具**
   - 当前：手动执行 SQL 文件
   - 推荐：Flyway 或 Liquibase (支持版本控制、回滚、跨环境)

2. **实施 CDC Pipeline**
   - 当前：手动同步 PostgreSQL → ClickHouse
   - 推荐：Debezium + Kafka Connect (自动 CDC)

3. **服务网格化查询**
   - 当前：服务间直接 PostgreSQL 跨库查询
   - 推荐：gRPC API 调用 + 数据缓存

4. **引入 CQRS 模式**
   - 当前：读写混合在同一 PostgreSQL
   - 推荐：写入 PostgreSQL，读取从 ClickHouse/Redis

5. **数据保留策略**
   - 当前：无自动清理
   - 推荐：PostgreSQL 分区 + TTL，ClickHouse TTL

---

## 附录 A: 数据库连接字符串规范

```bash
# ✅ 正确格式 (每个服务独立数据库)
DATABASE_URL=postgresql://nova_identity:password@postgres:5432/identity_db?sslmode=require
DATABASE_URL=postgresql://nova_content:password@postgres:5432/content_db?sslmode=require

# ❌ 错误格式 (所有服务共享同一数据库)
DATABASE_URL=postgresql://nova:password@postgres:5432/nova?sslmode=require
```

---

## 附录 B: 推荐工具链

| 工具 | 用途 | 链接 |
|------|------|------|
| **pgAdmin 4** | PostgreSQL GUI 管理 | https://www.pgadmin.org/ |
| **DBeaver** | 多数据库 GUI (PostgreSQL + ClickHouse) | https://dbeaver.io/ |
| **Flyway** | Schema migration 工具 | https://flywaydb.org/ |
| **Debezium** | CDC 平台 | https://debezium.io/ |
| **pg_stat_statements** | PostgreSQL 慢查询分析 | 内置扩展 |
| **pgBadger** | PostgreSQL 日志分析 | https://pgbadger.darold.net/ |
| **ClickHouse Play** | ClickHouse 在线查询 | https://play.clickhouse.com/ |

---

**报告结束**

Linus 的最后建议：

> "这个架构最大的问题不是技术选型，而是缺乏数据所有权的清晰定义。微服务拆分不仅仅是部署独立的进程，更重要的是数据的独立。如果 user-service 还在通过外键依赖 identity-service 的 users 表，那它不是真正的微服务。
>
> 修复的第一步不是重写代码，而是明确每个表的 owner。然后删除所有跨服务的物理依赖（外键、视图、JOIN）。只有这样，才能实现真正的独立部署和扩展。
>
> Never break userspace — 迁移时保持向后兼容，使用 expand-contract 模式，逐步演进，而不是大爆炸式重写。"

---

**审核人**: Linus Torvalds (Database Architect Persona)
**日期**: 2025-11-24
**版本**: 1.0
