# Nova iOS 后端服务架构审查报告
**Author**: Claude Code (Linus Torvalds Review Style)
**Date**: 2025-11-11
**Architecture Version**: v2.0.0
**Review Scope**: iOS App Backend Services Completeness & Security

---

## 执行摘要 (Executive Summary)

### Linus 风格评价

> **"这是一个有品味的架构基础,但有3个 BLOCKER 级别的问题。"**

**核心哲学符合度**:
- ✅ **Good Taste**: Transactional Outbox 消除了分布式事务的特殊情况 → **10/10**
- ✅ **Never Break Userspace**: Expand-contract 迁移策略保护向后兼容 → **9/10**
- ❌ **实用主义**: 安全层缺失,理论上很好但生产环境会被攻击 → **5/10**
- ✅ **简洁执念**: gRPC 定义清晰,无过度抽象 → **8/10**

**生产就绪度**: 🟡 **70% 完成 - 需要立即解决 P0 安全问题**

---

## 1. 用户注册与认证 (User Registration & Authentication)

### 架构设计 - 品味评分: 🟢 **8/10 (Good, but incomplete)**

#### 数据流
```
iOS App
  ↓ GraphQL Mutation register(email, username, password)
Gateway (JWT验证层)
  ↓ gRPC
Auth Service
  ├─ Argon2 哈希 (16MB, 4 iterations) ✅
  ├─ PostgreSQL 唯一约束检查 ✅
  └─ JWT 生成 (RS256, 1h expiry) ✅
```

#### 代码审查

**✅ 优秀的实现**

1. **密码强度验证** (`backend/graphql-gateway/src/schema/auth.rs:84`)
   ```rust
   if let Err(e) = req.validate() {
       if fields.contains_key("password") {
           return Err(AuthError::WeakPassword);
       }
   }
   ```
   - 使用 zxcvbn 库防止弱密码
   - 这是**正确的做法**,比简单的正则强100倍

2. **数据库约束** (`backend/migrations/001_initial_schema.sql:30-31`)
   ```sql
   CONSTRAINT email_format CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}$')
   CONSTRAINT username_format CHECK (username ~* '^[a-zA-Z0-9_]{3,50}$')
   ```
   - 数据库层面强制约束,避免应用层绕过
   - **"有品味的代码不需要特殊情况"** ✅

3. **幂等的重复检查** (`backend/auth-service/src/handlers/auth.rs:95-101`)
   ```rust
   if crate::db::users::email_exists(&state.db, &req.email).await? {
       return Err(AuthError::EmailAlreadyExists);
   }
   if crate::db::users::username_exists(&state.db, &req.username).await? {
       return Err(AuthError::UsernameAlreadyExists);
   }
   ```
   - TOCTOU 风险被数据库 UNIQUE 约束保护
   - 即使并发注册也不会崩溃

---

### **[BLOCKER] P0-1: 缺少 Email 验证流程**

**位置**: `backend/migrations/001_initial_schema.sql:96-114`

**问题描述**:
```sql
-- 表结构已存在,但未被使用
CREATE TABLE email_verification (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL,
    token VARCHAR(255) NOT NULL UNIQUE,
    expires_at TIMESTAMP NOT NULL,
    verified_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

**当前代码** (`backend/auth-service/src/handlers/auth.rs:106`):
```rust
// ❌ 直接创建用户,没有验证邮箱
let user = crate::db::users::create_user(
    &state.db,
    &req.email,
    &req.username,
    &password_hash
).await?;
```

**风险级别**: 🔴 **CRITICAL**
- 任何人可用他人的邮箱注册
- 垃圾账户可能大量注册
- iOS 应用无法区分已验证/未验证用户

**修复方案**:

```rust
// Step 1: 在 auth.rs 中修改注册流程
pub async fn register(
    pool: web::Data<PgPool>,
    req: web::Json<RegisterRequest>,
) -> Result<HttpResponse> {
    // ... 现有的验证逻辑

    // 生成验证令牌
    let verification_token = generate_secure_token(); // 随机 32 字节 hex

    // 开始事务
    let mut tx = pool.begin().await?;

    // 创建用户 (email_verified = false)
    let user = sqlx::query_as::<_, User>(
        "INSERT INTO users (email, username, password_hash, email_verified)
         VALUES ($1, $2, $3, false)
         RETURNING *"
    )
    .bind(&req.email)
    .bind(&req.username)
    .bind(&password_hash)
    .fetch_one(&mut *tx)
    .await?;

    // 插入验证记录
    sqlx::query(
        "INSERT INTO email_verification (user_id, email, token, expires_at)
         VALUES ($1, $2, $3, NOW() + INTERVAL '24 hours')"
    )
    .bind(user.id)
    .bind(&req.email)
    .bind(&verification_token)
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;

    // 异步发送验证邮件
    tokio::spawn({
        let email = req.email.clone();
        let token = verification_token.clone();
        async move {
            send_verification_email(&email, &token).await.ok();
        }
    });

    Ok(HttpResponse::Created().json(json!({
        "user_id": user.id,
        "message": "Please check your email to verify your account"
    })))
}

// Step 2: 添加验证端点
pub async fn verify_email(
    pool: web::Data<PgPool>,
    token: web::Query<String>,
) -> Result<HttpResponse> {
    let mut tx = pool.begin().await?;

    // 查询验证记录
    let verification = sqlx::query_as::<_, EmailVerification>(
        "SELECT * FROM email_verification
         WHERE token = $1 AND verified_at IS NULL AND expires_at > NOW()"
    )
    .bind(&*token)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(AppError::InvalidToken)?;

    // 更新用户状态
    sqlx::query(
        "UPDATE users SET email_verified = true WHERE id = $1"
    )
    .bind(verification.user_id)
    .execute(&mut *tx)
    .await?;

    // 标记验证完成
    sqlx::query(
        "UPDATE email_verification SET verified_at = NOW() WHERE id = $1"
    )
    .bind(verification.id)
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;

    Ok(HttpResponse::Ok().json(json!({
        "success": true,
        "message": "Email verified successfully"
    })))
}

// Step 3: 登录时检查验证状态
pub async fn login(...) -> Result<HttpResponse> {
    // ... 验证密码

    if !user.email_verified {
        return Err(AuthError::EmailNotVerified);
    }

    // ... 生成 JWT
}
```

**GraphQL Schema 添加**:
```graphql
type Mutation {
  register(email: String!, username: String!, password: String!): RegisterResponse!
  verifyEmail(token: String!): VerifyEmailResponse!
}

type RegisterResponse {
  userId: ID!
  message: String!
}

type VerifyEmailResponse {
  success: Boolean!
  message: String!
}
```

**iOS 集成**:
```swift
// 注册后显示提示
func register(email: String, username: String, password: String) async throws {
    let response = try await graphQL.mutate(
        mutation: RegisterMutation(email: email, username: username, password: password)
    )

    // 显示提示: "Please check your email"
    showAlert(response.message)
}

// 处理 Deep Link: novasocial://verify-email?token=xxx
func handleVerifyEmailDeepLink(token: String) async {
    let response = try await graphQL.mutate(
        mutation: VerifyEmailMutation(token: token)
    )

    if response.success {
        showSuccessAlert("Email verified! You can now log in.")
    }
}
```

**工作量估算**: 8-12 小时
- 后端实现: 4h
- GraphQL Schema: 1h
- 邮件服务集成: 2h
- iOS Deep Link: 2h
- 测试: 3h

---

### **[BLOCKER] P0-2: 缺少 Logout 端点**

**位置**: `backend/graphql-gateway/src/schema/auth.rs:51-54`

**问题描述**:
```rust
// ❌ 定义了类型,但没有实现
pub struct LogoutResponse {
    pub success: bool,
}

// 在 handlers 中找不到 logout 实现
```

**当前代码审查**:
```bash
# 搜索 logout 实现
$ grep -r "async fn logout" backend/auth-service/src/handlers/
# 结果: 空
```

**风险级别**: 🔴 **CRITICAL**
- iOS 用户退出登录后,旧的 access_token 仍然有效 (1小时)
- 如果设备被盗,无法远程吊销令牌
- 无法强制用户下线 (管理员功能)

**修复方案**:

```rust
// Step 1: 在 auth_service.proto 中添加
service AuthService {
    rpc Logout(LogoutRequest) returns (LogoutResponse);
}

