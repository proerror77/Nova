# Nova 数据库迁移深度审查报告

审查时间: 2025-11-05
范围: Nova 项目全部数据库迁移
架构风格评审: Linus Torvalds 模式 (代码品味 + 实用主义)

---

## 执行摘要

数据库架构存在**严重问题**。核心问题是**哲学冲突**:
- 多个版本的迁移文件在相同问题上提出了相互矛盾的解决方案
- 软删除(soft-delete)和级联删除(CASCADE)的策略不一致
- 跨服务的数据模型严重不一致
- 迁移顺序混乱，存在循环依赖风险

Linus 会说: **"不是代码垃圾，是架构垃圾。它违反了最基本的原则：数据结构的一致性。"**

---

## I. 严重问题清单 (需要立即修复)

### 问题 1: 迁移版本号重复 + 多版本迁移 (P0 CRITICAL)

**现象:**
```
065_merge_post_metadata_tables.sql
081_merge_post_metadata_v2.sql          ← 重复!

066_unify_soft_delete_naming.sql
082_unify_soft_delete_v2.sql            ← 重复!
066a_add_deleted_by_to_users_pre_outbox.sql  ← 临时补丁

067_fix_messages_cascade.sql
083_outbox_pattern_v2.sql               ← 重复!

068_add_message_encryption_versioning.sql
084_encryption_versioning_v2.sql        ← 重复!
```

**危害:**
1. 迁移工具无法确定执行顺序 (Flyway/Liquibase 会报错或随机选择)
2. 生产环境和开发环境的数据库 schema 可能不一致
3. 回滚变得不可能 (无法追踪哪个版本已执行)
4. 团队成员无法理解当前实际的 schema 状态

**根本原因:**
缺乏明确的架构决策。多个开发者在同一个问题上写了多个迁移，不知道哪个是"正确的"。

**立即修复:**
1. 确定每个号码应该执行哪个文件
2. 重新编号冗余文件
3. 删除 `_v2` 版本或明确标记为已弃用

**文件位置:**
- `/Users/proerror/Documents/nova/backend/migrations/06*.sql`
- `/Users/proerror/Documents/nova/backend/migrations/068*.sql`

---

### 问题 2: CASCADE vs RESTRICT 的哲学冲突 (P0 CRITICAL)

**症状:**

迁移 067 中存在**直接矛盾**:

**067_fix_messages_cascade.sql (旧版本):**
```sql
ALTER TABLE messages
    ADD CONSTRAINT fk_messages_sender_id_cascade
        FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE;
-- 解释: 当用户被删除，自动删除所有他们的消息
```

**083_outbox_pattern_v2.sql (新版本):**
```sql
ALTER TABLE messages
    DROP CONSTRAINT IF EXISTS messages_sender_id_fkey;
ALTER TABLE messages
    ADD CONSTRAINT fk_messages_sender_id
    FOREIGN KEY (sender_id) REFERENCES users(id)
    ON DELETE RESTRICT;  -- 不允许硬删除! 使用事件驱动
```

**070_unify_soft_delete_complete.sql (后来的):**
```sql
ALTER TABLE messages
  DROP CONSTRAINT IF EXISTS fk_messages_sender_id;
ALTER TABLE messages
  ADD CONSTRAINT fk_messages_sender_id
  FOREIGN KEY (sender_id) REFERENCES users(id)
  ON DELETE RESTRICT;  -- 再次改为 RESTRICT!
```

**对比:**

| 文件 | FK策略 | 删除流程 | 哲学 |
|------|--------|---------|------|
| 067v1 | CASCADE | 用户删除 → 消息自动删除 | Monolith 单体应用 |
| 067v2 | RESTRICT | 用户删除 → Outbox事件 → Kafka消费 → 消息软删除 | Microservice 微服务 |
| 070 | RESTRICT | 同v2 | 确认微服务 |

**危害:**
1. 如果执行了 067v1，然后 067v2，会添加重复约束，迁移失败
2. 硬删除时，行为不确定: 会自动删除消息吗？还是抛出错误？
3. 业务逻辑混乱: 无法确定消息何时被删除

