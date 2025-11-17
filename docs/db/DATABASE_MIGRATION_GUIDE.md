# Database Migration Guide (Phase 0-E Consolidation)

**Created**: 2025-11-12
**Status**: Action Required
**Purpose**: Resolve schema conflicts from service refactoring (17 → 14 services)

---

## Executive Summary

### 问题诊断
根据 `SERVICE_REFACTORING_PLAN.md`，Phase 0-E 已完成，但数据库 schema 存在严重冲突：

| 冲突类型 | 受影响服务 | 问题描述 |
|---------|-----------|---------|
| 🔴 表名冲突 | social-service | `post_shares` vs `shares`<br>`social_metadata` vs `post_counters` |
| 🔴 缺失表 | social-service | 主迁移缺少 `comment_likes`, `processed_events` |
| 🟡 重复定义 | realtime-chat-service | 主迁移 `018_messaging_schema.sql` vs 服务迁移 (10 files) |
| ✅ 无冲突 | feature-store | 主迁移无定义，可直接集成 |

### 修改清单
- ✅ 创建清理迁移：`999_cleanup_social_conflicts.sql`
- ✅ 创建清理迁移：`998_deprecate_old_messaging_schema.sql`
- ✅ 集成 social-service schema: `100_social_service_schema.sql`
- ✅ 集成 feature-store schema: `101_feature_store_metadata.sql`
- ⏳ 待执行：应用迁移并验证

---

## 数据库拓扑结构（推荐）

### 方案 A: 单库模式（当前实现）
```
PostgreSQL (nova)
  ├─ content-service 表
  ├─ user-service 表
  ├─ social-service 表 (新)
  ├─ feature-store metadata 表 (新)
  └─ realtime-chat-service 表 (新)

ClickHouse (feature_store)
  └─ features 表

Neo4j
  └─ FOLLOWS 边
```

**优点**: 简单，事务一致性
**缺点**: 服务耦合，扩展受限

---

### 方案 B: 微服务独立数据库（未来演进）
```
PostgreSQL (nova)          - content, user, identity
PostgreSQL (nova_social)   - social-service 独占
PostgreSQL (nova_chat)     - realtime-chat-service 独占
PostgreSQL (nova_features) - feature-store 独占
ClickHouse (feature_store) - 近线特征
Neo4j                      - 社交图谱
```

**优点**: 完全解耦，独立扩展
**缺点**: 运维复杂，需要 Saga 模式

---

## 迁移执行步骤

### 前提条件确认
```bash
# 1. 检查 PostgreSQL 是否运行
psql -U postgres -c "SELECT version();"

# 2. 检查当前数据库状态
psql -U postgres -d nova -c "\dt" | grep -E "(likes|shares|post_counters|conversations)"

# 3. 备份现有数据（如果有）
pg_dump -U postgres nova > backup_$(date +%Y%m%d_%H%M%S).sql
```

---

### Step 1: 清理冲突表 (social + messaging)

**执行**:
```bash
cd backend
sqlx migrate run --source migrations --database-url "postgres://postgres:postgres@localhost:5432/nova"
```

**预期结果**:
- ✅ 删除 `post_shares`, `social_metadata`, `bookmarks`
- ✅ 删除 `conversations`, `conversation_members`, `messages` (旧版)
- ✅ 迁移历史表更新

**验证**:
```sql
-- 确认旧表已删除
SELECT tablename FROM pg_tables WHERE schemaname = 'public'
  AND tablename IN ('post_shares', 'social_metadata', 'bookmarks');
-- 应该返回 0 行
```

---

### Step 2: 应用 social-service schema

**执行**:
```bash
# 迁移文件已复制到 backend/migrations/100_social_service_schema.sql
# 继续运行主迁移即可
sqlx migrate run --source migrations --database-url "postgres://postgres:postgres@localhost:5432/nova"
```

**预期结果**:
- ✅ 创建 `shares` (替代 `post_shares`)
- ✅ 创建 `post_counters` (替代 `social_metadata`)
- ✅ 创建 `comment_likes` (新)
- ✅ 创建 `processed_events` (新，幂等性支持)
- ✅ 创建 8 个触发器（自动计数维护）
- ✅ 创建 18 个索引

**验证**:
```sql
-- 确认新表已创建
SELECT tablename FROM pg_tables WHERE schemaname = 'public'
  AND tablename IN ('shares', 'post_counters', 'comment_likes', 'processed_events');
-- 应该返回 4 行

-- 检查触发器
SELECT tgname FROM pg_trigger WHERE tgname LIKE '%_counter%';
-- 应该返回 8 个触发器
```

---

### Step 3: 应用 feature-store schema (PostgreSQL)

**执行**:
```bash
# 迁移文件已复制到 backend/migrations/101_feature_store_metadata.sql
sqlx migrate run --source migrations --database-url "postgres://postgres:postgres@localhost:5432/nova"
```

