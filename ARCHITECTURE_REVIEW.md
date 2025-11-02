# 🔍 Nova 后端架构深度审查（Linus 式）

## 第一层：数据结构分析

### 问题 1️⃣：post_metadata vs social_metadata 的重复性

**发现的特殊情况：**

```
posts 表结构：
├─ post_metadata (like_count, comment_count, view_count)
└─ social_metadata (like_count, comment_count, view_count, ...)

🔴 两个表都维护相同的计数器！
```

**为什么这是垃圾设计？**
- `post_metadata` 在 003_posts_schema.sql 中定义
- `social_metadata` 在 004_social_graph_schema.sql 中定义
- 两个表都有触发器维护 like_count/comment_count
- 这违反了"单一真实源"原则
- 导致数据不一致的可能性

**Linus 的建议：**消除一个表。选择 `social_metadata`（更完整）或合并到 `posts`。


### 问题 2️⃣：post_metadata 和 posts 的设计冗余

**当前设计：**
```sql
posts 表
├─ id, user_id, caption, image_key, status...
└─ soft_delete (TIMESTAMP)

post_metadata 表（single row per post）
├─ post_id (PK)
├─ like_count
├─ comment_count
├─ view_count
```

**问题：**
- 每次创建 post，触发器自动创建 post_metadata
- 这是一个 1:1 关系，不需要分开的表
- 在读取时需要 JOIN，增加复杂性

**Linus 的建议：**将计数直接放在 posts 表中：
```sql
posts (
    ...,
    like_count INT DEFAULT 0,
    comment_count INT DEFAULT 0,
    view_count INT DEFAULT 0,
    updated_at TIMESTAMP  -- 单一 updated_at 列
)
```

**收益：**
- 消除 1:1 JOIN
- 单一事实源
- 简化触发器逻辑
- 降低查询复杂度


### 问题 3️⃣：soft_delete 设计的模糊性

**现状：**
```sql
posts.soft_delete (TIMESTAMP)  -- 表示删除时间
comments.soft_delete (TIMESTAMP)
messages.deleted_at (TIMESTAMP)  -- 名称不一致！
```

**问题：**
- 同一概念使用多种名称：soft_delete, deleted_at, deleted_ts
- 没有统一的枚举或标记位

**Linus 的建议：**全局统一为 `deleted_at`：
```sql
posts(deleted_at TIMESTAMP)
comments(deleted_at TIMESTAMP)
messages(deleted_at TIMESTAMP)
conversations(deleted_at TIMESTAMP)
```

---

## 第二层：特殊情况识别

### 问题 4️⃣：users.locked_until 但没有 locked_reason

```sql
users (
    locked_until TIMESTAMP WITH TIME ZONE,
    failed_login_attempts INT DEFAULT 0,
    -- ❌ 缺少：locked_reason VARCHAR
)
```

**为什么重要？**
当管理员手动锁定账户 vs 因登录失败自动锁定，应该有区别

**Linus 的建议：**
```sql
users (
    locked_until TIMESTAMP,
    locked_by_reason VARCHAR(50) CHECK (locked_by_reason IN ('failed_login', 'admin', NULL))
)
```


### 问题 5️⃣：conversations 的 name 设计

**问题：**
- 对于 direct conversation，name 是 NULL，但没有说明这是 @user1 + @user2
- 没有 display_name 计算逻辑
- 客户端需要反复 JOIN 来找出 direct message 的对方

**Linus 的建议：**创建 VIEW 而不是在应用层处理


### 问题 6️⃣：messages 的加密设计缺陷

```sql
messages (
    encrypted_content TEXT NOT NULL,
    nonce VARCHAR(48) NOT NULL,
    -- ❌ 缺少：encryption_algorithm VARCHAR
    -- ❌ 缺少：encryption_key_version INT
)
```

**问题：**
- 没有标记使用了哪个加密算法（AES-GCM v1? v2?）
- 如果需要重新加密，无法追踪哪些消息用了旧密钥
- key rotation 会变得不可能

