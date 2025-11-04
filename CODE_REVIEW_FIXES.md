# Phase 1 Week 3-4 代码审查修复指南

**日期**: November 4, 2025
**审查结果**: 5-6/10 (基础正确,但有生产级别问题)
**紧急程度**: 🔴 P0问题必须在生产部署前修复

---

## 📋 P0 问题 (立即修复)

### P0-1: SQL注入风险 - 字符串拼接构建SQL

**文件**: `backend/messaging-service/src/grpc/mod.rs`
**行数**: Line 47-56
**严重性**: 🔴 Critical

#### 当前代码 (错误)
```rust
let deleted_clause = if req.include_deleted {
    "".to_string()
} else {
    "AND deleted_at IS NULL".to_string()
};

let total_count: i64 = sqlx::query_scalar(
    &format!(
        "SELECT COUNT(*) FROM messages WHERE conversation_id = $1 {}",
        deleted_clause
    ),
)
```

#### 问题分析
- 虽然当前的`deleted_clause`是硬编码的,但**这种模式本身就是错误的**
- 任何未来的修改都可能引入SQL注入
- 这会在代码审查中被拒绝

#### 修复方案
```rust
// 方案 1: 分离SQL语句
async fn get_messages_internal(
    &self,
    conversation_id: &str,
    limit: i64,
    offset: i64,
    include_deleted: bool,
) -> Result<Vec<Message>, Status> {
    let query_str = if include_deleted {
        "SELECT ... FROM messages WHERE conversation_id = $1 ORDER BY created_at DESC LIMIT $2 OFFSET $3"
    } else {
        "SELECT ... FROM messages WHERE conversation_id = $1 AND deleted_at IS NULL ORDER BY created_at DESC LIMIT $2 OFFSET $3"
    };

    let rows = sqlx::query(query_str)
        .bind(conversation_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.state.db)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "Failed to fetch messages");
            Status::internal("Database error")
        })?;

    // 构建响应...
}

// 然后在get_messages中调用:
self.get_messages_internal(&conversation_id, limit, offset, req.include_deleted).await
```

#### 代码检查清单
- [ ] 检查所有sqlx::query中是否有format!宏
- [ ] 检查是否有任何字符串拼接的SQL
- [ ] 验证所有WHERE条件都使用.bind()
- [ ] 运行 `cargo clippy` 检查

---

### P0-2: 错误处理吞掉异常 - unwrap_or_default()

**文件**: `backend/messaging-service/src/grpc/mod.rs`
**行数**: Line 62-63, 82, 100-101, 428-437等
**严重性**: 🔴 Critical

#### 当前代码 (错误)
```rust
let total_count: i64 = sqlx::query_scalar(
    "SELECT COUNT(*) FROM messages WHERE conversation_id = $1 AND deleted_at IS NULL"
)
.bind(&req.conversation_id)
.fetch_one(&self.state.db)
.await
.unwrap_or(0);  // ❌ 数据库错误返回0!
```

#### 问题影响
| 场景 | 当前行为 | 后果 |
|------|---------|------|
| 数据库连接断开 | 返回0 | 用户看到"没有消息" |
| 查询超时 | 返回0 | 列表显示错误 |
| 权限错误 | 返回0 | 安全审计失败 |

#### 修复方案
```rust
let total_count: i64 = sqlx::query_scalar(
    "SELECT COUNT(*) FROM messages WHERE conversation_id = $1 AND deleted_at IS NULL"
)
.bind(&req.conversation_id)
.fetch_one(&self.state.db)
.await
.map_err(|e| {
    tracing::error!(
        error = %e,
        conversation_id = %req.conversation_id,
        "Failed to count messages"
    );
    Status::internal("Failed to retrieve message count")
})?;
```

#### 应用到其他文件
需要查找并修复这些文件中的所有`unwrap_or*()`:
```bash
# 查找所有unwrap_or
grep -n "unwrap_or" backend/messaging-service/src/grpc/mod.rs
grep -n "unwrap_or" backend/user-service/src/grpc/server.rs
grep -n "unwrap_or" backend/messaging-service/src/main.rs
grep -n "unwrap_or" backend/user-service/src/main.rs
```

#### 代码检查清单
- [ ] 替换所有 `unwrap_or(0)`
- [ ] 替换所有 `unwrap_or_default()`
- [ ] 替换所有 `let _ = query.execute(...).await;`
- [ ] 添加结构化日志记录error参数
- [ ] 验证所有错误都返回appropriate Status码

---

### P0-3: N+1查询性能问题

