# Nova 项目架构改进 - 实施指南

**日期**: 2025-10-25  
**目标**: 修复 4 个 Critical Issues + 4 个 High Priority Issues

---

## ✅ 已实施的改进

### 1. 改进了错误处理 (src/error.rs)
**改进内容**:
- ✅ 从 `String` 错误变更为 具体的枚举变体
- ✅ 添加 `is_retryable()` 方法（区分可重试 vs 永久失败）
- ✅ 添加 `status_code()` 方法（自动映射 HTTP 状态码）
- ✅ 实现 `From<sqlx::Error>` 自动转换

**优势**:
```rust
// 之前: 无法区分错误类型
match e {
    AppError::BadRequest(msg) => { /* 某个处理 */ }
    _ => { /* 全部当作通用错误 */ }
}

// 现在: 编译器强制处理所有情况，并可查询是否可重试
if error.is_retryable() {
    // 添加重试逻辑
} else {
    // 立即返回给客户端
}
```

---

### 2. 重新设计 Privacy Mode (src/models/conversation.rs)
**改进内容**:
- ✅ 使用 Rust 泛型 + Trait 强制编译期类型检查
- ✅ `Conversation<StrictE2E>` 和 `Conversation<SearchEnabled>` 是不同类型
- ✅ 混乱的 if-else 现在变成编译期错误
- ✅ 添加 `ConversationData` enum 作为存储的单一来源

**优势**:
```rust
// 之前: 容易忘记检查隐私模式
async fn send_message(conv_id: Uuid, msg: &str) {
    let conv = db.get_conversation(conv_id).await;
    // 😱 忘记检查 conv.privacy_mode，直接索引消息！
    index_message(msg).await;
}

// 现在: 编译器强制正确处理
async fn send_searchable_message(conv: SearchableConversation, msg: &str) {
    // ✅ 自动知道这个对话支持索引，无需检查标志位
    index_message(msg).await;
}

async fn send_e2e_message(conv: StrictE2EConversation, msg: &str) {
    // ❌ 这里调用 index_message() 会编译错误！
    // index_message(msg).await;  // 不允许！
}
```

---

### 3. 创建统一权限 Guard (src/middleware/guards.rs)
**改进内容**:
- ✅ 创建 `User` extractor（自动从 JWT 提取）
- ✅ 创建 `ConversationMember` extractor（单次查询验证所有权限）
- ✅ 创建 `ConversationAdmin` extractor（进一步限制仅管理员）
- ✅ 添加权限检查方法: `can_send()`, `can_delete_message()`

**优势**:
```rust
// 之前: 权限分散到每个 handler
#[post("/conversations/{id}/messages")]
async fn send_message(
    State(state): State<AppState>,
    user: User,
    Path(conv_id): Path<Uuid>,
    Json(req): Json<SendRequest>,
) -> Result<...> {
    // 检查权限 1: 用户是成员吗?
    let member = sqlx::query("SELECT ... FROM conversation_members ...")
        .fetch_optional(&state.db).await?;
    if member.is_none() {
        return Err(AppError::Unauthorized);
    }
    
    // 检查权限 2: 用户被禁言了吗?
    if member.unwrap().is_muted {
        return Err(AppError::Forbidden);
    }
    
    // 检查权限 3: 对话存在吗?
    let conv = sqlx::query("SELECT ... FROM conversations WHERE id = ?")
        .fetch_optional(&state.db).await?;
    if conv.is_none() {
        return Err(AppError::NotFound);
    }
    
    // 现在才开始实际逻辑
    send_message_db(&state.db, conv_id, user.id, req.content).await?
}

// 现在: 权限在 extractor 中自动处理
#[post("/conversations/{id}/messages")]
async fn send_message(
    member: ConversationMember,  // 自动验证！一个查询完成所有检查
    Json(req): Json<SendRequest>,
) -> Result<...> {
    // 检查发送权限（如果禁言会直接返回错误）
    member.can_send()?;
    
    // 现在可以直接实现逻辑，无需担心权限
    send_message_db(member.conversation_id, member.user_id, req.content).await?
}
```

