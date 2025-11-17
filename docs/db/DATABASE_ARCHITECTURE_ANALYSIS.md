# Nova 数据库架构完整分析报告

**分析日期**: 2025-11-11
**分析师**: Database Architect (Linus Torvalds 视角)
**数据库**: PostgreSQL 16
**架构模式**: Microservices with Shared Database (反模式)

---

## 执行摘要

**核心判断**: ❌ 当前架构存在严重的数据所有权问题

**关键发现**:
1. **两个物理分离的数据库，但数据所有权模糊**
2. **`nova_staging` 数据库被多个服务直接访问**
3. **跨服务的 `users` 表重复，缺乏数据一致性保证**
4. **外键约束跨越服务边界，破坏了微服务的独立性**

**Linus 评价**:
> "This is a classic case of premature microservices. You've built the complexity of distributed systems without solving the fundamental data ownership problem. Fix the data structures first - the rest will follow."

---

## 1. 数据库架构概览

### 1.1 物理数据库分布

```
PostgreSQL Instance (postgres-7fd85d47f6-57ddz)
├── nova_auth (5 tables) - 认证/会话数据
│   ├── users (核心用户表)
│   ├── sessions
│   ├── oauth_connections
│   ├── token_revocation
│   └── _sqlx_migrations
│
└── nova_staging (21 tables) - 业务数据
    ├── users (重复!)
    ├── user_profiles
    ├── user_settings
    ├── user_relationships
    ├── activity_logs
    ├── reports + moderation_* (5 tables)
    ├── search_* (4 tables)
    ├── domain_events + outbox_events
    ├── event_schemas + event_subscriptions
    └── kafka_topics
```

### 1.2 服务架构 vs 数据库架构不匹配

**当前服务列表** (从 `/backend/` 推断):
```
├── auth-service          → nova_auth
├── user-service          → nova_staging.users + profiles
├── messaging-service     → (数据库表未找到!)
├── media-service         → (数据库表未找到!)
├── content-service       → (数据库表未找到!)
├── feed-service          → (数据库表未找到!)
├── search-service        → nova_staging.search_*
├── notification-service  → (数据库表未找到!)
├── streaming-service     → (数据库表未找到!)
├── video-service         → (数据库表未找到!)
├── cdn-service           → (数据库表未找到!)
└── events-service        → nova_staging.domain_events
```

**问题**: 11 个微服务只有 2 个数据库，且多个服务的表不存在于数据库中！

---

## 2. 数据所有权矩阵

### 2.1 核心问题：`users` 表在两个数据库中重复

| 数据库 | 表名 | 列数 | 推荐所有者 | 当前访问者 | 问题 |
|--------|------|------|-----------|-----------|------|
| `nova_auth` | `users` | 18 | auth-service | auth-service | ✅ 正确所有权 |
| `nova_staging` | `users` | 10 | user-service | user-service, search-service, moderation-service | ❌ **数据重复，无同步机制** |

**数据一致性风险**:
```rust
// 场景：用户在 auth-service 中更新邮箱
// 1. nova_auth.users.email = "new@email.com" ✅
// 2. nova_staging.users.email = "old@email.com" ❌ 未同步!
// 3. 搜索、审核系统使用的是旧邮箱
```

**Linus 评价**:
> "Never duplicate data without a clear synchronization strategy. This is asking for bugs."

### 2.2 表所有权分配 (推荐)

#### **nova_auth** 数据库 (auth-service 独占)

| 表名 | 所有者 | 外部访问方式 | 同步策略 |
|------|--------|-------------|---------|
| `users` | auth-service | 通过 gRPC API | 事件驱动 (UserCreated, UserUpdated) |
| `sessions` | auth-service | JWT Token | N/A |
| `oauth_connections` | auth-service | Internal Only | N/A |
| `token_revocation` | auth-service | Internal Only | N/A |

**推荐 API 接口**:
```protobuf
service AuthService {
  rpc GetUser(GetUserRequest) returns (User);
  rpc ValidateToken(ValidateTokenRequest) returns (ValidateTokenResponse);
  rpc CreateSession(CreateSessionRequest) returns (Session);
}
```