message LogoutRequest {
    string token = 1;  // Access token to revoke
}

message LogoutResponse {
    bool success = 1;
}

// Step 2: 实现 Token 撤销列表 (Redis)
pub async fn logout(
    redis: web::Data<RedisPool>,
    req: web::Json<LogoutRequest>,
) -> Result<HttpResponse> {
    // 解析 JWT 获取 JTI (JWT ID)
    let claims = verify_jwt(&req.token)?;

    // 计算令牌剩余有效期
    let now = Utc::now().timestamp();
    let ttl = (claims.exp - now).max(0) as usize;

    if ttl == 0 {
        return Ok(HttpResponse::Ok().json(json!({
            "success": true,
            "message": "Token already expired"
        })));
    }

    // 添加到 Redis 撤销列表
    redis.setex(
        format!("revoked_token:{}", claims.jti),
        ttl,
        "1"
    ).await?;

    Ok(HttpResponse::Ok().json(json!({
        "success": true,
        "message": "Logged out successfully"
    })))
}

// Step 3: 在 JWT 验证中检查撤销列表
pub async fn verify_token(
    redis: &RedisPool,
    token: &str,
) -> Result<Claims> {
    let claims = decode_jwt(token)?;

    // ✅ 检查是否已撤销
    let is_revoked: bool = redis.exists(
        format!("revoked_token:{}", claims.jti)
    ).await?;

    if is_revoked {
        return Err(AuthError::TokenRevoked);
    }

    Ok(claims)
}
```

**GraphQL Schema**:
```graphql
type Mutation {
  logout: LogoutResponse!
}

type LogoutResponse {
  success: Boolean!
  message: String!
}
```

**iOS 集成**:
```swift
func logout() async throws {
    // 调用后端 logout
    let response = try await graphQL.mutate(mutation: LogoutMutation())

    // 清除本地存储的 token
    TokenStorage.shared.clearTokens()

    // 导航到登录页
    coordinator.navigateToLogin()
}
```

**工作量估算**: 4-6 小时

---

### **[BLOCKER] P0-3: Refresh Token 缺少轮换机制**

**位置**: `backend/proto/services/auth_service.proto:255-262`

**问题描述**:
```proto
message RefreshTokenRequest {
    string refresh_token = 1;
}

message RefreshTokenResponse {
    string token = 1;      // 新 access_token
    int64 expires_in = 2;
    // ❌ 没有返回新的 refresh_token!
}
```

**风险级别**: 🔴 **CRITICAL**
- 同一个 refresh_token 可无限期使用
- 如果刷新令牌泄露,攻击者可永久保持访问
- 不符合 OAuth2/OIDC 安全最佳实践

**修复方案**:

```proto
// Step 1: 更新 proto 定义
message RefreshTokenResponse {
    string token = 1;              // 新 access_token
    string refresh_token = 2;      // ✅ 新的 refresh_token (轮换)
    int64 expires_in = 3;
}

// Step 2: 实现轮换逻辑
pub async fn refresh_token(
    pool: web::Data<PgPool>,
    redis: web::Data<RedisPool>,
    req: web::Json<RefreshTokenRequest>,
) -> Result<HttpResponse> {
    // 验证 old refresh_token
    let old_token = &req.refresh_token;
    let claims = verify_refresh_token(old_token)?;

    let user_id = Uuid::parse_str(&claims.sub)?;

    // ✅ 检查是否已被撤销
    let is_revoked = redis.exists(format!("revoked_refresh_token:{}", claims.jti)).await?;
    if is_revoked {
        return Err(AuthError::TokenRevoked);
    }

    // 生成新的 token pair
    let new_access_token = generate_access_token(user_id)?;
    let new_refresh_token = generate_refresh_token(user_id)?;

    // ✅ 撤销旧的 refresh_token
    redis.setex(
        format!("revoked_refresh_token:{}", claims.jti),
        30 * 24 * 3600,  // 30 天
        "1"
    ).await?;

    // 存储新的 refresh_token 到数据库 (audit log)
    sqlx::query(
        "INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
         VALUES ($1, $2, NOW() + INTERVAL '30 days')"
    )
    .bind(user_id)
    .bind(hash_token(&new_refresh_token))
    .execute(pool.as_ref())
    .await?;

    Ok(HttpResponse::Ok().json(json!({
        "token": new_access_token,
        "refresh_token": new_refresh_token,  // ✅ 返回新的
        "expires_in": 3600
    })))
}
```

**iOS 集成**:
```swift
func refreshAccessToken() async throws -> TokenPair {
    let oldRefreshToken = try TokenStorage.shared.getRefreshToken()

    let response = try await graphQL.mutate(
        mutation: RefreshTokenMutation(refreshToken: oldRefreshToken)
    )

    // ✅ 存储新的 refresh_token
    try TokenStorage.shared.saveTokens(
        accessToken: response.token,
        refreshToken: response.refreshToken  // 新的 refresh_token
    )

    return TokenPair(
        accessToken: response.token,
        refreshToken: response.refreshToken
    )
}
```

**工作量估算**: 6-8 小时

---

### **[P1] 登录速率限制不足**

**位置**: `backend/user-service/src/handlers/auth.rs:150`

**当前实现**:
```rust
// 只有账户级别的自动锁定
if user.is_locked() {
    return Err(Status::permission_denied("Account is locked"));
}

// ❌ 没有 IP 级别的 DDoS 保护
```

**建议实现**:

```rust
// middleware/rate_limit.rs
pub struct RateLimitMiddleware {
    ip_buckets: DashMap<IpAddr, TokenBucket>,
    user_buckets: DashMap<UserId, TokenBucket>,
}

impl Middleware for RateLimitMiddleware {
    async fn pre_execution(&self, req: &HttpRequest) -> Result<()> {
        let ip = extract_ip(req);

        // IP 级别限制: 60s 内 10 次
        let ip_bucket = self.ip_buckets
            .entry(ip)
            .or_insert(TokenBucket::new(10, 60));

        if !ip_bucket.take_token() {
            return Err(AppError::RateLimitExceeded(
                "Too many requests from this IP".to_string()
            ));
        }

        // 用户级别限制: 60s 内 5 次
        if let Some(user_id) = extract_user_id(req) {
            let user_bucket = self.user_buckets
                .entry(user_id)
                .or_insert(TokenBucket::new(5, 60));

            if !user_bucket.take_token() {
                return Err(AppError::RateLimitExceeded(
                    "Too many login attempts".to_string()
                ));
            }
        }

        Ok(())
    }
}
```

**工作量估算**: 4 小时

---

## 2. 帖子创建与管理 (Post Management)

### 架构设计 - 品味评分: 🟢 **10/10 (Excellent)**

#### Linus 评价:
> **"这是整个系统中最有品味的部分。Transactional Outbox 完美地消除了分布式系统中的特殊情况。"**

**代码路径**:
- Handler: `backend/content-service/src/handlers/posts.rs:31-53`
- Outbox 库: `backend/libs/transactional-outbox/` (735 行)
- 迁移: `backend/migrations/083_outbox_pattern_v2.sql:26-88`

#### 数据流
```
iOS App
  ↓ GraphQL Mutation createPost(caption, imageKey)
Content Service
  ├─ BEGIN Transaction
  ├─ INSERT posts (creator_id, content, ...)
  ├─ INSERT outbox_events (type='post.created', payload={...})  ✅ 原子性
  └─ COMMIT (两者同时成功或失败)
    ↓
Background Processor (5s 轮询)
  ├─ SELECT unpublished events
  ├─ Kafka PUBLISH (幂等)
  └─ UPDATE outbox_events SET published_at = NOW()
    ↓
Feed Service (消费者)
  ├─ Idempotency Check: INSERT processed_event ON CONFLICT IGNORE
  ├─ 更新 Feed 缓存
  └─ Redis PUBLISH cache:invalidate
