# Nova V2 Service Consolidation Plan

**Generated**: 2025-11-11
**Purpose**: Consolidate overlapping functionality into V2 unified services
**Impact**: Reduce 16 services → 13 services, improve architecture clarity

---

## Executive Summary (Linus Style)

**Problem**: You have功能重複分散在多個服務中:
- **Auth功能**: auth-service (完整REST) + identity-service (空殼但有完整依賴)
- **Social功能**: likes/shares/comments分散在content-service + user-service
- **Communication功能**: messaging-service (E2EE) + notification-service (FCM/APNs/WebSocket/Email) + events-service

**Solution**: 合併成3個V2統一服務:
1. **identity-service V2** → 統一身份認證 (auth-service功能 + session管理 + token管理)
2. **social-service V2** → 統一社交互動 (likes/shares/comments/tags集中管理)
3. **communication-service V2** → 統一通訊渠道 (messaging + notification + events整合)

**Benefit**:
- 清晰的服務邊界 (Identity | Social | Communication)
- 減少跨服務調用 (like/comment不再跨content-service和user-service)
- 統一event publishing (communication-service統一處理所有通知)

---

## Current State Analysis

### 功能重疊分析

#### 1. Authentication & Identity (身份認證)

**auth-service (Production Ready)**:
- ✅ 完整REST實現 (419 lines main.rs)
- ✅ Handlers: auth.rs (421 lines), oauth.rs (68 lines)
- ✅ 功能: register, login, logout, refresh_token, password_reset, token_revocation
- ✅ 安全: Argon2, JWT, Redis blacklist, PostgreSQL persistence
- ❌ 缺點: REST-only, 沒有gRPC Proto完整定義

**identity-service V2 (Empty Shell but Full Dependencies)**:
- 📦 完整依賴: jsonwebtoken, argon2, crypto-core, grpc-tls, aws-secrets, resilience
- 📦 DDD架構: domain/, infrastructure/, application/ 目錄結構
- 📦 設計: AuthenticationService, SessionService, TokenService (已定義但未實現)
- ❌ 當前狀態: 只有209行main.rs,沒有實現

**整合意圖**:
```
identity-service V2 = auth-service完整功能 + Session管理 + mTLS + AWS Secrets Manager
```

**清晰的責任劃分**:
- **identity-service V2**: 身份認證、Session、Token、OAuth
- **auth-service**: 廢棄 → 功能遷移到identity-service

---

#### 2. Social Interactions (社交互動)

**當前分散狀態**:

**content-service** (Partial):
- ✅ `db/like_repo.rs` (150+ lines): create_like, delete_like, find_like, count_likes
- ✅ `db/comment_repo.rs`: create_comment, update_comment, delete_comment
- ✅ `grpc/server.rs`: like_post, unlike_post, create_comment, update_comment, delete_comment
- ✅ `cache/mod.rs`: cache_comment, invalidate_comment
- ✅ `middleware/permissions.rs`: check_comment_ownership, check_like_ownership

**user-service** (Partial):
- ✅ `db/post_share_repo.rs` (150+ lines): create_share, delete_share, get_post_shares, count_post_shares
- ✅ `grpc/clients.rs`: get_comments, like_post (跨服務調用content-service)
- ✅ `services/cdc/consumer.rs`: insert_comments_cdc, insert_likes_cdc (CDC同步)

**notification-service** (Trigger):
- ✅ `models/mod.rs`: NotificationType::Like, Comment, Follow, Mention
- ✅ 功能: 當like/comment發生時,發送通知

**問題**:
1. **跨服務依賴**: user-service要知道likes,必須調用content-service gRPC
2. **CDC同步**: user-service用CDC同步content-service的likes/comments數據(複雜)
3. **邊界不清**: "Like"是content概念還是social互動?
4. **Performance**: 查詢user的所有likes需要跨服務

**整合意圖**:
```
social-service V2 = 集中管理 likes + shares + comments + tags + mentions
```

**清晰的責任劃分**:
- **content-service**: 只負責Post/Story內容本身(CRUD, feed算法)
- **social-service V2**: 所有社交互動(likes, shares, comments, tags, mentions, follows)
- **notification-service**: 接收social-service事件,發送通知

**數據流**:
```
User likes post → social-service.like_post()
                → Publish LikeCreated event (Kafka)
                → content-service updates like_count (CDC consumer)
                → notification-service sends notification (Event consumer)
```

---

#### 3. Communication Channels (通訊渠道)

**當前分散狀態**:

**messaging-service** (E2EE Messages):
- ✅ 完整E2EE實現 (254 lines main.rs + 11 REST routes + 10 gRPC RPCs)
- ✅ 功能: send_message, get_message, create_conversation, E2EE key exchange
- ✅ WebSocket: wsroute.rs (482 lines) - 實時消息
- ✅ Calls: calls.rs (588 lines) - 音視頻通話
- ❌ 缺點: 不處理push notification, email

**notification-service** (Push Notifications):
- ✅ 完整通知渠道實現 (148 lines main.rs + 4 handlers)
- ✅ FCM: libs/nova-fcm-shared (16 lines) + services/fcm_client.rs
- ✅ APNs: libs/nova-apns-shared (16 lines) + services/apns_client.rs
- ✅ WebSocket: handlers/websocket.rs (244 lines) + websocket/manager.rs
- ✅ Email: 測試中提到但實現在archived-v1
- ❌ 缺點: 不處理messaging內容,只處理通知

**events-service** (Event Processing):
- ✅ 184 lines main.rs
- ✅ Kafka consumer for event processing
- ❌ 當前狀態: 基礎框架,沒有具體業務邏輯

