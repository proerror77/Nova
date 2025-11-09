# Nova 项目数据库架构深度分析

## 执行总结

**Linus 的判断：这是个真问题，但不完全是你想的那样。**

### 关键发现

1. **现状**：所有 92+ 个表确实在单个 `nova` 数据库中
2. **根本原因**：项目处于 monolithic 阶段，所有 migration 指向共享目录 `/backend/migrations/`
3. **微服务假象**：代码组织成了独立服务（auth-service, messaging-service 等），但**数据库没有分解**
4. **这不是偶然**：Terraform、K8s ConfigMap、Docker Compose 都配置了同一个 DATABASE_URL

---

## 第一层：数据结构分析

### 表的逻辑分布（按服务边界）

```
当前现实：
  nova 数据库
  ├── users (全局)
  ├── auth_logs, sessions, refresh_tokens (Auth)
  ├── posts, comments, likes (Content)
  ├── conversations, messages (Messaging)
  ├── videos, reels, streams (Media/Streaming)
  ├── follows, user_permissions (User)
  └── ... 79 其他表

应该是的样子：
  nova_auth       (9 tables)   - 认证和授权
  nova_user       (5 tables)   - 用户资料和社交图
  nova_content    (35 tables)  - 文章、视频、图片
  nova_messaging  (13 tables)  - 私聊、加密、反应
  nova_streaming  (5 tables)   - 直播流媒体
  nova_events     (1 table)    - Outbox 事件
  nova_shared     (optional)   - 共享数据（users？）
```

### 数据流和所有权分析

**当前的紧耦合：**

```
users 表是全局共享的
  ↓
所有 11 个服务都直接引用 user_id
  ↓
没有服务边界，无法独立扩展
  ↓
一个服务的 migration 失败 = 所有服务卡住
```

**问题根源：** Users 表是中心点，所有外键依赖它。

---

## 第二层：特殊情况识别

### 为什么设计现在这样？

| 表 | 为什么在 nova_content | 应该在哪 | 问题 |
|---|---|---|---|
| posts | 内容发布功能 | nova_content ✓ | soft_delete, image_key 设计合理 |
| messages | encrypted_content | nova_messaging ✓ | 加密 ✓ 但在主 DB 中 |
| users | 全局身份 | 有争议 | 核心瓶颈！所有外键依赖 |
| posts.user_id | 谁发布了文章 | nova_content? | 跨 DB 外键 = 痛点 |

### 设计问题梳理

**第1类：表结构本身没问题**
- posts 用 image_key（S3） + image_sizes（JSON）✓ 正确
- messages 用 encrypted_content + nonce ✓ 加密正确
- 所有表都有 created_at + updated_at ✓

**第2类：跨数据库引用**
```sql
-- 现在（单 DB）：
ALTER TABLE posts 
  ADD CONSTRAINT fk_user
  FOREIGN KEY (user_id) REFERENCES users(id);  -- ✓ 工作

-- 拆分后（多 DB）：
-- nova_content.posts 引用 nova_auth.users
-- PostgreSQL 不支持跨数据库外键！❌
```

---

## 第三层：复杂度审查

### Migration 架构的复杂性

```
当前：
  /backend/migrations/
  ├── 001_initial_schema.sql      (auth)
  ├── 002_add_auth_logs.sql
  ├── 003_posts_schema.sql         (content)
  ├── 018_messaging_schema.sql     (messaging)
  ├── 027_post_video_association.sql
  ├── 041_add_message_encryption.sql
  └── ...86 个文件混在一起

问题：
  1. 无法看出表属于哪个服务（需要读文件头）
  2. 如果 messaging-service 要新增表，放到哪里？
     - 选项A：backend/migrations/（混乱，所有服务跑）
     - 选项B：messaging-service/migrations/（自己创建了，但 main.rs 指向 ../migrations）
  3. 依赖关系隐藏：messaging 依赖 users，但无法从文件名看出
```

