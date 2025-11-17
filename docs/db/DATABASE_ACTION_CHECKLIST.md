# Nova 数据库重构行动清单

**日期**: 2025-11-11
**优先级**: 🔴 CRITICAL
**工作量**: 8 周 (2 Backend Engineers + 1 DevOps Engineer)

---

## 🚨 立即行动 (本周完成)

### [ ] 1. 获得管理层批准

**负责人**: 项目经理
**时间**: 1-2 天

**需要批准的内容**:
- [ ] 成本增加预算: $1000/月 (最终优化后 $653/月)
- [ ] 工程资源分配: 2 Backend + 1 DevOps (8 周全职)
- [ ] 风险接受: 数据库迁移的中等风险
- [ ] 时间承诺: 8 周完成重构

**提交材料**:
- [x] [DATABASE_EXECUTIVE_SUMMARY.md](DATABASE_EXECUTIVE_SUMMARY.md)
- [x] [DATABASE_ARCHITECTURE_ANALYSIS.md](DATABASE_ARCHITECTURE_ANALYSIS.md)
- [ ] ROI 分析报告 (待补充)

---

### [ ] 2. 数据一致性验证测试

**负责人**: Backend Team Lead
**时间**: 2-3 天

#### [ ] 2.1 验证 `users` 表数据差异

```sql
-- 连接到数据库
kubectl exec -n nova postgres-7fd85d47f6-57ddz -- psql -U postgres

-- 检查行数差异
SELECT 'nova_auth' AS db, COUNT(*) FROM nova_auth.users
UNION ALL
SELECT 'nova_staging' AS db, COUNT(*) FROM nova_staging.users;

-- 查找不一致的记录 (按 ID)
SELECT
  a.id,
  a.username AS auth_username,
  s.username AS staging_username,
  a.email AS auth_email,
  s.email AS staging_email,
  a.updated_at AS auth_updated,
  s.updated_at AS staging_updated
FROM nova_auth.users a
LEFT JOIN nova_staging.users s ON a.id = s.id
WHERE
  a.username != s.username
  OR a.email != s.email
  OR a.display_name != s.display_name;

-- 查找孤儿记录 (在 auth 但不在 staging)
SELECT id, username, email, created_at
FROM nova_auth.users
WHERE id NOT IN (SELECT id FROM nova_staging.users);

-- 查找孤儿记录 (在 staging 但不在 auth)
SELECT id, username, email, created_at
FROM nova_staging.users
WHERE id NOT IN (SELECT id FROM nova_auth.users);
```

**输出结果到文件**:
```bash
kubectl exec -n nova postgres-7fd85d47f6-57ddz -- psql -U postgres -d nova_auth -c "
SELECT ... (上述查询)
" > /tmp/user_table_inconsistency_report.txt
```

**期望结果**:
- 记录不一致率 (目标: < 1%)
- 孤儿记录数量
- 最后更新时间差异

---

#### [ ] 2.2 测试用户删除场景

**测试脚本**: `backend/scripts/test_user_deletion.sh`

```bash
#!/bin/bash
set -e

echo "=== 用户删除场景测试 ==="

# 1. 创建测试用户
USER_ID=$(uuidgen)
echo "创建测试用户: $USER_ID"

kubectl exec -n nova postgres-7fd85d47f6-57ddz -- psql -U postgres -d nova_auth -c "
INSERT INTO users (id, username, email, password_hash)
VALUES ('$USER_ID', 'test_delete_user', 'test@delete.com', 'hash');
"

kubectl exec -n nova postgres-7fd85d47f6-57ddz -- psql -U postgres -d nova_staging -c "
INSERT INTO users (id, username, email, password_hash)
VALUES ('$USER_ID', 'test_delete_user', 'test@delete.com', 'hash');

INSERT INTO user_profiles (id, username, email)
VALUES ('$USER_ID', 'test_delete_user', 'test@delete.com');

INSERT INTO search_history (id, user_id, query_type, query_text)
VALUES (gen_random_uuid(), '$USER_ID', 'user', 'test query');

INSERT INTO activity_logs (id, user_id, activity_type)
VALUES (gen_random_uuid(), '$USER_ID', 'test_activity');
"

# 2. 验证数据存在
echo "验证数据创建成功..."
kubectl exec -n nova postgres-7fd85d47f6-57ddz -- psql -U postgres -d nova_staging -c "
SELECT 'user_profiles' AS table, COUNT(*) FROM user_profiles WHERE id = '$USER_ID'
UNION ALL
SELECT 'search_history', COUNT(*) FROM search_history WHERE user_id = '$USER_ID'
UNION ALL
SELECT 'activity_logs', COUNT(*) FROM activity_logs WHERE user_id = '$USER_ID';
"

# 3. 删除 staging 用户 (触发 CASCADE)
echo "删除 staging.users (测试 CASCADE 行为)..."
kubectl exec -n nova postgres-7fd85d47f6-57ddz -- psql -U postgres -d nova_staging -c "
DELETE FROM users WHERE id = '$USER_ID';
"

# 4. 检查级联删除结果
echo "检查级联删除结果..."
kubectl exec -n nova postgres-7fd85d47f6-57ddz -- psql -U postgres -d nova_staging -c "
SELECT 'user_profiles' AS table, COUNT(*) FROM user_profiles WHERE id = '$USER_ID'
UNION ALL
SELECT 'search_history', COUNT(*) FROM search_history WHERE user_id = '$USER_ID'
UNION ALL
SELECT 'activity_logs', COUNT(*) FROM activity_logs WHERE user_id = '$USER_ID';
"

# 5. 检查 auth 表是否仍然存在
echo "检查 nova_auth.users 是否仍存在..."
kubectl exec -n nova postgres-7fd85d47f6-57ddz -- psql -U postgres -d nova_auth -c "
SELECT id, username, email FROM users WHERE id = '$USER_ID';
"

echo "=== 测试完成 ==="
```

**执行测试**:
```bash
chmod +x backend/scripts/test_user_deletion.sh
./backend/scripts/test_user_deletion.sh > /tmp/user_deletion_test_result.txt
```

**分析结果**:
- [ ] CASCADE 删除是否按预期工作?
- [ ] `nova_auth.users` 是否残留?
- [ ] 是否产生孤儿记录?

---

#### [ ] 2.3 查找现有孤儿记录