**真实问题:**
这不是代码问题，是**架构选择问题**。项目在从 Monolith(单体) 迁移到 Microservice(微服务)，但没有明确的迁移路径。

**必须回答的问题:**
- Nova 项目现在采用微服务架构吗？
- 如果是，为什么还有其他表使用 CASCADE？
- 如果不是，为什么创建了 Outbox 模式？

**立即修复:**
1. 删除 067_fix_messages_cascade.sql (旧版本)
2. 确认 083_outbox_pattern_v2.sql 是最终版本
3. 审查所有 FK 约束是否都遵循一致的删除策略

**涉及文件:**
```
067_fix_messages_cascade.sql           (旧，应删除)
083_outbox_pattern_v2.sql              (新，应保留)
070_unify_soft_delete_complete.sql     (依赖 067v2)
```

**相关表:**
- messages.sender_id → users(id)
- posts.user_id → users(id)
- comments.user_id → users(id)

---

### 问题 3: 跨服务 users 表不一致 (P0 CRITICAL)

**发现的三个不同的 users 表定义:**

**1. Main migrations (auth-service 在这里):**
```sql
-- /backend/migrations/001_initial_schema.sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) NOT NULL UNIQUE,
    username VARCHAR(50) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    email_verified BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    failed_login_attempts INT NOT NULL DEFAULT 0,
    locked_until TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    last_login_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE,
    -- 约束: email_format, username_format, password_hash_not_empty, 
    -- not_both_deleted_and_active
);
```

**2. Auth-service (独立数据库):**
```sql
-- /backend/auth-service/migrations/001_create_users_table.sql
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(255) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    email_verified BOOLEAN NOT NULL DEFAULT false,
    email_verified_at TIMESTAMP WITH TIME ZONE,      -- ← 额外列
    totp_enabled BOOLEAN NOT NULL DEFAULT false,    -- ← 额外列
    totp_secret VARCHAR(255),                        -- ← 额外列
    totp_verified BOOLEAN NOT NULL DEFAULT false,   -- ← 额外列
    phone_number VARCHAR(20),                        -- ← 额外列
    phone_verified BOOLEAN NOT NULL DEFAULT false,  -- ← 额外列
    locked_until TIMESTAMP WITH TIME ZONE,
    failed_login_attempts INT NOT NULL DEFAULT 0,
    last_login_at TIMESTAMP WITH TIME ZONE,
    last_password_change_at TIMESTAMP WITH TIME ZONE, -- ← 额外列
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE
);
-- 缺少: email_verified 布尔字段!, 缺少 is_active!
```

**3. Messaging-service (shadow copy，应该弃用):**
```sql
-- /backend/messaging-service/migrations/0001_create_users.sql
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY,
  username TEXT NOT NULL UNIQUE,
  public_key TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- 只有 3 列!
```

**差异分析:**

| 字段 | Main | Auth-Service | Messaging |
|------|------|--------------|-----------|
| id | UUID | UUID | UUID |
| username | VARCHAR(50) | VARCHAR(255) | TEXT |
| email | VARCHAR(255) | VARCHAR(255) | ✗ |
| password_hash | VARCHAR(255) | VARCHAR(255) | ✗ |
| email_verified | BOOLEAN | BOOLEAN | ✗ |
| email_verified_at | ✗ | TIMESTAMP | ✗ |
| totp_enabled | ✗ | BOOLEAN | ✗ |
| totp_secret | ✗ | VARCHAR(255) | ✗ |
| phone_number | ✗ | VARCHAR(20) | ✗ |
| is_active | BOOLEAN | ✗ | ✗ |
| public_key | ✗ | ✗ | TEXT |
| created_at | TIMESTAMP | TIMESTAMP | TIMESTAMP |
| deleted_at | TIMESTAMP | TIMESTAMP | ✗ |

**危害:**
1. **数据同步问题**: Messaging-service 的用户表没有密码、邮箱等信息。当用户被删除时，哪个表才是"真实的源"?
2. **应用业务逻辑混乱**: 代码需要检查多个 users 表, 导致 N+1 查询问题
3. **GDPR 合规性**: 当用户请求删除时，需要同时清理 3 个表，但没有事务保证原子性
4. **FK 约束无效**: Messaging-service 的 conversation_members.user_id 曾经指向本地 users 表，但现在指向... 哪里?