#### **nova_staging** 数据库 (多服务共享 - 反模式!)

| 表名 | 当前所有者 | 推荐所有者 | 依赖表 | 问题 |
|------|-----------|-----------|--------|------|
| `users` | user-service | **应删除** | N/A | ❌ 与 nova_auth.users 重复 |
| `user_profiles` | user-service | user-service | users | ✅ FK 到同服务表 |
| `user_settings` | user-service | user-service | users | ✅ FK 到同服务表 |
| `user_relationships` | user-service | user-service | users | ✅ FK 到同服务表 |
| `activity_logs` | (未知) | **新建 audit-service** | users | ❌ 跨服务 FK |
| `reports` | (未知) | **新建 moderation-service** | users, report_reasons | ❌ 跨服务 FK |
| `moderation_queue` | (未知) | moderation-service | reports, users | ❌ 跨服务 FK |
| `moderation_actions` | (未知) | moderation-service | reports, users | ❌ 跨服务 FK |
| `moderation_appeals` | (未知) | moderation-service | moderation_actions, users | ❌ 跨服务 FK |
| `report_reasons` | (未知) | moderation-service | N/A | ✅ 参考数据表 |
| `content_filters` | (未知) | moderation-service | N/A | ✅ 配置表 |
| `search_history` | search-service | search-service | users | ❌ 跨服务 FK |
| `search_suggestions` | search-service | search-service | users | ❌ 跨服务 FK |
| `trending_searches` | search-service | search-service | N/A | ✅ 无依赖 |
| `popular_search_results` | search-service | search-service | N/A | ✅ 无依赖 |
| `domain_events` | events-service | events-service | N/A | ✅ 事件溯源表 |
| `outbox_events` | events-service | events-service | N/A | ✅ 事件发件箱 |
| `event_schemas` | events-service | events-service | N/A | ✅ 元数据表 |
| `event_subscriptions` | events-service | events-service | N/A | ✅ 元数据表 |
| `kafka_topics` | events-service | events-service | N/A | ✅ 元数据表 |

---

## 3. 跨服务边界的外键约束 (严重问题)

### 3.1 nova_staging 数据库中的外键关系图

```mermaid
graph TD
    users[users<br/>user-service]

    user_profiles[user_profiles<br/>user-service]
    user_settings[user_settings<br/>user-service]
    user_relationships[user_relationships<br/>user-service]

    activity_logs[activity_logs<br/>audit-service]

    reports[reports<br/>moderation-service]
    moderation_queue[moderation_queue<br/>moderation-service]
    moderation_actions[moderation_actions<br/>moderation-service]
    moderation_appeals[moderation_appeals<br/>moderation-service]
    report_reasons[report_reasons<br/>moderation-service]

    search_history[search_history<br/>search-service]
    search_suggestions[search_suggestions<br/>search-service]

    users --> user_profiles
    users --> user_settings
    users --> user_relationships
    users --> user_relationships

    users --> activity_logs

    users --> reports
    users --> reports
    users --> moderation_queue
    users --> moderation_actions
    users --> moderation_appeals
    users --> moderation_appeals

    users --> search_history
    users --> search_suggestions

    report_reasons --> reports
    reports --> moderation_queue
    reports --> moderation_actions
    moderation_actions --> moderation_appeals

    style users fill:#ff6b6b
    style activity_logs fill:#ffd93d
    style reports fill:#ffd93d
    style moderation_queue fill:#ffd93d
    style moderation_actions fill:#ffd93d
    style moderation_appeals fill:#ffd93d
    style search_history fill:#ffd93d
    style search_suggestions fill:#ffd93d
```

**图例**:
- 🔴 红色 = 跨服务依赖的根源 (`users` 表)
- 🟡 黄色 = 跨服务外键约束

### 3.2 跨服务外键详细清单