```sql
-- 孤儿 user_profiles (user 已删除但 profile 仍存在)
SELECT COUNT(*) AS orphan_profiles
FROM nova_staging.user_profiles p
WHERE NOT EXISTS (
  SELECT 1 FROM nova_staging.users u WHERE u.id = p.id
);

-- 孤儿 search_history
SELECT COUNT(*) AS orphan_search_history
FROM nova_staging.search_history h
WHERE NOT EXISTS (
  SELECT 1 FROM nova_staging.users u WHERE u.id = h.user_id
);

-- 孤儿 activity_logs
SELECT COUNT(*) AS orphan_activity_logs
FROM nova_staging.activity_logs l
WHERE NOT EXISTS (
  SELECT 1 FROM nova_staging.users u WHERE u.id = l.user_id
);

-- 孤儿 reports
SELECT COUNT(*) AS orphan_reports
FROM nova_staging.reports r
WHERE
  NOT EXISTS (SELECT 1 FROM nova_staging.users u WHERE u.id = r.reporter_id)
  OR NOT EXISTS (SELECT 1 FROM nova_staging.users u WHERE u.id = r.reported_user_id);
```

**输出报告**:
```bash
kubectl exec -n nova postgres-7fd85d47f6-57ddz -- psql -U postgres -d nova_staging -c "
$(cat backend/scripts/find_orphan_records.sql)
" > /tmp/orphan_records_report.txt
```

---

### [ ] 3. 技术方案评审会议

**负责人**: Technical Lead
**时间**: 半天 (4 小时)

#### 议程

**09:00-10:00 - 问题分析**
- [ ] 展示数据一致性测试结果
- [ ] 讨论跨服务外键的影响
- [ ] 评估当前架构风险

**10:00-11:00 - 解决方案设计**
- [ ] auth-service gRPC API 设计
  - GetUser(user_id) → UserInfo
  - CheckUserExists(user_id) → bool
  - GetUserBatch(user_ids[]) → UserInfo[]
- [ ] 事件定义
  - UserCreated
  - UserUpdated
  - UserDeleted
- [ ] 缓存策略 (Redis + 本地缓存)

**11:00-12:00 - 迁移策略**
- [ ] Expand-Contract 模式细节
- [ ] 双写期间数据一致性保证
- [ ] 回滚计划

**13:00-14:00 - 测试策略**
- [ ] 单元测试覆盖率目标 (80%+)
- [ ] 集成测试场景
- [ ] 负载测试 (k6)
- [ ] 数据对账脚本

**输出物**:
- [ ] 技术设计文档 (TDD)
- [ ] API 规范 (Protobuf)
- [ ] 迁移时间表 (详细到天)
- [ ] 风险缓解矩阵

---

## 📋 Week 1-2: 消除 `users` 表重复

### [ ] Week 1: auth-service API 开发

**负责人**: Backend Engineer #1

#### [ ] 1.1 定义 Protobuf API

**文件**: `backend/proto/auth_service.proto`

```protobuf
syntax = "proto3";

package nova.auth.v1;

import "google/protobuf/timestamp.proto";

service AuthService {
  // 获取单个用户信息
  rpc GetUser(GetUserRequest) returns (GetUserResponse);

  // 批量获取用户信息
  rpc GetUserBatch(GetUserBatchRequest) returns (GetUserBatchResponse);

  // 检查用户是否存在
  rpc CheckUserExists(CheckUserExistsRequest) returns (CheckUserExistsResponse);

  // 验证 JWT Token
  rpc ValidateToken(ValidateTokenRequest) returns (ValidateTokenResponse);
}

message GetUserRequest {
  string user_id = 1;  // UUID
}

message GetUserResponse {
  User user = 1;
}

message GetUserBatchRequest {
  repeated string user_ids = 1;  // UUID[]
}

message GetUserBatchResponse {
  repeated User users = 1;
}

message CheckUserExistsRequest {
  string user_id = 1;  // UUID
}

message CheckUserExistsResponse {
  bool exists = 1;
}

message User {
  string id = 1;
  string username = 2;
  string email = 3;
  string display_name = 4;
  string avatar_url = 5;
  bool is_active = 6;
  bool email_verified = 7;
  google.protobuf.Timestamp created_at = 8;
  google.protobuf.Timestamp updated_at = 9;
}
```

**任务**:
- [ ] 定义 Protobuf 文件
- [ ] 生成 Rust 代码: `cargo build -p proto`
- [ ] 代码审查: Backend Team

---

#### [ ] 1.2 实现 auth-service gRPC Server

**文件**: `backend/auth-service/src/grpc/user_service.rs`

