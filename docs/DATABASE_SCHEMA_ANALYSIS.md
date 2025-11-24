# Nova 数据库架构分析报告

**生成时间**: 2025-11-24
**分析范围**: 用户账号、密码、设置、配置等核心数据存储

---

## 执行摘要

✅ **核心用户数据结构完整**
⚠️ **部分字段缺失需要补充**
✅ **密码安全存储机制正确**

---

## 1. 用户核心数据 (Identity Service)

### 1.1 `users` 表 - 主表 ✅

**定义位置**: `backend/migrations/001_initial_schema.sql`

| 字段名 | 类型 | 用途 | 状态 | iOS 对应 |
|--------|------|------|------|----------|
| `id` | UUID | 用户唯一标识 | ✅ 已建立 | `UserProfile.id` |
| `email` | VARCHAR(255) | 登录邮箱 | ✅ 已建立 | `UserProfile.email` |
| `username` | VARCHAR(50) | 用户名 (唯一) | ✅ 已建立 | `UserProfile.username` |
| `password_hash` | VARCHAR(255) | Argon2 哈希密码 | ✅ 已建立 | (后端only) |
| `email_verified` | BOOLEAN | 邮箱是否验证 | ✅ 已建立 | - |
| `is_active` | BOOLEAN | 账号是否激活 | ✅ 已建立 | - |
| `failed_login_attempts` | INT | 失败登录次数 | ✅ 已建立 | - |
| `locked_until` | TIMESTAMPTZ | 账号锁定截止时间 | ✅ 已建立 | - |
| `last_login_at` | TIMESTAMPTZ | 最后登录时间 | ✅ 已建立 | - |
| `deleted_at` | TIMESTAMPTZ | 软删除时间 | ✅ 已建立 | `UserProfile.deletedAt` |
| `created_at` | TIMESTAMPTZ | 创建时间 | ✅ 已建立 | `UserProfile.createdAt` |
| `updated_at` | TIMESTAMPTZ | 更新时间 | ✅ 已建立 | `UserProfile.updatedAt` |

**安全特性**:
- ✅ 密码使用 Argon2 哈希算法
- ✅ 邮箱格式验证 (CHECK 约束)
- ✅ 用户名格式验证 (正则: `^[a-zA-Z0-9_]{3,50}$`)
- ✅ 账号锁定机制 (防暴力破解)
- ✅ 软删除 (保留历史数据)

---

### 1.2 用户扩展字段 (Migration 028) ✅

**定义位置**: `backend/migrations/028_add_user_profile_fields.sql`

| 字段名 | 类型 | 用途 | 状态 | iOS 对应 |
|--------|------|------|------|----------|
| `display_name` | VARCHAR(100) | 显示名称 | ✅ 已建立 | `UserProfile.displayName` |
| `bio` | TEXT | 个人简介 | ✅ 已建立 | `UserProfile.bio` |
| `avatar_url` | VARCHAR(500) | 头像 URL | ✅ 已建立 | `UserProfile.avatarUrl` |
| `cover_photo_url` | VARCHAR(500) | 封面图 URL | ✅ 已建立 | `UserProfile.coverUrl` |
| `location` | VARCHAR(100) | 位置 | ✅ 已建立 | `UserProfile.location` |
| `private_account` | BOOLEAN | 私密账号 | ✅ 已建立 | `UserProfile.isPrivate` |

---

### 1.3 两步验证 (Migration 006) ✅

**定义位置**: `backend/migrations/006_add_two_factor_auth.sql`

| 字段名 | 类型 | 用途 | 状态 |
|--------|------|------|------|
| `totp_secret` | VARCHAR(32) | TOTP 密钥 | ✅ 已建立 |
| `totp_enabled` | BOOLEAN | 是否启用 2FA | ✅ 已建立 |
| `two_fa_enabled_at` | TIMESTAMPTZ | 2FA 启用时间 | ✅ 已建立 |