```

**✅ 优秀的实现**

1. **原子性保证** (`posts.rs:38-42`)
   ```rust
   let service = PostService::with_outbox(
       (**pool).clone(),
       cache.get_ref().clone(),
       outbox_repo.get_ref().clone(),
   );

   let post = service.create_post(...).await?;
   ```

   **内部实现** (伪代码):
   ```rust
   async fn create_post(&self, ...) -> Result<Post> {
       let mut tx = self.pool.begin().await?;

       // Step 1: 创建帖子
       let post = sqlx::query_as::<_, Post>(
           "INSERT INTO posts (...) VALUES (...) RETURNING *"
       ).execute(&mut *tx).await?;

       // Step 2: 同一事务中发布事件
       publish_event!(
           &mut tx,
           self.outbox_repo,
           "content", post.id, "post.created",
           json!({
               "post_id": post.id,
               "creator_id": user_id,
               "created_at": Utc::now()
           })
       )?;

       // Step 3: 原子提交
       tx.commit().await?;  // 要么都成功,要么都失败

       Ok(post)
   }
   ```

2. **幂等消费者** (Feed Service 中)
   ```rust
   // 确保"恰好一次"处理
   INSERT INTO processed_events (event_id, processed_at)
   VALUES ($1, NOW())
   ON CONFLICT (event_id) DO NOTHING;  // PostgreSQL 原子性

   if rows_affected() == 0 {
       return Ok(ProcessingResult::AlreadyProcessed);  // 重复,忽略
   }

   // 继续处理 (更新缓存等)
   ```

3. **多层缓存** (`posts.rs:61`)
   ```rust
   let service = PostService::with_cache(
       (**pool).clone(),
       cache.get_ref().clone()
   );

   match service.get_post(*post_id).await? {
       Some(post) => Ok(HttpResponse::Ok().json(post)),
       None => Ok(HttpResponse::NotFound().finish()),
   }
   ```

---

### **[P1] 缺少帖子内容验证**

**位置**: `backend/content-service/src/handlers/posts.rs:14-18`

**当前代码**:
```rust
#[derive(Debug, Deserialize)]
pub struct CreatePostRequest {
    pub caption: Option<String>,
    pub image_key: Option<String>,
    pub content_type: Option<String>,
}

// ❌ 没有验证长度、格式、XSS
```

**风险级别**: 🟡 **MEDIUM**
- 超长 caption 可能导致数据库性能问题
- 恶意 HTML/JS 可能导致 XSS 攻击
- 无效的 image_key 格式可能导致崩溃

**修复方案**:

```rust
use validator::Validate;

#[derive(Debug, Deserialize, Validate)]
pub struct CreatePostRequest {
    #[validate(length(min = 1, max = 2000, message = "Caption must be 1-2000 characters"))]
    pub caption: Option<String>,

    #[validate(regex(
        path = "IMAGE_KEY_REGEX",
        message = "Invalid image_key format"
    ))]
    pub image_key: Option<String>,

    #[validate(custom = "validate_content_type")]
    pub content_type: Option<String>,
}

lazy_static! {
    static ref IMAGE_KEY_REGEX: Regex = Regex::new(
        r"^s3://[a-z0-9-]+/[a-zA-Z0-9/_-]+\.(jpg|jpeg|png|gif|webp)$"
    ).unwrap();
}

fn validate_content_type(content_type: &str) -> Result<(), ValidationError> {
    let valid_types = ["image/jpeg", "image/png", "image/gif", "image/webp"];
    if !valid_types.contains(&content_type) {
        return Err(ValidationError::new("invalid_content_type"));
    }
    Ok(())
}

pub async fn create_post(
    pool: web::Data<PgPool>,
    req: web::Json<CreatePostRequest>,
    user_id: UserId,
) -> Result<HttpResponse> {
    // ✅ 验证输入
    req.validate()?;  // 验证失败返回 400

    // ✅ 清理 caption (移除危险的 HTML/JS)
    let safe_caption = sanitize_html(&req.caption.as_ref().unwrap_or(&String::new()));

    let post = service.create_post(
        user_id.0,
        &safe_caption,
        req.image_key.as_deref(),
        req.content_type.as_deref()
    ).await?;

    Ok(HttpResponse::Created().json(post))
}

// HTML 清理函数
fn sanitize_html(input: &str) -> String {
    use ammonia::Builder;

    Builder::new()
        .tags(hashset![])  // 不允许任何 HTML 标签
        .clean(input)
        .to_string()
}
```

**工作量估算**: 3 小时

---

### **[P1] 缺少所有权检查 (Authorization)**

**位置**: `backend/content-service/src/handlers/posts.rs:89-111`

**当前代码**:
```rust
pub async fn update_post_status(
    pool: web::Data<PgPool>,
    post_id: web::Path<Uuid>,
    user_id: UserId,
    req: web::Json<UpdatePostStatusRequest>,
) -> Result<HttpResponse> {
    // ❌ 这里没有检查 post.creator_id == user_id.0
    let updated = service.update_post_status(
        *post_id,
        user_id.0,
        &req.status
    ).await?;

    if updated {
        Ok(HttpResponse::Ok().finish())
    } else {
        Ok(HttpResponse::NotFound().finish())
    }
}
```

**风险级别**: 🟡 **MEDIUM**
- 如果 service 层没有检查,任何用户都可删除任何帖子
- 可能导致数据丢失或滥用

**修复方案**:

```rust
pub async fn delete_post(
    pool: web::Data<PgPool>,
    cache: web::Data<Arc<ContentCache>>,
    outbox_repo: web::Data<Arc<OutboxRepository>>,
    post_id: web::Path<Uuid>,
    user_id: UserId,
) -> Result<HttpResponse> {
    // ✅ Step 1: 查询帖子及所有者
    let post = sqlx::query_as::<_, Post>(
        "SELECT * FROM posts WHERE id = $1 AND deleted_at IS NULL"
    )
    .bind(*post_id)
    .fetch_optional(pool.as_ref())
    .await?
    .ok_or(AppError::NotFound)?;

    // ✅ Step 2: 验证所有权
    if post.creator_id != user_id.0 {
        return Err(AppError::Unauthorized(
            "You can only delete your own posts".to_string()
        ));
    }

    // ✅ Step 3: 软删除 (使用 Outbox)
    let service = PostService::with_outbox(
        (**pool).clone(),
        cache.get_ref().clone(),
        outbox_repo.get_ref().clone(),
    );

    let deleted = service.delete_post(*post_id, user_id.0).await?;

    if deleted {
        Ok(HttpResponse::NoContent().finish())
    } else {
        Ok(HttpResponse::NotFound().finish())
    }
}
```

**数据库约束加强** (迁移):
```sql
-- 确保删除时同时记录 deleted_by
ALTER TABLE posts ADD COLUMN deleted_by UUID REFERENCES users(id);

ALTER TABLE posts ADD CONSTRAINT chk_delete_consistency
    CHECK (
        (deleted_at IS NULL AND deleted_by IS NULL) OR
        (deleted_at IS NOT NULL AND deleted_by IS NOT NULL)
    );
```

**工作量估算**: 4 小时

---

## 3. 消息功能 (E2EE Messaging)

### 架构设计 - 品味评分: 🟢 **9/10 (Modern design, incomplete implementation)**

#### Linus 评价:
> **"E2EE 架构设计是现代的,与 Signal/Telegram 风格一致。但 Handler 实现缺失,这是个大问题。"**

**代码路径**:
- Proto: `backend/proto/services/messaging_service.proto:14-63, 305-343`
- 数据库: `backend/migrations/018_messaging_schema.sql:49-58`

#### 数据流
```
iOS App (User A)
  ├─ 生成 Curve25519 密钥对 (设备级)
  ├─ 上传公钥 → gRPC StoreDevicePublicKey
  └─ 输入消息
    ↓
Message Encryption Layer
  ├─ 获取接收者公钥 → GetPeerPublicKey
  ├─ ECDH 密钥协商 → shared_secret
  ├─ AES-256-GCM 加密消息
  ├─ 生成 nonce (96-bit)
    ↓ gRPC SendMessage
Messaging Service
  ├─ BEGIN Transaction
  ├─ INSERT messages (encrypted_content, nonce, ...)
  ├─ INSERT outbox_events ('message.created')
  └─ COMMIT
    ↓