```rust
use tonic::{Request, Response, Status};
use proto::auth_service_server::AuthService;
use proto::{GetUserRequest, GetUserResponse, User};

pub struct AuthServiceImpl {
    db_pool: PgPool,
    cache: Arc<RedisPool>,
}

#[tonic::async_trait]
impl AuthService for AuthServiceImpl {
    async fn get_user(
        &self,
        request: Request<GetUserRequest>,
    ) -> Result<Response<GetUserResponse>, Status> {
        let user_id = Uuid::parse_str(&request.into_inner().user_id)
            .map_err(|_| Status::invalid_argument("Invalid user_id"))?;

        // 1. 尝试从 Redis 缓存获取
        if let Some(cached_user) = self.get_from_cache(user_id).await? {
            return Ok(Response::new(GetUserResponse {
                user: Some(cached_user),
            }));
        }

        // 2. 从数据库查询
        let user = sqlx::query_as!(
            UserModel,
            r#"
            SELECT id, username, email, display_name, avatar_url,
                   is_active, email_verified, created_at, updated_at
            FROM users
            WHERE id = $1 AND deleted_at IS NULL
            "#,
            user_id
        )
        .fetch_optional(&self.db_pool)
        .await
        .map_err(|e| Status::internal(format!("Database error: {}", e)))?
        .ok_or_else(|| Status::not_found("User not found"))?;

        // 3. 写入 Redis 缓存
        self.cache_user(&user).await?;

        Ok(Response::new(GetUserResponse {
            user: Some(user.into()),
        }))
    }

    async fn get_user_batch(
        &self,
        request: Request<GetUserBatchRequest>,
    ) -> Result<Response<GetUserBatchResponse>, Status> {
        let user_ids: Vec<Uuid> = request
            .into_inner()
            .user_ids
            .iter()
            .filter_map(|id| Uuid::parse_str(id).ok())
            .collect();

        if user_ids.is_empty() {
            return Err(Status::invalid_argument("No valid user_ids provided"));
        }

        // 批量查询 (使用 IN 子句)
        let users = sqlx::query_as!(
            UserModel,
            r#"
            SELECT id, username, email, display_name, avatar_url,
                   is_active, email_verified, created_at, updated_at
            FROM users
            WHERE id = ANY($1) AND deleted_at IS NULL
            "#,
            &user_ids
        )
        .fetch_all(&self.db_pool)
        .await
        .map_err(|e| Status::internal(format!("Database error: {}", e)))?;

        Ok(Response::new(GetUserBatchResponse {
            users: users.into_iter().map(|u| u.into()).collect(),
        }))
    }

    async fn check_user_exists(
        &self,
        request: Request<CheckUserExistsRequest>,
    ) -> Result<Response<CheckUserExistsResponse>, Status> {
        let user_id = Uuid::parse_str(&request.into_inner().user_id)
            .map_err(|_| Status::invalid_argument("Invalid user_id"))?;

        let exists = sqlx::query_scalar!(
            r#"SELECT EXISTS(SELECT 1 FROM users WHERE id = $1 AND deleted_at IS NULL)"#,
            user_id
        )
        .fetch_one(&self.db_pool)
        .await
        .map_err(|e| Status::internal(format!("Database error: {}", e)))?
        .unwrap_or(false);

        Ok(Response::new(CheckUserExistsResponse { exists }))
    }
}

impl AuthServiceImpl {
    async fn get_from_cache(&self, user_id: Uuid) -> Result<Option<User>, Status> {
        let key = format!("user:{}", user_id);
        let cached = self.cache.get(&key).await
            .map_err(|e| Status::internal(format!("Cache error: {}", e)))?;

        Ok(cached.and_then(|json| serde_json::from_str(&json).ok()))
    }

    async fn cache_user(&self, user: &UserModel) -> Result<(), Status> {
        let key = format!("user:{}", user.id);
        let json = serde_json::to_string(user)
            .map_err(|e| Status::internal(format!("Serialization error: {}", e)))?;

        self.cache.set_ex(&key, &json, 3600).await  // 1 hour TTL
            .map_err(|e| Status::internal(format!("Cache error: {}", e)))?;

        Ok(())
    }
}
```

**任务**:
- [ ] 实现 3 个 gRPC 方法
- [ ] 添加 Redis 缓存层
- [ ] 单元测试覆盖率 > 80%
- [ ] 集成测试 (gRPC 客户端调用)
- [ ] 性能测试 (目标: < 50ms p95)

---

#### [ ] 1.3 实现事件发布

**文件**: `backend/auth-service/src/events/user_events.rs`

```rust
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "event_type")]
pub enum UserEvent {
    UserCreated(UserCreatedEvent),
    UserUpdated(UserUpdatedEvent),
    UserDeleted(UserDeletedEvent),
}

#[derive(Debug, Serialize, Deserialize)]
pub struct UserCreatedEvent {
    pub user_id: Uuid,
    pub username: String,
    pub email: String,
    pub display_name: Option<String>,
    pub avatar_url: Option<String>,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct UserUpdatedEvent {
    pub user_id: Uuid,
    pub username: Option<String>,
    pub email: Option<String>,
    pub display_name: Option<String>,
    pub avatar_url: Option<String>,
    pub updated_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct UserDeletedEvent {
    pub user_id: Uuid,
    pub deleted_at: chrono::DateTime<chrono::Utc>,
}

pub async fn publish_user_event(
    event: UserEvent,
    kafka_producer: &FutureProducer,
) -> Result<(), Box<dyn std::error::Error>> {
    let topic = "nova.user.events";
    let key = match &event {
        UserEvent::UserCreated(e) => e.user_id.to_string(),
        UserEvent::UserUpdated(e) => e.user_id.to_string(),
        UserEvent::UserDeleted(e) => e.user_id.to_string(),
    };
    let payload = serde_json::to_string(&event)?;

    kafka_producer
        .send(
            FutureRecord::to(topic)
                .key(&key)
                .payload(&payload),
            Duration::from_secs(5),
        )
        .await
        .map_err(|(err, _)| err)?;

    tracing::info!(
        event_type = ?event,
        "Published user event to Kafka"
    );

    Ok(())
}
```

**修改用户创建/更新/删除函数**:
```rust
// 示例: 用户创建
pub async fn create_user(
    db_pool: &PgPool,
    kafka_producer: &FutureProducer,
    input: CreateUserInput,
) -> Result<User, Error> {
    // 1. 插入数据库
    let user = sqlx::query_as!(
        UserModel,
        r#"INSERT INTO users (...) VALUES (...) RETURNING *"#,
        // ...
    )
    .fetch_one(db_pool)
    .await?;

    // 2. 发布事件
    publish_user_event(
        UserEvent::UserCreated(UserCreatedEvent {
            user_id: user.id,
            username: user.username.clone(),
            email: user.email.clone(),
            display_name: user.display_name.clone(),
            avatar_url: user.avatar_url.clone(),
            created_at: user.created_at,
        }),
        kafka_producer,
    )
    .await?;

    Ok(user.into())
}
```

**任务**:
- [ ] 定义事件结构
- [ ] 实现 Kafka 发布逻辑
- [ ] 修改 CRUD 函数以发布事件
- [ ] 测试事件发布 (消费端验证)

---

### [ ] Week 2: 其他服务集成

**负责人**: Backend Engineer #2

#### [ ] 2.1 user-service 集成

**文件**: `backend/user-service/src/clients/auth_client.rs`

```rust
use proto::auth_service_client::AuthServiceClient;
use tonic::transport::Channel;

pub struct AuthClient {
    client: AuthServiceClient<Channel>,
}

impl AuthClient {
    pub async fn new(endpoint: &str) -> Result<Self, Box<dyn std::error::Error>> {
        let client = AuthServiceClient::connect(endpoint.to_string()).await?;
        Ok(Self { client })
    }

    pub async fn get_user(&mut self, user_id: Uuid) -> Result<User, Status> {
        let request = Request::new(GetUserRequest {
            user_id: user_id.to_string(),
        });

        let response = self.client.get_user(request).await?;
        response.into_inner().user.ok_or_else(|| Status::not_found("User not found"))
    }

    pub async fn check_user_exists(&mut self, user_id: Uuid) -> Result<bool, Status> {
        let request = Request::new(CheckUserExistsRequest {
            user_id: user_id.to_string(),
        });

        let response = self.client.check_user_exists(request).await?;
        Ok(response.into_inner().exists)
    }
}
```