**Rust 模型对应**:
```rust
// backend/identity-service/src/models/user.rs
pub struct User {
    pub totp_enabled: bool,
    pub totp_secret: Option<String>,
    pub totp_verified: bool,
    // ... 其他字段
}
```

---

### 1.4 关联计数字段 (Migration 004) ✅

**定义位置**: `backend/migrations/004_social_graph_schema.sql`

| 字段名 | 类型 | 用途 | 状态 | iOS 对应 |
|--------|------|------|------|----------|
| `follower_count` | INT | 粉丝数 | ✅ 已建立 | `UserProfile.followerCount` |

**注意**: `following_count` 和 `post_count` 需要通过查询计算或在 iOS 端聚合显示。

---

## 2. 认证与会话管理 ✅

### 2.1 `sessions` 表 ✅

**用途**: 存储用户活跃会话 (access token)

| 字段名 | 类型 | 用途 |
|--------|------|------|
| `id` | UUID | 会话ID |
| `user_id` | UUID | 关联用户 |
| `access_token_hash` | VARCHAR(255) | JWT token SHA256 哈希 |
| `expires_at` | TIMESTAMPTZ | 过期时间 |
| `ip_address` | INET | 客户端 IP |
| `user_agent` | TEXT | 浏览器/设备信息 |
| `created_at` | TIMESTAMPTZ | 创建时间 |

**安全特性**:
- ✅ Token 以哈希形式存储 (SHA256)
- ✅ 支持 token 撤销 (删除会话即撤销)
- ✅ IP 和 User-Agent 记录 (审计日志)

---

### 2.2 `refresh_tokens` 表 ✅

**用途**: 存储长期 refresh token

| 字段名 | 类型 | 用途 |
|--------|------|------|
| `id` | UUID | Token ID |
| `user_id` | UUID | 关联用户 |
| `token_hash` | VARCHAR(255) | Refresh token SHA256 哈希 |
| `expires_at` | TIMESTAMPTZ | 过期时间 |
| `is_revoked` | BOOLEAN | 是否已撤销 |
| `revoked_at` | TIMESTAMPTZ | 撤销时间 |
| `ip_address` | INET | 客户端 IP |
| `user_agent` | TEXT | 设备信息 |
| `created_at` | TIMESTAMPTZ | 创建时间 |

**安全特性**:
- ✅ Token rotation 支持
- ✅ 撤销机制 (logout 时撤销)
- ✅ 设备绑定追踪

---

### 2.3 `email_verifications` 表 ✅

**用途**: 邮箱验证 token

| 字段名 | 类型 | 用途 |
|--------|------|------|
| `id` | UUID | Token ID |
| `user_id` | UUID | 关联用户 |
| `email` | VARCHAR(255) | 待验证邮箱 |
| `token_hash` | VARCHAR(255) | 验证 token 哈希 |
| `expires_at` | TIMESTAMPTZ | 过期时间 (24小时) |
| `is_used` | BOOLEAN | 是否已使用 |
| `used_at` | TIMESTAMPTZ | 使用时间 |
| `created_at` | TIMESTAMPTZ | 创建时间 |

---

### 2.4 `password_resets` 表 ✅

**用途**: 密码重置 token

| 字段名 | 类型 | 用途 |
|--------|------|------|
| `id` | UUID | Token ID |
| `user_id` | UUID | 关联用户 |
| `token_hash` | VARCHAR(255) | 重置 token 哈希 |
| `expires_at` | TIMESTAMPTZ | 过期时间 (1小时) |
| `is_used` | BOOLEAN | 是否已使用 |
| `used_at` | TIMESTAMPTZ | 使用时间 |
| `ip_address` | INET | 请求 IP |
| `created_at` | TIMESTAMPTZ | 创建时间 |

**安全特性**:
- ✅ 一次性使用 token
- ✅ 1小时过期
- ✅ IP 追踪 (防滥用)

---

## 3. ⚠️ 缺失的表和字段