**Linus 的建议：**
```sql
messages (
    encrypted_content TEXT NOT NULL,
    encryption_algorithm VARCHAR(20) DEFAULT 'AES-GCM-256',
    encryption_key_version INT DEFAULT 1,  -- 用于 key rotation
    nonce VARCHAR(48) NOT NULL,
    ...
)

-- 创建索引用于 key rotation
CREATE INDEX idx_messages_key_version ON messages(encryption_key_version);
```

---

## 第三层：复杂度审查

### 问题 7️⃣：触发器的黑魔法

**当前有 9 个触发器，其中部分维护计数：**

```
✅ update_updated_at_column() -- 4 次使用（这是ok的）
🔴 update_post_like_count() -- 维护 social_metadata
🔴 update_post_comment_count() -- 维护 social_metadata
🔴 update_user_follower_count() -- 维护 users.follower_count
```

**问题：**
- 计数维护分散在多个触发器中
- 触发器中的计数逻辑不可测试
- 如果两个表都在监听 likes，可能会不同步

**Linus 的建议：**
将计数维护从触发器移到应用层，或使用单一 event log：

```sql
-- 创建 immutable event log（不使用触发器）
CREATE TABLE post_events (
    id BIGSERIAL PRIMARY KEY,
    post_id UUID NOT NULL,
    event_type VARCHAR(20),  -- 'like_added', 'comment_added', 'view'
    created_at TIMESTAMP DEFAULT NOW()
);

-- 物化视图（每分钟刷新）
CREATE MATERIALIZED VIEW post_stats_cache AS
SELECT
    post_id,
    COUNT(CASE WHEN event_type = 'like_added' THEN 1 END) as like_count,
    COUNT(CASE WHEN event_type = 'comment_added' THEN 1 END) as comment_count,
    COUNT(CASE WHEN event_type = 'view' THEN 1 END) as view_count
FROM post_events
GROUP BY post_id;
```

**收益：**
- 可审计（event log 不可变）
- 可测试（SELECT COUNT 是纯逻辑）
- 重新计算简单（REFRESH VIEW）


### 问题 8️⃣：缺少显式 CASCADE 定义

```sql
-- ❌ 坏的：没有定义会怎样
sender_id UUID NOT NULL REFERENCES users(id)  -- 在 messages 表中！
```

如果用户被删除，messages 表会发生什么？会外键约束失败！

**Linus 的建议：**要么明确 CASCADE，要么用软删除。

---

## 第四层：破坏性风险分析

### 问题 9️⃣：用户删除的级联问题

**场景：**用户 alice 被删除（或申请 GDPR 删除）

```
当 alice (users.id = 123) 被删除时：
  ↓ 级联触发
posts (user_id = 123) 被删除
  ↓ 级联触发
post_metadata, post_images, likes, comments 都被删除
  ↓ 但是...

❌ messages.sender_id = 123
   外键约束失败！（没有定义 ON DELETE CASCADE）

❌ users.follower_count
   当 alice 的 follow 被删除时，
   这个计数没有自动更新
```

**Linus 的判断：** 这会导致**数据不一致**和**删除失败**。

**建议的解决方案：**

```sql
-- 推荐：软删除 + 应用层清理
ALTER TABLE users ADD COLUMN deleted_at TIMESTAMP;

-- 异步清理（Kafka consumer + background job）
-- 当 user.deleted_at IS SET:
--   1. 标记其 posts 为 archived
--   2. 清除其 messages
--   3. 解除其 follows 关系
```

### 问题 🔟：跨服务的隐式依赖

**当前状况：**

8 个服务都在同一个 PostgreSQL 数据库中，没有隔离：

```
auth-service ──→ users table（可读写）
user-service ──→ users table（可读写）
content-service ──→ posts, comments, likes table（可读写）
feed-service ──→ posts, users table（只读）
messaging-service ──→ conversations, messages table（可读写）
search-service ──→ 所有表（只读）
streaming-service ──→ ???
media-service ──→ ???
```

**问题：**
- 没有显式的服务所有权
- 任何服务都可以直接修改任何表
- 无法追踪谁修改了什么

**Linus 的建议：**

