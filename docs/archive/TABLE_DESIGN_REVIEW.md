# Nova 数据库表设计审查 - 代码品味评估

按照 Linus Torvalds 的标准审查核心表的设计。

## Posts 表设计评审

### 现在的实现

```sql
CREATE TABLE posts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    caption TEXT,
    image_key VARCHAR(512) NOT NULL,
    image_sizes JSONB,
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    soft_delete TIMESTAMP WITH TIME ZONE,
    CONSTRAINT caption_length CHECK (LENGTH(caption) <= 2200),
    CONSTRAINT image_key_not_empty CHECK (LENGTH(image_key) > 0),
    CONSTRAINT status_valid CHECK (status IN ('pending', 'processing', 'published', 'failed')),
    CONSTRAINT soft_delete_logic CHECK (soft_delete IS NULL OR soft_delete <= NOW())
);
```

### 品味评分：🟢 好品味

#### 为什么好

1. **image_key 不存储二进制** ✓
   - 存储 S3 对象键（字符串），不存储实际图像数据
   - 这是唯一正确的方式（数据库不是文件系统）

2. **image_sizes 用 JSON 追踪转码进度** ✓
   ```json
   {
     "original": { "url": "...", "width": 4000, "height": 3000 },
     "medium": { "url": "...", "width": 600, "height": 450 },
     "thumbnail": { "url": "...", "width": 150, "height": 112 }
   }
   ```
   这样可以快速检查转码是否完成，无需 JOIN post_images

3. **status 追踪异步处理状态** ✓
   - pending → processing → published/failed
   - 允许异步服务安全地更新进度

4. **soft_delete 支持 GDPR 合规** ✓
   - 用户删除文章 = 软删除（可撤销）
   - 与 ON DELETE CASCADE 一起，避免 orphaned comments

5. **约束条件清晰** ✓
   - caption 长度限制（2200 字符 ≈ Twitter 的 3 倍）
   - image_key 不为空
   - soft_delete 逻辑校验

### 问题和改进

#### P1：image_sizes 冗余性

当前有两个表存储图像信息：
```
posts.image_sizes JSONB              ← 快速查询，但冗余
post_images (post_id, s3_key, ...)  ← 详细信息
```

**问题**：
- image_sizes 存储的信息与 post_images 重叠
- 当添加新的 size variant 时，两个地方都要更新
- 违反数据库范式

**建议**：
```sql
-- 选项 A：删除 image_sizes，用视图
CREATE VIEW posts_with_images AS
SELECT 
  p.*,
  json_agg(json_build_object(
    'variant', pi.size_variant,
    'url', pi.url,
    'width', pi.width,
    'height', pi.height
  )) AS image_sizes
FROM posts p
LEFT JOIN post_images pi ON p.id = pi.post_id
WHERE pi.status = 'completed'
GROUP BY p.id;

-- 选项 B：保留 image_sizes 作为缓存（明确标记）
ALTER TABLE posts ADD COLUMN image_sizes_cache JSONB;  -- 标记为缓存
```

#### P2：Caption 允许 NULL，但最多 2200 字符

```sql
caption TEXT,  -- ← 应该是 NOT NULL DEFAULT ''

-- 建议
caption TEXT NOT NULL DEFAULT '',  -- 允许空字符串，但不是 NULL
CONSTRAINT caption_length CHECK (LENGTH(caption) <= 2200)
```

**原因**：
- NULL 表示"未设置"，空字符串表示"空内容"
- 两者语义不同，应该清晰

#### P3：没有 hashtag 或 mention 追踪

当前设计对于 posts 表本身是好的，但缺少：
```sql
-- 建议添加（后续 migration）
mentions_count INT DEFAULT 0,       -- 提及的用户数
mentions_text TEXT,                 -- "@alice @bob" 快速检查
hashtags JSONB,                     -- [{ "tag": "nova", "count": 100 }]
```

#### P4：edited_at 字段缺失

```sql
-- 建议添加（支持"编辑历史"）
edited_at TIMESTAMP WITH TIME ZONE,
edit_count INT DEFAULT 0,
```

**示例场景**：
- 用户编辑文章
- 显示"最后编辑于 2 小时前"
- 支持审计日志

### 建议的改进方案（零破坏性）

