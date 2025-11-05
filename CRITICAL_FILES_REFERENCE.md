# Nova 数据库迁移 - 关键文件速查表

## 立即需要修复的文件

### 1. 重复迁移 - 应删除的文件
| 文件路径 | 原因 | 操作 |
|---------|------|------|
| `backend/migrations/065_merge_post_metadata_tables.sql` | 旧版本，v2 更完整 | DELETE |
| `backend/migrations/066_unify_soft_delete_naming.sql` | 旧版本，v2 更完整 | DELETE |
| `backend/migrations/066a_add_deleted_by_to_users_pre_outbox.sql` | 临时补丁 | DELETE |
| `backend/migrations/067_fix_messages_cascade.sql` | 旧架构，被 v2 替代 | DELETE |
| `backend/migrations/068_add_message_encryption_versioning.sql` | 旧版本，v2 更完整 | DELETE |

### 2. 重复迁移 - 应重命名的文件
| 文件路径 | 新名称 | 原因 |
|---------|--------|------|
| `backend/migrations/081_merge_post_metadata_v2.sql` | `065_merge_post_metadata.sql` | 删除 `_v2` 后缀 |
| `backend/migrations/082_unify_soft_delete_v2.sql` | `066_unify_soft_delete.sql` | 删除 `_v2` 后缀 |
| `backend/migrations/083_outbox_pattern_v2.sql` | `067_outbox_pattern.sql` | 删除 `_v2` 后缀 |
| `backend/migrations/084_encryption_versioning_v2.sql` | `068_encryption_versioning.sql` | 删除 `_v2` 后缀 |

### 3. Messaging-Service 重复版本号
| 文件路径 | 新编号 | 原因 |
|---------|--------|------|
| `backend/messaging-service/migrations/0021_create_notification_jobs.sql` | `0022_create_notification_jobs.sql` | 与 location_sharing 冲突 |

---

## 核心问题所在的文件

### FK 约束冲突
| 文件 | 内容 | 问题 | 状态 |
|------|------|------|------|
| `backend/migrations/067_fix_messages_cascade.sql` | `ON DELETE CASCADE` | 旧架构 | 应删除 |
| `backend/migrations/083_outbox_pattern_v2.sql` | `ON DELETE RESTRICT` | 新架构 | 应保留 |
| `backend/migrations/070_unify_soft_delete_complete.sql` | `ON DELETE RESTRICT` | 确认微服务 | ✓ 正确 |

### Users 表不一致
| 文件 | 表位置 | 列数 | 是否 Canonical | 状态 |
|------|--------|------|----------------|------|
| `backend/migrations/001_initial_schema.sql` | Main | 13 | ❓ 不确定 | 需同步 |
| `backend/auth-service/migrations/001_create_users_table.sql` | Auth-Service | 18 | ✓ 推荐 | 应为主源 |
| `backend/messaging-service/migrations/0001_create_users.sql` | Messaging | 3 | ✗ Shadow | 应删除 |

### 软删除列混乱
| 文件 | 变更类型 | 涉及表 | 问题 |
|------|---------|--------|------|
| `backend/migrations/066_unify_soft_delete_naming.sql` | RENAME | posts, comments | 从 soft_delete → deleted_at |
| `backend/migrations/082_unify_soft_delete_v2.sql` | ADD deleted_by | 多个表 | 添加审计列 |
| `backend/migrations/070_unify_soft_delete_complete.sql` | 统一约束 | 所有表 | 需验证完整 |

### FK 约束已删除
| 文件 | 约束 | 表 | 影响 |
|------|------|------|------|
| `backend/messaging-service/migrations/0023_phase1_users_consolidation_app_level_fk.sql` | FK 删除 | conversation_members | 无数据库级保护 |

---

## 验证重点文件

### 需要检查的迁移
```
✓ 检查: backend/migrations/070_unify_soft_delete_complete.sql (行数: 445)
  - 验证所有 FK 都是 RESTRICT (行 203-255)
  - 验证所有软删除约束 (行 34-126)
  - 验证触发器完整 (行 42-445)

✓ 检查: backend/migrations/071_add_deleted_by_to_users.sql
  - 验证 users.deleted_by 外键 (行 19-20)
  - 验证自引用约束 (行 19)

✓ 检查: backend/messaging-service/migrations/0023_*
  - 审视为何删除 FK 约束 (设计决策）
```

---

## 关键统计数据

### 迁移文件统计
```
Main migrations:    62 个文件
Auth-Service:       4 个文件
User-Service:       2 个文件
Messaging-Service: 27 个文件
---
总计: 95 个迁移文件

发现的问题:
- 5 个重复版本号
- 1 个重复编号（Messaging 0021)
- 版本号缺失: 008, 009, 036, 037, 042-051
```

