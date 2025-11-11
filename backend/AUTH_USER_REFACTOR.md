# Auth/User Service 职责重构计划

**Date**: 2025-11-11
**Status**: Implementation Ready
**Priority**: P0 - Critical

---

## 现状问题分析

### 当前架构缺陷
```
auth-service: {
  ❌ 管理用户资料
  ❌ 处理权限配置
  ✅ JWT token 管理
  ❌ 存储用户数据
}

user-service: {
  ❌ 认证逻辑
  ❌ 重复的权限检查
  ✅ 用户资料管理
  ❌ session 管理混乱
}
```

**核心问题**: 两个服务职责交叉，违反单一职责原则

---

## 目标架构

### 1. Identity Service (认证域)
**原则**: "Token 的唯一真相源"

```rust
// Identity Service 职责
pub struct IdentityService {
    // 核心职责
    token_management: TokenManager,     // JWT 发放、验证、撤销
    session_store: SessionStore,        // Session 管理
    refresh_tokens: RefreshTokenStore,  // Refresh token 管理

    // 不包含
    // ❌ 用户资料
    // ❌ 角色权限配置
    // ❌ 用户偏好设置
}
```

**API 定义**:
```proto
service IdentityService {
    // Token 操作
    rpc IssueToken(IssueTokenRequest) returns (TokenResponse);
    rpc ValidateToken(ValidateTokenRequest) returns (ValidationResponse);
    rpc RefreshToken(RefreshTokenRequest) returns (TokenResponse);
    rpc RevokeToken(RevokeTokenRequest) returns (RevokeResponse);

    // Session 管理
    rpc CreateSession(CreateSessionRequest) returns (SessionResponse);
    rpc GetSession(GetSessionRequest) returns (SessionResponse);
    rpc EndSession(EndSessionRequest) returns (EndResponse);

    // 多因素认证
    rpc InitiateMFA(MFARequest) returns (MFAResponse);
    rpc VerifyMFA(VerifyMFARequest) returns (MFAVerificationResponse);
}
```

### 2. User Service (用户域)
**原则**: "用户数据的唯一所有者"

```rust
// User Service 职责
pub struct UserService {
    // 核心职责
    user_profiles: UserProfileStore,    // 用户资料
    roles: RoleStore,                   // 角色定义
    permissions: PermissionStore,       // 权限配置
    user_preferences: PreferenceStore,  // 用户偏好

    // 不包含
    // ❌ Token 验证
    // ❌ Session 管理
    // ❌ 认证逻辑
}
```

**API 定义**:
```proto
service UserService {
    // 用户管理
    rpc CreateUser(CreateUserRequest) returns (UserResponse);
    rpc GetUser(GetUserRequest) returns (UserResponse);
    rpc UpdateUser(UpdateUserRequest) returns (UserResponse);
    rpc DeleteUser(DeleteUserRequest) returns (DeleteResponse);

    // 角色权限
    rpc AssignRole(AssignRoleRequest) returns (RoleResponse);
    rpc GetUserRoles(GetRolesRequest) returns (RolesResponse);
    rpc GetUserPermissions(GetPermissionsRequest) returns (PermissionsResponse);

    // 用户偏好
    rpc UpdatePreferences(UpdatePreferencesRequest) returns (PreferencesResponse);
    rpc GetPreferences(GetPreferencesRequest) returns (PreferencesResponse);
}
```

---

## 实施步骤

### Phase 1: 创建 Identity Service (Day 1-2)

#### 1.1 初始化项目结构
```bash
backend/
├── identity-service/
│   ├── Cargo.toml
│   ├── src/
│   │   ├── main.rs
│   │   ├── token/
│   │   │   ├── mod.rs
│   │   │   ├── jwt.rs
│   │   │   └── refresh.rs
│   │   ├── session/
│   │   │   ├── mod.rs
│   │   │   └── store.rs
│   │   └── grpc/
│   │       ├── mod.rs
│   │       └── handlers.rs
│   ├── proto/
│   │   └── identity.proto
│   └── migrations/
│       └── 001_init_identity.sql
```