**可以消除的复杂性：**
- 92 个表的 migration 文件要排序才能找
- 服务启动时跑别人的 migration 没有意义
- 无法独立扩展单个服务的表

---

## 第四层：破坏性分析（Never Break Userspace）

### 如果现在分解数据库，会破坏什么？

**P0 破坏性（致命）**
```rust
// 所有服务代码都这么写
let user = db.query(
  "SELECT * FROM users WHERE id = $1",
  user_id
).await?;  // ← 在 nova_auth DB 中，但这里可能连的是 nova_content

// 修复：需要改所有 11 个服务的数据库连接逻辑
```

**P1 破坏性（严重）**
```sql
-- 当前这样工作：
INSERT INTO posts (user_id, caption, image_key)
VALUES ($1, $2, $3);  -- user_id 同一 DB 内外键检查

-- 拆分后无法工作：
INSERT INTO nova_content.posts (user_id, caption, image_key)
  -- nova_content 不再有 users 表！
  -- 外键约束会失败 ❌
```

**P2 破坏性（迁移复杂）**
```
当前：运行一次 migration，所有表都创建好
分解后：需要顺序创建 5 个数据库，确保依赖顺序
```

---

## 第五层：实用性验证

### 这个问题的严重性有多大？

**短期（当前）：** 5/10（麻烦但能工作）
- 所有表在一个地方，容易管理
- 外键约束有效
- Migration 按顺序跑

**中期（3-6 个月）：** 8/10（痛点开始爆发）
- messaging-service 独立扩展受限
- 无法为 messaging 单独配置资源
- Backup/Restore 不够灵活
- Content service 表数量爆炸，拖累 migration 速度

**长期（生产阶段）：** 9/10（必须解决）
- nova_content 可能 TB 级别（视频、图片）
  但 users 表只有 MB 级别
- 无法独立扩展或分片 messaging 数据库
- 数据合规性问题（GDPR）：删除一个用户影响 11 个服务

---

## Linus 式方案：简化优先

### 问题重新定义

**你问的是：** "为什么所有表都在同一个数据库？"

**真正的问题是：** "微服务代码架构与数据库架构不匹配，导致无法独立部署/扩展"

### 解决方案对比

#### 方案 A：完全拆分（复杂度高，风险大）✗
```
现在所有服务连到：
  DATABASE_URL=postgresql://postgres@postgres:5432/nova

变成：
  AUTH_DATABASE_URL=postgresql://postgres@postgres:5432/nova_auth
  CONTENT_DATABASE_URL=postgresql://postgres@postgres:5432/nova_content
  MESSAGING_DATABASE_URL=postgresql://postgres@postgres:5432/nova_messaging
  ...

问题：
  1. 所有 11 个服务都需要改代码（user 查询逻辑）
  2. 外键约束无法跨 DB
  3. 需要 5 个独立 RDS 实例（成本)
  4. 分布式事务复杂度爆炸
```

#### 方案 B：逻辑分离（现实的方案）✓
```
保持物理上单一 nova DB，但：

1. 在代码中实现 "数据库分片"
   - nova.auth_* (users, sessions, etc.)
   - nova.content_* (posts, videos, etc.)
   - nova.messaging_* (messages, conversations, etc.)

2. 每个服务有数据访问层，只操作自己的表

3. Users 表保持中央，但通过视图隐藏
   CREATE VIEW auth_users AS SELECT * FROM users WHERE ...

4. 文档中明确标记表的所有权：
   migration 文件命名：
   001_auth_initial_schema.sql
   003_content_posts_schema.sql
   018_messaging_schema.sql
```