Kafka 消费者
  ├─ 发布到 user_subscription topic
  ├─ WebSocket 推送给接收者
  └─ 离线队列
    ↓
iOS App (User B)
  ├─ 接收加密消息
  ├─ 使用设备私钥解密
  └─ 显示原文本
```

**✅ 优秀的 Proto 设计**

1. **设备级 E2EE** (`messaging_service.proto:14-28`)
   ```proto
   message Message {
       string id = 1;
       string conversation_id = 2;
       string sender_id = 3;
       string content = 4;              // 明文 (仅用于搜索/日志)
       bytes content_encrypted = 5;     // ✅ 加密内容
       bytes content_nonce = 6;         // ✅ 加密 nonce
       int32 encryption_version = 7;    // ✅ 支持算法版本升级
       int64 sequence_number = 8;       // ✅ 防止重放攻击
       string idempotency_key = 9;      // ✅ 幂等性
   }
   ```

2. **密钥交换流程** (`messaging_service.proto:306-329`)
   ```proto
   message StoreDevicePublicKeyRequest {
       string user_id = 1;
       string device_id = 2;
       string public_key = 3;  // Base64 encoded Curve25519
   }

   message GetPeerPublicKeyRequest {
       string conversation_id = 1;
       string peer_user_id = 2;
       string peer_device_id = 3;
   }

   message CompleteKeyExchangeRequest {
       string conversation_id = 1;
       string peer_user_id = 2;
       string shared_secret_hash = 3;
   }
   ```

3. **离线队列支持** (`messaging_service.proto:384-410`)
   ```proto
   message OfflineQueueEvent {
       string event_type = 3;
       string data = 4;  // JSON
   }

   service MessagingService {
       rpc GetOfflineEvents(GetOfflineEventsRequest) ...
       rpc AckOfflineEvent(AckOfflineEventRequest) ...
   }
   ```

---

### **[BLOCKER] P0-4: E2EE Handler 实现缺失**

**问题描述**:
```bash
# 搜索 E2EE 相关 handler
$ grep -r "GetPeerPublicKey\|StoreDevicePublicKey\|CompleteKeyExchange" \
    backend/messaging-service/src/handlers/

# ❌ 结果: 没有找到这些 RPC 的 handler 实现!
```

**风险级别**: 🔴 **CRITICAL**
- 密钥交换流程未实现
- 消息在服务器端是明文存储 (encrypted_content 字段为空)
- 如果服务器被攻破,所有历史消息被读取

**修复方案**:

创建新文件 `backend/messaging-service/src/handlers/encryption.rs`:

```rust
use actix_web::{web, HttpResponse};
use sqlx::PgPool;
use uuid::Uuid;
use base64::{Engine as _, engine::general_purpose};

pub async fn store_device_public_key(
    pool: web::Data<PgPool>,
    req: web::Json<StoreDevicePublicKeyRequest>,
) -> Result<HttpResponse> {
    // ✅ Step 1: 验证 public_key 格式
    let public_key_bytes = general_purpose::STANDARD
        .decode(&req.public_key)
        .map_err(|_| AppError::InvalidPublicKey)?;

    if public_key_bytes.len() != 32 {
        return Err(AppError::InvalidPublicKey);
    }

    // ✅ Step 2: 存储到数据库 (upsert)
    sqlx::query(
        "INSERT INTO device_public_keys
            (user_id, device_id, public_key, algorithm, created_at)
         VALUES ($1, $2, $3, 'Curve25519', NOW())
         ON CONFLICT (user_id, device_id)
         DO UPDATE SET
            public_key = $3,
            updated_at = NOW()"
    )
    .bind(Uuid::parse_str(&req.user_id)?)
    .bind(&req.device_id)
    .bind(&req.public_key)
    .execute(pool.as_ref())
    .await?;

    Ok(HttpResponse::Ok().json(json!({
        "success": true,
        "message": "Public key stored successfully"
    })))
}

pub async fn get_peer_public_key(
    pool: web::Data<PgPool>,
    req: web::Json<GetPeerPublicKeyRequest>,
) -> Result<HttpResponse> {
    // ✅ Step 1: 查询接收者的公钥
    let public_key = sqlx::query_as::<_, DevicePublicKey>(
        "SELECT * FROM device_public_keys
         WHERE user_id = $1 AND device_id = $2"
    )
    .bind(Uuid::parse_str(&req.peer_user_id)?)
    .bind(&req.peer_device_id)
    .fetch_optional(pool.as_ref())
    .await?
    .ok_or(AppError::DeviceNotFound)?;

    Ok(HttpResponse::Ok().json(GetPeerPublicKeyResponse {
        peer_user_id: req.peer_user_id.clone(),
        peer_device_id: req.peer_device_id.clone(),
        peer_public_key: public_key.public_key,
        algorithm: public_key.algorithm,
        created_at: public_key.created_at.timestamp(),
    }))
}

pub async fn complete_key_exchange(
    pool: web::Data<PgPool>,
    req: web::Json<CompleteKeyExchangeRequest>,
) -> Result<HttpResponse> {
    // ✅ 记录密钥交换完成 (audit log)
    sqlx::query(
        "INSERT INTO key_exchanges
            (conversation_id, user_id, peer_user_id, shared_secret_hash, created_at)
         VALUES ($1, $2, $3, $4, NOW())"
    )
    .bind(Uuid::parse_str(&req.conversation_id)?)
    .bind(Uuid::parse_str(&req.user_id)?)
    .bind(Uuid::parse_str(&req.peer_user_id)?)
    .bind(&req.shared_secret_hash)
    .execute(pool.as_ref())
    .await?;

    Ok(HttpResponse::Ok().json(json!({
        "success": true,
        "message": "Key exchange completed"
    })))
}

// 数据库模型
#[derive(sqlx::FromRow)]
struct DevicePublicKey {
    user_id: Uuid,
    device_id: String,
    public_key: String,
    algorithm: String,
    created_at: DateTime<Utc>,
}
```

**数据库迁移** (`migrations/019_device_public_keys.sql`):
```sql
CREATE TABLE device_public_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id VARCHAR(255) NOT NULL,
    public_key TEXT NOT NULL,  -- Base64 encoded
    algorithm VARCHAR(50) NOT NULL DEFAULT 'Curve25519',
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, device_id)
);

CREATE INDEX idx_device_public_keys_user ON device_public_keys(user_id);

CREATE TABLE key_exchanges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    peer_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    shared_secret_hash TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_key_exchanges_conversation ON key_exchanges(conversation_id);
```

**iOS 集成**:
```swift
// Step 1: 生成并上传公钥
func setupE2EE() async throws {
    // 生成 Curve25519 密钥对
    let keyPair = try Curve25519.KeyAgreement.PrivateKey()
    let publicKeyData = keyPair.publicKey.rawRepresentation
    let publicKeyBase64 = publicKeyData.base64EncodedString()

    // 存储私钥到 Keychain
    try KeychainManager.shared.savePrivateKey(keyPair)

    // 上传公钥到服务器
    let response = try await graphQL.mutate(
        mutation: StoreDevicePublicKeyMutation(
            userId: currentUserId,
            deviceId: UIDevice.current.identifierForVendor!.uuidString,
            publicKey: publicKeyBase64
        )
    )

    print("E2EE setup completed")
}

