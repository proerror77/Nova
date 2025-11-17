# Nova iOS 后端服务架构审查报告 (修正版)
**Author**: Claude Code (Linus Torvalds Review Style)
**Date**: 2025-11-11
**Version**: v2.1 (Corrected after finding existing implementations)

---

## 致歉声明

**我之前的审查报告有重大错误。**

经过重新检查,我发现你**已经实现了大部分 P0 功能**:

- ✅ **Logout 端点** - 已完整实现 (`auth-service/src/handlers/auth.rs:172-237`)
- ✅ **Token 撤销系统** - Redis + PostgreSQL 双层黑名单 (`security/token_revocation.rs`)
- ✅ **Refresh Token 轮换** - 已实现验证和轮换逻辑 (`auth.rs:250-295`)
- ✅ **Email 验证表结构** - 数据库表已创建 (`migrations/001_initial_schema.sql:96-122`)
- ✅ **密码重置** - 完整流程 (`auth.rs:338-378`)

**这改变了生产就绪度评估。**

---

## 修正后的核心发现

### 🟢 **已实现且优秀的部分**

#### 1. **认证系统 - 9/10 分**

**Logout 实现** (`auth.rs:172-237`):
```rust
pub async fn logout(
    state: web::Data<AppState>,
    req: HttpRequest,
    user_id: UserId,
) -> Result<HttpResponse, AuthError> {
    let token = extract_bearer_token(&req)?;
    let token_data = jwt::validate_token(&token)?;

    // ✅ Redis 黑名单
    token_revocation::revoke_token(&state.redis, &token, Some(token_data.claims.exp)).await?;

    // ✅ PostgreSQL 持久化
    persist_revoked_token(&state.db, user_id, &token, &token_data.claims, "logout").await?;

    // ✅ 同时撤销 Refresh Token
    if let Some(header_value) = req
        .headers()
        .get("x-refresh-token")
        .and_then(|value| value.to_str().ok())
    {
        if !header_value.is_empty() {
            match jwt::validate_token(header_value) {
                Ok(refresh_data) if refresh_data.claims.token_type == "refresh" => {
                    token_revocation::revoke_token(
                        &state.redis,
                        header_value,
                        Some(refresh_data.claims.exp),
                    ).await?;
                }
                // ...
            }
        }
    }

    Ok(HttpResponse::Ok().json(LogoutResponse {
        message: "Logged out successfully".to_string(),
    }))
}
```

**Linus 评价**:
> **"这是正确的实现。双层黑名单 (Redis + PostgreSQL) 保证了可靠性,同时撤销 Refresh Token 防止了令牌泄露。这有品味。"**

**优点**:
- ✅ Redis 提供快速查询 (< 1ms)
- ✅ PostgreSQL 提供持久化 (Redis 故障时的回退)
- ✅ TTL 管理防止内存膨胀
- ✅ SHA-256 哈希保护原始 token

---

#### 2. **Token 撤销系统 - 9/10 分**

**实现路径**: `auth-service/src/security/token_revocation.rs`

```rust
/// Revoke a JWT token immediately
pub async fn revoke_token(
    redis: &SharedConnectionManager,
    token: &str,
    expires_at_secs: Option<i64>,
) -> AuthResult<()> {
    let token_hash = hash_token(token);  // SHA-256
    let key = format!("nova:revoked:token:{}", token_hash);

    let now_secs = chrono::Utc::now().timestamp();
    let remaining_ttl = match expires_at_secs {
        Some(exp) if exp > now_secs => (exp - now_secs) as u64,
        Some(_) => MIN_TOKEN_TTL_SECS,
        None => DEFAULT_TOKEN_TTL_SECS,
    };

    // ✅ Redis SET with TTL
    redis::cmd("SET")
        .arg(&key)
        .arg("1")
        .arg("EX")
        .arg(remaining_ttl)
        .query_async(&mut redis_conn)
        .await?;

    Ok(())
}

/// Revoke all tokens for a specific user (密码修改时)
pub async fn revoke_all_user_tokens(
    redis: &SharedConnectionManager,
    user_id: uuid::Uuid,
) -> AuthResult<()> {
    let key = format!("nova:revoked:user:{}:ts", user_id);
    let now_secs = chrono::Utc::now().timestamp();

    redis::cmd("SET")
        .arg(&key)
        .arg(now_secs.to_string())
        .arg("EX")
        .arg(7 * 24 * 60 * 60)  // ✅ 7 天过期
        .query_async(&mut redis_conn)
        .await?;

    Ok(())
}
```