**問題**:
1. **通知分離**: 用戶發送message後,notification-service怎麼知道要push?
2. **WebSocket重複**: messaging-service有WebSocket, notification-service也有
3. **Email缺失**: 當前沒有email發送實現(archived-v1有)
4. **Event處理**: events-service和notification-service職責重疊

**整合意圖**:
```
communication-service V2 = messaging + notification + events統一通訊
```

**清晰的責任劃分**:
- **communication-service V2**: 統一所有通訊渠道
  - E2EE messaging (來自messaging-service)
  - Push notifications (FCM, APNs)
  - WebSocket real-time
  - Email sending (lettre)
  - SMS (future)
- **messaging-service**: 廢棄 → 功能遷移到communication-service
- **notification-service**: 廢棄 → 功能遷移到communication-service
- **events-service**: 廢棄 → 功能遷移到communication-service

**統一API**:
```rust
// 統一的SendMessage API
communication_service.send_message(SendMessageRequest {
    conversation_id: "...",
    content: "Hello",
    encrypted_content: "...",
    delivery_channels: vec![
        DeliveryChannel::WebSocket,  // 實時推送(如果online)
        DeliveryChannel::FCM,        // Push notification(如果offline)
        DeliveryChannel::Email,      // Email(如果設置)
    ],
})
```

---

## V2 Architecture Design

### Service Boundary Definitions

```
┌─────────────────────────────────────────────────────────────────┐
│                       GraphQL Gateway                             │
│                  (Unified API for iOS/Web)                        │
└─────────────────────────────────────────────────────────────────┘
                               │
          ┌────────────────────┼────────────────────┐
          ▼                    ▼                    ▼
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│ identity-service │  │ social-service   │  │communication-svc │
│       V2         │  │       V2         │  │       V2         │
└──────────────────┘  └──────────────────┘  └──────────────────┘
│                     │                     │
│ • Auth            │ • Likes             │ • E2EE Messaging  │
│ • Session         │ • Shares            │ • Push (FCM/APNs) │
│ • Token           │ • Comments          │ • WebSocket       │
│ • OAuth           │ • Tags              │ • Email (lettre)  │
│ • mTLS            │ • Mentions          │ • SMS (future)    │
│ • AWS Secrets     │ • Follows           │ • Event Bus       │
└──────────────────┘  └──────────────────┘  └──────────────────┘
```

### Remaining Services (No Changes)

**Core Content** (Keep):
- user-service (profiles, relationships, preferences) ✅
- content-service (posts, stories, feed algorithm) ✅
- feed-service (recommendations, trending, discover) ✅

**Media Stack** (Keep):
- media-service (S3, image processing) ✅
- video-service (S3, transcoding, CloudFront) ✅
- streaming-service (RTMP, HLS/DASH, live) ✅
- cdn-service (enterprise CDN, failover, origin shield) ✅

**Infrastructure** (Keep):
- search-service (full-text search) ✅
- graphql-gateway (unified API) ✅

**Total**: 16 services → 13 services (減少3個,合併到V2)

---

## Implementation Roadmap

### Phase 0: Feature Audit (1-2h)

**Goal**: 確認沒有遺漏的功能

#### Step 0.1: Auth功能完整性確認

```bash
# 檢查auth-service所有endpoints
grep -r "pub async fn" backend/auth-service/src/handlers/

# 檢查identity-service domain設計
ls -la backend/identity-service/src/domain/
ls -la backend/identity-service/src/application/
```

**確認清單**:
- [ ] Register (email + password)
- [ ] Login (JWT generation)
- [ ] Logout (token revocation)
- [ ] Refresh token (token rotation)
- [ ] Email verification
- [ ] Password reset (request + reset)
- [ ] OAuth (Google/Apple/Facebook)
- [ ] Session management
- [ ] Device tracking

#### Step 0.2: Social功能完整性確認

```bash
# 檢查content-service的social功能
ls -la backend/content-service/src/db/*like* *comment* *share*

# 檢查user-service的social功能
ls -la backend/user-service/src/db/*share*
```

**確認清單**:
- [ ] Likes (create, delete, count, list likers)
- [ ] Comments (create, update, delete, nested comments)
- [ ] Shares (create, delete, count, list shares)
- [ ] Tags (user tags in posts/comments)
- [ ] Mentions (@ mentions)
- [ ] Follows (在user-service relationships中)

#### Step 0.3: Communication功能完整性確認

```bash
# 檢查messaging-service所有routes
ls -la backend/messaging-service/src/routes/

# 檢查notification-service渠道實現
ls -la backend/notification-service/src/services/
```

**確認清單**:
- [ ] E2EE messaging (send, receive, key exchange)
- [ ] Conversations (1-on-1, group)
- [ ] Message attachments (images, files)
- [ ] Voice/Video calls (WebRTC)
- [ ] Push notifications (FCM, APNs)
- [ ] WebSocket real-time
- [ ] Email sending
- [ ] SMS (future)

---

### Phase 1: identity-service V2 Implementation (20-25h)

**Goal**: 完整替代auth-service

#### Step 1.1: Domain Layer (5-6h)

**File**: `backend/identity-service/src/domain/user.rs` (NEW)

```rust
use uuid::Uuid;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct User {
    pub id: Uuid,
    pub email: String,
    pub username: String,
    pub password_hash: String,
    pub is_verified: bool,
    pub is_active: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub id: Uuid,
    pub user_id: Uuid,
    pub device_id: String,
    pub device_name: Option<String>,
    pub ip_address: String,
    pub user_agent: String,
    pub access_token_hash: String,
    pub refresh_token_hash: String,
    pub expires_at: DateTime<Utc>,
    pub created_at: DateTime<Utc>,
    pub last_active_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TokenRevocation {
    pub id: Uuid,
    pub user_id: Uuid,
    pub token_hash: String,
    pub token_type: TokenType,
    pub reason: String,
    pub revoked_at: DateTime<Utc>,
    pub expires_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum TokenType {
    Access,
    Refresh,
}
```