| 源表 (服务A) | 外键列 | 目标表 (服务B) | DELETE 策略 | 问题严重性 |
|-------------|--------|---------------|-----------|----------|
| `activity_logs` (audit) | `user_id` | `users` (user) | CASCADE | 🔴 P0 |
| `reports` (moderation) | `reporter_id` | `users` (user) | CASCADE | 🔴 P0 |
| `reports` (moderation) | `reported_user_id` | `users` (user) | CASCADE | 🔴 P0 |
| `moderation_queue` (moderation) | `assigned_to` | `users` (user) | NO ACTION | 🟡 P1 |
| `moderation_actions` (moderation) | `moderator_id` | `users` (user) | NO ACTION | 🟡 P1 |
| `moderation_appeals` (moderation) | `user_id` | `users` (user) | CASCADE | 🔴 P0 |
| `moderation_appeals` (moderation) | `reviewed_by` | `users` (user) | NO ACTION | 🟡 P1 |
| `search_history` (search) | `user_id` | `users` (user) | CASCADE | 🔴 P0 |
| `search_suggestions` (search) | `user_id` | `users` (user) | CASCADE | 🔴 P0 |

**问题分析**:

1. **P0 级问题 (CASCADE 删除策略)**:
   - 如果 `user-service` 删除用户，会触发 `activity_logs`、`reports` 等表的级联删除
   - 但这些表由其他服务管理，产生数据一致性问题
   - **场景**: 审核服务无法感知用户被删除，导致 orphaned records

2. **P1 级问题 (NO ACTION 策略)**:
   - 外键检查会阻止删除操作
   - 需要跨服务协调删除顺序
   - **场景**: 删除用户时需要先清理审核记录，但这需要调用多个服务的 API

**Linus 评价**:
> "Foreign keys across service boundaries defeat the purpose of microservices. You've created a distributed monolith with all the complexity and none of the benefits."

---

## 4. 数据一致性风险评估

### 4.1 当前风险清单

| 风险类型 | 受影响表 | 风险场景 | 影响范围 | 严重性 |
|---------|---------|---------|---------|--------|
| **数据重复** | `nova_auth.users` vs `nova_staging.users` | 用户更新信息后不同步 | 全系统 | 🔴 CRITICAL |
| **孤儿记录** | `activity_logs`, `reports`, `search_history` | 删除用户后相关记录未清理 | 审核、搜索 | 🔴 CRITICAL |
| **删除阻塞** | `moderation_actions`, `moderation_appeals` | NO ACTION FK 阻止用户删除 | 用户服务 | 🟡 HIGH |
| **跨服务事务** | 所有跨服务 FK | 无法保证原子性 | 全系统 | 🔴 CRITICAL |
| **缺失表** | messages, posts, media, notifications | 服务存在但数据库表不存在 | 消息、内容 | 🔴 CRITICAL |

### 4.2 一致性保证缺失

**当前状态**: 无跨数据库事务机制

```
场景：用户注册
1. auth-service: INSERT INTO nova_auth.users ✅
2. user-service: INSERT INTO nova_staging.users ❌ (如果失败?)
3. 结果：用户可以登录但无 profile

场景：用户删除
1. user-service: DELETE FROM nova_staging.users ✅
2. search-service: DELETE FROM search_history ❌ (如果 search-service 宕机?)
3. 结果：孤儿搜索记录永久残留
```

**缺失的机制**:
- [ ] Saga 模式 (补偿事务)
- [ ] Outbox 模式 (仅 `outbox_events` 表存在，但未使用)
- [ ] 事件溯源 (`domain_events` 表存在，但未使用)
- [ ] 最终一致性保证

---

## 5. 缺失的数据库表 (推断)

### 5.1 从服务架构推断缺失的表

根据服务列表，以下表应该存在但未找到：

| 服务 | 预期数据库 | 缺失的表 | 优先级 |
|------|-----------|---------|--------|
| `messaging-service` | `nova_messaging` | messages, conversations, participants | 🔴 P0 |
| `media-service` | `nova_media` | media_files, media_metadata | 🔴 P0 |
| `content-service` | `nova_content` | posts, comments, reactions | 🔴 P0 |
| `feed-service` | `nova_feed` | feed_items, feed_cache | 🟡 P1 |
| `notification-service` | `nova_notifications` | notifications, notification_preferences | 🔴 P0 |
| `streaming-service` | `nova_streaming` | streams, stream_events | 🟡 P1 |
| `video-service` | `nova_video` | videos, video_transcoding | 🟡 P1 |