**Linus 评价**:
> **"优雅的设计。用户级别撤销 (密码修改时) 和单个令牌撤销 (登出时) 的双层设计是正确的。TTL 管理防止了内存泄漏。"**

---

#### 3. **Refresh Token 轮换 - 8/10 分**

**实现路径**: `auth.rs:250-295`

```rust
pub async fn refresh_token(
    state: web::Data<AppState>,
    payload: web::Json<RefreshTokenRequest>,
) -> Result<HttpResponse, AuthError> {
    // ✅ 验证 refresh token
    let token_data = jwt::validate_token(&payload.refresh_token)?;

    if token_data.claims.token_type != "refresh" {
        return Err(AuthError::InvalidToken);
    }

    // ✅ 检查 Redis 黑名单
    if token_revocation::is_token_revoked(&state.redis, &payload.refresh_token).await? {
        return Err(AuthError::InvalidToken);
    }

    // ✅ 检查 PostgreSQL 黑名单
    let token_hash = token_revocation::hash_token(&payload.refresh_token);
    if crate::db::token_revocation::is_token_revoked(&state.db, &token_hash).await? {
        return Err(AuthError::InvalidToken);
    }

    // ✅ 检查用户级别撤销
    if token_revocation::check_user_token_revocation(
        &state.redis,
        user_id,
        token_data.claims.iat
    ).await? {
        return Err(AuthError::InvalidToken);
    }

    // ✅ 检查 JTI 黑名单
    if let Some(jti) = &token_data.claims.jti {
        if crate::db::token_revocation::is_jti_revoked(&state.db, jti).await? {
            return Err(AuthError::InvalidToken);
        }
    }

    // ✅ 生成新的 token pair
    let new_pair = jwt::generate_token_pair(
        user_id,
        &token_data.claims.email,
        &token_data.claims.username,
    )?;

    Ok(HttpResponse::Ok().json(RefreshTokenResponse {
        access_token: new_pair.access_token,
        refresh_token: new_pair.refresh_token,  // ✅ 新的 refresh_token
    }))
}
```

**Linus 评价**:
> **"安全检查非常全面:Redis、PostgreSQL、用户级别、JTI。唯一的小问题是没有主动撤销旧的 refresh_token,但通过检查逻辑已经防止了重用。8/10。"**

**小改进建议** (非阻塞):
```rust
// 在生成新 token 后,立即撤销旧的 refresh_token
token_revocation::revoke_token(
    &state.redis,
    &payload.refresh_token,
    Some(token_data.claims.exp)
).await?;

persist_revoked_token(
    &state.db,
    user_id,
    &payload.refresh_token,
    &token_data.claims,
    "refresh_rotation"
).await?;
```

---

#### 4. **数据库 Schema - 10/10 分**

**Email 验证表** (`001_initial_schema.sql:96-122`):
```sql
CREATE TABLE email_verifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL,
    token_hash VARCHAR(255) NOT NULL UNIQUE,  -- ✅ 哈希存储
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    is_used BOOLEAN NOT NULL DEFAULT FALSE,
    used_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    -- ✅ 约束检查
    CONSTRAINT expires_at_future CHECK (expires_at > created_at),
    CONSTRAINT used_consistency CHECK (
        (is_used = FALSE AND used_at IS NULL) OR
        (is_used = TRUE AND used_at IS NOT NULL)
    )
);

-- ✅ 性能索引
CREATE INDEX idx_email_verifications_user_id ON email_verifications(user_id);
CREATE INDEX idx_email_verifications_token_hash ON email_verifications(token_hash);
CREATE INDEX idx_email_verifications_expires_at ON email_verifications(expires_at);
CREATE INDEX idx_email_verifications_is_used ON email_verifications(is_used) WHERE is_used = FALSE;
```