**File**: `backend/identity-service/src/domain/repositories.rs` (NEW)

```rust
use async_trait::async_trait;
use uuid::Uuid;
use super::{User, Session, TokenRevocation};

#[async_trait]
pub trait UserRepository: Send + Sync {
    async fn create(&self, user: User) -> Result<User>;
    async fn find_by_id(&self, id: Uuid) -> Result<Option<User>>;
    async fn find_by_email(&self, email: &str) -> Result<Option<User>>;
    async fn update(&self, user: User) -> Result<User>;
    async fn verify_email(&self, user_id: Uuid) -> Result<()>;
}

#[async_trait]
pub trait SessionRepository: Send + Sync {
    async fn create(&self, session: Session) -> Result<Session>;
    async fn find_by_id(&self, id: Uuid) -> Result<Option<Session>>;
    async fn find_by_user(&self, user_id: Uuid) -> Result<Vec<Session>>;
    async fn update_last_active(&self, session_id: Uuid) -> Result<()>;
    async fn revoke(&self, session_id: Uuid) -> Result<()>;
    async fn revoke_all_user_sessions(&self, user_id: Uuid) -> Result<()>;
}

#[async_trait]
pub trait TokenRevocationRepository: Send + Sync {
    async fn create(&self, revocation: TokenRevocation) -> Result<TokenRevocation>;
    async fn is_revoked(&self, token_hash: &str) -> Result<bool>;
    async fn cleanup_expired(&self) -> Result<u64>;
}
```

#### Step 1.2: Application Layer (8-10h)

**File**: `backend/identity-service/src/application/auth_service.rs` (NEW)

```rust
use crate::domain::{User, UserRepository, TokenRevocation, TokenRevocationRepository};
use crate::infrastructure::{CacheManager, EventPublisher};
use uuid::Uuid;
use argon2::{Argon2, PasswordHash, PasswordHasher, PasswordVerifier};
use argon2::password_hash::{rand_core::OsRng, SaltString};
use anyhow::{Context, Result};

pub struct AuthenticationService {
    user_repo: Arc<dyn UserRepository>,
    token_revocation_repo: Arc<dyn TokenRevocationRepository>,
    cache: Arc<CacheManager>,
    events: Arc<EventPublisher>,
    jwt_settings: JwtSettings,
}

impl AuthenticationService {
    pub async fn register(
        &self,
        email: String,
        password: String,
        username: String,
    ) -> Result<User> {
        // Check if email exists
        if let Some(_) = self.user_repo.find_by_email(&email).await? {
            return Err(anyhow!("Email already registered"));
        }

        // Hash password with Argon2
        let salt = SaltString::generate(&mut OsRng);
        let argon2 = Argon2::default();
        let password_hash = argon2
            .hash_password(password.as_bytes(), &salt)
            .context("Failed to hash password")?
            .to_string();

        // Create user
        let user = User {
            id: Uuid::new_v4(),
            email: email.clone(),
            username,
            password_hash,
            is_verified: false,
            is_active: true,
            created_at: Utc::now(),
            updated_at: Utc::now(),
        };

        let created_user = self.user_repo.create(user).await?;

        // Publish UserRegistered event
        self.events.publish("user.registered", &created_user).await?;

        Ok(created_user)
    }

    pub async fn login(
        &self,
        email: String,
        password: String,
        device_id: String,
        ip_address: String,
        user_agent: String,
    ) -> Result<(User, Session, TokenPair)> {
        // Find user
        let user = self.user_repo
            .find_by_email(&email)
            .await?
            .ok_or_else(|| anyhow!("Invalid email or password"))?;

        if !user.is_active {
            return Err(anyhow!("User account is disabled"));
        }

        // Verify password
        let parsed_hash = PasswordHash::new(&user.password_hash)
            .context("Failed to parse password hash")?;
        Argon2::default()
            .verify_password(password.as_bytes(), &parsed_hash)
            .map_err(|_| anyhow!("Invalid email or password"))?;

        // Generate tokens
        let token_pair = self.generate_token_pair(&user)?;

        // Create session
        let session = Session {
            id: Uuid::new_v4(),
            user_id: user.id,
            device_id,
            device_name: None,
            ip_address,
            user_agent,
            access_token_hash: hash_token(&token_pair.access_token),
            refresh_token_hash: hash_token(&token_pair.refresh_token),
            expires_at: Utc::now() + chrono::Duration::days(30),
            created_at: Utc::now(),
            last_active_at: Utc::now(),
        };

        let created_session = self.session_repo.create(session).await?;

        // Publish UserLoggedIn event
        self.events.publish("user.logged_in", &user).await?;

        Ok((user, created_session, token_pair))
    }

    pub async fn logout(&self, access_token: &str, refresh_token: Option<&str>) -> Result<()> {
        let token_hash = hash_token(access_token);

        // Revoke access token
        self.revoke_token(access_token, "logout").await?;

        // Revoke refresh token if provided
        if let Some(refresh) = refresh_token {
            self.revoke_token(refresh, "logout").await?;
        }

        // Cache revocation in Redis
        self.cache.set_token_revoked(&token_hash, 3600).await?;

        Ok(())
    }

    async fn revoke_token(&self, token: &str, reason: &str) -> Result<()> {
        let token_data = jwt::validate_token(token)?;
        let token_hash = hash_token(token);

        let revocation = TokenRevocation {
            id: Uuid::new_v4(),
            user_id: token_data.claims.sub,
            token_hash,
            token_type: TokenType::Access,
            reason: reason.to_string(),
            revoked_at: Utc::now(),
            expires_at: DateTime::from_timestamp(token_data.claims.exp, 0)
                .ok_or_else(|| anyhow!("Invalid token expiration"))?,
        };

        self.token_revocation_repo.create(revocation).await?;
        Ok(())
    }

    fn generate_token_pair(&self, user: &User) -> Result<TokenPair> {
        // Use crypto-core library
        crypto_core::jwt::generate_token_pair(
            user.id,
            &user.email,
            &user.username,
        )
    }
}

fn hash_token(token: &str) -> String {
    use sha2::{Sha256, Digest};
    let mut hasher = Sha256::new();
    hasher.update(token.as_bytes());
    format!("{:x}", hasher.finalize())
}
```