**证据 - 迁移 0023:**
```sql
-- /backend/messaging-service/migrations/0023_phase1_users_consolidation_app_level_fk.sql
ALTER TABLE conversation_members
  DROP CONSTRAINT IF EXISTS conversation_members_user_id_fkey;

COMMENT ON TABLE users IS
  'DEPRECATED: This is a shadow copy of auth-service.users. All new code MUST use auth_client gRPC API instead.
   This table will be removed in Phase 2 once all code migration is complete.';
```

这说明团队意识到了问题，但选择了**最坏的解决方案**: 删除 FK 约束，改用应用层验证。这意味着:
- 数据库无法保证数据完整性
- 孤立数据可能出现 (conversation_members.user_id 指向不存在的用户)
- 没有原子性保证

**立即修复:**
1. **统一 users 表定义** - 决定哪个是 canonical source
2. **删除 shadow copies** - Messaging-service 不应该有自己的 users 表副本
3. **恢复 FK 约束** - 用 RESTRICT 而不是 CASCADE (基于微服务哲学)
4. **使用 gRPC 跨服务通信** - 但也要保证数据库约束的一致性

**文件:**
```
/backend/migrations/001_initial_schema.sql
/backend/auth-service/migrations/001_create_users_table.sql
/backend/messaging-service/migrations/0001_create_users.sql
/backend/messaging-service/migrations/0023_phase1_users_consolidation_app_level_fk.sql
```

---

### 问题 4: 软删除(Soft Delete) 列定义不一致 (P0 HIGH)

**发现多个不同的软删除模式:**

**模式 1 - Main migration (001):**
```sql
deleted_at TIMESTAMP WITH TIME ZONE  -- 只有 deleted_at, 没有 deleted_by
```

**模式 2 - 066v1:**
```sql
-- soft_delete 列被重命名为 deleted_at
ALTER TABLE posts RENAME COLUMN soft_delete TO deleted_at;
```

**模式 3 - 066v2:**
```sql
deleted_at TIMESTAMP NULL;
deleted_by UUID;  -- ← 新增
```

**模式 4 - 070 (最终):**
```sql
deleted_at TIMESTAMP WITH TIME ZONE NULL DEFAULT NULL;
deleted_by UUID NULL;
-- 约束: (deleted_at IS NULL AND deleted_by IS NULL) OR (deleted_at IS NOT NULL AND deleted_by IS NOT NULL)
```

**问题:**
1. 某些表可能有 deleted_at 但没有 deleted_by
2. Outbox 触发器假设 deleted_by 存在，但可能为 NULL
3. 071 迁移添加 FK: `FOREIGN KEY (deleted_by) REFERENCES users(id) ON DELETE SET NULL` - 但如果 deleted_by 指向被删除的用户呢?

**涉及表:**
```
posts.deleted_at / posts.deleted_by
comments.deleted_at / comments.deleted_by
messages.deleted_at / messages.deleted_by
conversations.deleted_at / conversations.deleted_by
follows.deleted_at / follows.deleted_by
blocks.deleted_at / blocks.deleted_by
media.deleted_at / media.deleted_by
```

**立即修复:**
1. 审计所有表，确保都有 `(deleted_at, deleted_by)` 对
2. 添加约束确保两者同时为 NULL 或同时不为 NULL
3. 确认所有触发器使用了正确的列名

---

### 问题 5: Outbox 模式的递归风险 (P0 HIGH)

**在 071 迁移中:**
```sql
ALTER TABLE users
    ADD CONSTRAINT IF NOT EXISTS fk_users_deleted_by
    FOREIGN KEY (deleted_by) REFERENCES users(id) ON DELETE SET NULL;
```

这创建了自引用外键: `users.deleted_by → users.id`

**在 067_outbox_pattern_v2 中:**
```sql
CREATE OR REPLACE FUNCTION emit_user_deletion_event()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
        INSERT INTO outbox_events (...)
        VALUES ('User', NEW.id, 'UserDeleted', ...);
    END IF;
    RETURN NEW;
END;
```

