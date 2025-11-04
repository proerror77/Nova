# 🚀 Nova 后端架构重构 - Phase 0（准备阶段）

**开始日期**: 2025-11-04
**预计完成**: 2025-11-11 (1 周)
**团队配置**: 2-3 人（1 架构师 + 1-2 后端工程师）

---

## 📋 Phase 0 目标

Phase 0 是架构重构的**基础准备阶段**，为后续四个月的工作建立清晰的蓝图。完成此阶段后，团队应该对以下内容有深入理解：

1. **数据所有权模型** - 每个表属于哪个服务
2. **gRPC API 规范** - 跨服务通信接口
3. **迁移策略** - 从共享数据库到独立数据库的具体步骤
4. **回滚计划** - 如何在出现问题时快速恢复

---

## 🎯 Phase 0 交付物

### 1️⃣ 数据所有权分析 (0.5 天)

**目的**: 明确 56+ 个表的归属权，识别跨服务依赖

#### 1.1 数据表清单

```rust
// 数据所有权模型
struct DataOwnership {
    table_name: String,
    owner_service: ServiceName,
    dependent_services: Vec<ServiceName>,
    foreign_keys: Vec<ForeignKey>,
    cross_service_writes: Vec<ServiceName>,
    read_only_services: Vec<ServiceName>,
}

// 示例
auth_service::users {
    owner: AuthService,
    dependent: [
        UserService,        // needs user profile
        ContentService,     // needs user for posts
        MessagingService,   // needs user for messages
        FeedService,        // needs user for feed
        SearchService,      // needs user for search
        MediaService,       // needs user for media ownership
        StreamingService,   // needs user for streaming
    ],
    foreign_keys: [
        messages.sender_id -> users.id (CASCADE),
        messages.recipient_id -> users.id (CASCADE),
        posts.author_id -> users.id (CASCADE),
        // ... 10+ more
    ],
}
```

#### 1.2 可执行检查清单

- [ ] 运行数据库审计脚本：`backend/scripts/audit-db-schema.sql`
  - 提取所有 56+ 个表
  - 识别所有外键关系
  - 统计跨服务引用
  - 查找没有 FK 但引用的表（数据孤立风险）

- [ ] 分析代码中的跨服务查询
  ```bash
  # 搜索所有 SQL 查询，识别跨服务表访问
  grep -r "SELECT.*FROM" backend/*/src --include="*.rs" | grep -v "//"
  grep -r "INSERT INTO" backend/*/src --include="*.rs" | grep -v "//"
  grep -r "UPDATE.*SET" backend/*/src --include="*.rs" | grep -v "//"
  ```

- [ ] 绘制依赖图
  ```
  创建: docs/data-ownership-graph.txt

  示例结构:

  auth-service (owner of users)
    ├── users (primary owner)
    │   ├── FK to messages.sender_id (messaging-service reads)
    │   ├── FK to posts.author_id (content-service reads)
    │   └── FK to user_profiles.user_id (user-service reads)
    └── tokens (cache, Redis managed)

  messaging-service (owner of messages, conversations)
    ├── messages (primary owner)
    │   ├── FK to users.id (auth-service owner)
    │   ├── FK to conversations.id (self)
    │   └── attachments (owned)
    └── conversations (primary owner)
        ├── FK to users.id (many-to-many)
  ```

#### 1.3 输出文件

**文件**: `docs/DATA_OWNERSHIP_MODEL.md` (3-5 页)

```markdown
# 数据所有权模型

## 服务 1: auth-service

### 主要所有表
- users (主表，56 个 FK 指向这里)
- user_credentials
- email_verification_tokens
- password_reset_tokens

### 从属表（通过 FK 指向其他服务）
- none (auth-service 不依赖其他服务的表)

### 跨服务读权限
```sql
SELECT users.* FROM users
  LEFT JOIN messages ON messages.sender_id = users.id
  LEFT JOIN posts ON posts.author_id = users.id
  -- ... 7 more services reading users table