---

## 📋 后续需要实施的改进

### High Priority (这周完成)

#### 4. Redis Pub/Sub → Streams 迁移
**文件**: `src/websocket/pubsub.rs`

**当前问题**:
```rust
// 问题: Fire-and-forget，没有顺序保证、去重、回放
redis.publish(&format!("conversation:{}", conv_id), message).await?;
```

**改进方案**:
```rust
// 使用 Redis Streams (XADD + XREAD)
// 优势:
// 1. 消息历史 (新连接可以 catch-up)
// 2. Consumer Groups (幂等处理)
// 3. 顺序保证 (FIFO)
// 4. 流量控制 (XPENDING)

// 添加消息到 stream
redis.xadd(
    &format!("conversations:{}", conv_id),
    "*",  // Auto-generate ID
    &[
        ("message_id", message_id.to_string()),
        ("sender_id", sender_id.to_string()),
        ("content", content),
    ]
).await?;

// 消费消息 (幂等)
redis.xread_group(
    "messaging-service",  // Consumer group
    "instance-1",         // Consumer name
    &[&format!("conversations:{}", conv_id)],
    ">",                  // Only new messages
).await?;
```

**实施步骤**:
1. 在 `src/websocket/streams.rs` 中实现 Streams consumer
2. 更新 `src/websocket/mod.rs` 以使用新 consumer
3. 添加优雅关闭（确保 consumer 正确标记消息）
4. 添加测试覆盖

---

#### 5. 离线队列重新设计
**文件**: `frontend/src/services/offlineQueue/` 和 `src/services/offline_queue.rs`

**当前问题**:
```
客户端重放消息 + idempotency_key 去重
问题: 无法保证顺序，重复概率高
```

**改进方案**:
```
用 "sync from last known ID" 替代重放模式

客户端:
  1. 记录最后同步的 message_id
  2. 离线时，用本地 queue 缓存新消息
  3. 连接恢复时:
     - 请求 GET /conversations/{id}/messages?after=<last_id>
     - 合并服务器消息 + 本地缓存
     - 删除本地 queue

优势:
  - ✅ 自动排序 (基于服务器 sequence_number)
  - ✅ 无重复 (基于 message_id 去重)
  - ✅ 自动处理乱序 (客户端收到的是已排序列表)
```

**实施步骤**:
1. 修改 Message API 添加 `?after=` 参数
2. 更新客户端离线队列逻辑
3. 添加集成测试

---

#### 6. 缺少并发和恢复测试
**文件**: `backend/messaging-service/tests/integration/`

**需要添加的测试**:
```rust
#[tokio::test]
async fn test_concurrent_idempotency_deduplication() {
    // 同一 idempotency_key 发送 10 次，应该只有 1 条消息
}

#[tokio::test]
async fn test_muted_user_cannot_send() {
    // User 被禁音，发送消息应该失败
}

#[tokio::test]
async fn test_non_member_cannot_send() {
    // User 不在对话中，发送消息应该失败
}

#[tokio::test]
async fn test_member_cannot_delete_others_messages() {
    // 普通成员尝试删除他人消息，应该失败
}

#[tokio::test]
async fn test_db_timeout_triggers_retry() {
    // 数据库超时，client 应该重试而不是立即放弃
}

#[tokio::test]
async fn test_offline_queue_maintains_order() {
    // 离线状态下发送 10 条消息，连接恢复后顺序应该正确
}
```

---

#### 7. 数据库 sequence_number 明确定义
**文件**: 迁移脚本 + Message 模型

**当前问题**:
```sql
-- sequence_number 是全局 BIGSERIAL，分表后会有问题
sequence_number BIGSERIAL,
```

**改进方案**:
```sql
-- 改为每对话局部，添加复合唯一约束
sequence_number BIGINT NOT NULL,
UNIQUE(conversation_id, sequence_number)
```