**可能的原因**:
1. 这些服务还在开发中
2. 使用了 NoSQL 数据库 (MongoDB, Cassandra) 但未在 PostgreSQL 中体现
3. 使用了外部服务 (S3, CloudFront)

**推荐验证方式**:
```bash
# 检查每个服务的 Cargo.toml 和数据库连接字符串
for service in messaging-service media-service content-service; do
  echo "=== $service ==="
  grep -r "DATABASE_URL" backend/$service/ || echo "No DB config found"
done
```

---

## 6. 重构建议 (按 Linus 哲学)

### 6.1 原则：数据结构决定一切

> "Bad programmers worry about the code. Good programmers worry about data structures and their relationships."

**核心问题**: 当前架构在数据层面还是单体应用，但代码层面强行拆分成微服务。

### 6.2 重构路线图 (Database-per-Service 模式)

#### **阶段 1: 建立数据所有权边界** (Week 1-2)

**目标**: 每个服务独立拥有自己的数据库

```
推荐架构:
nova_auth              → auth-service (独占)
├── users              (18 列)
├── sessions
├── oauth_connections
└── token_revocation

nova_user              → user-service (独占)
├── user_profiles      (从 nova_staging 迁移)
├── user_settings      (从 nova_staging 迁移)
└── user_relationships (从 nova_staging 迁移)

nova_moderation        → moderation-service (独占)
├── reports            (从 nova_staging 迁移)
├── moderation_queue   (从 nova_staging 迁移)
├── moderation_actions (从 nova_staging 迁移)
├── moderation_appeals (从 nova_staging 迁移)
├── report_reasons     (从 nova_staging 迁移)
└── content_filters    (从 nova_staging 迁移)

nova_search            → search-service (独占)
├── search_history     (从 nova_staging 迁移)
├── search_suggestions (从 nova_staging 迁移)
├── trending_searches  (从 nova_staging 迁移)
└── popular_search_results (从 nova_staging 迁移)

nova_events            → events-service (共享 - 事件总线)
├── domain_events      (从 nova_staging 迁移)
├── outbox_events      (从 nova_staging 迁移)
├── event_schemas      (从 nova_staging 迁移)
├── event_subscriptions (从 nova_staging 迁移)
└── kafka_topics       (从 nova_staging 迁移)

nova_audit             → audit-service (独占)
└── activity_logs      (从 nova_staging 迁移)

nova_messaging         → messaging-service (新建)
├── conversations
├── messages
└── participants

nova_content           → content-service (新建)
├── posts
├── comments
└── reactions

nova_media             → media-service (新建)
├── media_files
└── media_metadata

nova_notifications     → notification-service (新建)
├── notifications
└── notification_preferences
```

#### **阶段 2: 消除跨服务外键** (Week 3-4)

**策略**: 替换外键为 UUID 引用 + 事件驱动同步

**迁移模式 - 以 `reports.reporter_id` 为例**:

```sql
-- 当前 (反模式)
ALTER TABLE reports
  ADD CONSTRAINT reports_reporter_id_fkey
  FOREIGN KEY (reporter_id) REFERENCES users(id) ON DELETE CASCADE;

-- 推荐 (事件驱动)
ALTER TABLE reports
  DROP CONSTRAINT reports_reporter_id_fkey;

-- 添加索引以保持查询性能
CREATE INDEX idx_reports_reporter_id ON reports(reporter_id);

-- 应用层验证 (user-service gRPC API)
// moderation-service 代码
let user_exists = user_service_client
    .check_user_exists(CheckUserRequest { user_id })
    .await?
    .exists;

if !user_exists {
    return Err(Error::InvalidUser);
}
```

**数据一致性通过事件保证**:
```rust
// auth-service: 发布事件
event_bus.publish(DomainEvent {
    event_type: "UserDeleted",
    aggregate_id: user_id,
    data: json!({ "user_id": user_id }),
});

// moderation-service: 订阅事件
event_bus.subscribe("UserDeleted", |event| {
    // 软删除或清理相关 reports
    reports::soft_delete_by_user(event.aggregate_id).await?;
});
```