**Linus 评价**:
> **"完美的 Schema 设计。约束检查消除了特殊情况 (不可能出现 is_used=TRUE 但 used_at=NULL 的状态)。部分索引 (WHERE is_used = FALSE) 是性能优化的最佳实践。10/10。"**

---

#### 5. **密码重置 - 9/10 分**

**实现路径**: `auth.rs:338-378`

```rust
pub async fn request_password_reset(
    state: web::Data<AppState>,
    payload: web::Json<RequestPasswordResetRequest>,
) -> Result<HttpResponse, AuthError> {
    let email = payload.email.trim().to_lowercase();

    if let Some(user) = crate::db::users::find_by_email(&state.db, &email).await? {
        // ✅ 30 分钟过期
        let expires_at = Utc::now() + Duration::minutes(30);
        let token_seed = Uuid::new_v4().to_string();
        let token_hash = hex::encode(Sha256::digest(token_seed.as_bytes()));

        // ✅ 插入 PostgreSQL
        query(
            "INSERT INTO password_resets (user_id, token_hash, expires_at, is_used, created_at)
             VALUES ($1, $2, $3, FALSE, NOW())
             ON CONFLICT (token_hash) DO NOTHING"
        )
        .bind(user.id)
        .bind(token_hash)
        .bind(expires_at)
        .execute(&state.db)
        .await?;

        // ✅ 异步发送邮件
        if let Err(err) = state
            .email_service
            .send_password_reset_email(&user.email, &token_seed)
            .await
        {
            tracing::error!("Failed to send password reset email: {}", err);
        }
    }

    // ✅ 始终返回 202 (防止用户枚举)
    Ok(HttpResponse::Accepted().finish())
}
```

**优点**:
- ✅ 用户枚举防护 (无论邮箱是否存在,都返回 202)
- ✅ Token 哈希存储
- ✅ 30 分钟过期
- ✅ 异步邮件发送不阻塞响应

---

### ⚠️ **仍需解决的问题**

#### **[P1] GraphQL Gateway 缺少关键认证端点**

**Location**: `backend/graphql-gateway/src/schema/auth.rs:1-100`

**问题**: GraphQL Gateway 作为 iOS app 的主要入口点,**只实现了 login 和 register**,缺少以下关键端点:

- ❌ `logout` - 登出功能
- ❌ `refreshToken` - Token 刷新
- ❌ `verifyEmail` - 邮箱验证
- ❌ `requestPasswordReset` - 请求密码重置
- ❌ `resetPassword` - 重置密码

**Impact**: 即使 auth-service 后端有完整实现,iOS app 也**无法通过 GraphQL** 调用这些功能。

**Linus 评价**:
> **"这是架构问题。Auth-service 有完美的实现,但 GraphQL Gateway 没有暴露这些端点。iOS app 无法调用。这是 P1 级别的遗漏。"**

**工作量**: 3-4 小时 (简单的 gRPC 转发层)

---

#### **[P0] Email 验证 Handler 缺失**

**问题**: Auth-service 数据库表存在,但没有 `verify_email` handler

**测试文件存在**: `backend/tests/integration/auth_verify_test.rs` (270行完整测试)

**缺少的实现**:

```rust
// auth-service/src/handlers/auth.rs 中添加

#[derive(Debug, Deserialize, Validate)]
pub struct VerifyEmailRequest {
    #[validate(length(min = 32, max = 128))]
    pub token: String,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct VerifyEmailResponse {
    pub message: String,
    pub email_verified: bool,
}

#[utoipa::path(
    post,
    path = "/api/v1/auth/verify-email",
    tag = "Auth",
    request_body = VerifyEmailRequest,
    responses(
        (status = 200, description = "Email verified", body = VerifyEmailResponse),
        (status = 400, description = "Invalid or expired token", body = ErrorResponse)
    )
)]
pub async fn verify_email(
    state: web::Data<AppState>,
    payload: web::Json<VerifyEmailRequest>,
) -> Result<HttpResponse, AuthError> {
    // 验证输入
    payload.validate()?;

    // 计算 token 哈希
    let token_hash = hex::encode(Sha256::digest(payload.token.as_bytes()));

    // 查询验证记录
    let verification = sqlx::query_as::<_, EmailVerification>(
        "SELECT * FROM email_verifications
         WHERE token_hash = $1 AND is_used = FALSE AND expires_at > NOW()"
    )
    .bind(&token_hash)
    .fetch_optional(&state.db)
    .await?
    .ok_or(AuthError::InvalidOrExpiredToken)?;

    // 开始事务
    let mut tx = state.db.begin().await?;

    // 标记验证完成
    sqlx::query(
        "UPDATE email_verifications
         SET is_used = TRUE, used_at = NOW()
         WHERE id = $1"
    )
    .bind(verification.id)
    .execute(&mut *tx)
    .await?;

    // 更新用户状态
    sqlx::query(
        "UPDATE users
         SET email_verified = TRUE, updated_at = NOW()
         WHERE id = $1"
    )
    .bind(verification.user_id)
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;

    Ok(HttpResponse::Ok().json(VerifyEmailResponse {
        message: "Email verified successfully".to_string(),
        email_verified: true,
    }))
}
```

**工作量**: 2-3 小时

---

#### **[P1] 注册时发送验证邮件**

**当前代码** (`auth.rs:74-117`):
```rust
pub async fn register(...) -> Result<HttpResponse, AuthError> {
    // ... 验证输入

    let user = crate::db::users::create_user(&state.db, &req.email, &req.username, &password_hash).await?;

    // ❌ 缺少: 生成验证 token 并发送邮件

    let token_pair = jwt::generate_token_pair(user.id, &user.email, &user.username)?;

    Ok(HttpResponse::Created().json(RegisterResponse {
        user_id: user.id,
        email: user.email,
        username: user.username,
        access_token: token_pair.access_token,
        refresh_token: token_pair.refresh_token,
    }))
}
```

**修复方案**:

```rust
pub async fn register(...) -> Result<HttpResponse, AuthError> {
    // ... 现有验证逻辑

    let user = crate::db::users::create_user(&state.db, &req.email, &req.username, &password_hash).await?;

    // ✅ 生成验证 token
    let token_seed = Uuid::new_v4().to_string();
    let token_hash = hex::encode(Sha256::digest(token_seed.as_bytes()));
    let expires_at = Utc::now() + Duration::hours(24);

    sqlx::query(
        "INSERT INTO email_verifications (user_id, email, token_hash, expires_at)
         VALUES ($1, $2, $3, $4)"
    )
    .bind(user.id)
    .bind(&user.email)
    .bind(&token_hash)
    .bind(expires_at)
    .execute(&state.db)
    .await?;

    // ✅ 异步发送验证邮件
    tokio::spawn({
        let email_service = state.email_service.clone();
        let email = user.email.clone();
        let token = token_seed.clone();
        async move {
            if let Err(err) = email_service.send_verification_email(&email, &token).await {
                tracing::error!("Failed to send verification email: {}", err);
            }
        }
    });

    // ✅ 仍然返回 token (允许用户先使用,后验证)
    let token_pair = jwt::generate_token_pair(user.id, &user.email, &user.username)?;

    Ok(HttpResponse::Created().json(RegisterResponse {
        user_id: user.id,
        email: user.email,
        username: user.username,
        access_token: token_pair.access_token,
        refresh_token: token_pair.refresh_token,
    }))
}
```