// Step 2: 发送加密消息
func sendEncryptedMessage(to peerId: String, content: String) async throws {
    // 获取接收者的公钥
    let peerPublicKeyResponse = try await graphQL.query(
        query: GetPeerPublicKeyQuery(
            peerUserId: peerId,
            peerDeviceId: "..."
        )
    )

    let peerPublicKeyData = Data(base64Encoded: peerPublicKeyResponse.peerPublicKey)!
    let peerPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKeyData)

    // ECDH 密钥协商
    let privateKey = try KeychainManager.shared.getPrivateKey()
    let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)

    // 使用 HKDF 派生加密密钥
    let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
        using: SHA256.self,
        salt: Data(),
        sharedInfo: Data(),
        outputByteCount: 32
    )

    // AES-256-GCM 加密
    let contentData = content.data(using: .utf8)!
    let sealedBox = try AES.GCM.seal(contentData, using: symmetricKey)

    // 发送加密消息
    let response = try await graphQL.mutate(
        mutation: SendMessageMutation(
            conversationId: conversationId,
            contentEncrypted: sealedBox.ciphertext.base64EncodedString(),
            contentNonce: sealedBox.nonce.base64EncodedString(),
            encryptionVersion: 2
        )
    )
}
```

**工作量估算**: 16-20 小时
- 后端 Handler 实现: 8h
- 数据库迁移: 2h
- iOS E2EE 集成: 8h
- 测试: 2h

---

### **[P1] 消息内容验证缺失**

**位置**: `backend/proto/services/messaging_service.proto:71-79`

**当前 Proto**:
```proto
message SendMessageRequest {
    string conversation_id = 1;
    string sender_id = 2;
    string content = 3;  // ❌ 无长度限制
    bytes content_encrypted = 4;  // ❌ 无大小限制
    bytes content_nonce = 5;
    int32 encryption_version = 6;
    string idempotency_key = 7;
}
```

**修复方案**:

```proto
message SendMessageRequest {
    string conversation_id = 1;
    string sender_id = 2;

    // ✅ 添加验证规则 (使用 protovalidate)
    string content = 3 [
        (validate.rules).string = {max_len: 4096}
    ];

    bytes content_encrypted = 4 [
        (validate.rules).bytes = {max_len: 8192}  // 8KB
    ];

    bytes content_nonce = 5 [
        (validate.rules).bytes = {len: 12}  // GCM nonce 固定 12 字节
    ];

    int32 encryption_version = 6 [
        (validate.rules).int32 = {gte: 1, lte: 2}
    ];

    string idempotency_key = 7 [
        (validate.rules).string = {pattern: "^[a-zA-Z0-9-_]{16,64}$"}
    ];
}
```

**Handler 中的验证**:
```rust
pub async fn send_message(
    pool: web::Data<PgPool>,
    req: web::Json<SendMessageRequest>,
) -> Result<HttpResponse> {
    // ✅ 验证加密版本
    if req.encryption_version != 2 {
        return Err(AppError::UnsupportedEncryptionVersion);
    }

    // ✅ 验证 nonce 长度
    if req.content_nonce.len() != 12 {
        return Err(AppError::InvalidNonceLength);
    }

    // ✅ 验证加密内容存在
    if req.content_encrypted.is_empty() {
        return Err(AppError::MissingEncryptedContent);
    }

    // ... 继续处理
}
```

**工作量估算**: 2 小时

---

## 4. Feed/Timeline & 用户关系 (Social Graph)

### 架构设计 - 品味评分: 🟢 **9/10 (Excellent with minor gaps)**

#### Linus 评价:
> **"关系操作使用 Outbox 是正确的,Feed 缓存失效的异步处理也很好。但 Follow 权限检查缺失是个大问题。"**

**代码路径**:
- Handler: `backend/user-service/src/handlers/relationships.rs:34-165`
- Proto: `backend/proto/services/user_service.proto:139-149, 269-288`
- GraphQL: `backend/graphql-gateway/src/schema/user.rs:95-122`

#### 数据流
```
iOS App
  ↓ GraphQL Mutation followUser(followeeId)
User Service
  ├─ BEGIN Transaction
  ├─ INSERT follows (follower_id, following_id)
  ├─ publish_event!('user.followed', {...})  ✅ Outbox
  └─ COMMIT
    ↓
Background 事件处理
  ├─ Kafka 消费 post.created 事件
  ├─ Feed Service 判断: 消费者是否 follow 作者?
  ├─ 如果是: 添加到消费者的 feed 缓存
  └─ Redis PUBLISH cache:invalidate
    ↓
Feed Cache 更新
  └─ 所有关注者的缓存同步失效
```

**✅ 优秀的实现**

1. **Follow 操作使用 Outbox** (`relationships.rs:73-126`)
   ```rust
   let mut tx = pool.begin().await?;

   // INSERT follow
   sqlx::query(
       "INSERT INTO follows (follower_id, following_id, created_at)
        VALUES ($1, $2, NOW())"
   )
   .bind(user.0)
   .bind(target_id)
   .execute(&mut *tx)
   .await?;

   // ✅ 同一事务中发布事件
   publish_event!(
       &mut tx,
       outbox_repo.get_ref().as_ref(),
       "user", user.0, "user.followed",
       json!({
           "follower_id": user.0.to_string(),
           "followee_id": target_id.to_string(),
           "timestamp": Utc::now().to_rfc3339()
       })
   )?;

   // ✅ 原子提交
   tx.commit().await?;
   ```

2. **异步缓存失效** (`relationships.rs:140-150`)
   ```rust
   // 通过 Feed Service gRPC 调用来失效缓存
   tokio::spawn(async move {
       match client.invalidate_feed_cache(follower_id, "new_follow").await {
           Ok(_) => record_social_follow_event("new_follow", "processed"),
           Err(e) => warn!("Failed to invalidate feed cache: {}", e),
       }
   });
   ```

   **这是好设计**:
   - 异步调用,不阻塞 HTTP 响应
   - 如果失效失败,日志记录而不是抛错
   - 最终一致性保证 (下次刷新时重新计算)

3. **Neo4j 图数据库支持** (`relationships.rs:133-138`)
   ```rust
   if graph.is_enabled() {
       let g = graph.get_ref().clone();
       tokio::spawn(async move {
           let _ = g.follow(user.0, target_id).await;
       });
   }
   ```

---

### **[BLOCKER] P0-5: Follow 操作缺少权限检查**

**位置**: `backend/user-service/src/handlers/relationships.rs:50-52`

**当前代码**:
```rust
pub async fn follow_user(...) -> HttpResponse {
    // 检查不能 follow 自己
    if target_id == user.0 {
        return HttpResponse::BadRequest().json(json!({
            "error": "cannot follow self"
        }));
    }

    // ❌ 缺少以下检查:
    // 1. 是否被 target_id 阻止 (blocked)
    // 2. 是否 target_id 是私密账户 (需要 approval)
    // 3. 是否已经 follow 了

    // ... 直接插入 follows 表
}
```

**风险级别**: 🔴 **CRITICAL**
- 任何人可以 follow 任何人,包括已阻止的用户
- 私密账户的隐私被绕过
- 重复 follow 可能导致数据库错误或幽灵关系

**修复方案**:

```rust
pub async fn follow_user(
    pool: web::Data<PgPool>,
    cache: web::Data<Arc<RelationshipCache>>,
    outbox_repo: web::Data<Arc<OutboxRepository>>,
    target_id: web::Path<Uuid>,
    user: UserId,
) -> Result<HttpResponse> {
    let target_id = *target_id;

    // ✅ Check 1: 不能 follow 自己
    if target_id == user.0 {
        return Err(AppError::BadRequest("cannot follow self".to_string()));
    }

    // ✅ Check 2: 检查是否被阻止
    let is_blocked = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(
            SELECT 1 FROM blocks
            WHERE (blocker_id = $1 AND blocked_id = $2)
               OR (blocker_id = $2 AND blocked_id = $1)
        )"
    )
    .bind(target_id)
    .bind(user.0)
    .fetch_one(pool.as_ref())
    .await
    .unwrap_or(false);

    if is_blocked {
        return Err(AppError::Forbidden(
            "Cannot follow this user".to_string()
        ));
    }

    // ✅ Check 3: 检查是否已 follow
    let already_following = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(
            SELECT 1 FROM follows
            WHERE follower_id = $1 AND following_id = $2
        )"
    )
    .bind(user.0)
    .bind(target_id)
    .fetch_one(pool.as_ref())
    .await
    .unwrap_or(false);

    if already_following {
        return Err(AppError::Conflict("Already following".to_string()));
    }

    // ✅ Check 4: 检查目标用户是否是私密账户
    let target_user = sqlx::query_as::<_, User>(
        "SELECT * FROM users WHERE id = $1"
    )
    .bind(target_id)
    .fetch_optional(pool.as_ref())
    .await?
    .ok_or(AppError::NotFound)?;

    let follow_status = if target_user.private_account {
        "pending"  // 需要 target_user 批准
    } else {
        "active"   // 立即生效
    };

    // ✅ 插入 follow 关系 (带 status)
    let mut tx = pool.begin().await?;

    sqlx::query(
        "INSERT INTO follows (follower_id, following_id, status, created_at)
         VALUES ($1, $2, $3, NOW())"
    )
    .bind(user.0)
    .bind(target_id)
    .bind(&follow_status)
    .execute(&mut *tx)
    .await?;

    // ✅ 发布事件 (带 status)
    publish_event!(
        &mut tx,
        outbox_repo.get_ref().as_ref(),
        "user", user.0, "user.followed",
        json!({
            "follower_id": user.0.to_string(),
            "followee_id": target_id.to_string(),
            "status": follow_status,
            "timestamp": Utc::now().to_rfc3339()
        })
    )?;

    tx.commit().await?;

    // 如果是 pending,发送通知给 target_user
    if follow_status == "pending" {
        tokio::spawn(async move {
            send_follow_request_notification(target_id, user.0).await.ok();
        });
    }

    Ok(HttpResponse::Ok().json(json!({
        "success": true,
        "status": follow_status,
        "message": if follow_status == "pending" {
            "Follow request sent"
        } else {
            "Successfully followed"
        }
    })))
}
```

**数据库迁移**:
```sql
-- 添加 status 字段
ALTER TABLE follows ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'active';
ALTER TABLE follows ADD CONSTRAINT chk_follow_status
    CHECK (status IN ('active', 'pending', 'rejected'));