**风险:**
当用户 A 被删除时:
1. 触发 UserDeleted 事件 → outbox_events 表
2. Kafka 消费者收到事件 → 删除用户 A 的所有相关数据
3. 如果系统管理员用户 B 执行了删除，那么 users.deleted_by = B
4. 如果管理员 B 后来被删除，会再次触发事件，可能导致级联问题

**不幂等性问题:**
如果迁移 0021 和 0023 都在 messaging-service 中执行:
```
0021_create_location_sharing.sql
0021_create_notification_jobs.sql  ← 重复号!
0022_notification_jobs_maintenance.sql
0023_phase1_users_consolidation_app_level_fk.sql
```

---

## II. 跨服务一致性问题

### 问题 6: Messaging-Service 有重复的迁移版本号

**发现:**
```
0021_create_location_sharing.sql
0021_create_notification_jobs.sql     ← 重复!
```

**危害:**
Flyway 不知道执行顺序。SQL 的字母顺序是:
1. `0021_create_location_sharing.sql`
2. `0021_create_notification_jobs.sql`

但这可能不是开发者的意图!

**文件:**
```
/backend/messaging-service/migrations/0021_create_location_sharing.sql
/backend/messaging-service/migrations/0021_create_notification_jobs.sql
```

---

### 问题 7: FK 约束跨服务不一致

**Messaging-Service:**
```sql
-- 0003_create_conversation_members.sql
ALTER TABLE conversation_members
  DROP CONSTRAINT IF EXISTS conversation_members_user_id_fkey;  -- 已移除!
```

**Main Migrations:**
```sql
-- 001_initial_schema.sql
REFERENCES users(id) ON DELETE CASCADE  -- 还在用 CASCADE!

-- 070_unify_soft_delete_complete.sql
REFERENCES users(id) ON DELETE RESTRICT  -- 改为 RESTRICT!
```

**问题:**
即使在 main migrations 中修复了 CASCADE，messaging-service 也没有 FK 约束了，所以没有保护!

---

## III. 索引优化问题

### 问题 8: 缺少关键索引

**高频查询的表 - 缺少复合索引:**

```sql
-- posts: 常见查询 - 获取用户的活跃帖子
SELECT * FROM posts WHERE user_id = ? AND deleted_at IS NULL ORDER BY created_at DESC;
-- 现有索引: idx_posts_active (user_id, created_at DESC) WHERE deleted_at IS NULL ✓ (OK)

-- messages: 常见查询 - 获取对话中的消息
SELECT * FROM messages WHERE conversation_id = ? AND deleted_at IS NULL ORDER BY created_at DESC;
-- 现有索引: idx_messages_active (conversation_id, created_at DESC) WHERE deleted_at IS NULL ✓ (OK)

-- conversation_members: 缺少索引!
SELECT * FROM conversation_members WHERE user_id = ? ORDER BY joined_at;
-- 无专用索引！会导致全表扫描

-- follows: 缺少索引!
SELECT * FROM follows WHERE follower_id = ? AND deleted_at IS NULL;
-- 无专用索引！会导致全表扫描
```

**发现的冗余索引:**

在 Auth-Service 中:
```sql
-- 001_create_users_table.sql
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at);
CREATE INDEX IF NOT EXISTS idx_users_deleted_at ON users(deleted_at);

-- 同时有 email 索引和 deleted_at 索引，但没有复合索引 (email, deleted_at)
-- 对于查询 "WHERE email = ? AND deleted_at IS NULL" 可能不高效
```

---

### 问题 9: 缺乏分区策略

**大表没有分区:**
- messages 表：预期数百万行，没有基于 created_at 的分区
- posts 表: 预期百万行，没有分区
- outbox_events: 是增长最快的表，没有分区 (会导致性能下降)

---

## IV. 迁移顺序 & 依赖关系问题

### 问题 10: 循环依赖和执行顺序不清晰

**发现的依赖链:**

```
066a (add deleted_by to users)
    ↓ depends on
067v2 (outbox 触发器使用 deleted_by)
    ↓ depends on
070 (统一软删除到所有表)
    ↓ depends on
071 (添加 FK fk_users_deleted_by)
```