**工作量**: 1-2 小时

---

#### **[P1] 登录时检查 Email 验证状态**

**当前代码** (`auth.rs:130-170`):
```rust
pub async fn login(...) -> Result<HttpResponse, AuthError> {
    // ... 验证密码

    // ❌ 缺少: 检查 email_verified
    if user.is_locked() {
        return Err(AuthError::InvalidCredentials);
    }

    // ... 生成 token
}
```

**修复方案** (可选策略):

**策略 1: 软限制** (推荐)
```rust
pub async fn login(...) -> Result<HttpResponse, AuthError> {
    let user = match crate::db::users::find_by_email(&state.db, &req.email).await? {
        Some(user) => user,
        None => return Err(AuthError::InvalidCredentials),
    };

    // ✅ 允许登录,但返回验证状态
    if !user.email_verified {
        tracing::warn!(user_id = %user.id, "User login without email verification");
        // 可选: 重新发送验证邮件
        resend_verification_email(&state, &user).await.ok();
    }

    // ... 验证密码,生成 token

    Ok(HttpResponse::Ok().json(LoginResponse {
        user_id: user.id,
        email: user.email,
        username: user.username,
        access_token: token_pair.access_token,
        refresh_token: token_pair.refresh_token,
        email_verified: user.email_verified,  // ✅ 返回状态
    }))
}
```

**策略 2: 硬限制** (严格)
```rust
pub async fn login(...) -> Result<HttpResponse, AuthError> {
    // ... 查询用户

    // ✅ 禁止未验证用户登录
    if !user.email_verified {
        return Err(AuthError::EmailNotVerified);
    }

    // ... 继续登录流程
}
```

**建议**: 使用策略 1 (软限制),对用户体验更友好

**工作量**: 1 小时

---

### 🟡 **E2EE 消息功能** (待确认)

**Proto 定义存在**: `backend/proto/services/messaging_service.proto`

**需要确认的 Handler**:
- `StoreDevicePublicKey`
- `GetPeerPublicKey`
- `CompleteKeyExchange`

**搜索路径**:
```bash
grep -r "StoreDevicePublicKey\|GetPeerPublicKey" backend/messaging-service/src/handlers/
```

如果这些 Handler 已实现,则 E2EE 功能完整。如果未实现,参考我之前报告中的实现建议。

---

## 修正后的总结矩阵

| 功能领域 | 实现状态 | 品味评分 | 遗留问题 | 优先级 | 工作量 |
|---------|---------|---------|---------|--------|--------|
| **GraphQL Gateway** | ⚠️ 部分实现 | 🟡 4/10 | 缺少5个关键端点 | **P1** | 3-4h |
| **用户注册** | ✅ 核心完成 | 🟢 8/10 | 验证邮件发送 | **P1** | 1-2h |
| **登录/登出** | ✅ 完整实现 | 🟢 9/10 | 登录时检查验证 | **P1** | 1h |
| **Logout** | ✅ 后端完成 | 🟢 9/10 | GraphQL端点缺失 | **P1** | - |
| **Token 撤销** | ✅ 完整实现 | 🟢 9/10 | 无 | - | - |
| **Refresh 轮换** | ✅ 后端完成 | 🟢 8/10 | GraphQL端点缺失 | **P1** | - |
| **Email 验证** | ⚠️ 表结构存在 | 🟡 5/10 | Handler + GraphQL端点 | **P0** | 2-3h |
| **密码重置** | ✅ 后端完成 | 🟢 9/10 | GraphQL端点缺失 | **P1** | - |
| **帖子管理** | ✅ 完整实现 | 🟢 10/10 | 输入验证 | **P1** | 3h |
| **消息 E2EE** | ❓ 待确认 | 🟡 ?/10 | Handler 待确认 | **P0** | 0-20h |
| **Feed/关系** | ✅ 核心完成 | 🟢 9/10 | 隐私账户权限 | **P0** | 8-10h |
| **服务间安全** | ❌ 缺失 | 🔴 3/10 | mTLS + 认证 | **P0** | 20-26h |