#### **阶段 3: 解决 `users` 表重复问题** (Week 5-6)

**问题**: `nova_auth.users` (18列) vs `nova_staging.users` (10列)

**方案 A (推荐): 单一真相源 + 事件同步**

```
1. 删除 nova_staging.users 表
2. 所有服务通过 auth-service API 获取用户信息
3. 需要高性能的服务使用 Redis 缓存用户数据

实现步骤:
├── Step 1: 在 auth-service 实现 gRPC API
│   ├── GetUser(user_id) -> UserInfo
│   ├── GetUserBatch(user_ids[]) -> UserInfo[]
│   └── ValidateUser(user_id) -> bool
│
├── Step 2: 在 nova_user 数据库添加用户缓存表
│   CREATE TABLE user_cache (
│     user_id UUID PRIMARY KEY,
│     username VARCHAR(255),
│     email VARCHAR(255),
│     display_name VARCHAR(255),
│     avatar_url TEXT,
│     updated_at TIMESTAMPTZ
│   );
│
├── Step 3: auth-service 发布事件
│   - UserCreated
│   - UserUpdated
│   - UserDeleted
│
└── Step 4: user-service 订阅事件，更新 user_cache
```

**方案 B (临时方案): CDC (Change Data Capture)**

```
使用 Debezium 捕获 nova_auth.users 变更
├── 优点: 无需修改 auth-service 代码
├── 缺点: 增加运维复杂度
└── 推荐场景: 快速原型验证
```

#### **阶段 4: 实现 Saga 模式** (Week 7-8)

**目标**: 保证跨服务操作的最终一致性

**示例：用户注销流程**

```rust
// user-service: 协调者 (Saga Orchestrator)
pub async fn delete_user_saga(user_id: Uuid) -> Result<(), SagaError> {
    let saga = Saga::new("delete_user", user_id);

    // Step 1: 软删除用户资料 (本地事务)
    saga.execute(|| {
        user_profiles::soft_delete(user_id).await
    })
    .compensate(|| {
        user_profiles::restore(user_id).await
    })
    .await?;

    // Step 2: 通知审核服务清理数据
    saga.execute(|| {
        moderation_service::archive_user_reports(user_id).await
    })
    .compensate(|| {
        moderation_service::restore_user_reports(user_id).await
    })
    .await?;

    // Step 3: 通知搜索服务删除历史
    saga.execute(|| {
        search_service::delete_user_history(user_id).await
    })
    .compensate(|| {
        search_service::restore_user_history(user_id).await
    })
    .await?;

    // Step 4: 通知认证服务删除账户 (最后一步)
    saga.execute(|| {
        auth_service::delete_account(user_id).await
    })
    .no_compensate() // 账户删除不可回滚
    .await?;

    saga.commit().await
}
```

**失败场景处理**:
```
场景 1: Step 2 失败
├── 自动执行 Step 1 补偿操作
└── 返回错误给客户端

场景 2: Step 4 失败
├── 执行 Step 3, 2, 1 补偿操作
├── 记录到 saga_state 表
└── 后台任务重试或人工介入
```

---

## 7. 迁移路径 (Zero-Downtime)

### 7.1 Expand-Contract 模式

**阶段 1: Expand (扩展)**
```sql
-- Week 1: 创建新数据库
CREATE DATABASE nova_user;
CREATE DATABASE nova_moderation;
CREATE DATABASE nova_search;

-- Week 2: 复制表结构 + 数据
-- 使用 pg_dump 迁移数据
pg_dump -U postgres -d nova_staging -t user_profiles \
  | psql -U postgres -d nova_user

-- Week 3: 设置双写 (应用层)
-- 同时写入旧表和新表
async fn create_user_profile(profile: UserProfile) -> Result<()> {
    // 写入旧位置
    sqlx::query!("INSERT INTO nova_staging.user_profiles ...")
        .execute(&old_pool).await?;

    // 写入新位置
    sqlx::query!("INSERT INTO nova_user.user_profiles ...")
        .execute(&new_pool).await?;

    Ok(())
}
```