```

### 风险评估
- **单点故障**: users 表是所有 8 个服务的依赖，任何故障影响全系统
- **写冲突**: auth-service (login) 和 user-service (profile) 同时 UPDATE users
- **扩展瓶颈**: QPS 上限 ~500（主键索引热点）

---

## 服务 2: messaging-service

### 主要所有表
- messages (4GB, 10M+ rows)
- conversations
- conversation_members
- message_attachments
- message_read_receipts

### 从属表（通过 FK 指向其他服务）
- users (FK: messages.sender_id → users.id) **需要迁移策略**
- posts (FK: message.referenced_post_id → posts.id) **可选参考**

### 跨服务读权限
- feed-service: 读 messages 以生成 Feed
- search-service: 读 messages 以索引

### 风险评估
- **重复数据**: messages 表同时在 postgres:5432 和 postgres-messaging:5432
- **一致性**: 不清楚谁是事实源，如何同步

---

## 完整表映射（所有 56+ 表）

[详细列表...]

```

---

### 2️⃣ gRPC API 规范设计 (1.5 天)

**目的**: 定义跨服务通信接口，使用 gRPC 替代直接数据库查询

#### 2.1 gRPC 服务定义模板

**文件**: `backend/proto/services/*`

```protobuf
// auth_service.proto - 新的 gRPC 接口
syntax = "proto3";
package nova.auth_service;

message User {
    string id = 1;
    string email = 2;
    string username = 3;
    int64 created_at = 4;
    bool is_active = 5;
}

message GetUserRequest {
    string user_id = 1;
}

message GetUserResponse {
    User user = 1;
}

message GetUsersByIdsRequest {
    repeated string user_ids = 1;
}

message GetUsersByIdsResponse {
    repeated User users = 1;
}

message CheckTokenValidityRequest {
    string token = 1;
}

message CheckTokenValidityResponse {
    bool is_valid = 1;
    string user_id = 2;
    int64 expires_at = 3;
}

service AuthService {
    rpc GetUser(GetUserRequest) returns (GetUserResponse);
    rpc GetUsersByIds(GetUsersByIdsRequest) returns (GetUsersByIdsResponse);
    rpc CheckTokenValidity(CheckTokenValidityRequest) returns (CheckTokenValidityResponse);
}
```

#### 2.2 服务间 API 清单

```markdown
## 必需的 gRPC 接口

### 1. auth-service → 其他服务
- GetUser(user_id) → User struct
- GetUsersByIds(user_ids[]) → User[]
- CheckTokenValidity(token) → {valid, user_id, expires_at}
- VerifyUserExists(user_id) → bool

### 2. messaging-service → auth-service
- GetUser(sender_id)
- GetUser(recipient_id)
- CheckTokenValidity(message_signature) [for signed messages]

### 3. content-service → auth-service
- GetUser(author_id)

### 4. feed-service → messaging-service
- GetMessages(conversation_id, limit, offset)
- GetConversationMembers(conversation_id)

### 5. search-service → [all services]
- GetMessageForIndexing(message_id)
- GetPostForIndexing(post_id)
- GetUserForIndexing(user_id)

### 6. user-service → auth-service
- UpdateUserMetadata(user_id, metadata) [replaces direct UPDATE]
- GetUser(user_id)

## 设计原则
- 【零隐式依赖】所有跨服务调用都显式定义为 gRPC
- 【幂等性】所有 RPC 必须是幂等的（支持重试）
- 【缓存策略】关键数据（users）必须在调用方缓存
- 【超时】所有 RPC 最长 5 秒，默认 1 秒
```

#### 2.3 可执行检查清单

- [ ] 创建 proto 文件结构
  ```bash
  mkdir -p backend/proto/nova/{auth,messaging,content,feed,user,search,media,streaming}
  touch backend/proto/services/auth_service.proto
  touch backend/proto/services/messaging_service.proto
  # ... 创建全部 8 个 proto 文件
  ```