**预期结果**:
- ✅ 创建 `entity_types` (实体类型定义)
- ✅ 创建 `feature_definitions` (特征元数据)

**验证**:
```sql
SELECT tablename FROM pg_tables WHERE schemaname = 'public'
  AND tablename IN ('entity_types', 'feature_definitions');
-- 应该返回 2 行
```

---

### Step 4: 应用 feature-store schema (ClickHouse)

**执行**:
```bash
cd backend/feature-store
clickhouse-client -h localhost --port 9000 < migrations/002_clickhouse_schema.sql
```

**验证**:
```bash
clickhouse-client -h localhost --query "SHOW TABLES FROM feature_store"
# 应该返回: features
```

---

### Step 5: 应用 realtime-chat-service schema

**方案 A: 共享主数据库 (简单)**
```bash
cd backend/realtime-chat-service
sqlx migrate run --source migrations --database-url "postgres://postgres:postgres@localhost:5432/nova"
```

**方案 B: 独立数据库 (推荐)**
```bash
# 1. 创建独立数据库
psql -U postgres -c "CREATE DATABASE nova_chat;"

# 2. 应用迁移
cd backend/realtime-chat-service
sqlx migrate run --source migrations --database-url "postgres://postgres:postgres@localhost:5432/nova_chat"

# 3. 更新服务配置
echo "DATABASE_URL=postgres://postgres:postgres@localhost:5432/nova_chat" > .env
```

**验证**:
```sql
-- 方案 A
SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename LIKE '%conversation%';

-- 方案 B
\c nova_chat
SELECT tablename FROM pg_tables WHERE schemaname = 'public';
-- 应该返回 10+ 张表
```

---

### Step 6: 验证所有服务启动

**执行**:
```bash
# 1. social-service
cd backend/social-service
cargo build --release

# 2. feature-store
cd backend/feature-store
cargo build --release

# 3. realtime-chat-service
cd backend/realtime-chat-service
cargo build --release
```

**检查启动日志**:
```
✅ 应该看到: "Running migrations..." → "Migrations complete"
❌ 不应该看到: "relation does not exist", "already exists"
```

---

## 迁移回滚计划

如果迁移失败，执行以下回滚：

```bash
# 1. 恢复备份
psql -U postgres -d nova < backup_YYYYMMDD_HHMMSS.sql

# 2. 删除新迁移记录
psql -U postgres -d nova -c "DELETE FROM _sqlx_migrations WHERE version >= 998;"

# 3. 验证回滚
psql -U postgres -d nova -c "\dt" | grep -E "(post_shares|social_metadata)"
# 应该看到旧表
```

---

## 常见问题

### Q1: "relation already exists" 错误
**原因**: 主迁移和服务迁移重复定义表
**解决**: 确保先运行 `998_deprecate_*` 和 `999_cleanup_*` 清理迁移

### Q2: "foreign key constraint" 错误
**原因**: 删除表时有外键约束
**解决**: 迁移文件已使用 `CASCADE`，应该不会出现此问题

### Q3: realtime-chat-service 应该用共享库还是独立库？
**建议**:
- **开发环境**: 共享 `nova` 库（简单）
- **生产环境**: 独立 `nova_chat` 库（隔离）

### Q4: 如何确认迁移已全部应用？
```sql
SELECT version, description, installed_on
FROM _sqlx_migrations
ORDER BY version DESC
LIMIT 20;
```

---

## 下一步行动

1. ✅ **立即执行**: 按照上述步骤应用迁移
2. ⏳ **验证服务**: 启动所有服务，检查无错误
3. ⏳ **更新文档**: 在 `SERVICE_REFACTORING_PLAN.md` 中标记数据库迁移完成
4. ⏳ **集成测试**: 运行 gRPC 集成测试，验证服务间通信

---

## 附录: 迁移文件清单

### 主数据库迁移 (backend/migrations/)
```
998_deprecate_old_messaging_schema.sql   - 删除旧 messaging 表
999_cleanup_social_conflicts.sql         - 删除旧 social 表
100_social_service_schema.sql            - social-service 新 schema
101_feature_store_metadata.sql           - feature-store metadata
```

### 服务独立迁移
```
social-service/migrations/
  002_create_social_tables.sql           - (已复制到主迁移 100)

feature-store/migrations/
  001_feature_metadata.sql               - (已复制到主迁移 101)
  002_clickhouse_schema.sql              - ClickHouse 独立迁移

realtime-chat-service/migrations/
  0002_create_conversations.sql
  0003_create_conversation_members.sql
  0004_create_messages.sql
  ... (10 个文件)
```

---

**作者**: Linus Torvalds Style Code Reviewer
**审核**: 基于 `SERVICE_REFACTORING_PLAN.md` Phase 0-E
**联系**: 如有问题，检查 `backend/migrations/` 和服务独立迁移文件