### 3.1 ❌ `user_settings` 表 - 需要创建

iOS 模型定义了 `UserSettings`，但数据库中没有对应的表：

```swift
// ios/NovaSocial/Shared/Models/User/UserModels.swift
struct UserSettings: Codable {
    let userId: String
    let emailNotifications: Bool       // ❌ 缺失
    let pushNotifications: Bool        // ❌ 缺失
    let marketingEmails: Bool          // ❌ 缺失
    let timezone: String               // ❌ 缺失
    let language: String               // ❌ 缺失
    let darkMode: Bool                 // ❌ 缺失
    let privacyLevel: String           // ❌ 缺失
    let allowMessages: Bool            // ❌ 缺失
    let createdAt: Int64
    let updatedAt: Int64
}
```

**建议**: 创建 `backend/migrations/130_create_user_settings.sql`:

```sql
CREATE TABLE user_settings (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    email_notifications BOOLEAN NOT NULL DEFAULT TRUE,
    push_notifications BOOLEAN NOT NULL DEFAULT TRUE,
    marketing_emails BOOLEAN NOT NULL DEFAULT FALSE,
    timezone VARCHAR(50) NOT NULL DEFAULT 'UTC',
    language VARCHAR(10) NOT NULL DEFAULT 'en',
    dark_mode BOOLEAN NOT NULL DEFAULT FALSE,
    privacy_level VARCHAR(20) NOT NULL DEFAULT 'public',
    allow_messages BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT privacy_level_check CHECK (privacy_level IN ('public', 'friends', 'private'))
);

CREATE INDEX idx_user_settings_user_id ON user_settings(user_id);

-- 为所有现有用户创建默认设置
INSERT INTO user_settings (user_id)
SELECT id FROM users
ON CONFLICT (user_id) DO NOTHING;
```

---

### 3.2 ❌ `users` 表缺失字段

| 字段名 | iOS 期望 | 数据库实际 | 状态 |
|--------|---------|----------|------|
| `website` | `UserProfile.website` | ❌ 不存在 | 需要添加 |
| `is_verified` | `UserProfile.isVerified` | ❌ 不存在 | 需要添加 |
| `following_count` | `UserProfile.followingCount` | ❌ 不存在 | 需要添加 |
| `post_count` | `UserProfile.postCount` | ❌ 不存在 | 需要添加 |

**建议**: 创建 `backend/migrations/131_add_missing_user_fields.sql`:

```sql
-- 添加网站和认证标识字段
ALTER TABLE users ADD COLUMN IF NOT EXISTS website VARCHAR(200);
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_verified BOOLEAN NOT NULL DEFAULT FALSE;

-- 添加关注数和帖子数 (denormalized counters)
ALTER TABLE users ADD COLUMN IF NOT EXISTS following_count INT NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS post_count INT NOT NULL DEFAULT 0;

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_users_is_verified ON users(is_verified) WHERE is_verified = TRUE;

-- 回填 following_count
UPDATE users u
SET following_count = COALESCE(
    (SELECT COUNT(*) FROM follows WHERE follower_id = u.id),
    0
);

-- 回填 post_count
UPDATE users u
SET post_count = COALESCE(
    (SELECT COUNT(*) FROM posts WHERE user_id = u.id AND soft_delete IS NULL),
    0
);

-- 触发器: 维护 following_count
CREATE OR REPLACE FUNCTION update_user_following_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE users SET following_count = following_count + 1 WHERE id = NEW.follower_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE users SET following_count = GREATEST(following_count - 1, 0) WHERE id = OLD.follower_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_following_count
AFTER INSERT OR DELETE ON follows
FOR EACH ROW EXECUTE FUNCTION update_user_following_count();

-- 触发器: 维护 post_count
CREATE OR REPLACE FUNCTION update_user_post_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE users SET post_count = post_count + 1 WHERE id = NEW.user_id;
    ELSIF TG_OP = 'UPDATE' THEN
        -- 软删除
        IF NEW.soft_delete IS NOT NULL AND OLD.soft_delete IS NULL THEN
            UPDATE users SET post_count = GREATEST(post_count - 1, 0) WHERE id = NEW.user_id;
        ELSIF NEW.soft_delete IS NULL AND OLD.soft_delete IS NOT NULL THEN
            UPDATE users SET post_count = post_count + 1 WHERE id = NEW.user_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_post_count
AFTER INSERT OR UPDATE ON posts
FOR EACH ROW EXECUTE FUNCTION update_user_post_count();
```