**修改现有代码**:
```rust
// 旧代码 (直接查询 nova_staging.users)
let user = sqlx::query_as!(
    UserModel,
    "SELECT * FROM users WHERE id = $1",
    user_id
)
.fetch_one(&db_pool)
.await?;

// 新代码 (通过 gRPC 调用 auth-service)
let user = auth_client.get_user(user_id).await?;
```

**任务**:
- [ ] 创建 auth-service gRPC 客户端
- [ ] 替换所有直接查询 `users` 表的代码
- [ ] 添加重试逻辑 (失败时降级到缓存)
- [ ] 测试客户端调用

---

#### [ ] 2.2 订阅 Kafka 事件

**文件**: `backend/user-service/src/events/user_event_handler.rs`

```rust
use rdkafka::consumer::{Consumer, StreamConsumer};
use rdkafka::Message;

pub async fn start_user_event_consumer(
    kafka_consumer: Arc<StreamConsumer>,
    db_pool: PgPool,
) {
    kafka_consumer.subscribe(&["nova.user.events"]).unwrap();

    loop {
        match kafka_consumer.recv().await {
            Ok(message) => {
                if let Some(payload) = message.payload_view::<str>() {
                    match payload {
                        Ok(json) => {
                            if let Err(e) = handle_user_event(json, &db_pool).await {
                                tracing::error!(
                                    error = ?e,
                                    "Failed to handle user event"
                                );
                            }
                        }
                        Err(e) => {
                            tracing::error!(error = ?e, "Invalid UTF-8 payload");
                        }
                    }
                }
            }
            Err(e) => {
                tracing::error!(error = ?e, "Kafka consumer error");
            }
        }
    }
}

async fn handle_user_event(
    json: &str,
    db_pool: &PgPool,
) -> Result<(), Box<dyn std::error::Error>> {
    let event: UserEvent = serde_json::from_str(json)?;

    match event {
        UserEvent::UserCreated(e) => {
            // 插入 user_cache 表
            sqlx::query!(
                r#"
                INSERT INTO user_cache (user_id, username, email, display_name, avatar_url, updated_at)
                VALUES ($1, $2, $3, $4, $5, $6)
                ON CONFLICT (user_id) DO UPDATE SET
                  username = EXCLUDED.username,
                  email = EXCLUDED.email,
                  display_name = EXCLUDED.display_name,
                  avatar_url = EXCLUDED.avatar_url,
                  updated_at = EXCLUDED.updated_at
                "#,
                e.user_id,
                e.username,
                e.email,
                e.display_name,
                e.avatar_url,
                e.created_at
            )
            .execute(db_pool)
            .await?;

            tracing::info!(user_id = %e.user_id, "Cached user from UserCreated event");
        }
        UserEvent::UserUpdated(e) => {
            // 更新 user_cache 表
            sqlx::query!(
                r#"
                UPDATE user_cache
                SET username = COALESCE($2, username),
                    email = COALESCE($3, email),
                    display_name = COALESCE($4, display_name),
                    avatar_url = COALESCE($5, avatar_url),
                    updated_at = $6
                WHERE user_id = $1
                "#,
                e.user_id,
                e.username,
                e.email,
                e.display_name,
                e.avatar_url,
                e.updated_at
            )
            .execute(db_pool)
            .await?;

            tracing::info!(user_id = %e.user_id, "Updated user cache from UserUpdated event");
        }
        UserEvent::UserDeleted(e) => {
            // 软删除 user_cache
            sqlx::query!(
                r#"
                UPDATE user_cache
                SET deleted_at = $2
                WHERE user_id = $1
                "#,
                e.user_id,
                e.deleted_at
            )
            .execute(db_pool)
            .await?;

            tracing::info!(user_id = %e.user_id, "Soft-deleted user cache from UserDeleted event");
        }
    }

    Ok(())
}
```

**创建 user_cache 表**:
```sql
-- backend/user-service/migrations/0002_create_user_cache.sql
CREATE TABLE user_cache (
  user_id UUID PRIMARY KEY,
  username VARCHAR(255) NOT NULL,
  email VARCHAR(255) NOT NULL,
  display_name VARCHAR(255),
  avatar_url TEXT,
  updated_at TIMESTAMPTZ NOT NULL,
  deleted_at TIMESTAMPTZ,
  synced_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_user_cache_username ON user_cache(username) WHERE deleted_at IS NULL;
CREATE INDEX idx_user_cache_email ON user_cache(email) WHERE deleted_at IS NULL;
```

**任务**:
- [ ] 创建 user_cache 表
- [ ] 实现 Kafka 消费者
- [ ] 测试事件处理逻辑
- [ ] 监控同步延迟 (目标: < 1s p95)

---

#### [ ] 2.3 删除 nova_staging.users 表

**⚠️ 警告**: 这是不可逆操作,确保所有测试通过

**前置条件**:
- [ ] auth-service gRPC API 已上线
- [ ] 所有服务已迁移到 gRPC 调用
- [ ] user_cache 表数据已同步
- [ ] 生产环境测试通过

**迁移脚本**: `backend/migrations/0010_drop_staging_users.sql`