**文件**: `backend/messaging-service/src/grpc/mod.rs`
**行数**: Line 548-562 (list_conversations)
**严重性**: 🔴 Critical

#### 当前代码 (错误)
```rust
async fn list_conversations(
    &self,
    request: Request<ListConversationsRequest>,
) -> Result<Response<ListConversationsResponse>, Status> {
    let req = request.into_inner();

    // 第1次查询
    let conversations = sqlx::query(
        "SELECT * FROM conversations WHERE $1 = ANY(member_ids)
         AND deleted_at IS NULL
         ORDER BY updated_at DESC
         LIMIT $2 OFFSET $3"
    )
    // ...
    .fetch_all(&self.state.db)
    .await?;

    // 第2-N次查询 (每个对话一次!)
    let unread_counts: Vec<i32> = futures::future::join_all(
        conversations.iter().map(|conv| async {
            let count: i64 = sqlx::query_scalar(
                "SELECT COUNT(*) FROM message_reads
                 WHERE user_id = $1 AND conversation_id = $2 AND is_read = false",
            )
            .bind(&req.user_id)
            .bind(&conv.id)
            .fetch_one(&self.state.db)
            .await
            .unwrap_or(0);
            count as i32
        }),
    )
    .await;
    // 问题: 100个对话 = 1 + 100 = 101次数据库往返!
}
```

#### 性能影响
- **查询次数**: 1 (主查询) + N (unread count)
- **延迟**: 100个对话 × 10ms RTT = **1秒以上**
- **连接池耗尽**: 高并发时连接池爆满

#### 修复方案
```rust
async fn list_conversations(
    &self,
    request: Request<ListConversationsRequest>,
) -> Result<Response<ListConversationsResponse>, Status> {
    let req = request.into_inner();

    // 一次查询搞定!
    let rows = sqlx::query(
        r#"
        SELECT
            c.id, c.name, c.updated_at,
            COUNT(CASE WHEN mr.is_read = false THEN 1 END) as unread_count
        FROM conversations c
        LEFT JOIN message_reads mr
            ON mr.conversation_id = c.id
            AND mr.user_id = $1
        WHERE $1 = ANY(c.member_ids)
            AND c.deleted_at IS NULL
        GROUP BY c.id, c.name, c.updated_at
        ORDER BY c.updated_at DESC
        LIMIT $2 OFFSET $3
        "#
    )
    .bind(&req.user_id)
    .bind(req.limit as i64)
    .bind(req.offset as i64)
    .fetch_all(&self.state.db)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "Failed to list conversations");
        Status::internal("Database error")
    })?;

    let conversations = rows.iter().map(|row| {
        Conversation {
            id: row.get("id"),
            name: row.get("name"),
            updated_at: row.get("updated_at"),
            unread_count: row.get("unread_count"),
        }
    }).collect();

    Ok(Response::new(ListConversationsResponse {
        conversations,
        total_count,
    }))
}
```

#### 验证修复
```bash
# 启用SQL日志
RUST_LOG=sqlx=debug cargo test

# 应该只看到1个SELECT,而不是 N+1 个
```

#### 代码检查清单
- [ ] 检查所有返回LIST的RPC方法
- [ ] 确认没有在循环中执行SQL查询
- [ ] 使用JOIN/GROUP BY替代N+1模式
- [ ] 测试with不同的列表大小

---

### P0-4: UpdateUserProfile COALESCE逻辑错误

**文件**: `backend/user-service/src/grpc/server.rs`
**行数**: Line 142-150
**严重性**: 🔴 Critical

#### 当前代码 (错误)
```rust
UPDATE user_profiles
SET
    display_name = COALESCE(NULLIF($2, ''), display_name),
    bio = COALESCE(NULLIF($3, ''), bio),
    is_private = COALESCE(NULLIF($8::boolean, false), is_private),
    // ...
WHERE id = $1
```

#### 问题
| 操作 | 期望 | 实际结果 | 问题 |
|------|------|---------|------|
| 设置 bio = "" | 清空bio | bio保持不变 | NULLIF返回NULL → COALESCE使用旧值 |
| 设置 bio = "Hello" | 更新bio | ✓ 正常 | |
| 设置 is_private = false | 取消私密 | is_private保持不变 | NULLIF(false, false)=NULL → COALESCE使用旧值 |

#### 修复方案

方案 A: 使用Optional字段(推荐)