**Similar files**:
- `session_service.rs` (Session CRUD, device management)
- `token_service.rs` (Token refresh, revocation check)
- `oauth_service.rs` (Google/Apple/Facebook OAuth)

#### Step 1.3: Infrastructure Layer (3-4h)

Implement repositories using existing patterns from auth-service:
- `UserRepositoryImpl` → Use auth-service's db queries
- `SessionRepositoryImpl` → New implementation
- `TokenRevocationRepositoryImpl` → Use auth-service's token_revocation logic

#### Step 1.4: gRPC Proto & Implementation (4-5h)

**File**: `backend/proto/services/identity_service.proto` (NEW)

```protobuf
syntax = "proto3";

package nova.identity;

service IdentityService {
  // Authentication
  rpc Register(RegisterRequest) returns (RegisterResponse);
  rpc Login(LoginRequest) returns (LoginResponse);
  rpc Logout(LogoutRequest) returns (LogoutResponse);
  rpc RefreshToken(RefreshTokenRequest) returns (RefreshTokenResponse);

  // Email verification
  rpc SendVerificationEmail(SendVerificationEmailRequest) returns (SendVerificationEmailResponse);
  rpc VerifyEmail(VerifyEmailRequest) returns (VerifyEmailResponse);

  // Password reset
  rpc RequestPasswordReset(RequestPasswordResetRequest) returns (RequestPasswordResetResponse);
  rpc ResetPassword(ResetPasswordRequest) returns (ResetPasswordResponse);

  // Session management
  rpc GetUserSessions(GetUserSessionsRequest) returns (GetUserSessionsResponse);
  rpc RevokeSession(RevokeSessionRequest) returns (RevokeSessionResponse);
  rpc RevokeAllUserSessions(RevokeAllUserSessionsRequest) returns (RevokeAllUserSessionsResponse);

  // Token validation
  rpc ValidateToken(ValidateTokenRequest) returns (ValidateTokenResponse);
  rpc IsTokenRevoked(IsTokenRevokedRequest) returns (IsTokenRevokedResponse);

  // OAuth
  rpc OAuthLogin(OAuthLoginRequest) returns (OAuthLoginResponse);
}

message RegisterRequest {
  string email = 1;
  string password = 2;
  string username = 3;
}

message RegisterResponse {
  string user_id = 1;
  string email = 2;
  string username = 3;
}

message LoginRequest {
  string email = 1;
  string password = 2;
  string device_id = 3;
  string ip_address = 4;
  string user_agent = 5;
}

message LoginResponse {
  string access_token = 1;
  string refresh_token = 2;
  User user = 3;
  Session session = 4;
}

message User {
  string id = 1;
  string email = 2;
  string username = 3;
  bool is_verified = 4;
  bool is_active = 5;
  string created_at = 6;
}

message Session {
  string id = 1;
  string user_id = 2;
  string device_id = 3;
  string device_name = 4;
  string ip_address = 5;
  string user_agent = 6;
  string expires_at = 7;
  string created_at = 8;
  string last_active_at = 9;
}

// ... other messages
```

**Implementation**: Migrate gRPC implementation from auth-service to identity-service.

---

### Phase 2: social-service V2 Implementation (15-18h)

**Goal**: 集中管理所有社交互動

#### Step 2.1: Domain Model (3-4h)

**File**: `backend/social-service/src/domain/mod.rs` (NEW)

```rust
use uuid::Uuid;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Like {
    pub id: Uuid,
    pub post_id: Uuid,
    pub user_id: Uuid,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Comment {
    pub id: Uuid,
    pub post_id: Uuid,
    pub user_id: Uuid,
    pub content: String,
    pub parent_comment_id: Option<Uuid>,  // For nested comments
    pub is_edited: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Share {
    pub id: Uuid,
    pub post_id: Uuid,
    pub user_id: Uuid,
    pub share_via: Option<String>,  // "facebook", "twitter", "instagram", "direct"
    pub shared_with_user_id: Option<Uuid>,  // For direct shares
    pub shared_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Tag {
    pub id: Uuid,
    pub object_id: Uuid,  // post_id or comment_id
    pub object_type: TagObjectType,
    pub user_id: Uuid,  // User being tagged
    pub tagged_by: Uuid,  // User who created the tag
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum TagObjectType {
    Post,
    Comment,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Mention {
    pub id: Uuid,
    pub object_id: Uuid,  // post_id or comment_id
    pub object_type: MentionObjectType,
    pub mentioned_user_id: Uuid,
    pub mentioned_by: Uuid,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum MentionObjectType {
    Post,
    Comment,
}
```

#### Step 2.2: Migrate Like/Comment/Share Logic (5-6h)

**Strategy**: 複製並改進content-service和user-service的實現

1. **Likes**:
   - Copy: `content-service/src/db/like_repo.rs` → `social-service/src/repositories/like_repo.rs`
   - Improve: Add caching, event publishing

2. **Comments**:
   - Copy: `content-service/src/db/comment_repo.rs` → `social-service/src/repositories/comment_repo.rs`
   - Improve: Nested comments support, better pagination