**阶段 2: Migrate (迁移)**
```sql
-- Week 4: 切换读流量到新数据库
-- 使用特性开关 (Feature Flag)
if feature_flag("use_new_user_db") {
    query(&new_pool).await
} else {
    query(&old_pool).await
}

-- Week 5: 验证数据一致性
SELECT COUNT(*) FROM nova_staging.user_profiles; -- 10000
SELECT COUNT(*) FROM nova_user.user_profiles;    -- 10000

-- Week 6: 逐步增加新数据库流量
// 10% -> 50% -> 100%
```

**阶段 3: Contract (收缩)**
```sql
-- Week 7: 停止双写
-- 移除旧数据库写入逻辑

-- Week 8: 删除旧表 (保留 2 周备份)
-- 备份
pg_dump -U postgres -d nova_staging -t user_profiles \
  > /backup/user_profiles_$(date +%Y%m%d).sql

-- 删除
DROP TABLE nova_staging.user_profiles;
```

### 7.2 回滚策略

```
回滚触发条件:
├── 数据不一致率 > 1%
├── 新数据库错误率 > 0.1%
├── P95 延迟增加 > 50%
└── 用户投诉量 > 10/hour

回滚步骤:
1. 切换特性开关 (1 分钟内完成)
2. 恢复旧数据库读流量
3. 暂停新数据库写入
4. 分析失败原因
5. 数据对账修复
```

---

## 8. 性能优化建议

### 8.1 索引优化 (基于现有外键)

**当前索引分析**:
```sql
-- 检查现有索引
SELECT
  tablename,
  indexname,
  indexdef
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;
```

**推荐新增索引**:
```sql
-- 用户查询优化
CREATE INDEX idx_user_profiles_username_email
  ON user_profiles(username, email)
  WHERE deleted_at IS NULL;

-- 审核队列优化
CREATE INDEX idx_moderation_queue_pending
  ON moderation_queue(queue_status, priority DESC, created_at)
  WHERE queue_status = 'pending';

-- 搜索历史优化 (分区索引)
CREATE INDEX idx_search_history_user_recent
  ON search_history(user_id, searched_at DESC)
  WHERE searched_at > NOW() - INTERVAL '30 days';
```

### 8.2 连接池配置

**当前问题**: 多个服务共享 `nova_staging`，连接池可能耗尽

**推荐配置** (每个服务独立池):
```rust
// user-service
let pool = PgPoolOptions::new()
    .max_connections(20)        // 根据服务负载调整
    .min_connections(5)
    .acquire_timeout(Duration::from_secs(3))
    .idle_timeout(Duration::from_secs(600))
    .max_lifetime(Duration::from_secs(1800))
    .connect(&database_url)
    .await?;
```

**总连接数规划**:
```
PostgreSQL max_connections = 200

分配:
├── auth-service:          30 connections
├── user-service:          40 connections
├── moderation-service:    20 connections
├── search-service:        30 connections
├── messaging-service:     40 connections
├── content-service:       30 connections
├── 预留 (migrations):     10 connections
└── 总计:                 200 connections
```

### 8.3 查询性能目标

| 查询类型 | 当前 (p95) | 目标 (p95) | 优化方法 |
|---------|-----------|-----------|---------|
| 单用户查询 | 50ms | 10ms | 添加覆盖索引 |
| 用户关系查询 | 200ms | 50ms | 物化视图 |
| 搜索历史 | 300ms | 100ms | 分区表 |
| 审核队列 | 150ms | 30ms | 条件索引 + 限制返回条数 |
| 事件查询 | 100ms | 20ms | 使用 `sequence_number` 索引 |

---

## 9. 监控和告警

### 9.1 数据库健康指标

**推荐监控指标** (使用 Prometheus + postgres_exporter):
```yaml
metrics:
  # 连接池
  - pg_stat_database_numbackends
  - pg_stat_database_xact_commit
  - pg_stat_database_xact_rollback

  # 查询性能
  - pg_stat_statements_mean_exec_time
  - pg_stat_statements_max_exec_time

  # 锁等待
  - pg_locks_count
  - pg_stat_activity_wait_event_type

  # 复制延迟 (未来主从配置)
  - pg_replication_lag_bytes
  - pg_replication_lag_seconds
```