#### 1.2 Token 管理实现
```rust
// src/token/jwt.rs
use jsonwebtoken::{encode, decode, Header, Algorithm, Validation, EncodingKey, DecodingKey};
use serde::{Serialize, Deserialize};
use chrono::{Utc, Duration};
use uuid::Uuid;

#[derive(Debug, Serialize, Deserialize)]
pub struct Claims {
    pub sub: Uuid,          // User ID
    pub iat: i64,           // Issued at
    pub exp: i64,           // Expiry
    pub jti: Uuid,          // JWT ID (for revocation)
    pub token_type: String, // "access" or "refresh"
}

pub struct JwtManager {
    encoding_key: EncodingKey,
    decoding_key: DecodingKey,
    algorithm: Algorithm,
    access_token_duration: Duration,
    refresh_token_duration: Duration,
}

impl JwtManager {
    pub async fn issue_tokens(&self, user_id: Uuid) -> Result<TokenPair, TokenError> {
        let now = Utc::now();

        // Access token (15 minutes)
        let access_claims = Claims {
            sub: user_id,
            iat: now.timestamp(),
            exp: (now + self.access_token_duration).timestamp(),
            jti: Uuid::new_v4(),
            token_type: "access".to_string(),
        };

        // Refresh token (7 days)
        let refresh_claims = Claims {
            sub: user_id,
            iat: now.timestamp(),
            exp: (now + self.refresh_token_duration).timestamp(),
            jti: Uuid::new_v4(),
            token_type: "refresh".to_string(),
        };

        // Store refresh token in database for revocation
        self.store_refresh_token(&refresh_claims).await?;

        Ok(TokenPair {
            access_token: encode(&Header::new(self.algorithm), &access_claims, &self.encoding_key)?,
            refresh_token: encode(&Header::new(self.algorithm), &refresh_claims, &self.encoding_key)?,
            expires_in: self.access_token_duration.num_seconds(),
        })
    }

    pub async fn validate_token(&self, token: &str) -> Result<Claims, TokenError> {
        // Check if token is revoked
        if self.is_revoked(token).await? {
            return Err(TokenError::Revoked);
        }

        let validation = Validation::new(self.algorithm);
        let token_data = decode::<Claims>(token, &self.decoding_key, &validation)?;

        Ok(token_data.claims)
    }

    pub async fn revoke_token(&self, jti: Uuid) -> Result<(), TokenError> {
        // Add to revocation list
        sqlx::query!(
            "INSERT INTO revoked_tokens (jti, revoked_at) VALUES ($1, $2)",
            jti,
            Utc::now()
        )
        .execute(&self.pool)
        .await?;

        Ok(())
    }
}
```

#### 1.3 Session 管理
```rust
// src/session/store.rs
use redis::aio::ConnectionManager;
use serde::{Serialize, Deserialize};
use uuid::Uuid;

#[derive(Serialize, Deserialize)]
pub struct Session {
    pub id: Uuid,
    pub user_id: Uuid,
    pub ip_address: String,
    pub user_agent: String,
    pub created_at: i64,
    pub last_activity: i64,
    pub expires_at: i64,
}

pub struct SessionStore {
    redis: ConnectionManager,
    ttl: Duration,
}

impl SessionStore {
    pub async fn create_session(&self, user_id: Uuid, metadata: SessionMetadata) -> Result<Session, SessionError> {
        let session = Session {
            id: Uuid::new_v4(),
            user_id,
            ip_address: metadata.ip_address,
            user_agent: metadata.user_agent,
            created_at: Utc::now().timestamp(),
            last_activity: Utc::now().timestamp(),
            expires_at: (Utc::now() + self.ttl).timestamp(),
        };

        let key = format!("session:{}", session.id);
        let value = serde_json::to_string(&session)?;

        self.redis
            .set_ex(&key, value, self.ttl.num_seconds() as usize)
            .await?;

        Ok(session)
    }

    pub async fn get_session(&self, session_id: Uuid) -> Result<Option<Session>, SessionError> {
        let key = format!("session:{}", session_id);
        let value: Option<String> = self.redis.get(&key).await?;

        match value {
            Some(json) => {
                let mut session: Session = serde_json::from_str(&json)?;

                // Update last activity
                session.last_activity = Utc::now().timestamp();
                let updated = serde_json::to_string(&session)?;
                self.redis.set_ex(&key, updated, self.ttl.num_seconds() as usize).await?;

                Ok(Some(session))
            },
            None => Ok(None),
        }
    }
}
```