```sql
-- 1. 备份表数据
CREATE TABLE users_backup AS SELECT * FROM users;

-- 2. 验证数据一致性
DO $$
DECLARE
  auth_count INTEGER;
  staging_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO auth_count FROM nova_auth.users;
  SELECT COUNT(*) INTO staging_count FROM nova_staging.users_backup;

  IF auth_count != staging_count THEN
    RAISE EXCEPTION 'User count mismatch: auth=%, staging=%', auth_count, staging_count;
  END IF;

  RAISE NOTICE 'Data validation passed: % users', auth_count;
END $$;

-- 3. 删除外键约束
ALTER TABLE user_profiles DROP CONSTRAINT fk_user_profiles_user;
ALTER TABLE user_settings DROP CONSTRAINT user_settings_user_id_fkey;
ALTER TABLE user_relationships DROP CONSTRAINT user_relationships_follower_id_fkey;
ALTER TABLE user_relationships DROP CONSTRAINT user_relationships_followee_id_fkey;
ALTER TABLE activity_logs DROP CONSTRAINT activity_logs_user_id_fkey;
ALTER TABLE reports DROP CONSTRAINT reports_reporter_id_fkey;
ALTER TABLE reports DROP CONSTRAINT reports_reported_user_id_fkey;
ALTER TABLE search_history DROP CONSTRAINT search_history_user_id_fkey;
ALTER TABLE search_suggestions DROP CONSTRAINT search_suggestions_user_id_fkey;
ALTER TABLE moderation_queue DROP CONSTRAINT moderation_queue_assigned_to_fkey;
ALTER TABLE moderation_actions DROP CONSTRAINT moderation_actions_moderator_id_fkey;
ALTER TABLE moderation_appeals DROP CONSTRAINT moderation_appeals_user_id_fkey;
ALTER TABLE moderation_appeals DROP CONSTRAINT moderation_appeals_reviewed_by_fkey;

-- 4. 删除 users 表
DROP TABLE users CASCADE;

-- 5. 记录删除事件
INSERT INTO migration_log (migration_name, executed_at, notes)
VALUES ('drop_staging_users', NOW(), 'Deleted nova_staging.users table after migrating to auth-service API');
```

**回滚脚本**: `backend/migrations/rollback_0010_drop_staging_users.sql`

```sql
-- 恢复 users 表
CREATE TABLE users AS SELECT * FROM users_backup;

-- 恢复外键约束
ALTER TABLE user_profiles
  ADD CONSTRAINT fk_user_profiles_user
  FOREIGN KEY (id) REFERENCES users(id) ON DELETE CASCADE;

-- (重复所有外键约束)

-- 删除备份表
DROP TABLE users_backup;
```

**执行步骤**:
```bash
# 1. 在测试环境验证
kubectl exec -n nova-staging postgres-... -- psql -U postgres -d nova_staging -f /migrations/0010_drop_staging_users.sql

# 2. 运行集成测试
cargo test --all

# 3. 在生产环境执行 (维护窗口)
kubectl exec -n nova postgres-... -- psql -U postgres -d nova_staging -f /migrations/0010_drop_staging_users.sql

# 4. 监控错误日志
kubectl logs -n nova -l app=user-service --tail=100 -f
```

**任务**:
- [ ] 编写迁移脚本
- [ ] 编写回滚脚本
- [ ] 测试环境验证
- [ ] 生产环境执行

---

## 📋 Week 3-6: 数据库拆分

### [ ] Week 3: 创建新数据库

**负责人**: DevOps Engineer

#### [ ] 3.1 创建数据库实例

**基础设施代码**: `infrastructure/terraform/databases.tf`

```hcl
# nova_user 数据库
resource "aws_db_instance" "nova_user" {
  identifier           = "nova-user-db"
  engine               = "postgres"
  engine_version       = "16.3"
  instance_class       = "db.t3.medium"
  allocated_storage    = 100
  storage_type         = "gp3"
  storage_encrypted    = true

  db_name  = "nova_user"
  username = var.db_username
  password = var.db_password

  vpc_security_group_ids = [aws_security_group.nova_db.id]
  db_subnet_group_name   = aws_db_subnet_group.nova.name

  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "Mon:04:00-Mon:05:00"

  skip_final_snapshot       = false
  final_snapshot_identifier = "nova-user-db-final-snapshot"

  tags = {
    Name        = "nova-user-database"
    Environment = "production"
    Service     = "user-service"
  }
}

# nova_moderation 数据库
resource "aws_db_instance" "nova_moderation" {
  identifier           = "nova-moderation-db"
  engine               = "postgres"
  engine_version       = "16.3"
  instance_class       = "db.t3.small"
  allocated_storage    = 50
  storage_type         = "gp3"
  storage_encrypted    = true

  db_name  = "nova_moderation"
  username = var.db_username
  password = var.db_password

  vpc_security_group_ids = [aws_security_group.nova_db.id]
  db_subnet_group_name   = aws_db_subnet_group.nova.name

  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "Mon:04:00-Mon:05:00"

  skip_final_snapshot       = false
  final_snapshot_identifier = "nova-moderation-db-final-snapshot"

  tags = {
    Name        = "nova-moderation-database"
    Environment = "production"
    Service     = "moderation-service"
  }
}

# 重复其他数据库 (nova_search, nova_audit, nova_events)
```

**任务**:
- [ ] 定义 Terraform 资源
- [ ] 创建数据库实例 (测试环境)
- [ ] 验证连接性
- [ ] 创建生产环境实例

---

#### [ ] 3.2 迁移表结构

**迁移脚本**: `backend/scripts/migrate_tables.sh`

```bash
#!/bin/bash
set -e

SOURCE_DB="nova_staging"
TARGET_DB="nova_user"
TABLES=("user_profiles" "user_settings" "user_relationships")

for table in "${TABLES[@]}"; do
  echo "=== Migrating $table ==="

  # 1. 导出表结构
  pg_dump -U postgres -h $SOURCE_HOST -d $SOURCE_DB \
    -t $table --schema-only > /tmp/${table}_schema.sql

  # 2. 导入到新数据库
  psql -U postgres -h $TARGET_HOST -d $TARGET_DB \
    -f /tmp/${table}_schema.sql

  # 3. 复制数据
  pg_dump -U postgres -h $SOURCE_HOST -d $SOURCE_DB \
    -t $table --data-only > /tmp/${table}_data.sql

  psql -U postgres -h $TARGET_HOST -d $TARGET_DB \
    -f /tmp/${table}_data.sql

  # 4. 验证行数
  SOURCE_COUNT=$(psql -U postgres -h $SOURCE_HOST -d $SOURCE_DB \
    -t -c "SELECT COUNT(*) FROM $table")

  TARGET_COUNT=$(psql -U postgres -h $TARGET_HOST -d $TARGET_DB \
    -t -c "SELECT COUNT(*) FROM $table")

  if [ "$SOURCE_COUNT" != "$TARGET_COUNT" ]; then
    echo "❌ Row count mismatch for $table: source=$SOURCE_COUNT, target=$TARGET_COUNT"
    exit 1
  fi

  echo "✅ Migrated $table: $SOURCE_COUNT rows"
done

echo "=== Migration Complete ==="
```