3. **Shares**:
   - Copy: `user-service/src/db/post_share_repo.rs` → `social-service/src/repositories/share_repo.rs`
   - Improve: Track share source (Facebook/Twitter/etc)

#### Step 2.3: Event-Driven Integration (4-5h)

**Pattern**: Transactional Outbox for all social interactions

```rust
// When user likes a post
pub async fn like_post(&self, post_id: Uuid, user_id: Uuid) -> Result<Like> {
    let mut tx = self.db.begin().await?;

    // 1. Create like
    let like = sqlx::query_as::<_, Like>(
        "INSERT INTO likes (post_id, user_id) VALUES ($1, $2) RETURNING *"
    )
    .bind(post_id)
    .bind(user_id)
    .fetch_one(&mut *tx)
    .await?;

    // 2. Insert into outbox (Transactional Outbox pattern)
    self.outbox.insert_event(
        &mut tx,
        "social.like_created",
        serde_json::json!({
            "like_id": like.id,
            "post_id": post_id,
            "user_id": user_id,
        }),
    ).await?;

    tx.commit().await?;

    // 3. Event will be published by outbox worker
    // → content-service updates like_count (CDC)
    // → communication-service sends notification

    Ok(like)
}
```

#### Step 2.4: gRPC Proto (3-4h)

**File**: `backend/proto/services/social_service.proto` (NEW)

```protobuf
syntax = "proto3";

package nova.social;

service SocialService {
  // Likes
  rpc LikePost(LikePostRequest) returns (LikePostResponse);
  rpc UnlikePost(UnlikePostRequest) returns (UnlikePostResponse);
  rpc GetPostLikes(GetPostLikesRequest) returns (GetPostLikesResponse);
  rpc GetUserLikes(GetUserLikesRequest) returns (GetUserLikesResponse);

  // Comments
  rpc CreateComment(CreateCommentRequest) returns (CreateCommentResponse);
  rpc UpdateComment(UpdateCommentRequest) returns (UpdateCommentResponse);
  rpc DeleteComment(DeleteCommentRequest) returns (DeleteCommentResponse);
  rpc GetPostComments(GetPostCommentsRequest) returns (GetPostCommentsResponse);

  // Shares
  rpc SharePost(SharePostRequest) returns (SharePostResponse);
  rpc GetPostShares(GetPostSharesRequest) returns (GetPostSharesResponse);

  // Tags
  rpc TagUser(TagUserRequest) returns (TagUserResponse);
  rpc GetObjectTags(GetObjectTagsRequest) returns (GetObjectTagsResponse);

  // Mentions
  rpc GetUserMentions(GetUserMentionsRequest) returns (GetUserMentionsResponse);
}
```

---

### Phase 3: communication-service V2 Implementation (18-22h)

**Goal**: 統一所有通訊渠道 (messaging + notifications + events)

#### Step 3.1: Unified Communication Model (4-5h)

**File**: `backend/communication-service/src/domain/message.rs` (NEW)

```rust
use uuid::Uuid;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub id: Uuid,
    pub conversation_id: Uuid,
    pub sender_id: Uuid,
    pub content: Option<String>,  // Plain content for search
    pub encrypted_content: String,  // E2EE content
    pub message_type: MessageType,
    pub delivery_status: DeliveryStatus,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum MessageType {
    Text,
    Image,
    Video,
    Audio,
    File,
    Location,
    Contact,
    Call,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum DeliveryStatus {
    Sending,
    Delivered,
    Read,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeliveryChannel {
    pub message_id: Uuid,
    pub channel_type: ChannelType,
    pub recipient_id: Uuid,
    pub device_token: Option<String>,
    pub status: ChannelDeliveryStatus,
    pub attempted_at: Option<DateTime<Utc>>,
    pub delivered_at: Option<DateTime<Utc>>,
    pub error_message: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum ChannelType {
    WebSocket,  // Real-time
    FCM,        // Android push
    APNs,       // iOS push
    Email,      // Email notification
    SMS,        // SMS (future)
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum ChannelDeliveryStatus {
    Pending,
    Sent,
    Delivered,
    Failed,
}
```

#### Step 3.2: Merge Messaging Service (5-6h)

**Strategy**: 複製messaging-service完整E2EE實現

1. **E2EE Messaging**:
   - Copy all 11 routes from `messaging-service/src/routes/` to `communication-service/src/modules/messaging/`
   - Keep: messages.rs (933 lines), conversations.rs (298 lines), groups.rs (474 lines)

2. **WebRTC Calls**:
   - Copy: calls.rs (588 lines)
   - Improve: Integrate with push notification for call ringing

3. **Key Exchange**:
   - Copy: key_exchange.rs (208 lines)

#### Step 3.3: Merge Notification Service (4-5h)

**Strategy**: 複製notification-service所有渠道

1. **FCM/APNs Clients**:
   - Copy: `notification-service/src/services/fcm_client.rs`
   - Copy: `notification-service/src/services/apns_client.rs`
   - Use existing libraries: `nova-fcm-shared`, `nova-apns-shared`

2. **WebSocket Manager**:
   - Copy: `notification-service/src/websocket/manager.rs`
   - Merge with messaging-service WebSocket (wsroute.rs)

3. **Email Sender**:
   - Implement: Use lettre library (dependency already in Cargo.toml)
   - Reference: archived-v1/auth-service/src/services/email.rs

**File**: `backend/communication-service/src/modules/email/sender.rs` (NEW)