### Phase 2: 重构 User Service (Day 3-4)

#### 2.1 移除认证逻辑
```rust
// BEFORE (user-service/src/auth.rs) - 删除这个文件
pub async fn authenticate_user(email: &str, password: &str) -> Result<User> {
    // ❌ 这不应该在 User Service 中
}

// AFTER - 仅保留用户数据管理
// user-service/src/users.rs
pub struct UserManager {
    pool: PgPool,
}

impl UserManager {
    pub async fn create_user(&self, req: CreateUserRequest) -> Result<User, UserError> {
        // 仅创建用户记录
        let user = sqlx::query_as!(
            User,
            r#"
            INSERT INTO users (id, email, username, full_name, created_at)
            VALUES ($1, $2, $3, $4, $5)
            RETURNING *
            "#,
            Uuid::new_v4(),
            req.email,
            req.username,
            req.full_name,
            Utc::now()
        )
        .fetch_one(&self.pool)
        .await?;

        // 发布事件
        self.event_bus.publish(Event::UserCreated {
            user_id: user.id,
            email: user.email.clone(),
        }).await?;

        Ok(user)
    }

    pub async fn get_user_with_roles(&self, user_id: Uuid) -> Result<UserWithRoles, UserError> {
        // 获取用户及其角色
        let user = self.get_user(user_id).await?;
        let roles = self.get_user_roles(user_id).await?;
        let permissions = self.get_permissions_for_roles(&roles).await?;

        Ok(UserWithRoles {
            user,
            roles,
            permissions,
        })
    }
}
```

#### 2.2 权限管理迁移
```rust
// user-service/src/permissions.rs
pub struct PermissionManager {
    pool: PgPool,
    cache: Cache,
}

impl PermissionManager {
    pub async fn check_permission(
        &self,
        user_id: Uuid,
        resource: &str,
        action: &str
    ) -> Result<bool, PermissionError> {
        // 从缓存或数据库获取权限
        let cache_key = format!("perms:{}:{}:{}", user_id, resource, action);

        if let Some(cached) = self.cache.get(&cache_key).await? {
            return Ok(cached);
        }

        let has_permission = sqlx::query_scalar!(
            r#"
            SELECT EXISTS(
                SELECT 1 FROM user_permissions up
                JOIN permissions p ON up.permission_id = p.id
                WHERE up.user_id = $1
                  AND p.resource = $2
                  AND p.action = $3
            ) as "has_permission!"
            "#,
            user_id,
            resource,
            action
        )
        .fetch_one(&self.pool)
        .await?;

        // 缓存结果
        self.cache.set(&cache_key, has_permission, Duration::minutes(5)).await?;

        Ok(has_permission)
    }
}
```

### Phase 3: 服务间集成 (Day 5)

#### 3.1 认证流程
```rust
// graphql-gateway/src/auth_flow.rs
pub async fn login(email: String, password: String) -> Result<LoginResponse> {
    // Step 1: 验证用户凭据 (调用 User Service)
    let user = user_client
        .verify_credentials(VerifyCredentialsRequest {
            email,
            password_hash: hash_password(&password),
        })
        .await?;

    // Step 2: 生成 Token (调用 Identity Service)
    let tokens = identity_client
        .issue_token(IssueTokenRequest {
            user_id: user.id,
            device_info: extract_device_info(),
        })
        .await?;

    // Step 3: 获取用户角色权限 (调用 User Service)
    let roles = user_client
        .get_user_roles(GetRolesRequest {
            user_id: user.id,
        })
        .await?;

    Ok(LoginResponse {
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token,
        user: UserInfo {
            id: user.id,
            email: user.email,
            roles: roles.into(),
        },
    })
}
```