- [ ] 验证 gRPC 依赖
  ```bash
  # 确保 Cargo.toml 中包含必要的 crates
  grep "tonic\|prost" backend/Cargo.toml
  ```

- [ ] 验证现有 gRPC 使用
  ```bash
  # 搜索代码中已有的 gRPC 调用
  grep -r "tonic::client" backend/ --include="*.rs"
  grep -r "GrpcClient" backend/ --include="*.rs"
  ```

#### 2.4 输出文件

**文件**: `docs/GRPC_API_SPECIFICATION.md` (8-10 页)

包含内容:
- 8 个服务的完整 proto 定义
- 服务间依赖图
- 超时和重试策略
- 错误处理约定
- 缓存策略

---

### 3️⃣ 数据库分离策略 (1.5 天)

**目的**: 规划如何将 8 个服务从共享数据库迁移到独立数据库

#### 3.1 迁移架构

```
当前状态（共享数据库）
┌──────────────────────────────────┐
│  PostgreSQL (nova_auth)          │
├──────────────────────────────────┤
│ users (auth-service owned)       │
│ messages (messaging-service)     │
│ posts (content-service)          │
│ conversations (messaging)        │
│ ... 56+ more tables              │
└──────────────────────────────────┘
         ↓
   迁移中间状态
┌─────────────────┐
│ PostgreSQL A    │ (auth-service)
│ users, tokens   │
└─────────────────┘
         ↑
    ┌────────────────────┐
    │ gRPC routing layer │ (compatibility)
    └────────────────────┘
         ↓
┌─────────────────┐
│ PostgreSQL B    │ (messaging-service)
│ messages, conv  │
└─────────────────┘
         ...
         ↓
   目标状态（独立数据库）
┌──────────┐   ┌──────────┐   ┌──────────┐
│ Postgres │   │ Postgres │   │ Postgres │
│ auth     │   │ messaging│   │ content  │
└──────────┘   └──────────┘   └──────────┘
     ↓              ↓              ↓
  gRPC API    gRPC API      gRPC API
```

#### 3.2 迁移步骤（细节）

```markdown
### Step 1: 创建新的独立数据库实例

对于每个服务，在单独的 PostgreSQL 实例中创建:

auth-service database:
  - users (with all indexes)
  - user_credentials
  - email_verification_tokens
  - password_reset_tokens
  - oauth_connections

messaging-service database:
  - messages
  - conversations
  - conversation_members
  - message_attachments
  - message_read_receipts

... [7 more services]

### Step 2: 建立临时"兼容层"

在每个原始表创建 PostgreSQL VIEW，指向新数据库:

```sql
-- 在旧数据库中创建 VIEW（指向新 auth-service 数据库）
CREATE FOREIGN DATA WRAPPER postgres_new_auth_db
  VALIDATOR postgres_fdw_validator;

CREATE SERVER new_auth_db
  FOREIGN DATA WRAPPER postgres_new_auth_db
  OPTIONS (host 'auth-postgres', port '5432', dbname 'nova_auth');

CREATE FOREIGN TABLE users_foreign (
  id UUID,
  email TEXT,
  ...
) SERVER new_auth_db
  OPTIONS (schema_name 'public', table_name 'users');

-- 在旧表位置创建 VIEW（对应用透明）
CREATE VIEW users AS SELECT * FROM users_foreign;
```

### Step 3: 迁移应用代码

```rust
// 阶段 1: 代码改为使用 gRPC 而不是直接 SQL
// 示例：auth-service 中的 GetUser

// 旧方式（直接 SQL）
let user = sqlx::query_as::<_, User>(
    "SELECT * FROM users WHERE id = $1"
).bind(user_id).fetch_one(pool).await?;

// 新方式（gRPC）
let user = auth_service_client
    .get_user(GetUserRequest { user_id })
    .await?
    .into_inner().user;