最现实的方案：**应用层强制**

```rust
// auth-service/src/handlers.rs
pub async fn delete_user(user_id: UUID) -> Result<()> {
    // 1. 发布 UserDeleted 事件到 Kafka
    kafka.send("user.events", UserDeletedEvent { user_id, ... }).await?;

    // 2. 其他服务消费这个事件并清理
    // content-service 删除 posts
    // messaging-service 清除 messages
}
```

---

## 第五层：实用性验证

### 问题表：哪些问题真的会导致生产事故？

| 问题 | 严重性 | 会导致事故 | 修复成本 |
|------|--------|---------|---------|
| post_metadata vs social_metadata 重复 | 🔴 高 | ✅ 是 | 低（表合并） |
| posts 和 post_metadata 1:1 关系 | 🟡 中 | ❌ 否（低效） | 低 |
| soft_delete vs deleted_at 命名 | 🟡 中 | ✅ 是（查询错误） | 很低 |
| locked_reason 缺失 | 🟡 中 | ❌ 否（可 workaround） | 低 |
| messages 加密版本 | 🔴 高 | ✅ 是（key rotation） | 高 |
| 触发器维护计数 | 🟡 中 | ✅ 是（不一致） | 中 |
| CASCADE 定义不完整 | 🔴 高 | ✅ 是（FK 失败） | 高 |
| 用户删除级联问题 | 🔴 高 | ✅ 是（GDPR） | 很高 |
| 跨服务隐式耦合 | 🔴 高 | ✅ 是（难维护） | 很高 |

---

## 最终评分与建议

### Linus 式架构评分：🟡 **5.5/10**

**做对了：**
✅ 使用 PostgreSQL 作为单一真实源
✅ 有约束和索引
✅ 有软删除和审计字段
✅ 使用 UUID 而不是自增 ID
✅ 基本的数据正规化

**做错了：**
❌ 特殊情况太多（重复的计数表）
❌ 命名不一致（soft_delete vs deleted_at）
❌ 触发器黑魔法（不可测试）
❌ CASCADE 定义不完整
❌ 跨服务依赖没有隔离

---

## 立即行动：本周修复的 4 个快赢

### 1. 合并 post_metadata 和 social_metadata（2小时）

```sql
-- 步骤：
-- 1. ALTER TABLE posts ADD COLUMN (like_count, comment_count, view_count)
-- 2. UPDATE posts SET counts FROM post_metadata
-- 3. 删除 social_metadata 的触发器
-- 4. 删除 post_metadata 表和 social_metadata（保留一个）
-- 5. 更新应用代码（改 post_metadata -> posts）
```

### 2. 统一 soft_delete -> deleted_at（1小时）

全局统一命名：
- posts.soft_delete → deleted_at
- comments.soft_delete → deleted_at
- conversations（add deleted_at）

### 3. 修复 messages.sender_id 外键（1小时）

```sql
ALTER TABLE messages
ADD CONSTRAINT fk_messages_sender_id_cascade
FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE;
```

### 4. 添加加密版本号到 messages（1小时）

```sql
ALTER TABLE messages ADD COLUMN encryption_key_version INT DEFAULT 1;
CREATE INDEX idx_messages_key_version ON messages(encryption_key_version);
```

---

## 中期改进：3-6 个月

1. **事件日志替代触发器** - 创建 immutable event log，停用触发器
2. **服务所有权文档** - 明确声明每个表由哪个服务拥有
3. **异步事件处理** - 用户删除通过 Kafka event，不是直接 CASCADE

---

## 核心洞察：Linus 三问

```
1. "这是真问题吗？"
   ✅ 是。post_metadata 重复会导致数据不一致。

2. "有更简单的方法吗？"
   ✅ 是。把计数放在 posts 表中，消除 JOIN。

3. "会破坏什么吗？"
   ✅ 会。需要 migration，但可以在离线完成。
```

**最后一句话：**

> "Bad programmers worry about the code. Good programmers worry about data structures."

你的 schema 最大的问题不在代码，而在**数据结构重复和命名不一致**。修复这些，一切都会简单得多。