#### 3.2 请求认证中间件
```rust
// common/src/middleware/auth.rs
pub struct AuthMiddleware {
    identity_client: IdentityServiceClient,
    user_client: UserServiceClient,
}

impl AuthMiddleware {
    pub async fn verify_request(&self, req: &Request) -> Result<AuthContext, AuthError> {
        // Extract token
        let token = extract_bearer_token(req)?;

        // Validate with Identity Service
        let validation = self.identity_client
            .validate_token(ValidateTokenRequest { token })
            .await?;

        // Get user permissions from User Service (cached)
        let permissions = self.user_client
            .get_user_permissions(GetPermissionsRequest {
                user_id: validation.user_id,
            })
            .await?;

        Ok(AuthContext {
            user_id: validation.user_id,
            permissions: permissions.into(),
            token_jti: validation.jti,
        })
    }
}
```

---

## 数据库迁移

### Identity Service Tables
```sql
-- identity-service/migrations/001_init_identity.sql
CREATE TABLE refresh_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    jti UUID NOT NULL UNIQUE,
    user_id UUID NOT NULL,
    token_hash VARCHAR(255) NOT NULL,
    device_id VARCHAR(100),
    ip_address INET,
    user_agent TEXT,
    issued_at TIMESTAMP WITH TIME ZONE NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    revoked_at TIMESTAMP WITH TIME ZONE,
    service_owner VARCHAR(50) DEFAULT 'identity-service' NOT NULL,
    CONSTRAINT owned_by_identity CHECK (service_owner = 'identity-service')
);

CREATE TABLE revoked_tokens (
    jti UUID PRIMARY KEY,
    revoked_at TIMESTAMP WITH TIME ZONE NOT NULL,
    reason VARCHAR(100),
    service_owner VARCHAR(50) DEFAULT 'identity-service' NOT NULL,
    CONSTRAINT owned_by_identity_revoked CHECK (service_owner = 'identity-service')
);

CREATE INDEX idx_refresh_tokens_user ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_expires ON refresh_tokens(expires_at);
CREATE INDEX idx_revoked_tokens_time ON revoked_tokens(revoked_at);
```

### User Service Tables
```sql
-- user-service/migrations/001_user_tables.sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL UNIQUE,
    username VARCHAR(100) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255),
    avatar_url TEXT,
    is_active BOOLEAN DEFAULT true,
    email_verified BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    service_owner VARCHAR(50) DEFAULT 'user-service' NOT NULL,
    CONSTRAINT owned_by_user CHECK (service_owner = 'user-service')
);

CREATE TABLE roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    is_system BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    service_owner VARCHAR(50) DEFAULT 'user-service' NOT NULL,
    CONSTRAINT owned_by_user_roles CHECK (service_owner = 'user-service')
);

CREATE TABLE permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    resource VARCHAR(100) NOT NULL,
    action VARCHAR(50) NOT NULL,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    service_owner VARCHAR(50) DEFAULT 'user-service' NOT NULL,
    UNIQUE(resource, action),
    CONSTRAINT owned_by_user_perms CHECK (service_owner = 'user-service')
);

CREATE TABLE user_roles (
    user_id UUID NOT NULL,
    role_id UUID NOT NULL REFERENCES roles(id),
    assigned_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    assigned_by UUID,
    service_owner VARCHAR(50) DEFAULT 'user-service' NOT NULL,
    PRIMARY KEY (user_id, role_id),
    CONSTRAINT owned_by_user_ur CHECK (service_owner = 'user-service')
);

CREATE TABLE role_permissions (
    role_id UUID NOT NULL REFERENCES roles(id),
    permission_id UUID NOT NULL REFERENCES permissions(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    service_owner VARCHAR(50) DEFAULT 'user-service' NOT NULL,
    PRIMARY KEY (role_id, permission_id),
    CONSTRAINT owned_by_user_rp CHECK (service_owner = 'user-service')
);
```