#### 方案 C：零成本的当前最优做法 ✓✓（推荐）
```
1. 重组 migration 文件（不改数据库结构）：
   /backend/migrations/
   ├── auth/
   │   ├── 001_users.sql
   │   ├── 002_sessions.sql
   │   └── 006_two_fa.sql
   ├── content/
   │   ├── 003_posts.sql
   │   ├── 027_post_video.sql
   │   └── ...
   └── messaging/
       ├── 018_messaging.sql
       ├── 041_encryption.sql
       └── ...

2. 在每个 migration 文件顶部标记：
   -- SERVICE: auth-service
   -- DEPENDS_ON: (none)
   
3. 创建服务依赖图文档：
   auth-service: ← (独立)
   content-service: ← users (auth-service)
   messaging-service: ← users (auth-service)
   
4. 在代码中添加 package-level 注释：
   // auth_service::models::User
   // Owned by: auth-service
   // Can be queried by: all services via auth gRPC
   // Cannot be modified by: content-service, messaging-service

5. 长期计划：
   Phase 1（现在）：组织 migration 文件（零成本）
   Phase 2（3个月）：创建 users 的 read-only 视图给其他服务
   Phase 3（6个月）：如果真需要拆分，数据已经逻辑清晰
```

---

## 表结构质量评估

### Posts 表设计（image-first）

```sql
-- 现在的设计 ✓ 好品味
posts (
  id UUID PRIMARY KEY,
  user_id UUID,                    -- 谁发布的
  caption TEXT,                    -- 文本描述
  image_key VARCHAR(512),          -- S3 路径，NOT 二进制！
  image_sizes JSONB,               -- { "thumb": {...}, "medium": {...} }
  status VARCHAR(50),              -- pending|processing|published|failed
  created_at, updated_at,
  soft_delete TIMESTAMP            -- GDPR 合规
)

为什么这是好设计：
  1. image_key 不存储二进制（SQL 不是文件系统）
  2. image_sizes 用 JSON 记录转码进度
  3. status 追踪异步处理
  4. soft_delete 支持撤销（不丢数据）
  5. 复杂的获取逻辑在应用层（get_post_with_images 函数）

缺陷：
  1. post_images 重复存储了 s3_key？
     post.image_sizes 和 post_images 表有重叠
     建议：post_images 保留，image_sizes 可以删除（冗余）
  2. caption 最多 2200 字符，但允许 NULL（应该是 NOT NULL DEFAULT ''）
```

### Messages 表设计（加密）

```sql
-- 现在的设计 ✓ 合理
messages (
  id UUID PRIMARY KEY,
  conversation_id UUID,
  sender_id UUID,
  encrypted_content TEXT NOT NULL,  -- ✓ 密文存储
  nonce VARCHAR(48),                -- ✓ 用于解密
  message_type VARCHAR(20),
  created_at, edited_at, deleted_at -- ✓ 审计追踪
)

为什么好：
  1. 永不存储明文（encrypted_content）
  2. Nonce 防止重放攻击
  3. soft_delete （edited_at、deleted_at）支持"编辑" / "撤回"

缺陷：
  1. 加密版本硬编码在应用代码中？
     migration 084 引入了 encryption_versioning_v2
     但不清楚当前用的是哪个版本
     
  2. 没有 hmac 或完整性检查标志
     建议：添加 content_hmac 字段防篡改
```

### Users 表设计

```sql
users (
  id UUID PRIMARY KEY,
  email VARCHAR(255) UNIQUE,
  username VARCHAR(50) UNIQUE,
  password_hash VARCHAR(255),       -- Argon2？应该在代码检查
  email_verified BOOLEAN,
  is_active BOOLEAN,
  failed_login_attempts INT,
  locked_until TIMESTAMP,
  created_at, updated_at,
  last_login_at,
  deleted_at                        -- soft_delete for GDPR
)

缺陷：
  1. 字段太少，没有 avatar_url, display_name 等
     （这些可能在另一个表？需要查证）
  2. password_hash 长度 255，Argon2 通常需要 60 字符
     （实际够用，但留的空间太多）
  3. 没有 phone_number 字段（许多服务需要）
  4. 没有 account_type (personal|business)
     
总体：基础但不完整。后续 migration 应该填补这些。
```