---

## 4. 社交关系数据 (Graph Service)

### 4.1 `follows` 表 ✅

**定义位置**: `backend/migrations/004_social_graph_schema.sql`

| 字段名 | 类型 | 用途 |
|--------|------|------|
| `id` | UUID | 关系ID |
| `follower_id` | UUID | 关注者 |
| `following_id` | UUID | 被关注者 |
| `created_at` | TIMESTAMP | 创建时间 |

**约束**:
- ✅ UNIQUE(follower_id, following_id) - 防止重复关注
- ✅ CHECK(follower_id != following_id) - 防止自己关注自己

**触发器**:
- ✅ `update_user_follower_count()` - 自动更新 `users.follower_count`

---

## 5. iOS UI 数据完整性检查

### 5.1 ProfileView 所需数据 ✅

| UI 元素 | 数据来源 | 状态 |
|---------|---------|------|
| 用户名 "Bruce Li" | `users.display_name` 或 `username` | ✅ 存在 |
| 头像 | `users.avatar_url` | ✅ 存在 |
| 位置 "China" | `users.location` | ✅ 存在 |
| 职位 "Illustrator..." | `users.bio` | ✅ 存在 |
| Following 数 "592" | ⚠️ `users.following_count` (需添加) | ❌ 缺失 |
| Followers 数 "1449" | `users.follower_count` | ✅ 存在 |
| Likes 数 "452" | 聚合查询 `likes` 表 | ✅ 可查询 |
| 认证徽章 | ⚠️ `users.is_verified` (需添加) | ❌ 缺失 |
| Posts/Saved/Liked | `posts`, `bookmarks`, `likes` 表 | ✅ 存在 |

---

### 5.2 SettingsView 所需数据 ⚠️

| UI 设置项 | 数据来源 | 状态 |
|----------|---------|------|
| Profile Settings | `users` 表字段 | ✅ 存在 |
| My Account | 账号信息 (`users` 表) | ✅ 存在 |
| Devices | ❌ 缺失设备管理表 | ❌ 需创建 |
| Invite Friends | 可用现有 `users` 表 | ✅ 存在 |
| My Channels | ❌ 频道功能未实现 | ❌ 需设计 |
| Dark Mode | ⚠️ `user_settings.dark_mode` | ❌ 缺失 |
| Sign Out | Session 管理 | ✅ 存在 |

---

## 6. 数据安全性评估

### 6.1 ✅ 已实现的安全措施

1. **密码安全**:
   - ✅ Argon2 哈希算法
   - ✅ 密码复杂度验证 (最少8位)
   - ✅ 失败登录锁定机制

2. **Token 安全**:
   - ✅ Access token 哈希存储
   - ✅ Refresh token rotation
   - ✅ Token 过期机制

3. **审计日志**:
   - ✅ IP 地址记录
   - ✅ User-Agent 记录
   - ✅ 登录时间追踪

4. **数据保护**:
   - ✅ 软删除 (保留历史)
   - ✅ 外键级联删除
   - ✅ CHECK 约束验证

---

## 7. 性能优化状态

### 7.1 ✅ 已建立的索引

- ✅ `idx_users_email` - 登录查询
- ✅ `idx_users_username` - 用户名查询
- ✅ `idx_users_is_active` - 活跃用户筛选
- ✅ `idx_users_display_name` - 搜索公开用户
- ✅ `idx_users_private_account` - 隐私账号筛选
- ✅ `idx_follows_follower` - 查询用户关注列表
- ✅ `idx_follows_following` - 查询粉丝列表