**任务**:
- [ ] 迁移 user-service 表
- [ ] 迁移 moderation-service 表
- [ ] 迁移 search-service 表
- [ ] 验证数据完整性

---

### [ ] Week 4-5: 双写实现

**负责人**: Backend Engineer #1

#### [ ] 4.1 实现双写逻辑

**文件**: `backend/user-service/src/repository/dual_write.rs`

```rust
pub struct DualWriteRepository {
    old_pool: PgPool,  // nova_staging
    new_pool: PgPool,  // nova_user
    feature_flag: Arc<FeatureFlags>,
}

impl DualWriteRepository {
    pub async fn insert_user_profile(
        &self,
        profile: &UserProfile,
    ) -> Result<(), Error> {
        // 1. 写入旧数据库 (必须成功)
        sqlx::query!(
            "INSERT INTO user_profiles (...) VALUES (...)",
            // ...
        )
        .execute(&self.old_pool)
        .await?;

        // 2. 写入新数据库 (可失败,记录错误)
        if let Err(e) = sqlx::query!(
            "INSERT INTO user_profiles (...) VALUES (...)",
            // ...
        )
        .execute(&self.new_pool)
        .await
        {
            tracing::error!(
                error = ?e,
                profile_id = %profile.id,
                "Failed to write to new database"
            );

            // 记录到对账表
            self.record_sync_failure(profile.id, "insert").await?;
        }

        Ok(())
    }

    pub async fn read_user_profile(
        &self,
        profile_id: Uuid,
    ) -> Result<UserProfile, Error> {
        // 根据特性开关决定读取哪个数据库
        if self.feature_flag.is_enabled("use_new_user_db") {
            self.read_from_new_db(profile_id).await
        } else {
            self.read_from_old_db(profile_id).await
        }
    }
}
```

**对账表**:
```sql
CREATE TABLE dual_write_sync_failures (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type VARCHAR(50) NOT NULL,
  entity_id UUID NOT NULL,
  operation VARCHAR(20) NOT NULL,  -- insert, update, delete
  error_message TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  resolved_at TIMESTAMPTZ
);

CREATE INDEX idx_sync_failures_unresolved
  ON dual_write_sync_failures(entity_type, created_at)
  WHERE resolved_at IS NULL;
```

**任务**:
- [ ] 实现双写 Repository
- [ ] 添加特性开关
- [ ] 创建对账表
- [ ] 测试双写逻辑

---

#### [ ] 4.2 数据对账脚本

**文件**: `backend/scripts/reconcile_dual_write.sh`

```bash
#!/bin/bash
set -e

echo "=== Dual Write Data Reconciliation ==="

OLD_DB="nova_staging"
NEW_DB="nova_user"

# 检查未解决的同步失败
FAILURES=$(psql -U postgres -d $NEW_DB -t -c "
  SELECT COUNT(*)
  FROM dual_write_sync_failures
  WHERE resolved_at IS NULL
")

echo "Unresolved sync failures: $FAILURES"

if [ "$FAILURES" -gt 0 ]; then
  # 对账并修复
  psql -U postgres -d $NEW_DB -c "
    SELECT entity_type, entity_id, operation, error_message
    FROM dual_write_sync_failures
    WHERE resolved_at IS NULL
    ORDER BY created_at DESC
    LIMIT 100
  "

  # 手动修复或自动重试
  # ...
fi

# 验证数据一致性
for table in user_profiles user_settings user_relationships; do
  OLD_COUNT=$(psql -U postgres -h $OLD_HOST -d $OLD_DB -t -c "SELECT COUNT(*) FROM $table")
  NEW_COUNT=$(psql -U postgres -h $NEW_HOST -d $NEW_DB -t -c "SELECT COUNT(*) FROM $table")

  if [ "$OLD_COUNT" != "$NEW_COUNT" ]; then
    echo "❌ $table: old=$OLD_COUNT, new=$NEW_COUNT (mismatch!)"
  else
    echo "✅ $table: $OLD_COUNT rows"
  fi
done

echo "=== Reconciliation Complete ==="
```

**Cron 定时任务**:
```yaml
# k8s/cronjobs/dual-write-reconcile.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: dual-write-reconcile
  namespace: nova
spec:
  schedule: "*/5 * * * *"  # 每 5 分钟
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: reconcile
            image: postgres:16
            command: ["/scripts/reconcile_dual_write.sh"]
            volumeMounts:
            - name: scripts
              mountPath: /scripts
          restartPolicy: OnFailure
          volumes:
          - name: scripts
            configMap:
              name: reconcile-scripts
```

**任务**:
- [ ] 编写对账脚本
- [ ] 创建 CronJob
- [ ] 测试对账逻辑
- [ ] 监控对账结果

---

### [ ] Week 6: 流量切换

**负责人**: DevOps Engineer

#### [ ] 6.1 逐步增加新数据库流量

**特性开关配置**:
```yaml
# backend/user-service/config/feature_flags.yaml
feature_flags:
  use_new_user_db:
    enabled: true
    rollout_percentage: 10  # 开始时 10%
    whitelist_user_ids:     # 内部测试用户
      - "uuid-1"
      - "uuid-2"
```

**监控指标**:
```promql
# 查询延迟对比
histogram_quantile(0.95,
  rate(user_service_query_duration_seconds_bucket{db="old"}[5m])
) vs
histogram_quantile(0.95,
  rate(user_service_query_duration_seconds_bucket{db="new"}[5m])
)

# 错误率对比
rate(user_service_query_errors_total{db="old"}[5m]) vs
rate(user_service_query_errors_total{db="new"}[5m])
```

**切换计划**:
```
Day 1: 10% 流量 → 观察 24 小时
Day 3: 25% 流量 → 观察 24 小时
Day 5: 50% 流量 → 观察 48 小时
Day 8: 75% 流量 → 观察 24 小时
Day 10: 100% 流量 → 观察 1 周
```

**任务**:
- [ ] 配置特性开关
- [ ] 设置监控仪表板
- [ ] 逐步增加流量百分比
- [ ] 验证性能指标

---

#### [ ] 6.2 停止双写并清理

**⚠️ 警告**: 确保 100% 流量已切换到新数据库