```rust
use lettre::message::{header, Mailbox, Message};
use lettre::transport::smtp::authentication::Credentials;
use lettre::{AsyncSmtpTransport, AsyncTransport, Tokio1Executor};
use anyhow::{Context, Result};

pub struct EmailSender {
    transport: AsyncSmtpTransport<Tokio1Executor>,
    from_address: Mailbox,
}

impl EmailSender {
    pub fn new(smtp_host: &str, smtp_port: u16, username: &str, password: &str, from: &str) -> Result<Self> {
        let creds = Credentials::new(username.to_string(), password.to_string());

        let transport = AsyncSmtpTransport::<Tokio1Executor>::relay(smtp_host)
            .context("Failed to create SMTP transport")?
            .port(smtp_port)
            .credentials(creds)
            .build();

        let from_address = from.parse().context("Failed to parse from address")?;

        Ok(Self {
            transport,
            from_address,
        })
    }

    pub async fn send_verification_email(&self, to: &str, token: &str) -> Result<()> {
        let verification_link = format!("https://nova.app/verify-email?token={}", token);

        let email = Message::builder()
            .from(self.from_address.clone())
            .to(to.parse().context("Failed to parse recipient address")?)
            .subject("Verify Your Email - Nova")
            .header(header::ContentType::TEXT_HTML)
            .body(format!(
                r#"
                <h1>Welcome to Nova!</h1>
                <p>Please verify your email by clicking the link below:</p>
                <a href="{}">Verify Email</a>
                <p>This link expires in 24 hours.</p>
                "#,
                verification_link
            ))
            .context("Failed to build email message")?;

        self.transport.send(email).await.context("Failed to send email")?;

        Ok(())
    }

    pub async fn send_password_reset_email(&self, to: &str, token: &str) -> Result<()> {
        let reset_link = format!("https://nova.app/reset-password?token={}", token);

        let email = Message::builder()
            .from(self.from_address.clone())
            .to(to.parse().context("Failed to parse recipient address")?)
            .subject("Reset Your Password - Nova")
            .header(header::ContentType::TEXT_HTML)
            .body(format!(
                r#"
                <h1>Password Reset Request</h1>
                <p>Click the link below to reset your password:</p>
                <a href="{}">Reset Password</a>
                <p>This link expires in 1 hour.</p>
                <p>If you didn't request this, please ignore this email.</p>
                "#,
                reset_link
            ))
            .context("Failed to build email message")?;

        self.transport.send(email).await.context("Failed to send email")?;

        Ok(())
    }
}
```

#### Step 3.4: Unified Delivery Logic (5-6h)

**Pattern**: Multi-channel delivery with fallback

```rust
pub async fn send_message_with_delivery(
    &self,
    message: Message,
    recipient_id: Uuid,
) -> Result<()> {
    // 1. Store message in DB
    let stored_msg = self.message_repo.create(message).await?;

    // 2. Attempt WebSocket delivery (real-time)
    if self.websocket_manager.is_user_online(recipient_id).await? {
        self.websocket_manager.send_to_user(recipient_id, &stored_msg).await?;
        self.mark_channel_delivered(stored_msg.id, ChannelType::WebSocket).await?;
        return Ok(());
    }

    // 3. Fallback to push notification
    let device_tokens = self.device_repo.find_active_tokens(recipient_id).await?;

    for device in device_tokens {
        match device.channel {
            NotificationChannel::FCM => {
                self.fcm_client.send_notification(&device.token, &stored_msg).await?;
            }
            NotificationChannel::APNs => {
                self.apns_client.send_notification(&device.token, &stored_msg).await?;
            }
            _ => {}
        }
        self.mark_channel_delivered(stored_msg.id, device.channel.into()).await?;
    }

    // 4. Optional: Send email notification if enabled
    if self.should_send_email(recipient_id).await? {
        let user_email = self.get_user_email(recipient_id).await?;
        self.email_sender.send_message_notification(&user_email, &stored_msg).await?;
    }

    Ok(())
}
```

---

### Phase 4: GraphQL Gateway Integration (8-10h)

#### Step 4.1: Connect identity-service V2

**File**: `backend/graphql-gateway/src/clients.rs`

```rust
pub struct ServiceClients {
    // OLD: auth_channel (remove)
    // NEW: identity_channel
    identity_channel: Arc<Channel>,
    user_channel: Arc<Channel>,
    content_channel: Arc<Channel>,
    feed_channel: Arc<Channel>,
    messaging_channel: Arc<Channel>,  // Still needed for now
    // NEW V2 channels
    social_channel: Arc<Channel>,
    communication_channel: Arc<Channel>,
}

impl ServiceClients {
    pub async fn new() -> Result<Self> {
        let identity_channel = Arc::new(
            Channel::from_static("http://identity-service:9090")
                .connect()
                .await?
        );

        let social_channel = Arc::new(
            Channel::from_static("http://social-service:9091")
                .connect()
                .await?
        );

        let communication_channel = Arc::new(
            Channel::from_static("http://communication-service:9092")
                .connect()
                .await?
        );

        Ok(Self {
            identity_channel,
            social_channel,
            communication_channel,
            // ... other channels
        })
    }
}
```

#### Step 4.2: Update Auth Schema

**File**: `backend/graphql-gateway/src/schema/auth.rs`

Change all auth gRPC calls from `auth_service_client` to `identity_service_client`.

#### Step 4.3: Create Social Schema

**File**: `backend/graphql-gateway/src/schema/social.rs` (NEW)