```rust
// 在proto中定义:
message UpdateUserProfileRequest {
    string user_id = 1;
    optional string display_name = 2;
    optional string bio = 3;
    optional bool is_private = 8;
}

// 在Rust中:
let mut update_fields = vec![];
let mut bindings = vec![];
let mut param_count = 2;

if let Some(display_name) = &req.display_name {
    update_fields.push(format!("display_name = ${}", param_count));
    bindings.push(display_name.clone());
    param_count += 1;
}

if let Some(bio) = &req.bio {
    update_fields.push(format!("bio = ${}", param_count));
    bindings.push(bio.clone());
    param_count += 1;
}

if let Some(is_private) = req.is_private {
    update_fields.push(format!("is_private = ${}", param_count));
    bindings.push(is_private);
    param_count += 1;
}

let update_clause = update_fields.join(", ");
let sql = format!(
    "UPDATE user_profiles SET {}, updated_at = NOW(), version_number = version_number + 1
     WHERE id = $1 AND version_number = ${}",
    update_clause,
    param_count
);
```

#### 代码检查清单
- [ ] 审查所有UPDATE语句的WHERE条件
- [ ] 验证COALESCE用法(仅在设置默认值时使用)
- [ ] 测试设置字段为空值的场景
- [ ] 添加单元测试验证各种更新组合

---

### P0-5: 生产环境迁移错误被忽略

**文件**: `backend/user-service/src/main.rs`
**行数**: Line 120-126
**严重性**: 🔴 Critical

#### 当前代码 (错误)
```rust
match run_migrations(&db_pool).await {
    Ok(_) => tracing::info!("Database migrations completed"),
    Err(e) => {
        // 容忍本地/历史迁移缺口(如 VersionMissing),避免开发环境崩溃
        tracing::warn!("Skipping migrations due to error: {:#}", e);
    }
}
```

#### 问题
- 生产环境数据库Schema和应用代码不匹配
- 应用启动成功,但SQL查询开始失败
- 导致5xx错误暴增,用户无法使用
- 运维看不到明显的启动失败信号

#### 修复方案
```rust
// 检查环境
let app_env = std::env::var("APP_ENV")
    .unwrap_or_else(|_| "development".to_string());

let is_production = app_env == "production" || app_env == "prod";

match run_migrations(&db_pool).await {
    Ok(_) => {
        tracing::info!("Database migrations completed");
    }
    Err(e) => {
        if is_production {
            // 生产环境: 迁移失败 = 致命错误
            tracing::error!(
                error = %e,
                "Database migrations failed in production environment. \
                 Refusing to start. Database schema must match application version."
            );
            std::process::exit(1);
        } else {
            // 开发环境: 给开发者一个警告但继续
            tracing::warn!(
                error = %e,
                "Database migrations failed in development. \
                 The application may not function correctly. \
                 Please run: sqlx migrate run"
            );
        }
    }
}
```

#### Kubernetes配置
在deployment中添加环境变量:
```yaml
env:
  - name: APP_ENV
    value: "production"
```

#### 代码检查清单
- [ ] 区分production和development环境
- [ ] 生产环境迁移失败必须返回非0 exit code
- [ ] 添加清晰的错误日志说明如何修复
- [ ] 测试迁移失败时的启动行为

---

## 🟡 P1 问题 (本周内修复)

### P1-1: 缺少事务处理
**文件**: `backend/messaging-service/src/grpc/mod.rs`
**方法**: `send_message`, `update_message`, `delete_message`

**修复**:
```rust
async fn send_message(&self, request: Request<SendMessageRequest>)
    -> Result<Response<Message>, Status> {
    let req = request.into_inner();

    // 开始事务
    let mut tx = self.state.db.begin().await
        .map_err(|e| {
            tracing::error!(error = %e, "Failed to begin transaction");
            Status::internal("Database error")
        })?;

    // 插入消息
    let message_id = sqlx::query_scalar::<_, String>(
        "INSERT INTO messages (conversation_id, sender_id, content, created_at)
         VALUES ($1, $2, $3, NOW())
         RETURNING id"
    )
    .bind(&req.conversation_id)
    .bind(&req.sender_id)
    .bind(&req.content)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "Failed to insert message");
        Status::internal("Failed to send message")
    })?;

    // 更新会话的updated_at (在同一事务中)
    sqlx::query(
        "UPDATE conversations SET updated_at = NOW() WHERE id = $1"
    )
    .bind(&req.conversation_id)
    .execute(&mut *tx)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "Failed to update conversation");
        Status::internal("Failed to update conversation")
    })?;

    // 提交事务
    tx.commit().await
        .map_err(|e| {
            tracing::error!(error = %e, "Failed to commit transaction");
            Status::internal("Database error")
        })?;

    // 返回响应...
}
```