```sql
-- Migration: 001_improve_posts_table.sql

-- 1. 添加新字段（向后兼容）
ALTER TABLE posts
  ADD COLUMN IF NOT EXISTS edited_at TIMESTAMP WITH TIME ZONE,
  ADD COLUMN IF NOT EXISTS edit_count INT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS mentions_count INT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS hashtags JSONB;

-- 2. 标记 image_sizes 为缓存（注释）
COMMENT ON COLUMN posts.image_sizes IS 'Cache of post_images; for quick queries only; source of truth is post_images table';

-- 3. 创建视图供应用使用
CREATE OR REPLACE VIEW posts_extended AS
SELECT 
  p.*,
  (SELECT json_agg(json_build_object(
    'variant', pi.size_variant,
    'url', pi.url,
    'width', pi.width,
    'height', pi.height,
    'status', pi.status
  ) ORDER BY 
    CASE pi.size_variant 
      WHEN 'thumbnail' THEN 1
      WHEN 'medium' THEN 2
      WHEN 'original' THEN 3
      ELSE 4
    END
  ) FILTER (WHERE pi.status = 'completed'))
  AS image_variants
FROM posts p;
```

---

## Messages 表设计评审

### 现在的实现

```sql
CREATE TABLE messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id),
    encrypted_content TEXT NOT NULL,
    nonce VARCHAR(48) NOT NULL,
    message_type VARCHAR(20) DEFAULT 'text' CHECK (message_type IN ('text', 'system')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    edited_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE
);
```

### 品味评分：🟢 好品味

#### 为什么好

1. **加密内容存储** ✓
   - encrypted_content 存储密文，从不存储明文
   - 应用层负责加密/解密

2. **Nonce 防止重放攻击** ✓
   ```
   消息内容 + Nonce → 加密 → 存储
   即使两条消息内容相同，加密结果也不同（因为 nonce 不同）
   ```

3. **Soft Delete 支持撤回和历史** ✓
   ```
   deleted_at IS NULL        → 可见
   edited_at IS NOT NULL     → 显示"已编辑"
   deleted_at IS NOT NULL    → 已撤回（可恢复或物理删除）
   ```

4. **message_type 扩展** ✓
   - text: 普通文本
   - system: 系统消息（"Alice 加入了对话"）
   - 可以在 CHECK 约束中添加更多类型

### 问题和改进

#### P1：缺少加密版本控制

当前设计假设所有消息用同一加密算法：
```sql
encrypted_content TEXT NOT NULL,  -- ← 使用哪个加密版本？
```

**问题**：
- 如果想升级加密算法（AES256 → ChaCha20），旧消息无法解密
- Migration 084 引入了 encryption_versioning_v2，但不清楚现在用的是什么

**建议**：
```sql
ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS encryption_version INT NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS encryption_algorithm VARCHAR(50) DEFAULT 'aes-256-gcm';

-- 定义版本映射（在应用代码中或数据库注释中）
COMMENT ON COLUMN messages.encryption_version IS 
'1: AES-256-GCM (2024-01 to 2024-03)
 2: ChaCha20-Poly1305 (2024-03+)
 When decrypting, use this version to select correct algorithm';
```

#### P2：缺少完整性检查

当前只有加密和 nonce，没有 HMAC：
```sql
encrypted_content TEXT NOT NULL,  -- 加密了，但有没有被篡改？
```

**问题**：
- 攻击者可能修改 encrypted_content（虽然会失败解密，但无法审计）
- 没有办法验证消息的完整性

**建议**：
```sql
ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS content_hmac VARCHAR(64),
  ADD COLUMN IF NOT EXISTS hmac_algorithm VARCHAR(20) DEFAULT 'sha256';

-- 在应用层：
-- 1. 加密消息
-- 2. 计算 HMAC(encrypted_content)
-- 3. 存储两者
-- 4. 解密时验证 HMAC

-- 数据库级验证（防止应用层 bug）
CREATE CONSTRAINT TRIGGER verify_message_integrity
  AFTER UPDATE ON messages
  FOR EACH ROW
  WHEN (NEW.content_hmac IS NOT NULL)
  EXECUTE FUNCTION validate_message_hmac();
```

#### P3：没有 sender_id 的防护

```sql
sender_id UUID NOT NULL REFERENCES users(id),  -- ← 可以伪造吗？
```

**问题**：
- 应用层需要检查 sender_id == current_user
- 如果应用 bug，用户可能看到伪造的消息

