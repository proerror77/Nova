# Nova 数据库迁移 - 快速修复清单

## P0 CRITICAL - 必须立即修复

### 1. 删除重复的迁移文件

**受影响的文件:**
```
backend/migrations/065_merge_post_metadata_tables.sql (删除 - 旧版本)
backend/migrations/066_unify_soft_delete_naming.sql (删除 - 旧版本)
backend/migrations/067_fix_messages_cascade.sql (删除 - 旧版本)
backend/migrations/068_add_message_encryption_versioning.sql (删除 - 旧版本)
backend/messaging-service/migrations/0021_create_location_sharing.sql (检查 - 可能错误编号)
```

**操作:**
```bash
cd backend/migrations
git rm 065_merge_post_metadata_tables.sql
git rm 066_unify_soft_delete_naming.sql
git rm 067_fix_messages_cascade.sql
git rm 068_add_message_encryption_versioning.sql
git rm 066a_add_deleted_by_to_users_pre_outbox.sql  # 临时补丁，应删除

# 重命名 _v2 版本（删除后缀）
git mv 081_merge_post_metadata_v2.sql 065_merge_post_metadata.sql
git mv 082_unify_soft_delete_v2.sql 066_unify_soft_delete.sql
git mv 083_outbox_pattern_v2.sql 067_outbox_pattern.sql
git mv 084_encryption_versioning_v2.sql 068_encryption_versioning.sql
```

### 2. 统一 FK 约束（必须全部改为 RESTRICT）

**涉及文件:** `backend/migrations/070_unify_soft_delete_complete.sql`

**检查项:**
```sql
-- ✓ 已正确: users(id) ← ? ON DELETE RESTRICT
SELECT constraint_name, table_name, column_name, foreign_table_name
FROM information_schema.referential_constraints
WHERE foreign_table_name = 'users'
ORDER BY table_name;
```

**确保所有 FK 都有 ON DELETE RESTRICT:**
- [x] posts.user_id → users(id)
- [x] comments.user_id → users(id)
- [x] messages.sender_id → users(id)
- [x] follows.follower_id → users(id)
- [x] follows.following_id → users(id)
- [x] blocks.blocker_id → users(id)
- [x] blocks.blocked_id → users(id)
- [x] media.owner_id → users(id)

### 3. 统一 users 表定义

**决策:** Auth-Service 是 canonical source
- [x] Auth-Service: 包含完整的 users 信息
- [ ] Main Migrations: 001_initial_schema.sql 应与 Auth-Service 一致
- [ ] Messaging-Service: 删除 shadow users 表，改用 gRPC

**需要修复的不一致:**
```
Main migration 001 vs Auth-Service 001:
- Main 有 is_active, Auth-Service 没有 ← 需要同步
- Auth-Service 有 totp_*, phone_*, email_verified_at ← Main 没有
- Messaging-Service: 只有 3 列，严重不足 ← 应删除，改用 gRPC
```

### 4. 恢复 FK 约束（Messaging-Service）

**受影响的文件:** `backend/messaging-service/migrations/0023_phase1_users_consolidation_app_level_fk.sql`

**当前状态:**
```sql
-- ❌ 已移除 FK 约束
ALTER TABLE conversation_members
  DROP CONSTRAINT IF EXISTS conversation_members_user_id_fkey;
```

**应修复为:**
```sql
-- 创建新迁移: 0024_restore_fk_constraints.sql
-- 但前提是先恢复 canonical users 表

-- Step 1: 检查孤立数据
SELECT COUNT(*) FROM conversation_members cm
WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.id = cm.user_id);

-- Step 2: 清理孤立数据（如果有）
DELETE FROM conversation_members cm
WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.id = cm.user_id);

-- Step 3: 恢复 FK
ALTER TABLE conversation_members
    ADD CONSTRAINT fk_conversation_members_user_id
    FOREIGN KEY (user_id) REFERENCES users(id)
    ON DELETE RESTRICT;

-- Step 4: 删除 shadow users 表
DROP TABLE IF EXISTS users;

-- Step 5: 应用应该使用 gRPC 调用 auth-service
```

---

## P0 HIGH - 需要在 2-3 天内修复

### 5. 检查所有软删除表的 (deleted_at, deleted_by) 对

**需要验证的表:**
```sql
SELECT table_name 
FROM information_schema.columns 
WHERE column_name = 'deleted_at'
GROUP BY table_name;
```

**检查清单:**
- [x] posts: 有 deleted_at, deleted_by, 有约束
- [x] comments: 有 deleted_at, deleted_by, 有约束
- [x] messages: 有 deleted_at, deleted_by, 有约束
- [x] conversations: 有 deleted_at, deleted_by, 有约束
- [x] follows: 有 deleted_at, deleted_by, 有约束
- [x] blocks: 有 deleted_at, deleted_by, 有约束
- [x] media: 有 deleted_at, deleted_by, 有约束
- [ ] users: 有 deleted_at, deleted_by, 有约束 ← 检查