### P1-2: 缺少真实集成测试
**文件**: `tests/grpc_cross_service_integration_test.rs`

当前的测试全是空壳。需要用真实的gRPC调用替代。

**示例修复**:
```rust
#[tokio::test]
async fn test_user_service_can_get_profile() {
    // 设置测试
    let db = setup_test_database().await;
    let server_handle = start_user_service_test_server(&db).await;

    // 创建测试数据
    let user_id = "test-user-123";
    create_test_user(&db, user_id, "Alice").await;

    // 连接到gRPC服务
    let mut client = UserServiceClient::connect("http://127.0.0.1:9081")
        .await
        .expect("Failed to connect");

    // 调用gRPC方法
    let request = GetUserProfileRequest {
        user_id: user_id.to_string(),
    };

    let response = client.get_user_profile(request)
        .await
        .expect("gRPC call failed");

    // 验证响应
    let profile = response.get_ref().profile.as_ref()
        .expect("Profile should not be empty");
    assert_eq!(profile.id, user_id);
    assert_eq!(profile.username, "Alice");

    // 清理
    cleanup(&db, user_id).await;
    drop(server_handle);
}
```

### P1-3: Follow/Block关系状态机问题
**文件**: `backend/user-service/src/grpc/server.rs`
**方法**: `follow_user`, `block_user`

**修复**:
```rust
async fn follow_user(&self, request: Request<FollowUserRequest>)
    -> Result<Response<RelationshipResponse>, Status> {
    let req = request.into_inner();

    // 防止block关系被覆盖为follow
    sqlx::query(
        r#"
        INSERT INTO user_relationships
            (follower_id, followee_id, relationship_type, status, created_at)
        VALUES ($1, $2, 'follow', 'active', NOW())
        ON CONFLICT (follower_id, followee_id) DO UPDATE SET
            relationship_type = CASE
                WHEN excluded.relationship_type = 'block' THEN 'block'
                ELSE 'follow'
            END,
            status = CASE
                WHEN relationship_type = 'block' THEN 'active'
                ELSE 'active'
            END,
            updated_at = NOW()
        WHERE relationship_type != 'block'  -- 关键: 不覆盖block
        "#
    )
    .bind(&req.follower_id)
    .bind(&req.followee_id)
    .execute(&self.db)
    .await
    .map_err(|e| {
        tracing::error!(error = %e, "Failed to create follow relationship");
        Status::internal("Failed to follow user")
    })?;

    Ok(Response::new(RelationshipResponse { /* ... */ }))
}
```

---

## 📊 修复优先级汇总

| ID | 问题 | 文件 | 优先级 | 修复时间 |
|----|------|------|--------|---------|
| P0-1 | SQL注入 | messaging-service/grpc/mod.rs | 🔴 Critical | 1h |
| P0-2 | 错误掩盖 | messaging-service/grpc/mod.rs | 🔴 Critical | 2h |
| P0-3 | N+1查询 | messaging-service/grpc/mod.rs | 🔴 Critical | 2h |
| P0-4 | COALESCE | user-service/grpc/server.rs | 🔴 Critical | 1h |
| P0-5 | 迁移忽略 | user-service/main.rs | 🔴 Critical | 30min |
| P1-1 | 事务处理 | messaging-service/grpc/mod.rs | 🟡 High | 2h |
| P1-2 | 集成测试 | tests/grpc_*.rs | 🟡 High | 4h |
| P1-3 | 状态机 | user-service/grpc/server.rs | 🟡 High | 1h |

**总修复时间**: P0 = 6.5小时, P1 = 7小时

---

## ✅ 修复验证清单

修复完成后,验证:

- [ ] 所有P0问题都已修复
- [ ] `cargo test` 全部通过
- [ ] `cargo clippy` 无警告
- [ ] `cargo fmt` 通过检查
- [ ] SQL日志中没有N+1查询
- [ ] 错误日志清晰描述问题原因
- [ ] 集成测试能启动真实gRPC服务
- [ ] Kubernetes资源定义验证通过 (`kubectl apply --dry-run`)

---

## 🚀 后续步骤

1. **立即** (今天): 修复所有P0问题
2. **明天**: 修复所有P1问题
3. **本周**: 通过code review
4. **下周**: 部署到staging进行负载测试
5. **生产部署**: 仅在通过所有验证后

---

## 联系方式

如果修复过程中有疑问:

1. 检查这份指南中的修复示例
2. 参考已有的working code (如Auth Service)
3. 运行单个修改的测试: `cargo test test_name -- --nocapture`