---

## 测试策略

### 单元测试
```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_token_generation() {
        let manager = JwtManager::new(test_config());
        let user_id = Uuid::new_v4();

        let tokens = manager.issue_tokens(user_id).await.unwrap();

        assert!(!tokens.access_token.is_empty());
        assert!(!tokens.refresh_token.is_empty());
        assert_eq!(tokens.expires_in, 900); // 15 minutes
    }

    #[tokio::test]
    async fn test_token_validation() {
        let manager = JwtManager::new(test_config());
        let user_id = Uuid::new_v4();

        let tokens = manager.issue_tokens(user_id).await.unwrap();
        let claims = manager.validate_token(&tokens.access_token).await.unwrap();

        assert_eq!(claims.sub, user_id);
        assert_eq!(claims.token_type, "access");
    }

    #[tokio::test]
    async fn test_permission_check() {
        let manager = PermissionManager::new(test_pool());
        let user_id = create_test_user().await;
        assign_test_role(user_id, "admin").await;

        let has_perm = manager
            .check_permission(user_id, "posts", "delete")
            .await
            .unwrap();

        assert!(has_perm);
    }
}
```

### 集成测试
```rust
#[tokio::test]
async fn test_full_auth_flow() {
    let identity_service = spawn_identity_service().await;
    let user_service = spawn_user_service().await;

    // Create user
    let user = user_service
        .create_user(CreateUserRequest {
            email: "test@example.com".to_string(),
            password: "password123".to_string(),
        })
        .await
        .unwrap();

    // Issue tokens
    let tokens = identity_service
        .issue_token(IssueTokenRequest {
            user_id: user.id,
        })
        .await
        .unwrap();

    // Validate token
    let validation = identity_service
        .validate_token(ValidateTokenRequest {
            token: tokens.access_token,
        })
        .await
        .unwrap();

    assert_eq!(validation.user_id, user.id);
    assert!(validation.is_valid);
}
```

---

## 回滚计划

如果重构出现问题：

1. **立即回滚**:
   ```bash
   # 切换到备份分支
   git checkout backup/pre-auth-refactor

   # 恢复数据库
   psql $DATABASE_URL < backups/auth_backup.sql
   ```

2. **部分回滚**:
   - 保留 Identity Service
   - 恢复 auth-service 原有功能
   - 通过 feature flag 控制流量

3. **数据恢复**:
   ```sql
   -- 恢复原表结构
   ALTER TABLE users DROP CONSTRAINT owned_by_user;
   -- 重新启用原有服务
   ```

---

## 监控指标

```yaml
metrics:
  - name: token_generation_rate
    type: counter
    labels: [token_type]

  - name: token_validation_latency
    type: histogram
    buckets: [0.001, 0.005, 0.01, 0.05, 0.1]

  - name: permission_check_cache_hit_rate
    type: gauge

  - name: auth_failures
    type: counter
    labels: [reason]

alerts:
  - name: high_token_failure_rate
    expr: rate(auth_failures[5m]) > 0.1
    severity: critical

  - name: slow_permission_checks
    expr: histogram_quantile(0.99, permission_check_latency) > 0.1
    severity: warning
```

---

## 成功标准

- [ ] Token 生成延迟 < 50ms (P99)
- [ ] Token 验证延迟 < 10ms (P99)
- [ ] 权限检查缓存命中率 > 95%
- [ ] 零认证相关的数据不一致
- [ ] 服务间调用减少 30%
- [ ] 代码复杂度降低 (圈复杂度 < 10)