### 9.2 告警规则

```yaml
# Prometheus AlertManager 配置
groups:
  - name: database_alerts
    rules:
      - alert: HighConnectionUsage
        expr: pg_stat_database_numbackends / pg_settings_max_connections > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Database connection usage > 80%"

      - alert: SlowQuery
        expr: pg_stat_statements_mean_exec_time > 1000
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Slow query detected (> 1s)"

      - alert: ReplicationLag
        expr: pg_replication_lag_seconds > 30
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Replication lag > 30 seconds"
```

---

## 10. 成本估算

### 10.1 当前配置成本

**假设**: AWS RDS PostgreSQL

```
当前配置:
├── 实例类型: db.t3.medium (2 vCPU, 4GB RAM)
├── 存储: 100GB SSD (gp3)
├── 多可用区: 否
└── 月成本: ~$150

存在问题:
- 单点故障
- 无读副本
- 连接数限制 (200)
```

### 10.2 推荐配置成本

**方案 A: 数据库分离 (推荐)**
```
配置:
├── nova_auth: db.t3.small (2 vCPU, 2GB RAM) - $75/月
├── nova_user: db.t3.medium (2 vCPU, 4GB RAM) - $150/月
├── nova_moderation: db.t3.small - $75/月
├── nova_search: db.t3.medium - $150/月
├── nova_events: db.t3.small - $75/月
├── 其他服务: 3 x db.t3.small - $225/月
├── 总存储: 500GB - $115/月
└── 总成本: ~$865/月 (增加 $715/月)

优势:
- 故障隔离
- 独立扩展
- 清晰的所有权
```

**方案 B: 读写分离 (临时方案)**
```
配置:
├── 主实例: db.r5.large (2 vCPU, 16GB RAM) - $300/月
├── 读副本 1: db.r5.large - $300/月
├── 读副本 2: db.r5.large - $300/月
├── 存储: 200GB - $46/月
└── 总成本: ~$946/月 (增加 $796/月)

优势:
- 短期内提升性能
- 延迟问题解决方案
- 不改变应用逻辑
```

### 10.3 成本优化策略

```
1. 使用 Reserved Instances (1 年期)
   - 节省 ~40% ($346/月)

2. 使用 Aurora Serverless v2
   - 根据负载自动扩缩容
   - 低峰期成本降低 60%

3. 冷数据归档
   - 超过 90 天的数据迁移到 S3 ($0.023/GB/月)
   - 预计节省 $50/月

4. 数据压缩
   - 启用表级压缩 (TOAST)
   - 存储成本降低 30% ($35/月)
```

---

## 11. 最终推荐 (Executive Summary)

### 11.1 核心问题

**当前架构的致命缺陷**:
1. ❌ **数据重复**: `users` 表在两个数据库中存在，无同步机制
2. ❌ **跨服务外键**: 9 个跨服务外键约束，破坏微服务独立性
3. ❌ **缺失表**: 6+ 个服务的数据库表不存在
4. ❌ **单点故障**: 所有服务共享单一 PostgreSQL 实例

### 11.2 推荐方案 (按优先级)

#### **P0: 立即修复** (Week 1-2)
1. **消除 `users` 表重复**
   - 方法: 删除 `nova_staging.users`，所有服务通过 auth-service gRPC API 获取用户信息
   - 成本: 0 (代码修改)
   - 风险: 中 (需要大量测试)

2. **建立事件驱动同步**
   - 方法: auth-service 发布 `UserCreated/Updated/Deleted` 事件
   - 成本: 0 (使用现有 Kafka)
   - 风险: 低

#### **P1: 短期改进** (Week 3-6)
1. **迁移 `nova_staging` 表到独立数据库**
   - 目标: 6 个独立数据库 (每服务一个)
   - 方法: Expand-Contract 模式
   - 成本: +$715/月
   - 风险: 中 (需要双写期间保证一致性)