**前置条件**:
- [ ] 新数据库流量 = 100% (持续 1 周)
- [ ] 无对账失败记录
- [ ] 性能指标正常

**清理步骤**:
```bash
# 1. 停止双写 (修改代码)
# 移除 DualWriteRepository,使用 SingleWriteRepository

# 2. 删除旧表 (保留备份 2 周)
psql -U postgres -d nova_staging -c "
  CREATE TABLE user_profiles_backup AS SELECT * FROM user_profiles;
  DROP TABLE user_profiles;
"

# 3. 清理对账表
psql -U postgres -d nova_user -c "
  DELETE FROM dual_write_sync_failures
  WHERE resolved_at IS NOT NULL
    AND resolved_at < NOW() - INTERVAL '30 days';
"
```

**任务**:
- [ ] 移除双写逻辑
- [ ] 删除旧表 (保留备份)
- [ ] 清理对账数据
- [ ] 更新文档

---

## 📋 Week 7-8: 消除外键 + Saga

### [ ] Week 7: 删除跨服务外键

**负责人**: Backend Engineer #2

#### [ ] 7.1 识别并删除外键约束

**脚本**: `backend/scripts/drop_cross_service_fks.sql`

```sql
-- 1. 备份外键信息
CREATE TABLE fk_backup AS
SELECT
  tc.table_name,
  kcu.column_name,
  tc.constraint_name,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name,
  rc.delete_rule
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
JOIN information_schema.referential_constraints AS rc
  ON rc.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY';

-- 2. 删除跨服务外键 (nova_moderation.reports)
ALTER TABLE reports DROP CONSTRAINT reports_reporter_id_fkey;
ALTER TABLE reports DROP CONSTRAINT reports_reported_user_id_fkey;

-- 3. 添加索引以保持查询性能
CREATE INDEX idx_reports_reporter_id ON reports(reporter_id);
CREATE INDEX idx_reports_reported_user_id ON reports(reported_user_id);

-- 4. 重复其他跨服务外键
-- activity_logs, search_history, moderation_queue, etc.
```

**任务**:
- [ ] 备份外键信息
- [ ] 删除所有跨服务外键
- [ ] 添加索引
- [ ] 验证查询性能

---

#### [ ] 7.2 应用层验证

**文件**: `backend/moderation-service/src/validators/user_validator.rs`

```rust
use proto::auth_service_client::AuthServiceClient;

pub struct UserValidator {
    auth_client: AuthServiceClient<Channel>,
}

impl UserValidator {
    pub async fn validate_user_exists(
        &mut self,
        user_id: Uuid,
    ) -> Result<(), Error> {
        let exists = self.auth_client
            .check_user_exists(CheckUserExistsRequest {
                user_id: user_id.to_string(),
            })
            .await
            .map_err(|e| Error::AuthServiceUnavailable(e.to_string()))?
            .into_inner()
            .exists;

        if !exists {
            return Err(Error::UserNotFound(user_id));
        }

        Ok(())
    }
}

// 使用示例
pub async fn create_report(
    validator: &mut UserValidator,
    input: CreateReportInput,
) -> Result<Report, Error> {
    // 1. 验证用户存在 (替代外键约束)
    validator.validate_user_exists(input.reporter_id).await?;
    validator.validate_user_exists(input.reported_user_id).await?;

    // 2. 插入 report
    let report = sqlx::query_as!(
        ReportModel,
        r#"
        INSERT INTO reports (reporter_id, reported_user_id, ...)
        VALUES ($1, $2, ...)
        RETURNING *
        "#,
        input.reporter_id,
        input.reported_user_id,
        // ...
    )
    .fetch_one(&db_pool)
    .await?;

    Ok(report.into())
}
```

**任务**:
- [ ] 实现 UserValidator
- [ ] 替换所有依赖外键的代码
- [ ] 添加降级逻辑 (auth-service 不可用时)
- [ ] 测试验证逻辑

---

### [ ] Week 8: Saga 模式实现

**负责人**: Backend Engineer #1 + #2

#### [ ] 8.1 Saga 框架

**文件**: `backend/libs/saga/src/lib.rs`

```rust
use async_trait::async_trait;
use std::collections::HashMap;
use std::sync::Arc;

#[async_trait]
pub trait SagaStep: Send + Sync {
    async fn execute(&self) -> Result<(), Box<dyn std::error::Error>>;
    async fn compensate(&self) -> Result<(), Box<dyn std::error::Error>>;
}

pub struct Saga {
    name: String,
    aggregate_id: Uuid,
    steps: Vec<Box<dyn SagaStep>>,
    state: SagaState,
}

#[derive(Debug, Clone)]
pub enum SagaState {
    Pending,
    Running,
    Completed,
    Compensating,
    Failed,
}

impl Saga {
    pub fn new(name: &str, aggregate_id: Uuid) -> Self {
        Self {
            name: name.to_string(),
            aggregate_id,
            steps: Vec::new(),
            state: SagaState::Pending,
        }
    }

    pub fn add_step(&mut self, step: Box<dyn SagaStep>) {
        self.steps.push(step);
    }

    pub async fn execute(&mut self) -> Result<(), SagaError> {
        self.state = SagaState::Running;
        let mut completed_steps = 0;

        for (i, step) in self.steps.iter().enumerate() {
            match step.execute().await {
                Ok(_) => {
                    completed_steps += 1;
                    tracing::info!(
                        saga = %self.name,
                        step = i,
                        "Saga step completed"
                    );
                }
                Err(e) => {
                    tracing::error!(
                        saga = %self.name,
                        step = i,
                        error = ?e,
                        "Saga step failed, starting compensation"
                    );

                    self.state = SagaState::Compensating;
                    self.compensate(completed_steps).await?;

                    self.state = SagaState::Failed;
                    return Err(SagaError::StepFailed {
                        step: i,
                        error: e.to_string(),
                    });
                }
            }
        }

        self.state = SagaState::Completed;
        Ok(())
    }

    async fn compensate(&self, steps_to_compensate: usize) -> Result<(), SagaError> {
        for i in (0..steps_to_compensate).rev() {
            if let Err(e) = self.steps[i].compensate().await {
                tracing::error!(
                    saga = %self.name,
                    step = i,
                    error = ?e,
                    "Compensation failed"
                );

                return Err(SagaError::CompensationFailed {
                    step: i,
                    error: e.to_string(),
                });
            }
        }

        Ok(())
    }
}

#[derive(Debug, thiserror::Error)]
pub enum SagaError {
    #[error("Saga step {step} failed: {error}")]
    StepFailed { step: usize, error: String },

    #[error("Compensation for step {step} failed: {error}")]
    CompensationFailed { step: usize, error: String },
}
```