```

### Step 4: 激活新数据库，关闭旧数据库访问

```bash
# Step 4.1: 验证所有读写都通过 gRPC
# 运行测试套件，确保零失败
cargo test --all

# Step 4.2: 在生产环境灰度发布
# 10% 流量 → 新数据库
# 等待 24h 监控
# 50% 流量 → 新数据库
# 等待 24h 监控
# 100% 流量 → 新数据库

# Step 4.3: 删除 VIEW，删除旧表
DROP VIEW IF EXISTS users CASCADE;
```

### Step 5: 完全移除共享数据库

```bash
# 验证所有数据已迁移
# 删除旧的 PostgreSQL 连接字符串
# 更新所有应用配置
```
```

#### 3.3 可执行检查清单

- [ ] 列出所有 8 个数据库的创建脚本
  ```bash
  ls -la backend/migrations/*/001_initial_schema.sql
  ```

- [ ] 验证 PostgreSQL 外数据包装器支持
  ```bash
  # 检查 PostgreSQL 是否编译了 postgres_fdw 支持
  psql -c "CREATE EXTENSION postgres_fdw;"
  ```

- [ ] 规划灰度发布策略
  ```markdown
  Week 1: 10% traffic → new DB (monitoring)
  Week 2: 50% traffic → new DB (stability check)
  Week 3: 100% traffic → new DB (validation)
  ```

#### 3.4 输出文件

**文件**: `docs/DATABASE_MIGRATION_STRATEGY.md` (10-12 页)

包含内容:
- 按服务列出的迁移步骤
- 8 个数据库的初始化脚本
- 灰度发布计划
- 回滚程序
- 性能基准

---

### 4️⃣ 回滚计划 (1 天)

**目的**: 确保在迁移出问题时可以快速恢复

#### 4.1 回滚决策树

```
┌─ 检测到问题
├─ 问题严重等级?
├─ P0 (数据损坏):
│  └─ 立即切换回旧数据库 (< 5 分钟)
├─ P1 (功能故障):
│  └─ 切换 10% 流量回旧 DB，分析问题 (< 30 分钟)
└─ P2 (性能降级):
   └─ 优化 gRPC 调用，缓存策略调整 (< 1 小时)
```

#### 4.2 回滚程序

```bash
#!/bin/bash
# scripts/rollback-to-shared-db.sh

# Step 1: 重新激活旧数据库的 VIEW
psql -d nova_auth << EOF
  CREATE VIEW users AS SELECT * FROM users_foreign;
  CREATE VIEW messages AS SELECT * FROM messages_foreign;
  -- ... 56+ more VIEWs
EOF

# Step 2: 重新配置应用连接字符串
export DATABASE_URL="postgresql://localhost/nova_auth"

# Step 3: 重启所有服务
for service in auth-service messaging-service content-service ...; do
  systemctl restart $service
done

# Step 4: 验证健康检查
for service in auth-service messaging-service ...; do
  curl http://localhost:8000/health
done

echo "✅ Rollback complete. Old database activated."
```

#### 4.3 可执行检查清单

- [ ] 创建完整的数据备份
  ```bash
  # 全量备份当前数据库
  pg_dump nova_auth > backups/nova_auth_2025-11-04_full.sql
  ```

- [ ] 创建每日增量备份
  ```bash
  # WAL 归档配置
  # 在 postgresql.conf 中启用 wal_level = logical
  # 配置 archive_command 定期备份
  ```

- [ ] 模拟回滚练习
  ```bash
  # 在测试环境运行完整回滚，验证步骤
  ./scripts/rollback-to-shared-db.sh
  ./tests/verify-rollback-success.sh
  ```

#### 4.4 输出文件

**文件**: `docs/ROLLBACK_PROCEDURE.md` (4-5 页)

包含内容:
- 故障场景 (5 种)
- 对应的回滚步骤
- 验证检查清单
- 时间成本估计

---

## 📊 Phase 0 完成标准

所有以下条件必须满足，Phase 0 才能被视为完成：