**建议**：
```sql
-- 约束：不允许非成员发送消息
ALTER TABLE messages
  ADD CONSTRAINT sender_must_be_member
  CHECK (
    sender_id IN (
      SELECT user_id FROM conversation_members 
      WHERE conversation_id = messages.conversation_id
    )
  );

-- 注意：这个约束在 PostgreSQL 中需要触发器实现
-- 因为 CHECK 不支持子查询
```

#### P4：缺少 attachments 关联

```sql
-- 当前：message_attachments 是独立表
CREATE TABLE message_attachments (
  id UUID PRIMARY KEY,
  message_id UUID REFERENCES messages(id),
  ...
);

-- 建议：在 messages 表中标记是否有附件（快速查询）
ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS has_attachments BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS attachment_count INT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS attachments_size_bytes INT;

-- 这样可以快速过滤"有图片的消息"而不 JOIN
```

### 建议的改进方案

```sql
-- Migration: improve_messages_security.sql

-- 1. 添加加密版本控制
ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS encryption_version INT NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS encryption_algorithm VARCHAR(50) DEFAULT 'aes-256-gcm',
  ADD COLUMN IF NOT EXISTS content_hmac VARCHAR(64),
  ADD COLUMN IF NOT EXISTS hmac_algorithm VARCHAR(20) DEFAULT 'sha256';

-- 2. 添加附件计数缓存
ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS has_attachments BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS attachment_count INT DEFAULT 0;

-- 3. 创建索引支持常见查询
CREATE INDEX IF NOT EXISTS idx_messages_sender_created 
  ON messages(sender_id, created_at DESC) 
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_messages_attachments
  ON messages(conversation_id, created_at DESC)
  WHERE has_attachments = TRUE AND deleted_at IS NULL;

-- 4. 更新触发器自动维护缓存
CREATE OR REPLACE FUNCTION update_message_attachment_count()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE messages SET 
    has_attachments = (SELECT COUNT(*) > 0 FROM message_attachments WHERE message_id = NEW.message_id),
    attachment_count = (SELECT COUNT(*) FROM message_attachments WHERE message_id = NEW.message_id)
  WHERE id = NEW.message_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_attachment_count
  AFTER INSERT OR DELETE ON message_attachments
  FOR EACH ROW
  EXECUTE FUNCTION update_message_attachment_count();
```

---

## Users 表设计评审

### 现在的实现

```sql
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
    CONSTRAINT email_format CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}$'),
    CONSTRAINT username_format CHECK (username ~* '^[a-zA-Z0-9_]{3,50}$'),
    CONSTRAINT password_hash_not_empty CHECK (LENGTH(password_hash) > 0),
    CONSTRAINT not_both_deleted_and_active CHECK (NOT (deleted_at IS NOT NULL AND is_active = TRUE))
);
```

### 品味评分：🟡 凑合

#### 为什么凑合

1. **基础认证字段** ✓
   - email, username, password_hash 足够
   - email 验证标志合理

2. **安全设计** ✓
   - failed_login_attempts 支持暴力破解防护
   - locked_until 临时锁定账户
   - soft_delete（deleted_at）支持 GDPR

3. **索引很好** ✓
   - email, username 都唯一（自动索引）
   - created_at 支持"最新注册用户"查询

#### 问题

#### P1：字段不完整

```sql
-- 当前缺失的字段
avatar_url VARCHAR(1024),              -- 用户头像
display_name VARCHAR(255),             -- 显示名称（可能与 username 不同）
bio TEXT,                              -- 个人简介
phone_number VARCHAR(20),              -- 电话号码
date_of_birth DATE,                    -- 年龄验证（COPPA）
preferred_language VARCHAR(10),        -- 语言偏好（en, zh, etc.）
timezone VARCHAR(50),                  -- 时区
account_type VARCHAR(20),              -- personal | business | creator
is_verified BOOLEAN,                   -- 蓝勾（认证账户）
```

**为什么重要**：
- nova 是社交平台，需要完整的用户资料
- 这些字段现在可能存在别的表（profile? user_details?）
- 分散的字段会导致多次 JOIN

#### P2：phone_number 不在 users 表中

如果 phone_number 用于 2FA 或登录，应该在 users 表：
```sql
-- 建议
ALTER TABLE users
  ADD COLUMN phone_number VARCHAR(20) UNIQUE,
  ADD COLUMN phone_verified BOOLEAN DEFAULT FALSE;

-- 但这需要 privacy 考虑（可能需要加密存储）
```