-- 添加 blocks 表
CREATE TABLE blocks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    blocker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (blocker_id, blocked_id),
    CHECK (blocker_id != blocked_id)
);

CREATE INDEX idx_blocks_blocker ON blocks(blocker_id);
CREATE INDEX idx_blocks_blocked ON blocks(blocked_id);

-- 添加 private_account 字段
ALTER TABLE users ADD COLUMN private_account BOOLEAN NOT NULL DEFAULT false;
```

**iOS 集成**:
```swift
func followUser(userId: String) async throws -> FollowResult {
    let response = try await graphQL.mutate(
        mutation: FollowUserMutation(followeeId: userId)
    )

    switch response.status {
    case "active":
        showSuccess("Successfully followed")
        return .followed

    case "pending":
        showInfo("Follow request sent. Waiting for approval.")
        return .pending

    default:
        throw AppError.unknownStatus
    }
}

// 接收 follow request 通知
func handleFollowRequest(notification: FollowRequestNotification) {
    showAlert(
        title: "Follow Request",
        message: "\(notification.followerUsername) wants to follow you",
        actions: [
            .default("Accept") {
                approveFollowRequest(requestId: notification.requestId)
            },
            .destructive("Decline") {
                rejectFollowRequest(requestId: notification.requestId)
            }
        ]
    )
}
```

**工作量估算**: 8-10 小时

---

### **[P1] Feed 缓存预热策略不清晰**

**问题描述**:
当用户注册或首次登录时,Feed 缓存应该预热。但当前代码中找不到相关逻辑。

**修复方案**:

```proto
// feed_service.proto 中添加
message WarmupFeedCacheRequest {
    string user_id = 1;
}

message WarmupFeedCacheResponse {
    bool success = 1;
    int32 posts_loaded = 2;
}

service FeedService {
    rpc WarmupFeedCache(WarmupFeedCacheRequest) returns (WarmupFeedCacheResponse);
}
```

**在 Auth Service 的 Login/Register 成功后调用**:

```rust
// auth-service/src/handlers/auth.rs

pub async fn login(...) -> Result<HttpResponse> {
    // ... 验证密码

    let token_pair = jwt::generate_token_pair(user.id)?;

    // ✅ 异步预热 Feed 缓存 (不阻塞登录响应)
    tokio::spawn({
        let feed_client = feed_client.clone();
        let user_id = user.id.to_string();
        async move {
            match feed_client.warmup_feed_cache(&user_id).await {
                Ok(_) => tracing::info!("Feed cache warmed for user {}", user_id),
                Err(e) => tracing::warn!("Failed to warmup feed cache: {}", e),
            }
        }
    });

    Ok(HttpResponse::Ok().json(LoginResponse {
        user_id: user.id.to_string(),
        token: token_pair.access_token,
        refresh_token: token_pair.refresh_token,
        expires_in: 3600,
    }))
}
```

**Feed Service 实现**:

```rust
// feed-service/src/handlers/feed.rs

pub async fn warmup_feed_cache(
    pool: web::Data<PgPool>,
    cache: web::Data<Arc<FeedCache>>,
    req: WarmupFeedCacheRequest,
) -> Result<WarmupFeedCacheResponse> {
    let user_id = Uuid::parse_str(&req.user_id)?;

    // ✅ 查询用户 follow 的所有人
    let following_ids: Vec<Uuid> = sqlx::query_scalar(
        "SELECT following_id FROM follows
         WHERE follower_id = $1 AND status = 'active'"
    )
    .bind(user_id)
    .fetch_all(pool.as_ref())
    .await?;

    // ✅ 查询最近的 50 条帖子
    let posts: Vec<Post> = sqlx::query_as(
        "SELECT * FROM posts
         WHERE creator_id = ANY($1)
            AND deleted_at IS NULL
         ORDER BY created_at DESC
         LIMIT 50"
    )
    .bind(&following_ids)
    .fetch_all(pool.as_ref())
    .await?;

    // ✅ 缓存到 Redis + DashMap
    for post in &posts {
        cache.insert_post(post.id, post.clone()).await?;
    }

    // ✅ 缓存用户的 feed 列表
    let post_ids: Vec<Uuid> = posts.iter().map(|p| p.id).collect();
    cache.insert_user_feed(user_id, post_ids).await?;

    Ok(WarmupFeedCacheResponse {
        success: true,
        posts_loaded: posts.len() as i32,
    })
}
```

**工作量估算**: 4-6 小时

---

## 5. 跨服务安全性 (Cross-Service Security)

### 架构设计 - 品味评分: 🔴 **3/10 (Critical security gaps)**

#### Linus 评价:
> **"这是最严重的问题。无论架构多么优雅,如果服务间没有认证,一个恶意 Pod 可以摧毁整个系统。这不是理论问题,这是生产环境的真实风险。"**

---

### **[BLOCKER] P0-6: 缺少 gRPC 服务间 mTLS**

**问题描述**:

文档明确说明:
> ⚠️ **安全加固**: 需立即实现 mTLS 和服务间认证 (P0)

**当前状态**:
```rust
// clients/mod.rs (推测)
let channel = tonic::transport::Channel::from_static(
    "http://content-service:8081"  // ❌ 明文 HTTP
)
.connect()
.await?;
```

**风险级别**: 🔴 **CRITICAL**
- 任何人可冒充 Auth Service 返回假 token
- MITM 攻击可修改消息内容
- 同集群内的恶意 Pod 可窃听流量

**修复方案**:

**已提供的库**: `backend/libs/grpc-tls/src/mtls.rs`

```rust
// grpc-tls/src/mtls.rs

use tonic::transport::{Channel, ClientTlsConfig, Identity, Certificate};

pub struct MtlsConfig {
    pub cert_path: String,
    pub key_path: String,
    pub ca_cert_path: String,
}

pub async fn create_secure_channel(
    address: &str,
    mtls_config: &MtlsConfig,
) -> Result<Channel> {
    // ✅ Step 1: 加载客户端证书和私钥
    let cert = tokio::fs::read(&mtls_config.cert_path).await?;
    let key = tokio::fs::read(&mtls_config.key_path).await?;
    let identity = Identity::from_pem(cert, key);

    // ✅ Step 2: 加载 CA 证书 (验证服务器)
    let ca_cert = tokio::fs::read(&mtls_config.ca_cert_path).await?;
    let ca_certificate = Certificate::from_pem(ca_cert);

    // ✅ Step 3: 配置双向 TLS
    let tls = ClientTlsConfig::new()
        .identity(identity)           // 客户端证书
        .ca_certificate(ca_certificate)  // 验证服务器证书
        .domain_name("content-service.nova.svc.cluster.local");

    // ✅ Step 4: 创建安全连接
    Channel::from_static(address)
        .tls_config(tls)?
        .connect()
        .await
}