### 7.2 ⚠️ 建议添加的索引

```sql
-- 在 131 迁移中添加
CREATE INDEX IF NOT EXISTS idx_users_post_count ON users(post_count DESC) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_users_follower_count ON users(follower_count DESC) WHERE is_active = TRUE;
```

---

## 8. 总结与建议

### 8.1 ✅ 已完成的部分

1. **核心认证系统完整**:
   - ✅ 用户注册、登录、密码重置
   - ✅ 邮箱验证、两步验证
   - ✅ Session 和 Refresh Token 管理

2. **基础用户资料完整**:
   - ✅ 个人信息 (username, email, bio, avatar)
   - ✅ 隐私设置 (private_account)
   - ✅ 社交计数 (follower_count)

3. **安全机制健全**:
   - ✅ 密码哈希、Token 加密
   - ✅ 账号锁定、IP 追踪
   - ✅ 软删除、审计日志

---

### 8.2 ⚠️ 需要立即修复

#### 优先级 P0 (阻塞 iOS 功能)

1. **创建 `user_settings` 表** (Migration 130):
   - ❌ `email_notifications`, `push_notifications`
   - ❌ `dark_mode`, `timezone`, `language`
   - ❌ `privacy_level`, `allow_messages`

2. **添加缺失的 `users` 字段** (Migration 131):
   - ❌ `website` - 用户网站链接
   - ❌ `is_verified` - 认证徽章
   - ❌ `following_count` - 关注数
   - ❌ `post_count` - 帖子数

#### 优先级 P1 (功能增强)

3. **创建设备管理表** (Migration 132):
   ```sql
   CREATE TABLE user_devices (
       id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
       user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
       device_name VARCHAR(100) NOT NULL,
       device_type VARCHAR(20) NOT NULL, -- 'ios', 'android', 'web'
       device_token TEXT, -- FCM/APNS token
       last_active_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
       created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
   );
   ```

4. **创建频道管理表** (Migration 133):
   ```sql
   CREATE TABLE user_channels (
       id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
       owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
       channel_name VARCHAR(100) NOT NULL,
       description TEXT,
       subscriber_count INT NOT NULL DEFAULT 0,
       created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
   );
   ```

---

### 8.3 数据库架构评分

| 维度 | 评分 | 说明 |
|------|------|------|
| **完整性** | 7.5/10 | 核心表完整,部分辅助表缺失 |
| **安全性** | 9.5/10 | 密码加密、Token 管理优秀 |
| **性能** | 8.0/10 | 索引覆盖良好,计数器优化到位 |
| **可扩展性** | 8.5/10 | 模块化设计,易于扩展 |
| **规范性** | 9.0/10 | 命名规范,约束完善 |

**总体评分**: **8.5/10** - 优秀,需补充部分表和字段

---

## 9. 下一步行动

### 立即执行 (本周)

```bash
# 1. 创建 user_settings 表
sqlx migrate add create_user_settings

# 2. 添加缺失的 users 字段
sqlx migrate add add_missing_user_fields

# 3. 测试迁移
sqlx migrate run --database-url $DATABASE_URL

# 4. 更新 Rust 模型
# backend/identity-service/src/models/user.rs 添加新字段

# 5. 更新 iOS API 调用
# 测试 UserProfile 和 UserSettings 的 API
```

### 后续优化 (下周)

1. 创建设备管理功能
2. 实现频道系统
3. 添加用户活动日志表
4. 实现 GDPR 数据导出功能

---

## 10. 参考资料

- 迁移文件: `backend/migrations/`
- Rust 模型: `backend/identity-service/src/models/user.rs`
- iOS 模型: `ios/NovaSocial/Shared/Models/User/UserModels.swift`
- 数据库迁移指南: `backend/migrations/MIGRATION_GUIDE.md`