#### P3：password_hash 长度 255 可能不够

Argon2 输出：
```
$argon2id$v=19$m=19456,t=2,p=1$R9qqu3hQvJT6z5RPOYWUbQ$...
```

实际需要 ~100 字符，255 足够，但建议更清晰：
```sql
-- 建议
password_hash VARCHAR(512) NOT NULL,  -- Argon2i 最多 ~100 字符，留足空间
```

#### P4：deleted_at 对业务的影响

当前设计允许"反注册"（撤销删除）：
```sql
-- 用户删除账户
UPDATE users SET deleted_at = NOW(), is_active = FALSE WHERE id = ...;

-- 7 天内可以恢复
UPDATE users SET deleted_at = NULL, is_active = TRUE WHERE id = ... AND deleted_at > NOW() - '7 days'::INTERVAL;
```

**问题**：
- 没有法律保护期的定义（GDPR 要求 30 天，CCPA 要求不同）
- 没有字段记录"删除理由"（审计）

**建议**：
```sql
ALTER TABLE users
  ADD COLUMN deleted_at TIMESTAMP WITH TIME ZONE,
  ADD COLUMN deletion_reason VARCHAR(50),  -- user_requested | legal | fraud
  ADD COLUMN deletion_requested_at TIMESTAMP WITH TIME ZONE;

-- 约束：deleted_at 后不能再修改关键信息
CREATE CONSTRAINT TRIGGER prevent_modification_after_deletion
  BEFORE UPDATE ON users
  FOR EACH ROW
  WHEN (OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL)
  EXECUTE FUNCTION reject_undelete_without_consent();
```

#### P5：is_active 和 deleted_at 的关系不清晰

```sql
is_active BOOLEAN,          -- 主动禁用账户（管理员操作）
deleted_at TIMESTAMP,       -- 用户请求删除（GDPR）

-- 这两个应该独立吗？还是 is_active 就够了？
```

**建议定义清晰的状态机**：
```sql
-- 或者用单个 status 字段
ALTER TABLE users
  DROP COLUMN is_active,
  DROP COLUMN deleted_at,
  ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'inactive', 'suspended', 'deleted'));

-- 状态含义：
-- active: 正常账户
-- inactive: 用户临时禁用（可随时启用）
-- suspended: 管理员禁用（因违规）
-- deleted: 用户请求删除（可在 30 天内恢复）
```

### 建议的改进方案

**阶段 1（立即）**：添加缺失的基本字段
```sql
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS display_name VARCHAR(255),
  ADD COLUMN IF NOT EXISTS avatar_url VARCHAR(1024),
  ADD COLUMN IF NOT EXISTS bio TEXT DEFAULT '',
  ADD COLUMN IF NOT EXISTS timezone VARCHAR(50) DEFAULT 'UTC',
  ADD COLUMN IF NOT EXISTS preferred_language VARCHAR(10) DEFAULT 'en';
```

**阶段 2（2 周）**：改进状态管理
```sql
-- 不破坏现有数据的迁移（使用视图和触发器）
CREATE OR REPLACE VIEW user_status_enum AS
SELECT 
  id,
  CASE 
    WHEN deleted_at IS NOT NULL THEN 'deleted'
    WHEN is_active = FALSE THEN 'inactive'
    ELSE 'active'
  END AS status
FROM users;

-- 应用层使用视图，数据库保持向后兼容
```

**阶段 3（下个月）**：规范化物理存储
```sql
-- 完全迁移到单一 status 字段（需要计划和测试）
```

---

## 总结评分

| 表 | 品味 | 问题等级 | 优先级 |
|---|---|---|---|
| posts | 🟢 好 | P2（冗余缓存） | 低 |
| messages | 🟢 好 | P1（缺版本控制） | 中 |
| users | 🟡 凑合 | P1（字段不完整） | 高 |
| videos | 未审查 | - | - |
| conversations | 未审查 | - | - |

## 立即行动

1. **Users 表**：添加 display_name, avatar_url, bio 字段（0 破坏性）
2. **Messages 表**：添加 encryption_version 字段（向后兼容）
3. **Posts 表**：标记 image_sizes 为缓存（文档化）
4. **所有表**：在新 migration 中添加版本注释

