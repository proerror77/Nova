# Nova 项目数据库迁移审查 - 执行总结

**审查日期:** 2025-11-05  
**审查范围:** 全部后端数据库迁移  
**总体风险评级:** 🔴 **中等 - 需立即行动**

---

## 核心发现 (3个P0问题)

### 问题 1: 迁移版本号冲突 🔴 CRITICAL
**状态:** 已发现，需立即修复  
**影响:** 迁移系统不可靠，生产-开发环境 schema 可能不同步

**发现的重复:**
- `065_*.sql` (2个版本)
- `066_*.sql` (2个版本 + 1个临时补丁)
- `067_*.sql` (2个版本)
- `068_*.sql` (2个版本)
- `0021_*.sql` (Messaging-service 中重复)

**修复工作量:** 2 小时  
**优先级:** P0 - 第一天完成

---

### 问题 2: FK 约束策略矛盾 🔴 CRITICAL
**状态:** 已发现，需立即统一  
**影响:** 删除行为不一致，数据完整性风险

**症状:**
```
067_fix_messages_cascade.sql:     ON DELETE CASCADE    (旧、单体应用思路)
083_outbox_pattern_v2.sql:        ON DELETE RESTRICT   (新、微服务思路)
070_unify_soft_delete_complete.sql: ON DELETE RESTRICT (确认微服务)
```

**决策:** 全部改为 `RESTRICT` + Outbox 事件驱动删除  
**修复工作量:** 4 小时  
**优先级:** P0 - 第二天完成

---

### 问题 3: 跨服务 users 表严重不一致 🔴 CRITICAL
**状态:** 已发现，团队已察觉但采取了最坏的解决方案  
**影响:** 数据同步困难，GDPR 合规性问题，孤立数据风险

**三个不同的 users 表定义:**
1. **Main migration** (001): 完整的认证字段
2. **Auth-Service** (001): 包含 TOTP、电话、邮件验证时间（比 Main 更完整）
3. **Messaging-Service** (0001): 只有 3 列（shadow copy，已标记为弃用）

**当前最坏的决策:**
```sql
-- Messaging-Service 0023 中删除了 FK 约束
ALTER TABLE conversation_members
  DROP CONSTRAINT IF EXISTS conversation_members_user_id_fkey;
```
→ 现在可以插入孤立数据，没有数据库级保护

**正确做法:**
- Auth-Service 是 canonical source
- 删除 Messaging-Service 的 shadow users 表
- 恢复 FK 约束: `ON DELETE RESTRICT`
- 应用层使用 gRPC API 调用 auth-service

**修复工作量:** 6 小时  
**优先级:** P0 - 第二天完成

---

## 其他严重问题 (2个P0-HIGH)

### 问题 4: 软删除列定义混乱
- 某些表有 `deleted_at` 但没有 `deleted_by`
- Outbox 触发器假设两列都存在
- 需要统一约束: `(deleted_at IS NULL AND deleted_by IS NULL) OR (...)`

**修复工作量:** 2 小时  
**优先级:** P0-HIGH

### 问题 5: 缺失 FK 约束（Messaging-Service）
- `conversation_members.user_id` 没有 FK 约束
- 可能存在孤立数据
- 需要恢复约束

**修复工作量:** 2 小时  
**优先级:** P0-HIGH

---

## 性能问题 (P1)

### 索引缺失
- `conversation_members` 缺少 `user_id` 索引
- `follows` 缺少复合索引

### 缺乏分区
- `outbox_events` 快速增长，需要按月分区
- `messages` 需要按月分区

**预计工作量:** 1-2 天  
**优先级:** P1 - 2 周内完成

---

## 文档/流程问题 (P2)

- 缺乏迁移策略文档
- 无 CI/CD 验证
- 无迁移验证脚本

**预计工作量:** 1 天  
**优先级:** P2 - 1 个月内完成

---

## 数据丢失风险评估

**当前:** ⚠️ 中等风险
- 迁移使用 `IF NOT EXISTS`，大部分是幂等的
- 但由于版本号混乱，可能在生产环境中执行错误的迁移
- FK 约束已被删除，孤立数据可能存在

**修复后:** ✅ 低风险

---

## 快速修复计划 (3天)