**问题:**
- 066a 应该在 067v2 之前执行，但文件名排序不保证这一点
- 文件 066a 本身就是"临时补丁"，说明设计有问题

**迁移版本号缺失:**
```
007 → 010 (缺失 008, 009)
035 → 038 (缺失 036, 037)
041 → 052 (缺失 042-051)
```

**后果:**
新开发者无法理解"为什么跳过了这些号码？" 可能是:
1. 他们被删除了
2. 他们被合并了
3. 它们只存在于不同的分支中
4. 有某种隐藏的命名约定

---

## V. 不幂等操作 & 重复执行风险

### 问题 11: 某些迁移不幂等

**大部分迁移使用 `IF NOT EXISTS`，这很好:**
```sql
CREATE TABLE IF NOT EXISTS users (...)  ✓ 幂等
CREATE INDEX IF NOT EXISTS idx_... ✓ 幂等
ALTER TABLE ... ADD COLUMN IF NOT EXISTS ...  ✓ 幂等
```

**但有些是不幂等的:**

```sql
-- 067_fix_messages_cascade.sql (旧版本) - 行 24-25
ALTER TABLE messages
    DROP CONSTRAINT IF EXISTS messages_sender_id_fkey;  -- ✓ 幂等

-- 070_unify_soft_delete_complete.sql - 行 278
DROP VIEW IF EXISTS active_posts CASCADE;  -- ✓ 幂等
```

**总体:** 幂等性不错，但有异常。

---

## VI. 数据完整性和 GDPR 合规性问题

### 问题 12: 孤立数据风险

**在 Messaging-Service 中移除了 FK 约束:**
```sql
ALTER TABLE conversation_members
  DROP CONSTRAINT IF EXISTS conversation_members_user_id_fkey;
```

**现在:**
```sql
INSERT INTO conversation_members (conversation_id, user_id, role)
VALUES (conv_id, non_existent_user_id, 'member');
-- ✓ 成功插入！ (应该失败)

SELECT * FROM conversation_members cm
WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.id = cm.user_id);
-- 可能返回孤立记录
```

**GDPR 问题:**
当用户要求"删除我的所有数据"时：
```
1. 删除 users 表中的记录 (已删除)
2. 需要删除 conversation_members 中指向该用户的所有行
   - 但没有 FK 约束，所以需要应用层循环检查所有表
3. 需要删除 messages 表中该用户发送的所有消息
   - 同样需要应用层处理
4. 如果有任何服务 DOWN，删除可能不完整，导致 GDPR 违规
```

**立即修复:**
恢复 FK 约束，使用:
- 对于硬删除: `ON DELETE RESTRICT` (强制先清理)
- 对于软删除: 在应用层实现，FK 也用 RESTRICT

---

## VII. 迁移测试和验证问题

### 问题 13: 缺乏迁移验证脚本

**发现的文件：**
```
/backend/messaging-service/migrations/verify_migrations.sh
```

但其他服务都没有验证脚本！

**应该有的验证:**
1. 检查所有表都有 created_at
2. 检查所有软删除表都有 (deleted_at, deleted_by) 对
3. 检查所有 FK 约束是一致的 (CASCADE vs RESTRICT)
4. 检查没有 orphaned 约束
5. 检查索引命名约定

---

## 优化建议

### 高优先级 (实施后立即改进系统稳定性)

#### 1. 清理迁移文件重复 (1-2小时)
```bash
# 步骤:
1. 创建新分支: git checkout -b fix/db-migrations-cleanup
2. 确定哪个版本是"最终版本":
   - 066v2 是否包含066的所有改动? ✓ 是
   - 067v2 是否是预期的最终版本? ✓ 是
   - 068v2 是否完整? ✓ 是
3. 删除旧版本，重新编号新版本:
   066_unify_soft_delete_naming.sql        → 删除
   082_unify_soft_delete_v2.sql            → 重命名为 066_unify_soft_delete_naming.sql
   067_fix_messages_cascade.sql             → 删除
   083_outbox_pattern_v2.sql               → 重命名为 067_outbox_pattern.sql
   068_add_message_encryption_versioning.sql → 删除
   084_encryption_versioning_v2.sql         → 重命名为 068_encryption_versioning.sql
4. 删除临时补丁:
   066a_add_deleted_by_to_users_pre_outbox.sql → 合并到 066
5. 删除冗余:
   065_merge_post_metadata_tables.sql      → 删除 (v2 是完整版)
```

