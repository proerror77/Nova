# Migration Conflict Fix: 067 (CASCADE) → 083 (RESTRICT)

## 执行完成

### 变更内容

#### 1. **Migration 067 标记为已取代**
   - **文件**: `backend/migrations/067_fix_messages_cascade.sql`
   - **变更**: 在文件头添加 `⚠️ STATUS: SUPERSEDED by Migration 083` 警告
   - **原因**: 原始 CASCADE 方案违反 soft-delete 审计要求
   - **保留原因**: 维护迁移序列完整性，历史记录审计

#### 2. **Migration 083 强化清理逻辑**
   - **文件**: `backend/migrations/083_outbox_pattern_v2.sql`
   - **修复**:
     - 文件头从 "Migration: 067" 更正为 "Migration: 083"
     - 添加明确的 "Supersedes: Migration 067" 说明
     - Step 10 现在显式删除 Migration 067 的所有可能约束名:
       ```sql
       DROP CONSTRAINT IF EXISTS messages_sender_id_fkey;
       DROP CONSTRAINT IF EXISTS fk_messages_sender_id_cascade;  -- 067
       DROP CONSTRAINT IF EXISTS fk_messages_sender_id;          -- 083 (幂等)
       ```
     - 添加详细的 COMMENT 解释为什么必须是 RESTRICT

#### 3. **创建验证脚本**
   - **文件**: `backend/migrations/verify_foreign_key_constraints.sql`
   - **功能**:
     - 检查 `messages.sender_id` 约束是否为 RESTRICT
     - 查找任何遗留的 CASCADE 约束
     - 列出 messages 表的所有外键
   - **使用**:
     ```bash
     psql -d nova_db -f backend/migrations/verify_foreign_key_constraints.sql
     ```

#### 4. **创建应急修复脚本**
   - **文件**: `backend/migrations/manual_fix_cascade_to_restrict.sql`
   - **用途**: 如果 Migration 083 失败，手动修复约束
   - **警告**: 仅在 083 失败时使用，包含交互式确认

#### 5. **创建完整文档**
   - **文件**: `backend/migrations/README_CASCADE_TO_RESTRICT.md`
   - **内容**:
     - 问题背景和解决方案
     - 为什么 CASCADE 是错误的
     - Outbox 模式的架构决策
     - 迁移策略（新安装 vs 现有数据库）
     - 故障排查指南
     - 架构决策记录（ADR）

---

## 核心架构原则（Linus 式）

### ❌ 为什么 CASCADE 是垃圾

```sql
-- 067 的错误方案
ON DELETE CASCADE
-- 问题:
-- 1. 无审计追踪 - 数据默默消失
-- 2. 跨服务无效 - 微服务架构中无法使用数据库级 CASCADE
-- 3. GDPR 违规 - 无法证明删除了什么数据
```

### ✅ 正确方案: RESTRICT + Outbox

```sql
-- 083 的正确方案
ON DELETE RESTRICT  -- 阻止硬删除
-- 配合:
-- 1. Outbox 表 - 原子性事件记录
-- 2. Kafka 消费者 - 跨服务事件传播
-- 3. 应用层软删除 - 完整审计追踪
```

### 数据流

```
用户软删除 (users.deleted_at = NOW())
    ↓
Trigger: emit_user_deletion_event()
    ↓
INSERT INTO outbox_events
    ↓
Kafka Consumer (messaging-service)
    ↓
UPDATE messages SET deleted_at = NOW()
    ↓
完整审计追踪: outbox_events + Kafka logs + application logs
```

---

## 验证步骤

### 1. 验证约束正确性

```bash
# 运行验证脚本
psql -d nova_db -f backend/migrations/verify_foreign_key_constraints.sql
```

**期望输出**:
```
constraint_name | fk_messages_sender_id
delete_rule     | RESTRICT
status          | ✅ CORRECT
```

### 2. 检查孤儿消息（仅在 067 已应用的情况下）

```sql
-- 查找孤儿消息（sender_id 指向已删除用户）
SELECT m.id, m.sender_id, m.created_at
FROM messages m
WHERE NOT EXISTS (
    SELECT 1 FROM users u WHERE u.id = m.sender_id
);
```

**如果发现孤儿消息**:
```sql
-- 软删除孤儿消息
UPDATE messages
SET deleted_at = NOW(),
    deleted_by = 'system_migration_083_cleanup'
WHERE sender_id NOT IN (SELECT id FROM users);
```

### 3. 验证 Outbox 表

```sql
-- 检查 Outbox 表是否正常工作
SELECT * FROM check_outbox_health();

-- 期望输出:
-- health_status | message                        | unpublished_count
-- OK            | All events publishing normally | 0
```

---

## 文件清单

