# P0: user-service 删除迁移计划

**状态**: 草案
**优先级**: P0 (最高)
**预计影响**: 14→13 服务, 消除数据所有权混乱
**风险等级**: 高 (需要数据库迁移 + 多服务协调)

---

## 1. 问题诊断

### 1.1 当前状态

`user-service` 是历史遗留的单体服务残骸，具有以下问题：

```
┌─────────────────────────────────────────────────────────────────┐
│                    user-service (垃圾桶服务)                      │
├─────────────────────────────────────────────────────────────────┤
│ ✗ 无 gRPC 消费者 - graphql-gateway 已弃用所有 user-service 客户端 │
│ ✗ 功能混杂 - Profile + Moderation + Events + CDC                │
│ ✗ 数据重复 - blocks/follows 表与 graph-service 重复              │
│ ✗ REST 孤岛 - 仅提供 REST API，与微服务架构不一致                  │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 依赖关系分析

| 消费者 | 依赖类型 | 依赖细节 | 状态 |
|--------|----------|----------|------|
| graphql-gateway | gRPC | 无 - 已在 `clients.rs` 中注释弃用 | ✅ 无依赖 |
| realtime-chat-service | 共享数据库 | 直接查询 `blocks`, `follows`, `user_settings` | ❌ 需修复 |
| 其他服务 | 无 | - | ✅ 无依赖 |

### 1.3 表所有权混乱

```
┌─────────────────┬───────────────────────┬─────────────────────┬────────────────┐
│ 表名            │ 当前写入者             │ 应有所有者           │ 数据库         │
├─────────────────┼───────────────────────┼─────────────────────┼────────────────┤
│ users           │ identity + user + chat│ identity-service    │ PostgreSQL     │
│ user_settings   │ user + chat           │ identity-service    │ PostgreSQL     │
│ blocks          │ user + chat + graph   │ graph-service       │ Neo4j          │
│ follows         │ user + social + graph │ graph-service       │ Neo4j          │
│ reports         │ user                  │ trust-safety        │ PostgreSQL     │
│ moderation_*    │ user                  │ trust-safety        │ PostgreSQL     │
└─────────────────┴───────────────────────┴─────────────────────┴────────────────┘
```

---

## 2. 功能迁移映射

### 2.1 REST Handlers 迁移

| 源文件 | 端点 | 目标服务 | 迁移方式 |
|--------|------|----------|----------|
| `handlers/users.rs` | `GET /api/v1/users/{id}` | identity-service | gRPC 代理 (已实现) |
| `handlers/users.rs` | `PATCH /api/v1/users/me` | identity-service | gRPC 代理 (已实现) |
| `handlers/users.rs` | `PUT /api/v1/users/me/public-key` | identity-service | 已委托 auth-service |
| `handlers/preferences.rs` | `GET/PUT feed_preferences` | content-service | 新建 gRPC + REST |
| `handlers/preferences.rs` | `POST/DELETE blocks` | graph-service | gRPC 调用 |
| `handlers/moderation.rs` | 全部 | trust-safety-service | 代码迁移 |

### 2.2 gRPC Server 迁移

| RPC 方法 | 源: `user-service/grpc/server.rs` | 目标服务 |
|----------|-----------------------------------|----------|
| `GetUserProfile` | 读取 users 表 | identity-service (已存在) |
| `UpdateUserProfile` | 更新 users 表 | identity-service (已存在) |
| `GetUserSettings` | 读取 user_settings 表 | identity-service (新增) |
| `UpdateUserSettings` | 更新 user_settings 表 | identity-service (新增) |
| `FollowUser` | 写入 follows 表 | social-service (已存在) |
| `UnfollowUser` | 删除 follows 表 | social-service (已存在) |
| `BlockUser` | 写入 blocks 表 | graph-service (新增) |
| `UnblockUser` | 删除 blocks 表 | graph-service (新增) |
| `GetUserFollowers` | 读取 follows 表 | graph-service (已存在) |
| `GetUserFollowing` | 读取 follows 表 | graph-service (已存在) |
| `CheckUserRelationship` | 查询 follows/blocks | graph-service (已存在) |
| `SearchUsers` | 读取 users 表 | search-service (已存在) |

### 2.3 Services 模块迁移

| 模块 | 目标 | 迁移复杂度 |
|------|------|-----------|
| `services/moderation_service.rs` | trust-safety-service | 中等 |
| `services/cdc.rs` | analytics-service | 低 |
| `services/events.rs` | analytics-service | 低 |
| `services/kafka_producer.rs` | analytics-service | 低 |
| `services/token_revocation.rs` | identity-service | 低 |
| `services/query_profiler.rs` | 删除或移至 libs | 低 |
| `services/redis_job.rs` | feed-service | 低 |
| `services/storage.rs` | media-service | 低 |

---

## 3. 数据库迁移策略

### 3.1 Expand-Contract 模式

```
Phase 1: EXPAND (双写)
├── identity-service 添加 user_settings 表
├── trust-safety-service 添加 moderation_* 表
└── 启用双写：user-service + 新服务同时写入