#### 2. 统一所有 FK 约束策略 (2-4小时)

**决策: 采用 RESTRICT + Outbox 模式 (微服务架构)**

```sql
-- 原则: 不允许硬删除，强制使用软删除 + Outbox 事件
-- 所有 FK 都改为:
ON DELETE RESTRICT  -- 防止意外删除，强制先软删除

-- 核对清单:
users(id) ← 所有 FK 都应该是 RESTRICT
    posts.user_id
    comments.user_id
    messages.sender_id
    follows.follower_id
    follows.following_id
    blocks.blocker_id
    blocks.blocked_id
    media.owner_id
    ... (检查所有)
```

#### 3. 统一 users 表定义 (4-6小时)

**决策: Auth-Service 是 canonical source**

在 Auth-Service 中维护完整的 users 表:
```sql
-- auth-service users 表应该包含:
id, username, email, password_hash,
email_verified, email_verified_at,
totp_enabled, totp_secret, totp_verified,
phone_number, phone_verified,
locked_until, failed_login_attempts,
last_login_at, last_password_change_at,
is_active, created_at, updated_at, deleted_at, deleted_by
```

其他服务通过 gRPC API 调用，不维护本地副本:
```rust
// auth_client.user_exists(user_id) → Bool
// auth_client.get_user(user_id) → User
```

删除 Messaging-Service 的 shadow users 表。

#### 4. 恢复并审计所有 FK 约束 (2-3小时)

**迁移:**
```sql
-- 新增: 074_restore_fk_constraints_audit.sql
-- 步骤 1: 检查孤立数据
SELECT 'orphaned_conversation_members' as table_name, COUNT(*) as orphan_count
FROM conversation_members cm
WHERE NOT EXISTS (SELECT 1 FROM auth_service.users u WHERE u.id = cm.user_id);

-- 如果有孤立数据，先清理:
DELETE FROM conversation_members 
WHERE NOT EXISTS (SELECT 1 FROM auth_service.users u WHERE u.id = user_id);

-- 步骤 2: 恢复 FK
ALTER TABLE conversation_members
    ADD CONSTRAINT fk_conversation_members_user_id
    FOREIGN KEY (user_id) REFERENCES users(id)
    ON DELETE RESTRICT;

-- 对所有表重复...
```

#### 5. 添加分区策略 (1-2天，可递增执行)

**优先级顺序:**
1. outbox_events - 按 created_at 按月分区 (增长最快)
2. messages - 按 created_at 按月分区
3. posts - 按 created_at 按季度分区
4. auth_logs - 按 created_at 按年分区

```sql
-- 075_add_partitioning_outbox_events.sql
-- 创建分区表，重定向流量，删除旧表
```

---

### 中优先级 (改进查询性能)

#### 6. 添加缺失的复合索引

```sql
-- 新增: 076_add_missing_composite_indexes.sql
CREATE INDEX idx_conversation_members_user_id ON conversation_members(user_id);
CREATE INDEX idx_follows_follower_id ON follows(follower_id, deleted_at) WHERE deleted_at IS NULL;
CREATE INDEX idx_blocks_blocker_id ON blocks(blocker_id, deleted_at) WHERE deleted_at IS NULL;
```

#### 7. 创建迁移验证脚本

```bash
# scripts/verify_migrations.sql
-- 检查清单:
1. 所有表都有 created_at
2. 所有软删除表都有 (deleted_at, deleted_by) 对
3. 检查约束一致性
4. 检查索引覆盖率
5. 生成报告
```

---

### 低优先级 (文档和流程改进)

#### 8. 文档化迁移策略