```rust
use async_graphql::*;

#[derive(Default)]
pub struct SocialQuery;

#[Object]
impl SocialQuery {
    async fn post_likes(
        &self,
        ctx: &Context<'_>,
        post_id: String,
    ) -> Result<Vec<Like>> {
        let clients = ctx.data::<ServiceClients>()?;
        let mut client = clients.social_client().await?;

        let request = tonic::Request::new(proto::GetPostLikesRequest {
            post_id,
        });

        let response = client.get_post_likes(request).await?;

        Ok(response.into_inner().likes.into_iter().map(|l| Like {
            id: l.id,
            post_id: l.post_id,
            user_id: l.user_id,
            created_at: l.created_at,
        }).collect())
    }

    async fn post_comments(
        &self,
        ctx: &Context<'_>,
        post_id: String,
    ) -> Result<Vec<Comment>> {
        // Similar implementation
    }
}

#[derive(Default)]
pub struct SocialMutation;

#[Object]
impl SocialMutation {
    async fn like_post(
        &self,
        ctx: &Context<'_>,
        post_id: String,
    ) -> Result<Like> {
        let user_id = ctx.data::<UserId>()?;
        let clients = ctx.data::<ServiceClients>()?;
        let mut client = clients.social_client().await?;

        let request = tonic::Request::new(proto::LikePostRequest {
            post_id,
            user_id: user_id.to_string(),
        });

        let response = client.like_post(request).await?;
        let like = response.into_inner();

        Ok(Like {
            id: like.id,
            post_id: like.post_id,
            user_id: like.user_id,
            created_at: like.created_at,
        })
    }

    async fn create_comment(
        &self,
        ctx: &Context<'_>,
        post_id: String,
        content: String,
    ) -> Result<Comment> {
        // Similar implementation
    }
}

#[derive(SimpleObject)]
pub struct Like {
    pub id: String,
    pub post_id: String,
    pub user_id: String,
    pub created_at: String,
}

#[derive(SimpleObject)]
pub struct Comment {
    pub id: String,
    pub post_id: String,
    pub user_id: String,
    pub content: String,
    pub created_at: String,
    pub updated_at: String,
}
```

#### Step 4.4: Update Schema Composition

**File**: `backend/graphql-gateway/src/schema/mod.rs`

```rust
pub mod social;  // ADD
pub mod communication;  // ADD (rename from messaging)

#[derive(MergedObject, Default)]
pub struct QueryRoot(
    user::UserQuery,
    content::ContentQuery,
    auth::AuthQuery,  // Now uses identity-service
    social::SocialQuery,  // NEW
    communication::CommunicationQuery,  // NEW (replaces messaging)
);

#[derive(MergedObject, Default)]
pub struct MutationRoot(
    user::UserMutation,
    content::ContentMutation,
    auth::AuthMutation,
    social::SocialMutation,  // NEW
    communication::CommunicationMutation,  // NEW
);
```

---

### Phase 5: Database Migration & Cleanup (6-8h)

#### Step 5.1: Social Service Database

**File**: `backend/social-service/migrations/001_initial_schema.sql` (NEW)

```sql
-- Likes table
CREATE TABLE likes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id UUID NOT NULL,
    user_id UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    UNIQUE(post_id, user_id)
);

CREATE INDEX idx_likes_post_id ON likes(post_id);
CREATE INDEX idx_likes_user_id ON likes(user_id);
CREATE INDEX idx_likes_created_at ON likes(created_at DESC);

-- Comments table
CREATE TABLE comments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id UUID NOT NULL,
    user_id UUID NOT NULL,
    content TEXT NOT NULL,
    parent_comment_id UUID REFERENCES comments(id) ON DELETE CASCADE,
    is_edited BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    CHECK (char_length(content) <= 5000)
);

CREATE INDEX idx_comments_post_id ON comments(post_id);
CREATE INDEX idx_comments_user_id ON comments(user_id);
CREATE INDEX idx_comments_parent_id ON comments(parent_comment_id) WHERE parent_comment_id IS NOT NULL;
CREATE INDEX idx_comments_created_at ON comments(created_at DESC);

-- Shares table
CREATE TABLE shares (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id UUID NOT NULL,
    user_id UUID NOT NULL,
    share_via VARCHAR(50),  -- 'facebook', 'twitter', 'instagram', 'direct'
    shared_with_user_id UUID,  -- For direct shares
    shared_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_shares_post_id ON shares(post_id);
CREATE INDEX idx_shares_user_id ON shares(user_id);
CREATE INDEX idx_shares_shared_at ON shares(shared_at DESC);

-- Tags table
CREATE TABLE tags (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    object_id UUID NOT NULL,  -- post_id or comment_id
    object_type VARCHAR(20) NOT NULL CHECK (object_type IN ('post', 'comment')),
    user_id UUID NOT NULL,  -- User being tagged
    tagged_by UUID NOT NULL,  -- User who created the tag
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    UNIQUE(object_id, object_type, user_id)
);

CREATE INDEX idx_tags_object ON tags(object_id, object_type);
CREATE INDEX idx_tags_user_id ON tags(user_id);

-- Mentions table
CREATE TABLE mentions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    object_id UUID NOT NULL,
    object_type VARCHAR(20) NOT NULL CHECK (object_type IN ('post', 'comment')),
    mentioned_user_id UUID NOT NULL,
    mentioned_by UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    UNIQUE(object_id, object_type, mentioned_user_id)
);

CREATE INDEX idx_mentions_object ON mentions(object_id, object_type);
CREATE INDEX idx_mentions_user_id ON mentions(mentioned_user_id);
```

#### Step 5.2: Data Migration Strategy

**Option 1: Zero-downtime migration** (推薦):

1. **Phase 1**: Deploy social-service V2 alongside content-service
2. **Phase 2**: Dual-write (write to both content-service and social-service)
3. **Phase 3**: Backfill historical data to social-service
4. **Phase 4**: Switch reads to social-service
5. **Phase 5**: Remove likes/comments tables from content-service

**Option 2: Maintenance window**:

1. Announce maintenance window (2-4 hours)
2. Stop writes to content-service likes/comments
3. Copy all data to social-service
4. Deploy new services
5. Resume writes to social-service

#### Step 5.3: Remove Deprecated Services

After verification:

```bash
# Archive old services
mv backend/auth-service backend/archived-v2/auth-service
mv backend/messaging-service backend/archived-v2/messaging-service
mv backend/notification-service backend/archived-v2/notification-service
mv backend/events-service backend/archived-v2/events-service

# Remove from workspace Cargo.toml
# Remove from k8s deployments
```

---

## Testing Strategy

### Unit Tests (Per Service)

**identity-service V2**:
```bash
cd backend/identity-service
cargo test --lib
```

**social-service V2**:
```bash
cd backend/social-service
cargo test --lib
```

**communication-service V2**:
```bash
cd backend/communication-service
cargo test --lib
```

### Integration Tests

**File**: `backend/tests/integration/v2_services_test.rs` (NEW)

```rust
#[tokio::test]
async fn test_identity_service_login_flow() {
    // 1. Register
    let register_response = identity_client.register(RegisterRequest {
        email: "test@example.com".to_string(),
        password: "password123".to_string(),
        username: "testuser".to_string(),
    }).await.unwrap();

    // 2. Login
    let login_response = identity_client.login(LoginRequest {
        email: "test@example.com".to_string(),
        password: "password123".to_string(),
        device_id: "device1".to_string(),
        ip_address: "127.0.0.1".to_string(),
        user_agent: "test".to_string(),
    }).await.unwrap();

    assert!(login_response.access_token.len() > 0);
    assert!(login_response.refresh_token.len() > 0);

    // 3. Logout
    let logout_response = identity_client.logout(LogoutRequest {
        access_token: login_response.access_token,
        refresh_token: Some(login_response.refresh_token),
    }).await.unwrap();

    assert_eq!(logout_response.message, "Logged out successfully");
}

#[tokio::test]
async fn test_social_service_like_flow() {
    // 1. Create post (content-service)
    let post = content_client.create_post(CreatePostRequest {
        user_id: user_id.to_string(),
        content: "Test post".to_string(),
    }).await.unwrap();

    // 2. Like post (social-service)
    let like = social_client.like_post(LikePostRequest {
        post_id: post.id,
        user_id: user_id.to_string(),
    }).await.unwrap();

    // 3. Verify like created
    let likes = social_client.get_post_likes(GetPostLikesRequest {
        post_id: post.id,
    }).await.unwrap();

    assert_eq!(likes.likes.len(), 1);
    assert_eq!(likes.likes[0].user_id, user_id.to_string());
}

#[tokio::test]
async fn test_communication_service_multi_channel_delivery() {
    // 1. Send message
    let message = communication_client.send_message(SendMessageRequest {
        conversation_id: conversation_id.to_string(),
        sender_id: sender_id.to_string(),
        content: "Hello".to_string(),
        encrypted_content: "encrypted_hello".to_string(),
    }).await.unwrap();

    // 2. Wait for delivery
    tokio::time::sleep(Duration::from_secs(2)).await;

    // 3. Check delivery channels
    let delivery_status = communication_client.get_delivery_status(GetDeliveryStatusRequest {
        message_id: message.id,
    }).await.unwrap();

    // Should be delivered via WebSocket OR Push notification
    assert!(
        delivery_status.channels.iter().any(|c| c.status == "delivered")
    );
}
```

---

## Deployment Strategy

### Phased Rollout

**Week 1: identity-service V2**
- Deploy identity-service alongside auth-service
- Update GraphQL Gateway to use identity-service
- Monitor for 3 days
- If stable, deprecate auth-service

**Week 2: social-service V2**
- Deploy social-service
- Enable dual-write (write to both content-service and social-service)
- Backfill historical data
- Switch GraphQL Gateway reads to social-service
- Monitor for 3 days

**Week 3: communication-service V2**
- Deploy communication-service
- Gradually migrate traffic from messaging-service + notification-service
- Monitor multi-channel delivery
- Full cutover after 3 days

### Rollback Plan

Each service has rollback capability:

```bash
# Rollback identity-service
kubectl rollout undo deployment/identity-service

# Switch GraphQL Gateway back to auth-service
kubectl set env deployment/graphql-gateway USE_AUTH_SERVICE=true
```

---

## Success Metrics

### Performance
- [ ] API latency < 100ms (p95)
- [ ] gRPC call latency < 50ms (p95)
- [ ] Database query latency < 20ms (p95)

### Reliability
- [ ] 99.9% uptime for each V2 service
- [ ] Zero data loss during migration
- [ ] < 5 minutes downtime (maintenance window only)

### Architecture
- [ ] Service count: 16 → 13 (3 fewer services)
- [ ] Cross-service calls reduced by 40% (fewer like/comment cross-calls)
- [ ] Clear service boundaries (Identity | Social | Communication)

---

## Final Linus-Style Summary

**What we're doing**: 合併4個空殼/重疊服務成3個統一V2服務。

**Why it matters**:
- 清晰的責任劃分 (不再有"Like是content還是social?"的疑問)
- 減少跨服務調用 (social-service統一管理所有互動)
- 統一event publishing (communication-service統一所有通知)

**What won't change**:
- User/Content/Feed/Media services保持不變 ✅
- 現有GraphQL API向後兼容 ✅
- iOS app不需要任何改動 ✅

**Timeline**:
- Phase 1 (identity-service): 20-25h (3-4 work days)
- Phase 2 (social-service): 15-18h (2-3 work days)
- Phase 3 (communication-service): 18-22h (3-4 work days)
- Phase 4 (GraphQL integration): 8-10h (1-2 work days)
- Phase 5 (cleanup): 6-8h (1 work day)

**Total**: 67-83 hours (9-11 work days)

**Risk**: Low. All features already exist, just reorganizing. Dual-write strategy ensures zero data loss.

**Benefit**: Clean architecture that will scale better. No more "where should this feature go?" confusion.

---

**Document Version**: 1.0
**Author**: Claude Code (Architecture Consolidation Mode)
**Last Updated**: 2025-11-11