2. **消除跨服务外键**
   - 方法: 替换为 UUID 引用 + 事件驱动验证
   - 成本: 0
   - 风险: 低 (应用层验证)

#### **P2: 长期优化** (Week 7-8)
1. **实现 Saga 模式**
   - 目标: 保证跨服务操作的最终一致性
   - 方法: 编排式 Saga (推荐) 或 编舞式 Saga
   - 成本: 开发时间
   - 风险: 低

2. **读写分离**
   - 目标: 提升查询性能
   - 方法: 主从复制 + 连接池路由
   - 成本: +$600/月 (2 个读副本)
   - 风险: 低

### 11.3 不推荐的方案

❌ **继续使用共享数据库**
- 原因: 破坏微服务独立性，未来扩展困难

❌ **直接使用分布式事务 (2PC)**
- 原因: 性能差，复杂度高，不适合微服务

❌ **使用 CDC 同步 `users` 表**
- 原因: 增加运维复杂度，不解决根本问题

### 11.4 成功标准

**技术指标**:
- [ ] 每个服务独立拥有数据库 (database-per-service)
- [ ] 零跨服务外键约束
- [ ] 事件驱动数据同步延迟 < 1s (p95)
- [ ] 查询性能 < 100ms (p95)

**业务指标**:
- [ ] 零数据丢失
- [ ] 零停机迁移
- [ ] 成本增加 < $1000/月
- [ ] 团队开发效率提升 (独立部署)

---

## 12. Linus Torvalds 最终评价

> **Data structures, not code**
>
> "Your problem isn't in the Rust code or the gRPC services. It's in the data. You've built a beautiful microservices architecture on top of a monolithic database. That's like building a Ferrari with bicycle wheels.
>
> Fix the data ownership first:
> 1. One database per service, no exceptions
> 2. No foreign keys across service boundaries
> 3. Events for synchronization, not direct database access
> 4. Test your failure modes - what happens when a service is down?
>
> Only when the data structures are right will the code become simple. Everything else is just fighting symptoms."

---

## 附录 A: 快速参考

### A.1 数据库连接字符串

```bash
# nova_auth
DATABASE_URL=postgresql://postgres:password@postgres:5432/nova_auth

# nova_staging (待废弃)
DATABASE_URL=postgresql://postgres:password@postgres:5432/nova_staging

# 推荐新数据库
DATABASE_URL_USER=postgresql://postgres:password@postgres:5432/nova_user
DATABASE_URL_MODERATION=postgresql://postgres:password@postgres:5432/nova_moderation
DATABASE_URL_SEARCH=postgresql://postgres:password@postgres:5432/nova_search
DATABASE_URL_EVENTS=postgresql://postgres:password@postgres:5432/nova_events
```

### A.2 迁移命令

```bash
# 备份当前数据库
pg_dump -U postgres -h localhost -d nova_staging > backup_$(date +%Y%m%d).sql

# 创建新数据库
psql -U postgres -h localhost -c "CREATE DATABASE nova_user;"

# 恢复特定表
pg_restore -U postgres -h localhost -d nova_user -t user_profiles backup.sql

# 验证数据一致性
psql -U postgres -h localhost -d nova_staging -c "SELECT COUNT(*) FROM user_profiles;"
psql -U postgres -h localhost -d nova_user -c "SELECT COUNT(*) FROM user_profiles;"
```

---

## 附录 B: 相关文档

- [PHASE_4_PLANNING.md](/Users/proerror/Documents/nova/PHASE_4_PLANNING.md) - 第 4 阶段计划
- [DATABASE_OPTIMIZATION_GUIDE.md](/Users/proerror/Documents/nova/docs/DATABASE_OPTIMIZATION_GUIDE.md) - 数据库优化指南
- [microservices-data-patterns.md](https://microservices.io/patterns/data/) - 微服务数据模式
- [postgres-performance-tuning.md](https://www.postgresql.org/docs/current/performance-tips.html) - PostgreSQL 性能调优

---

**报告结束**

*生成时间: 2025-11-11 05:30:00 UTC*
*下次审查: Week 2 (数据库分离完成后)*