创建 `/backend/docs/DATABASE_MIGRATION_STRATEGY.md`:
```markdown
## Nova 数据库迁移策略

### 原则
1. **幂等性**: 所有迁移都必须可以安全重复执行
2. **微服务架构**: 使用 RESTRICT FK + Outbox 模式实现级联删除
3. **GDPR 合规**: 所有删除都必须是可审计的 (deleted_at, deleted_by)
4. **版本连续**: 迁移版本号必须连续，不能有间隙

### 命名约定
- 格式: `NNN_short_description.sql`
- 不允许 `_v2`, `_v3` 等后缀
- 如果需要修改已发布的迁移，创建新编号的迁移，不要编辑旧的

### 执行顺序
1. 始终按版本号升序执行
2. 所有服务使用相同的迁移工具 (推荐: Flyway)
3. 关键的交叉服务迁移应该在"迁移窗口"期间协调执行

### FK 约束规则
- 所有 FK 都使用 `ON DELETE RESTRICT` (微服务架构)
- 级联删除由 Outbox 事件处理，不是 DB 约束
- 不允许硬删除，强制使用软删除流程

### 软删除模式
- 表必须有 (deleted_at TIMESTAMP, deleted_by UUID) 对
- 两个列必须同时为 NULL 或同时不为 NULL (约束保证)
- 所有查询必须包含 `WHERE deleted_at IS NULL` (除非明确需要已删除数据)
- 所有删除必须发出 Outbox 事件 (触发器)
```

#### 9. 设置 CI/CD 迁移检查

```yaml
# .github/workflows/db-migration-check.yml
- name: Verify migrations
  script: |
    # 1. 检查版本号连续性
    # 2. 检查所有迁移都是幂等的
    # 3. 检查没有 _v2 后缀
    # 4. 检查没有硬 FK CASCADE
    # 5. 检查所有软删除表都有两列约束
```

---

## 数据丢失风险评估

### 当前状态: 中等风险 ⚠️

**最坏的情况：**
```
1. Messaging-Service 的 cascade.sql 先执行
2. 然后 Main 的 070_unify_soft_delete_complete.sql 执行
3. FK 约束从 CASCADE 改为 RESTRICT
4. 现在，如果尝试硬删除用户，会失败
   - 但旧代码可能期望 CASCADE 行为
   - 导致运行时错误
```

**但由于使用了 `ADD IF NOT EXISTS` 和 `DROP IF EXISTS`，实际数据丢失风险较低。**

---

## 总结 & 优先级排序

| 优先级 | 项目 | 工作量 | 影响 |
|--------|------|--------|------|
| P0 CRITICAL | 清理迁移重复 | 2h | 修复迁移系统的基础问题 |
| P0 CRITICAL | 统一 FK 策略 (RESTRICT vs CASCADE) | 4h | 防止意外删除 |
| P0 CRITICAL | 统一 users 表定义 | 6h | 解决跨服务数据不一致 |
| P0 HIGH | 恢复 FK 约束审计 | 3h | 防止孤立数据 |
| P1 MEDIUM | 添加分区 (outbox_events) | 1d | 防止性能下降 |
| P1 MEDIUM | 添加缺失索引 | 2h | 改进查询性能 |
| P2 LOW | 文档化策略 | 2h | 防止未来的问题 |
| P2 LOW | CI/CD 检查 | 4h | 自动化质量控制 |

**总估计工作量: 2-3 天 (如果有经验的 DBA)**

---

## 引用 Linus 的哲学

> **"好程序员关心代码。优秀程序员关心数据结构。"**

Nova 的问题不是代码垃圾，而是**数据结构设计不清晰**:
- 三个不同的 users 表定义
- 不一致的 FK 策略
- 没有明确的微服务 vs 单体决策

> **"只有笨蛋才会在代码级别进行版本控制。"**

这些 `_v2` 后缀证明了迁移策略的失败。应该:
1. 制定明确的架构决策
2. 一次性正确实施
3. 使用分支进行迭代，不要 `_v2`

> **"使用最简单的解决方案。"**

对 CASCADE vs RESTRICT，应该有**单一的决策**:
- 如果是微服务 → 全部 RESTRICT + Outbox
- 如果是单体 → 全部 CASCADE (但这样写的注释要很清楚)

不要同时有两种方式！

---