### 受影响的表
```
直接涉及 FK 约束冲突的表:
- users (central table)
- posts, comments, messages, follows, blocks, media (9 个 FK 关系)
- conversation_members (已移除 FK，需恢复)

受软删除列混乱影响的表:
- posts, comments, messages, conversations, follows, blocks, media
- 可能某些表缺少 deleted_by 列
```

---

## 修复顺序（推荐）

### 第 1 步: 清理迁移版本
**涉及文件:**
```
DELETE:
  065_merge_post_metadata_tables.sql
  066_unify_soft_delete_naming.sql
  066a_add_deleted_by_to_users_pre_outbox.sql
  067_fix_messages_cascade.sql
  068_add_message_encryption_versioning.sql
  
RENAME:
  081_merge_post_metadata_v2.sql → 065_merge_post_metadata.sql
  082_unify_soft_delete_v2.sql → 066_unify_soft_delete.sql
  083_outbox_pattern_v2.sql → 067_outbox_pattern.sql
  084_encryption_versioning_v2.sql → 068_encryption_versioning.sql
  
RENUMBER:
  0021_create_notification_jobs.sql → 0022_create_notification_jobs.sql
```

**验证命令:**
```bash
git log --oneline backend/migrations/06*.sql
ls backend/migrations/ | grep "_v2" | wc -l  # 应该 = 0
```

### 第 2 步: 统一 FK 约束
**涉及文件:**
```
主要: backend/migrations/070_unify_soft_delete_complete.sql
验证: 所有指向 users 的 FK 都有 ON DELETE RESTRICT
```

**SQL 验证:**
```sql
SELECT t.table_name, kcu.column_name, ccu.table_name, rc.delete_rule
FROM information_schema.table_constraints t
JOIN information_schema.key_column_usage kcu USING(table_name, constraint_name)
JOIN information_schema.constraint_column_usage ccu ON t.constraint_name = ccu.constraint_name
JOIN information_schema.referential_constraints rc ON t.constraint_name = rc.constraint_name
WHERE ccu.table_name = 'users' AND t.constraint_type = 'FOREIGN KEY'
ORDER BY t.table_name;
-- 所有 delete_rule 应该 = 'RESTRICT'
```

### 第 3 步: 统一 users 表
**涉及文件:**
```
主源: backend/auth-service/migrations/001_create_users_table.sql
同步: backend/migrations/001_initial_schema.sql (需添加缺失列)
删除: backend/messaging-service/migrations/0001_create_users.sql

创建新迁移: 074_sync_users_schema_across_services.sql
```

### 第 4 步: 恢复 FK 约束
**涉及文件:**
```
处理: backend/messaging-service/migrations/0023_phase1_users_consolidation_app_level_fk.sql

创建新迁移: backend/messaging-service/migrations/0024_restore_fk_constraints.sql
- 检查孤立数据
- 恢复 conversation_members FK
- 添加其他缺失的 FK
```

---

## 快速检查命令

```bash
# 1. 查看所有迁移版本号
ls backend/migrations/*.sql | sed 's/.*\///' | sed 's/_.*$//' | sort -n | uniq -c

# 2. 查找 _v2 文件（应该没有）
find backend -name "*_v2.sql"

# 3. 查找 CASCADE FK（应该没有）
grep -r "ON DELETE CASCADE" backend/migrations/06*.sql backend/migrations/07*.sql

# 4. 验证 IF NOT EXISTS（应该都有）
grep -L "IF NOT EXISTS" backend/migrations/07[0-9]*.sql

# 5. 计算迁移文件总数
find backend -path "*migrations*.sql" -type f | wc -l

# 6. 检查最新的迁移版本号
ls backend/migrations/*.sql | sed 's/.*\///' | sed 's/_.*$//' | sort -n | tail -5
```

---

## 文件修改影响范围

### 高风险修改（需要测试）
- 删除或重命名迁移文件
- 修改 FK 约束（影响所有指向用户的表）
- 删除 shadow users 表（影响 Messaging-Service）

### 中等风险修改（需要代码审查）
- 统一 users 表定义（影响认证流程）
- 恢复 FK 约束（影响数据验证）

### 低风险修改（自动化）
- 添加缺失索引
- 添加缺失约束
- 更新文档

---

## 文档位置

### 本次审查生成的文档
```
/DATABASE_MIGRATION_AUDIT.md (810 行详细分析)
/DB_MIGRATION_FIXES_CHECKLIST.md (执行清单)
/AUDIT_EXECUTIVE_SUMMARY.md (高管摘要)
/CRITICAL_FILES_REFERENCE.md (本文件)
```

### 应该创建的文档
```
backend/docs/DATABASE_MIGRATION_STRATEGY.md
backend/docs/FK_CONSTRAINTS_POLICY.md
backend/docs/SOFT_DELETE_PATTERN.md
```

---

**最后更新:** 2025-11-05  
**审查者:** Linus-style Architecture Review  
**风险评级:** 🔴 中等 → ✅ 低 (修复后)