// Server 端配置
use tonic::transport::{Server, ServerTlsConfig};

pub async fn create_secure_server(
    mtls_config: &MtlsConfig,
) -> Result<Server> {
    // ✅ 加载服务器证书
    let cert = tokio::fs::read(&mtls_config.cert_path).await?;
    let key = tokio::fs::read(&mtls_config.key_path).await?;
    let identity = Identity::from_pem(cert, key);

    // ✅ 加载 CA 证书 (验证客户端)
    let ca_cert = tokio::fs::read(&mtls_config.ca_cert_path).await?;
    let ca_certificate = Certificate::from_pem(ca_cert);

    // ✅ 配置双向 TLS
    let tls = ServerTlsConfig::new()
        .identity(identity)
        .client_ca_root(ca_certificate);  // 要求客户端证书

    Ok(Server::builder().tls_config(tls)?)
}
```

**Kubernetes 部署配置**:

```yaml
# 1. 生成证书 (使用 cert-manager)
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: content-service-cert
  namespace: nova
spec:
  secretName: content-service-tls
  issuerRef:
    name: nova-ca-issuer
    kind: ClusterIssuer
  dnsNames:
    - content-service.nova.svc.cluster.local
  usages:
    - digital signature
    - key encipherment
    - server auth
    - client auth  # ✅ 双向 TLS

---
# 2. 挂载证书到 Pod
apiVersion: apps/v1
kind: Deployment
metadata:
  name: content-service
spec:
  template:
    spec:
      containers:
      - name: content-service
        image: nova/content-service:latest
        env:
        - name: TLS_CERT_PATH
          value: /etc/tls/tls.crt
        - name: TLS_KEY_PATH
          value: /etc/tls/tls.key
        - name: TLS_CA_CERT_PATH
          value: /etc/tls/ca.crt
        volumeMounts:
        - name: tls-certs
          mountPath: /etc/tls
          readOnly: true
      volumes:
      - name: tls-certs
        secret:
          secretName: content-service-tls
```

**在所有服务中启用 mTLS**:

```rust
// content-service/src/main.rs

#[tokio::main]
async fn main() -> Result<()> {
    let config = load_config()?;

    // ✅ 配置 mTLS
    let mtls_config = MtlsConfig {
        cert_path: env::var("TLS_CERT_PATH")?,
        key_path: env::var("TLS_KEY_PATH")?,
        ca_cert_path: env::var("TLS_CA_CERT_PATH")?,
    };

    let addr = "[::1]:50051".parse()?;

    // ✅ 创建安全的 gRPC server
    let server = create_secure_server(&mtls_config).await?;

    server
        .add_service(ContentServiceServer::new(content_impl))
        .serve(addr)
        .await?;

    Ok(())
}
```

**工作量估算**: 12-16 小时
- 设置 cert-manager: 2h
- 实现 mTLS 客户端/服务器: 4h
- 部署到所有服务: 4h
- 测试: 4h
- 文档: 2h

---

### **[BLOCKER] P0-7: GraphQL Gateway 没有 gRPC 认证**

**问题描述**:

当某个 gRPC 客户端调用 content-service 时,没有验证调用者身份:

```rust
// content-service 的 RPC 实现
impl ContentService for ContentServiceImpl {
    async fn create_post(
        &self,
        request: Request<CreatePostRequest>,
    ) -> Result<Response<CreatePostResponse>> {
        let req = request.into_inner();

        // ❌ 没有检查请求来源是否被授权
        // 任何服务都可以代表任何 user_id 创建帖子

        let post = self.db.create_post(req.creator_id, req.content).await?;
        Ok(Response::new(CreatePostResponse { post: Some(post) }))
    }
}
```

**风险级别**: 🔴 **CRITICAL**
- 内部服务可被未授权访问
- 恶意服务可冒充任何用户执行操作
- 无法追踪哪个服务发起了请求

**修复方案**:

```rust
// grpc-tls/src/interceptor.rs

use tonic::{Request, Status};
use tonic::service::Interceptor;
use jsonwebtoken::{decode, DecodingKey, Validation};

pub struct AuthInterceptor {
    jwt_secret: DecodingKey,
}

impl Interceptor for AuthInterceptor {
    fn call(&mut self, mut request: Request<()>) -> Result<Request<()>, Status> {
        // ✅ Step 1: 从 metadata 提取 Bearer token
        let metadata = request.metadata();
        let auth_header = metadata
            .get("authorization")
            .ok_or(Status::unauthenticated("Missing auth token"))?
            .to_str()
            .map_err(|_| Status::unauthenticated("Invalid token format"))?;

        if !auth_header.starts_with("Bearer ") {
            return Err(Status::unauthenticated("Invalid auth scheme"));
        }

        let token = &auth_header[7..];

        // ✅ Step 2: 验证 token (可以是 JWT 或 service token)
        let claims = decode::<Claims>(
            token,
            &self.jwt_secret,
            &Validation::default(),
        )
        .map_err(|e| {
            tracing::warn!("JWT validation failed: {}", e);
            Status::unauthenticated("Invalid token")
        })?;

        // ✅ Step 3: 将 claims 注入到 request extensions
        request.extensions_mut().insert(claims.claims);

        Ok(request)
    }
}

// 在每个 gRPC server 启动时添加
#[tokio::main]
async fn main() -> Result<()> {
    let jwt_secret = load_jwt_secret()?;

    let content_impl = ContentServiceImpl::new(...);

    // ✅ 添加认证拦截器
    let server = Server::builder()
        .add_service(
            ContentServiceServer::with_interceptor(
                content_impl,
                AuthInterceptor {
                    jwt_secret: DecodingKey::from_secret(jwt_secret.as_bytes()),
                },
            )
        )
        .serve(addr)
        .await?;

    Ok(())
}
```

**GraphQL Gateway 中传播 JWT**:

```rust
// graphql-gateway/src/clients/content_client.rs

pub async fn create_post(
    &self,
    user_id: Uuid,
    caption: &str,
    image_key: &str,
    jwt_token: &str,  // ✅ 从 GraphQL context 中获取
) -> Result<Post> {
    let mut request = tonic::Request::new(CreatePostRequest {
        creator_id: user_id.to_string(),
        caption: caption.to_string(),
        image_key: image_key.to_string(),
    });

    // ✅ 将 JWT 添加到 metadata
    request.metadata_mut().insert(
        "authorization",
        format!("Bearer {}", jwt_token).parse().unwrap(),
    );

    let response = self.client.create_post(request).await?;
    Ok(response.into_inner().post.unwrap())
}
```

**工作量估算**: 8-10 小时

---

### **[P1] GraphQL 速率限制不足**

**位置**: `backend/graphql-gateway/src/middleware/rate_limit.rs`

**当前实现**:
- 只有 100 req/s 的全局限制
- 没有按用户限制
- 没有按 IP 限制
- 没有按操作类型限制

**修复方案**:

```rust
// middleware/rate_limit.rs (增强版)

use dashmap::DashMap;
use std::net::IpAddr;
use uuid::Uuid;

pub struct RateLimitConfig {
    global_rps: u32,           // 全局限制
    per_user_rps: u32,         // 按用户限制
    per_ip_rps: u32,           // 按 IP 限制
    mutation_per_minute: u32,  // 写操作限制
}

pub struct RateLimitMiddleware {
    config: RateLimitConfig,
    global: TokenBucket,
    per_user: DashMap<Uuid, TokenBucket>,
    per_ip: DashMap<IpAddr, TokenBucket>,
    mutation_buckets: DashMap<Uuid, TokenBucket>,
}

impl RateLimitMiddleware {
    pub fn new(config: RateLimitConfig) -> Self {
        Self {
            global: TokenBucket::new(config.global_rps, 1),
            per_user: DashMap::new(),
            per_ip: DashMap::new(),
            mutation_buckets: DashMap::new(),
            config,
        }
    }