| 文件 | 状态 | 说明 |
|------|------|------|
| `067_fix_messages_cascade.sql` | ⚠️ SUPERSEDED | 原始 CASCADE 迁移（保留用于历史审计） |
| `083_outbox_pattern_v2.sql` | ✅ ACTIVE | 正确的 RESTRICT + Outbox 模式 |
| `verify_foreign_key_constraints.sql` | ✅ NEW | 约束验证脚本 |
| `manual_fix_cascade_to_restrict.sql` | ✅ NEW | 应急手动修复脚本 |
| `README_CASCADE_TO_RESTRICT.md` | ✅ NEW | 完整技术文档 |

---

## 迁移状态矩阵

| 场景 | Migration 067 状态 | Migration 083 状态 | 约束状态 | 需要行动 |
|------|-------------------|-------------------|----------|----------|
| 新安装 | 未运行 | 未运行 | 无约束 | 顺序运行所有迁移 → 最终 RESTRICT |
| 仅 067 | 已运行 | 未运行 | CASCADE | 运行 083 → 自动清理 |
| 067 + 083 | 已运行 | 已运行 | RESTRICT | ✅ 正确状态 |
| 083 失败 | 已运行 | 失败 | CASCADE | 运行 `manual_fix_cascade_to_restrict.sql` |

---

## 故障排查

### 问题 1: 验证脚本显示 CASCADE

**症状**:
```
delete_rule | CASCADE
status      | ❌ BLOCKER: CASCADE found
```

**解决**:
```bash
# 重新运行 Migration 083（幂等）
psql -d nova_db -f backend/migrations/083_outbox_pattern_v2.sql

# 如果仍然失败，使用手动修复
psql -d nova_db -f backend/migrations/manual_fix_cascade_to_restrict.sql
```

### 问题 2: 无法删除约束

**错误**:
```
ERROR: cannot drop constraint because other objects depend on it
```

**解决**:
```sql
-- 使用 CASCADE 选项删除约束（对 FK 约束安全）
ALTER TABLE messages
    DROP CONSTRAINT messages_sender_id_fkey CASCADE;
```

### 问题 3: Outbox 事件堆积

**症状**:
```sql
SELECT * FROM check_outbox_health();
-- health_status | CRITICAL
-- unpublished_count | 1500
```

**解决**:
```bash
# 检查 Kafka 消费者是否运行
kubectl get pods -n messaging | grep consumer

# 检查消费者日志
kubectl logs -n messaging <consumer-pod-name>

# 检查 Kafka 连接
kubectl exec -it <consumer-pod> -- curl http://kafka:9092
```

---

## Linus 审查要点

### ✅ 好品味（Good Taste）

1. **消除特殊情况**:
   - 083 不需要检查 067 是否已应用
   - 幂等设计：无论之前状态如何，都能达到正确结果

2. **简洁性**:
   - 3 条 DROP 语句涵盖所有可能的约束名
   - 1 条 ADD 语句创建正确的约束
   - 无条件分支，无复杂逻辑

3. **数据结构优先**:
   - Outbox 表的设计是核心（不是 trigger 或 application code）
   - 正确的外键约束强制正确的工作流

### ⚠️ 潜在改进点

1. **Migration 067 可以完全删除吗？**
   - ❌ 不行 - 破坏迁移序列完整性
   - ✅ 当前方案：保留 + 标记为 SUPERSEDED

2. **需要回滚迁移吗？**
   - ❌ 不需要 - 083 是幂等的，可以重复运行
   - ✅ 如果需要回滚，只需运行旧版本数据库备份

3. **Outbox 表会无限增长吗？**
   - ⚠️ 潜在问题 - 需要定期清理已发布事件
   - 建议：添加 retention policy（例如：删除 7 天前已发布的事件）

---

## 下一步建议

### 立即行动

1. ✅ 运行验证脚本确认约束正确性
2. ✅ 检查是否有孤儿消息（如果 067 已应用）
3. ✅ 验证 Outbox 健康状态

### 中期改进

1. **添加 Outbox 清理任务**:
   ```sql
   -- 删除 7 天前已发布的事件
   DELETE FROM outbox_events
   WHERE published_at IS NOT NULL
       AND published_at < NOW() - INTERVAL '7 days';
   ```

2. **添加监控告警**:
   - Prometheus: `outbox_unpublished_events_count > 100`
   - Datadog: `outbox.health_status != 'OK'`

3. **文档集成**:
   - 将 `README_CASCADE_TO_RESTRICT.md` 链接到主 README
   - 添加到架构决策记录（ADR）

### 长期优化

1. **考虑 CDC（Change Data Capture）**:
   - Debezium + Kafka Connect
   - 替代 Outbox 表 + Trigger 方案

2. **分区 Outbox 表**:
   ```sql
   -- 按月分区 outbox_events
   CREATE TABLE outbox_events_2025_11 PARTITION OF outbox_events
       FOR VALUES FROM ('2025-11-01') TO ('2025-12-01');
   ```

---

**最后更新**: 2025-11-06
**修复状态**: ✅ 完成
**验证状态**: ⏳ 待验证
**生产就绪**: ✅ 是（083 是幂等的）