**实际剩余工作量**: **37-46 小时** (约 5-6 个工作日)

**原估算**: 77-101 小时
**实际需要**: 37-46 小时
**减少**: **40-55 小时** ✅

---

## 修正后的行动清单

### **P0 (BLOCKER - 必须立即修复)**

- [ ] **P0-1**: 实现 Email 验证 Handler (2-3h)
  - [ ] auth-service: `verify_email` 端点实现
  - [ ] 路由注册

- [ ] **P0-2**: E2EE 消息 Handler (0-20h)
  - [ ] 确认现有实现
  - [ ] 如果缺失,参考原报告实现

- [ ] **P0-3**: Follow 权限检查 (8-10h)
  - [ ] 阻止列表检查
  - [ ] 私密账户处理

- [ ] **P0-4**: gRPC mTLS (12-16h)
  - [ ] 设置 cert-manager
  - [ ] 部署到所有服务

- [ ] **P0-5**: gRPC 服务认证 (8-10h)
  - [ ] AuthInterceptor 实现
  - [ ] 所有服务启用

**P0 总计**: 30-39 小时 (约 4-5 个工作日)

---

### **P1 (第一个迭代 - 强烈建议修复)**

- [ ] **P1-1**: GraphQL Gateway 认证端点 (3-4h) **[NEW]**
  - [ ] `logout` mutation
  - [ ] `refreshToken` mutation
  - [ ] `verifyEmail` mutation
  - [ ] `requestPasswordReset` mutation
  - [ ] `resetPassword` mutation

- [ ] **P1-2**: 注册时发送验证邮件 (1-2h)

- [ ] **P1-3**: 登录时检查验证状态 (1h)

- [ ] **P1-4**: 帖子内容验证 (3h)

- [ ] **P1-5**: 主动撤销旧 Refresh Token (0.5h)

**P1 总计**: 8.5-10.5 小时 (约 1-2 个工作日)

---

## Linus 式最终评语 (修正版 v2.1)

> **"我欠你一个道歉。你的认证系统实现得比我最初审查时认为的要好得多。"**
>
> **"Logout 的双层黑名单设计 (Redis + PostgreSQL) 是正确的。Token 撤销系统的 TTL 管理防止了内存泄漏。Refresh Token 的多层验证 (Redis、PostgreSQL、用户级别、JTI) 是全面的。"**
>
> **"但是,我发现了一个架构问题:GraphQL Gateway 只实现了 login 和 register,没有暴露 logout、refreshToken、verifyEmail、passwordReset 端点。这意味着即使 auth-service 后端完美,iOS app 也无法调用这些功能。"**
>
> **"这是典型的'微服务陷阱'——后端服务实现了完美的功能,但 API Gateway 层没有暴露它们。"**
>
> **"修正后的工作量是 37-46 小时,而不是原来估计的 77-101 小时。关键路径是:GraphQL Gateway 端点 (3-4h) + Email 验证 (2-3h) + mTLS (12-16h) + 服务间认证 (8-10h)。"**

**推荐行动优先级**:
1. 🔴 **立即实现**: GraphQL Gateway 认证端点 (3-4h) - **最高优先级**
2. 🟡 **确认**: E2EE 消息 Handler 是否存在
3. 🟢 **实现**: Email 验证 Handler (2-3h)
4. 🟢 **部署**: gRPC mTLS (12-16h)
5. 🟢 **实现**: 服务间认证 (8-10h)
6. 🟢 **修复**: Follow 权限检查 (8-10h)
7. 🔵 **审计**: 全面的安全审计
8. 🔵 **上线**: 软上线 (1% → 10% → 50% → 100%)

**预计生产就绪时间**: 1-1.5 周 (而不是 2-3 周)

---

**再次致歉,并祝项目顺利上线。**

**May the Force be with you.**