**实施步骤**:
1. 创建数据库迁移脚本
2. 更新 Message 模型文档
3. 验证现有查询仍然有效

---

### Medium Priority (下周开始)

#### 8. 反应计数改为动态计算
**问题**: `messages.reaction_count` 冗余且容易不一致

**方案**:
```rust
// 方案 A: 每次计算 (简单但慢)
SELECT COUNT(*) FROM message_reactions WHERE message_id = $1

// 方案 B: Redis 缓存 + 事件驱动 (推荐)
- 添加反应时: INCR messages:{id}:reaction_count
- 删除反应时: DECR messages:{id}:reaction_count
- 定期同步到 PostgreSQL (防止丢失)
```

---

## 🚀 立即执行清单

### 今天 (2025-10-25)
- [x] 改进错误处理枚举
- [x] 重新设计 Privacy Mode
- [x] 创建权限 Guard 模块
- [ ] 更新中间件导出
- [ ] 编译检查

### 明天 (2025-10-26)
- [ ] 开始 Redis Streams 迁移
- [ ] 离线队列重新设计
- [ ] 添加并发测试

### 本周 (2025-10-27-31)
- [ ] 完成所有 Critical Issues
- [ ] 代码审查
- [ ] 合并到主分支

### 下周 (2025-11-03+)
- [ ] Medium Priority Issues
- [ ] 性能优化
- [ ] 推进 Phase 3 其他用户故事

---

## 💡 最佳实践指南

### 使用新的 Error 处理
```rust
// ✅ 好
async fn send_message(db: &Pool<Postgres>, msg: &str) -> AppResult<MessageId> {
    sqlx::query(...).fetch_one(db).await?  // 自动转换为 AppError::Database
}

// ❌ 不好
async fn send_message(db: &Pool<Postgres>, msg: &str) -> AppResult<MessageId> {
    sqlx::query(...)
        .fetch_one(db)
        .await
        .map_err(|e| AppError::StartServer(e.to_string()))?  // 丢失信息
}
```

### 使用新的 Privacy Types
```rust
// ✅ 好
async fn index_message(conv: SearchableConversation, msg: &str) {
    // 编译器保证这是可索引的
    elasticsearch_index(msg).await?;
}

async fn send_e2e_message(conv: StrictE2EConversation, msg: &str) {
    // 编译器保证不会尝试索引
}

// ❌ 不好
async fn send_message(conv: Conversation, msg: &str) {
    if conv.privacy_mode == PrivacyMode::SearchEnabled {
        // 容易忘记这个检查
        elasticsearch_index(msg).await?;
    }
}
```

### 使用新的 Guards
```rust
// ✅ 好
#[post("/conversations/{id}/messages")]
async fn send_message(
    member: ConversationMember,  // 自动验证所有权限
    Json(req): Json<SendRequest>,
) -> AppResult<Json<MessageResponse>> {
    member.can_send()?;  // 快速权限检查
    // 实现逻辑...
}

// ❌ 不好
#[post("/conversations/{id}/messages")]
async fn send_message(
    State(state): State<AppState>,
    user: User,
    Path(conv_id): Path<Uuid>,
    Json(req): Json<SendRequest>,
) -> AppResult<...> {
    // 手动检查权限...
}
```

---

## 📊 进度追踪

```
Critical Issues:
- [x] #1: Privacy Mode 混乱 (已改进模型)
- [ ] #2: 权限检查分散 (已创建 Guard，需集成到 routes)
- [ ] #3: Redis Pub/Sub (待实施)
- [ ] #4: sequence_number 语义 (待迁移)

High Priority:
- [ ] #5: 错误处理 (已改进 error.rs，需更新所有调用点)
- [ ] #6: 离线队列 (待重设计)
- [ ] #7: 并发/恢复测试 (待添加)
- [ ] #8: 反应计数 (待改进)
```

---

**最后更新**: 2025-10-25  
**状态**: 实施中 - 还需 2-3 周完成所有 Critical Issues