### 检查清单

- [ ] **数据所有权模型**
  - [ ] 所有 56+ 表已分类到对应服务
  - [ ] 所有 FK 关系已记录
  - [ ] 跨服务依赖图已绘制
  - [ ] 文档: `docs/DATA_OWNERSHIP_MODEL.md` 已完成

- [ ] **gRPC API 规范**
  - [ ] 8 个 proto 文件已编写
  - [ ] 所有服务间 API 已定义
  - [ ] 缓存和超时策略已设定
  - [ ] 文档: `docs/GRPC_API_SPECIFICATION.md` 已完成

- [ ] **迁移策略**
  - [ ] 8 个数据库初始化脚本已创建
  - [ ] gRPC 路由层设计已完成
  - [ ] 灰度发布计划已制定
  - [ ] 文档: `docs/DATABASE_MIGRATION_STRATEGY.md` 已完成

- [ ] **回滚计划**
  - [ ] 5 种故障场景已列举
  - [ ] 回滚脚本已编写并测试
  - [ ] 备份和恢复流程已验证
  - [ ] 文档: `docs/ROLLBACK_PROCEDURE.md` 已完成

### 验证步骤

```bash
# 1. 验证所有文档已创建
ls -1 docs/DATA_OWNERSHIP_MODEL.md \
      docs/GRPC_API_SPECIFICATION.md \
      docs/DATABASE_MIGRATION_STRATEGY.md \
      docs/ROLLBACK_PROCEDURE.md

# 2. 验证所有 proto 文件已创建
find backend/proto -name "*.proto" | wc -l
# 应该 ≥ 8

# 3. 验证回滚脚本可执行
ls -la scripts/rollback-to-shared-db.sh
file scripts/rollback-to-shared-db.sh

# 4. 验证备份存在
ls -la backups/nova_auth_*.sql | head -5

# 5. 代码审查
# 所有文档必须经过架构师审查和批准
```

---

## 🎬 Phase 0 → Phase 1 的交接

Phase 0 完成后，生成最终的**Phase 1 启动文档**：

**文件**: `docs/PHASE_1_KICKOFF.md`

包含内容:
- 数据所有权确认表（签名）
- gRPC API 最终规范（已审查）
- Phase 1 详细任务列表（T001-T020）
- 人员分配计划
- 周期计划表（12 周 Phase 1）

---

## 💡 Phase 0 最佳实践

### 1. 使用版本控制

```bash
# Phase 0 工作应该在专门的分支上
git checkout -b feature/architecture-phase-0

# 每天提交进度
git add docs/
git commit -m "docs(phase-0): complete gRPC specification"

# 完成时提交
git push origin feature/architecture-phase-0
# 创建 PR 供审查
```

### 2. 团队同步

- **每日站会** (15 分钟): 进度更新 + 阻塞项
- **中期检查** (第 3 天): 检查 1/2 内容完成情况
- **最终审查** (第 6 天): 全面审查所有交付物

### 3. 文档质量

每份文档必须包含:
- 清晰的目标和范围
- 具体的示例和代码片段
- 可执行的检查清单
- 风险评估和缓解措施

---

## 📚 相关文档

参考以下已完成的文档:

- `ARCHITECTURE_EXECUTIVE_SUMMARY.md` - 架构现状分析
- `ARCHITECTURE_DEEP_ANALYSIS.md` - 详细技术分析
- 现有迁移脚本: `backend/migrations/*.sql`

---

## ✅ 下一步

1. **现在** (今天): 批准 Phase 0 计划
2. **明天**: 分配团队成员，创建工作分支
3. **第 2 天**: 启动数据所有权分析
4. **第 7 天**: 完成所有 Phase 0 交付物
5. **第 8 天**: 启动 Phase 1 (实施 gRPC + 独立数据库)

---

**责任人**: 架构师 + 高级后端工程师
**状态**: 📋 计划阶段
**下次更新**: 2025-11-05