Phase 2: MIGRATE (数据迁移)
├── 运行一次性迁移脚本
├── 验证数据一致性
└── 切换读取路径到新服务

Phase 3: CONTRACT (删除旧表)
├── 停用 user-service 写入
├── 观察期 (1-2 周)
└── 删除 user-service 及相关表
```

### 3.2 迁移脚本

#### 3.2.1 user_settings → identity-service

```sql
-- identity-service/migrations/006_migrate_user_settings.sql

-- Step 1: Create table (if not exists)
CREATE TABLE IF NOT EXISTS user_settings (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    email_notifications BOOLEAN DEFAULT true,
    push_notifications BOOLEAN DEFAULT true,
    marketing_emails BOOLEAN DEFAULT false,
    timezone VARCHAR(50) DEFAULT 'UTC',
    language VARCHAR(10) DEFAULT 'en',
    dark_mode BOOLEAN DEFAULT false,
    privacy_level VARCHAR(20) DEFAULT 'public',
    allow_messages BOOLEAN DEFAULT true,
    dm_permission VARCHAR(20) DEFAULT 'mutuals',
    show_online_status BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Step 2: Migrate data (run once)
INSERT INTO user_settings (user_id, dm_permission, created_at, updated_at)
SELECT user_id, dm_permission, created_at, updated_at
FROM public.user_settings  -- old shared schema
ON CONFLICT (user_id) DO UPDATE SET
    dm_permission = EXCLUDED.dm_permission,
    updated_at = NOW();
```

#### 3.2.2 moderation_* → trust-safety-service

```sql
-- trust-safety-service/migrations/003_migrate_moderation_tables.sql

-- Reports table
CREATE TABLE IF NOT EXISTS reports (
    id UUID PRIMARY KEY,
    reporter_id UUID NOT NULL,
    reported_user_id UUID,
    reason_id UUID NOT NULL,
    reason_code VARCHAR(50) NOT NULL,
    target_type VARCHAR(50) NOT NULL,
    target_id UUID NOT NULL,
    description TEXT,
    status VARCHAR(50) DEFAULT 'open',
    severity VARCHAR(50) DEFAULT 'low',
    priority INT DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    resolved_at TIMESTAMPTZ
);

-- Moderation actions table
CREATE TABLE IF NOT EXISTS moderation_actions (
    id UUID PRIMARY KEY,
    report_id UUID REFERENCES reports(id),
    moderator_id UUID NOT NULL,
    action_type VARCHAR(50) NOT NULL,
    target_type VARCHAR(50),
    target_id UUID,
    duration_days INT,
    reason TEXT,
    notes TEXT,
    status VARCHAR(50) DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL
);

-- Data migration script (run once)
INSERT INTO trust_safety.reports SELECT * FROM public.reports;
INSERT INTO trust_safety.moderation_actions SELECT * FROM public.moderation_actions;
INSERT INTO trust_safety.moderation_appeals SELECT * FROM public.moderation_appeals;
INSERT INTO trust_safety.moderation_queue SELECT * FROM public.moderation_queue;
```

### 3.3 blocks/follows 表处理

**决策**: 这些表应完全由 graph-service (Neo4j) 所有

```
当前状态:
├── PostgreSQL.blocks (user-service, realtime-chat-service)
├── PostgreSQL.follows (user-service, social-service)
└── Neo4j.FOLLOWS/BLOCKS (graph-service) ← 真正的所有者

迁移策略:
1. realtime-chat-service 改为调用 graph-service gRPC
2. 废弃 PostgreSQL 中的 blocks/follows 表
3. 所有关系查询走 Neo4j
```

---

## 4. realtime-chat-service 修复

### 4.1 问题代码

`realtime-chat-service/src/services/relationship_service.rs`:

```rust
// ❌ 当前: 直接查询共享 PostgreSQL 表
pub async fn is_blocked_by(db: &Pool<Postgres>, user_a: Uuid, user_b: Uuid) -> Result<bool, AppError> {
    let result: Option<(i32,)> = sqlx::query_as(
        "SELECT 1 FROM blocks WHERE blocker_id = $1 AND blocked_id = $2 LIMIT 1",
    )
    .bind(user_b)
    .bind(user_a)
    .fetch_optional(db)
    .await?;
    Ok(result.is_some())
}
```

### 4.2 修复方案

```rust
// ✅ 修复: 调用 graph-service gRPC
use grpc_clients::graph::GraphServiceClient;

pub async fn is_blocked_by(
    graph_client: &GraphServiceClient,
    user_a: Uuid,
    user_b: Uuid,
) -> Result<bool, AppError> {
    let response = graph_client
        .check_relationship(CheckRelationshipRequest {
            source_user_id: user_b.to_string(),
            target_user_id: user_a.to_string(),
            relationship_type: "BLOCKS".to_string(),
        })
        .await?;
    Ok(response.exists)
}
```

### 4.3 需要新增的 graph-service gRPC

```protobuf
// proto/services_v2/graph_service.proto

service GraphService {
  // 现有方法...

  // 新增: Block 操作
  rpc BlockUser(BlockUserRequest) returns (BlockUserResponse);
  rpc UnblockUser(UnblockUserRequest) returns (UnblockUserResponse);
  rpc IsBlocked(IsBlockedRequest) returns (IsBlockedResponse);
  rpc GetBlockedUsers(GetBlockedUsersRequest) returns (GetBlockedUsersResponse);
}

message BlockUserRequest {
  string blocker_id = 1;
  string blocked_id = 2;
  string reason = 3;
}

message IsBlockedRequest {
  string user_id = 1;
  string target_id = 2;
}

message IsBlockedResponse {
  bool is_blocked = 1;
  bool is_blocking = 2;
}
```

---

## 5. 执行计划

### Phase 1: 准备 (1 周)

| 任务 | 负责服务 | 优先级 |
|------|----------|--------|
| graph-service 添加 Block gRPC | graph-service | P0 |
| identity-service 添加 user_settings gRPC | identity-service | P0 |
| trust-safety-service 添加 moderation 表 | trust-safety-service | P1 |

### Phase 2: 双写 (1 周)

| 任务 | 描述 |
|------|------|
| 启用双写 | user-service 同时写入新旧位置 |
| 监控 | 确保数据一致性 |
| 测试 | 验证新服务 gRPC 正常 |

### Phase 3: 切换 (1 周)

| 任务 | 描述 |
|------|------|
| 修复 realtime-chat-service | 替换直接 SQL 为 gRPC 调用 |
| 切换读取路径 | 所有读取走新服务 |
| 停用 user-service 写入 | Feature flag 控制 |

### Phase 4: 清理 (1 周)

| 任务 | 描述 |
|------|------|
| 删除 user-service | 从 Cargo.toml workspace 移除 |
| 删除旧表 | 运行 drop table 迁移 |
| 更新文档 | 移除所有 user-service 引用 |

---

## 6. 回滚计划

### 6.1 Phase 1-2 回滚

```bash
# 停止新服务写入
kubectl scale deployment trust-safety-service --replicas=0

# 恢复 user-service 单写
kubectl set env deployment/user-service DUAL_WRITE_ENABLED=false
```

### 6.2 Phase 3 回滚

```bash
# 恢复 realtime-chat-service 旧代码
kubectl rollout undo deployment/realtime-chat-service

# 恢复读取路径到 user-service
kubectl set env deployment/graphql-gateway USER_SERVICE_ENABLED=true
```

---

## 7. 验证检查清单

### 7.1 迁移前

- [ ] graph-service Block gRPC 测试通过
- [ ] identity-service user_settings gRPC 测试通过
- [ ] trust-safety-service moderation 表存在
- [ ] 双写机制就绪

### 7.2 迁移中

- [ ] 数据一致性验证脚本运行通过
- [ ] 无 500 错误
- [ ] Prometheus 监控无告警

### 7.3 迁移后

- [ ] `UserServiceClient` 在 codebase 中无引用
- [ ] `user-service` 进程已停止
- [ ] 旧表已清理
- [ ] 文档已更新

---

## 8. 附录

### 8.1 受影响文件清单

```
删除:
├── backend/user-service/ (整个目录)
├── backend/Cargo.toml (移除 user-service member)
└── backend/proto/services/user_service.proto (弃用)

修改:
├── backend/realtime-chat-service/src/services/relationship_service.rs
├── backend/realtime-chat-service/src/services/conversation_service.rs
├── backend/graph-service/src/grpc/server.rs (添加 Block RPCs)
├── backend/identity-service/src/grpc/server.rs (添加 Settings RPCs)
└── backend/trust-safety-service/src/services/moderation.rs (新增)
```

### 8.2 Proto 变更

```protobuf
// proto/services_v2/user_service.proto
// 标记为 deprecated, 最终删除

// 所有功能已迁移至:
// - identity-service: User Profile + Settings
// - graph-service: Relationships (follow/block)
// - trust-safety-service: Moderation
// - search-service: User Search
```

---

**审批**: 待定
**执行日期**: 待定
**负责人**: 待定