**任务**:
- [ ] 实现 Saga 框架
- [ ] 添加状态持久化 (saga_state 表)
- [ ] 添加重试逻辑
- [ ] 单元测试

---

#### [ ] 8.2 用户删除 Saga

**文件**: `backend/user-service/src/sagas/delete_user_saga.rs`

```rust
use saga::{Saga, SagaStep};

struct SoftDeleteUserProfileStep {
    user_id: Uuid,
    db_pool: PgPool,
}

#[async_trait]
impl SagaStep for SoftDeleteUserProfileStep {
    async fn execute(&self) -> Result<(), Box<dyn std::error::Error>> {
        sqlx::query!(
            "UPDATE user_profiles SET deleted_at = NOW() WHERE id = $1",
            self.user_id
        )
        .execute(&self.db_pool)
        .await?;

        Ok(())
    }

    async fn compensate(&self) -> Result<(), Box<dyn std::error::Error>> {
        sqlx::query!(
            "UPDATE user_profiles SET deleted_at = NULL WHERE id = $1",
            self.user_id
        )
        .execute(&self.db_pool)
        .await?;

        Ok(())
    }
}

struct ArchiveUserReportsStep {
    user_id: Uuid,
    moderation_client: ModerationServiceClient<Channel>,
}

#[async_trait]
impl SagaStep for ArchiveUserReportsStep {
    async fn execute(&self) -> Result<(), Box<dyn std::error::Error>> {
        self.moderation_client
            .archive_user_reports(ArchiveUserReportsRequest {
                user_id: self.user_id.to_string(),
            })
            .await?;

        Ok(())
    }

    async fn compensate(&self) -> Result<(), Box<dyn std::error::Error>> {
        self.moderation_client
            .restore_user_reports(RestoreUserReportsRequest {
                user_id: self.user_id.to_string(),
            })
            .await?;

        Ok(())
    }
}

pub async fn delete_user_saga(
    user_id: Uuid,
    db_pool: PgPool,
    moderation_client: ModerationServiceClient<Channel>,
    search_client: SearchServiceClient<Channel>,
    auth_client: AuthServiceClient<Channel>,
) -> Result<(), SagaError> {
    let mut saga = Saga::new("delete_user", user_id);

    // Step 1: 软删除用户资料
    saga.add_step(Box::new(SoftDeleteUserProfileStep {
        user_id,
        db_pool: db_pool.clone(),
    }));

    // Step 2: 归档审核数据
    saga.add_step(Box::new(ArchiveUserReportsStep {
        user_id,
        moderation_client,
    }));

    // Step 3: 删除搜索历史
    saga.add_step(Box::new(DeleteUserSearchHistoryStep {
        user_id,
        search_client,
    }));

    // Step 4: 删除认证账户 (最后一步,不可回滚)
    saga.add_step(Box::new(DeleteAuthAccountStep {
        user_id,
        auth_client,
    }));

    saga.execute().await
}
```

**任务**:
- [ ] 实现用户删除 Saga
- [ ] 实现所有 Saga Steps
- [ ] 测试正常流程
- [ ] 测试补偿流程

---

#### [ ] 8.3 Saga 状态持久化

**表结构**:
```sql
CREATE TABLE saga_state (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  saga_name VARCHAR(100) NOT NULL,
  aggregate_id UUID NOT NULL,
  state VARCHAR(50) NOT NULL,
  current_step INTEGER NOT NULL DEFAULT 0,
  total_steps INTEGER NOT NULL,
  error_message TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ
);

CREATE INDEX idx_saga_state_pending
  ON saga_state(state, created_at)
  WHERE state = 'Running';

CREATE INDEX idx_saga_state_failed
  ON saga_state(state, created_at)
  WHERE state = 'Failed';
```

**后台重试任务**:
```rust
pub async fn retry_failed_sagas(db_pool: PgPool) {
    loop {
        let failed_sagas = sqlx::query_as!(
            SagaStateModel,
            r#"
            SELECT *
            FROM saga_state
            WHERE state = 'Failed'
              AND created_at > NOW() - INTERVAL '24 hours'
            ORDER BY created_at
            LIMIT 10
            "#
        )
        .fetch_all(&db_pool)
        .await
        .unwrap_or_default();

        for saga_state in failed_sagas {
            tracing::info!(
                saga_id = %saga_state.id,
                saga_name = %saga_state.saga_name,
                "Retrying failed saga"
            );

            // 重建 Saga 并重试
            // ...
        }

        tokio::time::sleep(Duration::from_secs(60)).await;
    }
}
```

**任务**:
- [ ] 创建 saga_state 表
- [ ] 实现状态持久化
- [ ] 实现后台重试任务
- [ ] 监控 Saga 成功率

---

## ✅ 验收标准

### 技术指标

- [ ] 每个服务独立拥有数据库
- [ ] 零跨服务外键约束
- [ ] 事件同步延迟 < 1s (p95)
- [ ] 查询性能 < 100ms (p95)
- [ ] 数据一致性 > 99.99%
- [ ] Saga 成功率 > 99%

### 业务指标

- [ ] 零数据丢失
- [ ] 零停机迁移
- [ ] 用户体验无降级
- [ ] 成本增加 < $1000/月

### 文档完整性

- [ ] 技术设计文档 (TDD)
- [ ] API 规范 (Protobuf)
- [ ] 迁移 Runbook
- [ ] 回滚 Playbook
- [ ] 监控仪表板
- [ ] 告警规则

---

## 📞 联系方式

### 项目团队

- **项目经理**: [姓名] (Slack: @pm)
- **Backend Lead**: [姓名] (Slack: @backend-lead)
- **DevOps Lead**: [姓名] (Slack: @devops-lead)

### 关键会议

- **每日站会**: 10:00 AM (15 分钟)
- **周中审查**: 每周三 14:00 (1 小时)
- **周末回顾**: 每周五 16:00 (1 小时)

---

**最后更新**: 2025-11-11
**下次审查**: Week 2 Checkpoint (2025-11-25)