---

## Terraform 配置分析

```terraform
# ✓ 好的地方
resource "aws_db_instance" "main" {
  allocated_storage     = 100
  max_allocated_storage = 1000        -- ✓ 自动扩展
  storage_encrypted     = true        -- ✓ 安全
  backup_retention_period = var.environment == "production" ? 7 : 3
  performance_insights_enabled = true -- ✓ 可观测性
}

# ❌ 问题
1. 只有一个 RDS 实例（nova-${var.environment}）
2. 所有微服务连到同一个数据库
3. Terraform 没有为不同服务创建单独的数据库

# 建议修改
# 如果真的要拆分，Terraform 应该创建：
# - aws_db_instance "nova_auth"
# - aws_db_instance "nova_content"
# - aws_db_instance "nova_messaging"
```

---

## Migration 依赖分析

### 当前 Migration 顺序问题

```
001_initial_schema.sql      创建 users（auth 依赖）
  ↓ 所有其他 migration 都隐含依赖这个
003_posts_schema.sql        创建 posts（content）
  ↓ FOREIGN KEY (user_id) REFERENCES users(id)
018_messaging_schema.sql    创建 conversations（messaging）
  ↓ FOREIGN KEY (created_by) REFERENCES users(id)
...

问题：
  1. 看不出谁依赖谁（除非读 SQL）
  2. 如果要删除一个 migration，无法判断影响范围
  3. 如果要给 messaging 独立 DB，需要在 nova_messaging 里
     创建 users 的镜像表（外键目标）
```

### 推荐的 Migration 重组

```
/backend/migrations/
├── _00_foundations/
│   ├── 001_auth_initial_schema.sql
│   ├── 002_auth_logs.sql
│   └── 005_users_deleted_at.sql
│
├── _01_content/
│   ├── 003_posts_schema.sql
│   ├── 027_post_video_association.sql
│   └── 069_text_posts_support.sql
│
├── _02_social/
│   ├── 004_social_graph_schema.sql
│   ├── 024_add_privacy_mode.sql
│   └── 035_trending_system.sql
│
├── _03_messaging/
│   ├── 018_messaging_schema.sql
│   ├── 041_add_message_encryption.sql
│   └── 039_message_recall_versioning.sql
│
└── _04_shared/
    ├── 083_outbox_pattern_v2.sql
    └── 086_add_deleted_by_to_users.sql

好处：
  1. 清晰的层级关系
  2. 后续拆分数据库时，可以把 _00_* 和 _03_* 分别复制到不同 DB
  3. 新 migration 时知道放在哪个目录
```

---

## 完整修复建议

### 立即可做（零成本）

**1. 重组 Migration 文件结构**
```bash
# 不改数据库，只改文件位置
/backend/migrations/ → 按服务分组：
  auth/
  content/
  messaging/
  streaming/
  shared/

# 修改所有 main.rs：
# 从：sqlx::migrate!("../migrations").run(&db)
# 到：sqlx::migrate!("../migrations").run(&db) // 自动扫描所有子目录
```

**2. 添加 Service Ownership 标记**
```sql
-- 003_content_posts_schema.sql
-- SERVICE: content-service
-- DEPENDS_ON: auth-service (users table)
-- BREAKING_CHANGES: None
-- ROLLBACK_COMPATIBLE: Yes

CREATE TABLE posts (
  ...
)
```

**3. 创建文档**
```
/backend/DATABASE_ARCHITECTURE.md

## Table Ownership

### auth-service (nova.auth_*)
- users: Core user identity
- sessions: Active sessions
- ...

### content-service (nova.content_*)
- posts: User posts
- ...
```

### 短期（1-2 个月）