    pub async fn check(
        &self,
        user_id: Option<Uuid>,
        ip: IpAddr,
        is_mutation: bool,
    ) -> Result<()> {
        // ✅ 全局限制
        if !self.global.take_token() {
            return Err(AppError::RateLimitExceeded(
                "Global rate limit exceeded".to_string()
            ));
        }

        // ✅ 用户级限制
        if let Some(uid) = user_id {
            let user_bucket = self.per_user
                .entry(uid)
                .or_insert_with(|| TokenBucket::new(self.config.per_user_rps, 1));

            if !user_bucket.take_token() {
                return Err(AppError::RateLimitExceeded(
                    "User rate limit exceeded".to_string()
                ));
            }

            // ✅ Mutation 特殊限制
            if is_mutation {
                let mutation_bucket = self.mutation_buckets
                    .entry(uid)
                    .or_insert_with(|| TokenBucket::new(self.config.mutation_per_minute, 60));

                if !mutation_bucket.take_token() {
                    return Err(AppError::RateLimitExceeded(
                        "Too many mutations. Please slow down.".to_string()
                    ));
                }
            }
        }

        // ✅ IP 级限制
        let ip_bucket = self.per_ip
            .entry(ip)
            .or_insert_with(|| TokenBucket::new(self.config.per_ip_rps, 1));

        if !ip_bucket.take_token() {
            return Err(AppError::RateLimitExceeded(
                "IP rate limit exceeded".to_string()
            ));
        }

        Ok(())
    }
}

// Token Bucket 实现
struct TokenBucket {
    capacity: u32,
    tokens: std::sync::atomic::AtomicU32,
    refill_rate: u32,
    last_refill: std::sync::Mutex<std::time::Instant>,
}

impl TokenBucket {
    fn new(capacity: u32, refill_interval_secs: u32) -> Self {
        Self {
            capacity,
            tokens: std::sync::atomic::AtomicU32::new(capacity),
            refill_rate: capacity / refill_interval_secs,
            last_refill: std::sync::Mutex::new(std::time::Instant::now()),
        }
    }

    fn take_token(&self) -> bool {
        // Refill tokens
        {
            let mut last_refill = self.last_refill.lock().unwrap();
            let now = std::time::Instant::now();
            let elapsed = now.duration_since(*last_refill).as_secs() as u32;

            if elapsed > 0 {
                let refill_amount = (elapsed * self.refill_rate).min(self.capacity);
                self.tokens.fetch_add(refill_amount, std::sync::atomic::Ordering::SeqCst);
                *last_refill = now;
            }
        }

        // Take token
        let current = self.tokens.load(std::sync::atomic::Ordering::SeqCst);
        if current > 0 {
            self.tokens.fetch_sub(1, std::sync::atomic::Ordering::SeqCst);
            true
        } else {
            false
        }
    }
}
```

**工作量估算**: 4-6 小时

---

## 总结矩阵 (Summary Matrix)

| 功能领域 | 实现状态 | 品味评分 | 关键问题 | 优先级 | 工作量 |
|---------|---------|---------|---------|--------|--------|
| **用户注册** | ✅ 核心完成 | 🟢 8/10 | Email 验证缺失 | **P0** | 8-12h |
| **登录/登出** | ⚠️ 部分实现 | 🟡 6/10 | 无 logout/刷新轮换 | **P0** | 10-14h |
| **帖子管理** | ✅ 完整实现 | 🟢 10/10 | 权限检查,输入验证 | **P1** | 7h |
| **消息 E2EE** | ⚠️ Proto 定义 | 🟢 9/10 | Handler 未实现 | **P0** | 16-20h |
| **Feed/关系** | ✅ 核心完成 | 🟢 9/10 | 隐私账户权限 | **P0** | 12-16h |
| **服务间安全** | ❌ 缺失 | 🔴 3/10 | 无 mTLS/无认证 | **P0** | 20-26h |
| **速率限制** | ⚠️ 基础实现 | 🟡 5/10 | 缺少多维度限制 | **P1** | 4-6h |

**总计工作量**: **77-101 小时** (约 10-13 个工作日)

---

## iOS 应用上线前的行动清单 (Action Checklist)

### **P0 (BLOCKER - 必须立即修复)**

- [ ] **P0-1**: 实现 Email 验证流程 (8-12h)
  - [ ] 后端验证端点
  - [ ] 邮件服务集成
  - [ ] iOS Deep Link 处理
  - [ ] 登录时检查验证状态

- [ ] **P0-2**: 添加 Logout 端点 + Token 撤销 (4-6h)
  - [ ] Redis Token Revocation List
  - [ ] Logout RPC 实现
  - [ ] JWT 验证时检查撤销列表

- [ ] **P0-3**: 实现 Refresh Token 轮换 (6-8h)
  - [ ] 更新 Proto 定义
  - [ ] 实现轮换逻辑
  - [ ] iOS Token 管理

- [ ] **P0-4**: 完成 E2EE 消息 Handler (16-20h)
  - [ ] StoreDevicePublicKey 实现
  - [ ] GetPeerPublicKey 实现
  - [ ] CompleteKeyExchange 实现
  - [ ] 数据库迁移
  - [ ] iOS E2EE 集成

- [ ] **P0-5**: 修复 Follow 权限检查 (8-10h)
  - [ ] 阻止列表检查
  - [ ] 私密账户处理
  - [ ] Follow Request 通知
  - [ ] iOS Follow Request UI

- [ ] **P0-6**: 部署 gRPC mTLS (12-16h)
  - [ ] 设置 cert-manager
  - [ ] 实现 mTLS 客户端/服务器
  - [ ] 部署到所有服务
  - [ ] 测试

- [ ] **P0-7**: 实现 gRPC 服务认证 (8-10h)
  - [ ] AuthInterceptor 实现
  - [ ] 所有服务启用拦截器
  - [ ] JWT 传播

**P0 总计**: 62-82 小时 (约 8-11 个工作日)

---

### **P1 (第一个迭代 - 强烈建议修复)**

- [ ] **P1-1**: 登录速率限制 (4h)
  - [ ] IP 级别限制
  - [ ] 账户级别限制

- [ ] **P1-2**: 帖子内容验证 (3h)
  - [ ] 输入验证 (validator)
  - [ ] XSS 防护 (ammonia)

- [ ] **P1-3**: 帖子所有权检查 (4h)
  - [ ] 删除/更新前验证所有者

- [ ] **P1-4**: 消息内容验证 (2h)
  - [ ] Proto 验证规则
  - [ ] Handler 验证

- [ ] **P1-5**: Feed 缓存预热 (4-6h)
  - [ ] WarmupFeedCache RPC
  - [ ] 登录时调用

- [ ] **P1-6**: GraphQL 多维度速率限制 (4-6h)
  - [ ] 按用户限制
  - [ ] 按 IP 限制
  - [ ] 按操作类型限制

**P1 总计**: 21-25 小时 (约 3 个工作日)

---

### **P2 (性能优化 - 可后续改进)**

- [ ] 实现 PgBouncer 连接池
- [ ] 添加 PostgreSQL 读副本
- [ ] WebSocket 连接管理优化
- [ ] 离线消息队列持久化策略
- [ ] Chaos Engineering 测试

---

## Linus 式最终评语

> **"这个架构的核心思想是正确的 - Transactional Outbox 消除了分布式系统中最常见的特殊情况,这是有品味的代码。但安全层的缺失会被攻击者在生产环境的第一天就利用。"**
>
> **"优先修复 P0 问题。没有 mTLS,这个系统在生产环境中就是裸奔。没有 Email 验证,垃圾账户会泛滥。没有 E2EE 实现,承诺的隐私保护就是谎言。"**
>
> **"修复这些问题后,这将是一个世界级的 Rust 微服务参考实现。但在那之前,这只是一个理论上很好的架构。"**

**推荐行动**:
1. ✅ 立即启动 P0 任务 (8-11 个工作日)
2. ✅ 完成 P1 任务 (3 个工作日)
3. ✅ 进行全面的安全审计
4. ✅ 执行负载测试 (K6)
5. ✅ 软上线 (1% → 10% → 50% → 100%)

**预计生产就绪时间**: 2-3 周

---

**May the Force be with you.**