### 第一天 (4小时)
1. ✅ 删除重复迁移文件 (30分钟)
   - 删除旧版本（非 _v2）
   - 重命名 _v2 为主版本

2. ✅ 统一 FK 约束 (2小时)
   - 审查 070 迁移确保所有 FK 都是 RESTRICT
   - 创建新迁移修复任何遗漏的 CASCADE

3. ✅ 检查软删除列 (1.5小时)
   - 确保所有表有 (deleted_at, deleted_by) 对
   - 验证约束存在

### 第二天 (6小时)
4. ✅ 统一 users 表定义 (3小时)
   - 决定 canonical source (推荐: Auth-Service)
   - 同步 Main migration 和 Auth-Service
   - 创建迁移删除 Messaging-Service 的 shadow users

5. ✅ 恢复 FK 约束 (2小时)
   - 检查孤立数据
   - 恢复 conversation_members FK
   - 测试

6. ✅ 修复 Messaging-Service 迁移版本号 (1小时)

### 第三天 (4小时)
7. ✅ 添加缺失索引 (1小时)
8. ✅ 创建文档 (2小时)
9. ✅ 设置 CI/CD 检查 (1小时)

**总计:** 14 小时 (2 个工作日)

---

## 建议行动

### 立即行动 (今天)
1. [ ] 召开 3 人会议 (架构师 + DBA + Lead)
2. [ ] 确认 FK 策略决策: CASCADE vs RESTRICT
3. [ ] 确认 users 表 canonical source
4. [ ] 创建修复 PR 分支

### 这周完成
1. [ ] 执行第一天修复
2. [ ] 执行第二天修复  
3. [ ] 在开发环境中验证
4. [ ] PR 审查 + 合并

### 下周
1. [ ] 执行第三天改进
2. [ ] 更新文档
3. [ ] 培训团队新的迁移策略

---

## 关键指标

| 指标 | 当前状态 | 目标状态 | 检验方法 |
|------|---------|---------|---------|
| 迁移版本重复 | 5 个冲突 | 0 个冲突 | `git ls backend/migrations/` |
| FK 约束一致性 | 混乱 | 100% RESTRICT | SQL 查询 `information_schema` |
| users 表定义 | 3 个不同定义 | 1 个 canonical | 对比 SQL schema |
| 孤立数据 | 未检查 | 0 条 | SQL COUNT 查询 |
| 软删除列对 | 缺失 | 100% 完整 | SQL 查询验证 |

---

## 成功标准

修复完成后，应该能通过:

```bash
# 1. 迁移脚本能确定执行顺序
flyway validate

# 2. 没有重复的迁移版本号
ls backend/migrations/*.sql | sed 's/_.*//' | sort | uniq -d
# 输出: (空)

# 3. 所有 FK 都是 RESTRICT
psql -c "SELECT constraint_name FROM information_schema.referential_constraints 
         WHERE foreign_table_name='users' AND delete_rule != 'RESTRICT';"
# 输出: (无行)

# 4. 没有孤立数据
psql -c "SELECT COUNT(*) FROM conversation_members cm 
         WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.id = cm.user_id);"
# 输出: 0

# 5. 所有软删除表有完整约束
psql -c "SELECT table_name FROM information_schema.columns 
         WHERE column_name='deleted_at' GROUP BY table_name
         EXCEPT
         SELECT table_name FROM information_schema.columns 
         WHERE column_name='deleted_by';"
# 输出: (无行)
```

---

## 预期收益

### 技术债减少
- ✅ 消除迁移混乱，提高系统可靠性
- ✅ 统一 FK 策略，降低数据损坏风险
- ✅ 消除跨服务数据不一致
- ✅ 改进开发体验

### 运维改善
- ✅ 能够预测数据库行为
- ✅ 能够安全地回滚迁移
- ✅ 能够在生产环境中复现 schema
- ✅ 完全自动化的验证

### 合规改进
- ✅ GDPR 审计日志完整
- ✅ 数据完整性有保证
- ✅ 没有孤立数据

---

**总体评价:** 项目采用了正确的架构方向（微服务 + Outbox 模式），但执行过程中出现了多个不协调的更改。通过 2-3 天的集中修复，可以将系统从"中等风险"降低到"低风险"。

**下一步:** 联系架构师，确认决策，启动修复。