**4. 添加 Foreign Key 文档**
```
创建 /backend/FK_DEPENDENCIES.md
列出所有外键关系，标记哪些是跨服务的：

posts.user_id → users.id [CROSS_SERVICE] auth-service
  Risk: 如果 auth-service 删除用户，会 CASCADE
  Mitigation: Use soft_delete, never CASCADE
```

**5. 添加服务间数据访问规范**
```rust
// content_service/src/db/models/post.rs

/// Posts owned by content-service
/// Users queried from auth-service gRPC, NOT direct DB access
pub struct Post {
    pub id: Uuid,
    pub user_id: Uuid,  // ← Never SELECT users.* here!
    pub caption: String,
}

impl Post {
    /// ❌ 不允许
    async fn get_user_from_db(&self, db: &Pool) -> Result<User> {
        db.query("SELECT * FROM users WHERE id = $1", self.user_id).await
    }
    
    /// ✓ 正确做法
    async fn get_user_from_rpc(&self, auth_client: &AuthClient) -> Result<User> {
        auth_client.get_user(self.user_id).await
    }
}
```

### 长期（6+ 个月）

**6. 分库准备**
```
如果真的需要分库（一般不需要）：

Phase A: 创建 5 个 PostgreSQL 数据库（同一 RDS）
  postgres://host:5432/nova_auth
  postgres://host:5432/nova_content
  postgres://host:5432/nova_messaging
  postgres://host:5432/nova_streaming
  postgres://host:5432/nova_shared  # 只有 users

Phase B: 逐个服务迁移（每次迁移一个数据库连接）
  1. 复制 auth 相关 tables
  2. 复制 users（nova_shared）
  3. 重定向 auth-service → nova_auth
  4. 验证...

Phase C: 应用架构调整（业务代码改动）
  content-service 不再直接查询 users
  改为通过 auth-service gRPC
```

---

## 答案总结

### 为什么所有表都在 nova_content？

**不是 nova_content，是 `nova` 数据库**

真相：
1. 代码组织成了微服务，但数据库没有分解
2. 所有 migration 指向 `/backend/migrations/`
3. Terraform 配置了单一 RDS 实例
4. 这在初期是合理的（复杂度最低）

### 应该怎么办？

**立即做（零成本）：**
- 重组 migration 文件按服务分组
- 添加 Service Ownership 文档
- 在外键处标记"这是跨服务依赖"

**不建议现在做的（破坏性太大）：**
- 将表分散到 5 个不同的数据库
- 原因：所有 11 个服务代码都要改（跨 DB 外键无法自动约束）
- 除非：真的需要独立扩展某个服务数据库（现在没有这个需求）

### Posts 和 Messages 的设计问题

都是 **好品味**（按 Linus 的标准）：

| 特性 | Posts | Messages |
|---|---|---|
| 避免 SQL 中存二进制 | ✓ image_key (S3) | - |
| 加密敏感数据 | - | ✓ encrypted_content |
| Soft Delete | ✓ | ✓ |
| 版本控制 | ✓ image_sizes JSON | ✓ nonce 防重放 |
| 异步处理跟踪 | ✓ status 字段 | - |

**微小改进：**
1. posts: 删除冗余的 image_sizes（post_images 表已经有了）
2. messages: 添加 content_hmac 防篡改
3. users: 添加 avatar_url, display_name（后续 migration）

---

## 最终建议（Linus 会说什么）

> "你有数据库架构和代码架构不匹配。修复数据库架构不是复制表到 5 个数据库，而是清楚地**文档化表的所有权**。
>
> 做这件事：
> 1. 重组你的 migration 文件（5 分钟）
> 2. 写一份清晰的所有权文档（1 小时）
> 3. 在外键注释中标记跨服务依赖（30 分钟）
> 4. 不要现在拆分数据库（太复杂，没有收益）
>
> 做完这些，你的架构清晰了。如果 6 个月后真的需要拆分，数据已经逻辑分离了，拆分会很简单。
>
> 这就是好品味：预留扩展空间，但不过度设计。"