**验证约束存在:**
```sql
SELECT constraint_name FROM information_schema.check_constraints
WHERE table_name = 'posts' AND constraint_name LIKE '%deleted%';
-- 应该看到: posts_deleted_at_logic (或类似的名称)
```

### 6. 检查消息服务中的迁移版本号

**问题:** 0021 重复
```
0021_create_location_sharing.sql
0021_create_notification_jobs.sql  ← 重复
```

**修复:** 其中一个应该重新编号为 0022
```bash
cd backend/messaging-service/migrations
git mv 0021_create_notification_jobs.sql 0022_create_notification_jobs.sql
```

---

## P1 MEDIUM - 1-2 周内改进

### 7. 添加分区（从 outbox_events 开始）

**优先级:**
1. outbox_events (增长最快)
2. messages (百万级行)
3. posts (百万级行)

### 8. 添加缺失的索引

```sql
-- 新增迁移: 074_add_missing_indexes.sql
CREATE INDEX IF NOT EXISTS idx_conversation_members_user_id 
    ON conversation_members(user_id);

CREATE INDEX IF NOT EXISTS idx_follows_follower_active
    ON follows(follower_id, created_at DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_blocks_blocker_active
    ON blocks(blocker_id, created_at DESC)
    WHERE deleted_at IS NULL;
```

---

## P2 LOW - 文档和流程改进

### 9. 创建迁移验证脚本

**文件:** `backend/scripts/verify_database_schema.sql`

```sql
-- 检查清单
1. 所有用户端表都有 created_at
2. 所有软删除表都有 (deleted_at, deleted_by) 对且有约束
3. 所有指向 users 的 FK 都是 RESTRICT
4. 没有 orphaned 约束（已删除但约束还在）
5. 没有重复索引
```

### 10. 文档化迁移策略

**文件:** `backend/docs/DATABASE_MIGRATION_STRATEGY.md`

**内容应包括:**
- 迁移命名约定
- 版本号连续性要求
- FK 约束规则（全部 RESTRICT）
- 软删除模式（always (deleted_at, deleted_by)）
- Outbox 事件触发器

### 11. 设置 CI/CD 检查

**文件:** `.github/workflows/db-migration-check.yml`

```yaml
name: Database Migration Checks
on: [pull_request]

jobs:
  migrations:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Check migration continuity
        script: |
          # 检查版本号没有间隙（除了已知的）
          # 检查没有 _v2 后缀
          # 检查没有硬 CASCADE FK
          # 检查所有软删除表都有约束
```

---

## 验证清单

执行这些查询以验证修复：

```sql
-- 1. 检查重复的迁移版本号
SELECT COUNT(*) as migration_count,
       substring(file_name FROM 1 FOR 3) as version
FROM schema_migrations_log
GROUP BY version
HAVING COUNT(*) > 1;
-- 预期: 无结果

-- 2. 检查 FK 约束
SELECT constraint_name, table_name, 
       delete_rule, update_rule
FROM information_schema.referential_constraints
WHERE foreign_table_name = 'users'
ORDER BY table_name;
-- 预期: 所有 delete_rule = 'RESTRICT'

-- 3. 检查软删除列
SELECT table_name FROM information_schema.columns
WHERE column_name = 'deleted_at'
EXCEPT
SELECT table_name FROM information_schema.columns
WHERE column_name = 'deleted_by';
-- 预期: 无结果（所有有 deleted_at 的表都有 deleted_by）

-- 4. 检查孤立 FK 约束
SELECT constraint_name FROM information_schema.table_constraints
WHERE constraint_type = 'FOREIGN KEY'
  AND table_name NOT IN (SELECT table_name FROM information_schema.tables);
-- 预期: 无结果

-- 5. 检查 Outbox 事件
SELECT COUNT(*) as unpublished_events
FROM outbox_events
WHERE published_at IS NULL
  AND created_at > NOW() - INTERVAL '24 hours'
  AND retry_count < 3;
-- 预期: 应该逐渐减少
```

---

## 风险评估

### 当前风险: ⚠️ 中等

**如果不修复:**
- 迁移可能以不同顺序执行，导致不同的 schema
- 硬删除行为不一致（CASCADE vs RESTRICT）
- 孤立数据可能出现
- GDPR 合规性问题

**修复后:** ✅ 低风险

---

## 实施顺序

1. **第一天上午:** 删除重复迁移，重新提交
2. **第一天下午:** 检查并统一 FK 约束
3. **第二天上午:** 统一 users 表定义，恢复 FK
4. **第二天下午:** 验证修复，修改 Messaging-Service
5. **第三天:** 文档化、CI/CD 设置、性能优化

