# Nova Backend 深度架構審計報告
**Date**: 2025-11-11
**Reviewer**: Claude Code (Linus Torvalds Style - 重新審查)
**Scope**: 全部 16 個微服務 + Proto 定義 + GraphQL Gateway 集成

---

## 執行摘要

經過深度代碼掃描,發現:

### 🎯 **核心發現**

1. **服務實現狀況**:
   - ✅ **5 個完整實現**: auth, user, content, messaging, feed
   - ⚠️ **6 個部分實現**: cdn, events, media, notification, search, streaming
   - ❌ **3 個空殼**: communication, social, identity (各只有 1 行代碼)
   - ⚠️ **2 個極簡**: video (57行), graphql-gateway (194行但架構完善)

2. **GraphQL Gateway 現狀**:
   - ✅ **架構優秀**: DataLoader, Complexity Limit, Backpressure, Pagination
   - ✅ **已連接 4 個服務**: auth, user, content, feed
   - ❌ **只暴露 5 個 mutations**: login, register, followUser, createPost, deletePost
   - ❌ **缺少關鍵端點**: logout, refreshToken, verifyEmail, passwordReset

3. **Proto 定義問題**:
   - ✅ Auth Proto 有 `Refresh` RPC
   - ❌ Auth Proto **缺少** `Logout`, `VerifyEmail`, `RequestPasswordReset`, `ResetPassword`
   - ⚠️ 但 auth-service 的 **REST handlers 有實現這些功能**!

4. **架構不一致**:
   - 部分服務走 gRPC (auth, user, content)
   - 部分服務走 REST (messaging 有 11 個 REST routes)
   - GraphQL Gateway 只連接 gRPC 服務
   - REST 端點無法通過 GraphQL 訪問

---

## 第一部分:服務實現矩陣

### 🟢 **Tier 1: 生產就緒服務** (5/16)

| 服務 | Main | Handlers | gRPC | REST | Tests | 狀態 | 評分 |
|------|------|----------|------|------|-------|------|------|
| **auth-service** | 419行 | 2個 (auth, oauth) | ✅ 10 RPCs | ❌ | 7 | 🟢 完整 | 9/10 |
| **user-service** | 1205行 | 6個 | ✅ 實現 | ❌ | 20 | 🟢 完整 | 10/10 |
| **content-service** | 718行 | 4個 (posts, comments, stories, feed) | ✅ 實現 | ❌ | 7 | 🟢 完整 | 10/10 |
| **messaging-service** | 254行 | 0 | ✅ 10 RPCs | ✅ 11 routes | 30 | 🟢 完整 | 10/10 |
| **feed-service** | 368行 | 4個 | ✅ 實現 | ❌ | 3 | 🟢 完整 | 9/10 |

**評語**:
> **"這 5 個服務是整個系統的核心。實現質量高,測試覆蓋完整。Messaging service 的 REST + gRPC 混合架構是合理的 (WebSocket 需要 REST)。"**

---

### 🟡 **Tier 2: 部分實現服務** (6/16)

| 服務 | Main | Handlers | gRPC | REST | Tests | 狀態 | 評分 |
|------|------|----------|------|------|-------|------|------|
| **cdn-service** | 129行 | 0 | ❌ | ❌ | 0 | 🟡 基礎 | 3/10 |
| **events-service** | 184行 | 0 | ❌ | ❌ | 0 | 🟡 基礎 | 4/10 |
| **media-service** | 303行 | 3個 (uploads, videos, reels) | ❌ | ✅ | 0 | 🟡 部分 | 6/10 |
| **notification-service** | 148行 | 4個 | ❌ | ✅ | 4 | 🟡 部分 | 7/10 |
| **search-service** | 1010行 | 0 | ❌ | ❌ | 1 | 🟡 基礎 | 5/10 |
| **streaming-service** | 228行 | 2個 (streams, websocket) | ❌ | ✅ | 0 | 🟡 部分 | 6/10 |

**評語**:
> **"這些服務有基礎實現,但沒有 gRPC,無法被 GraphQL Gateway 調用。Notification 和 Media 有 REST API,但與主架構不一致。"**

---

### 🔴 **Tier 3: 空殼服務** (3/16)

| 服務 | Main | 狀態 | 評分 |
|------|------|------|------|
| **communication-service** | 1行 | ❌ 空殼 | 0/10 |
| **social-service** | 1行 | ❌ 空殼 | 0/10 |
| **identity-service** | 209行 | ⚠️ 極簡 | 2/10 |

**Code**:
```rust
// communication-service/src/main.rs
fn main() { println!("Communication Service V2"); }

// social-service/src/main.rs
fn main() { println!("Social Service V2"); }
```

**評語**:
> **"這些是 V2 重構的遺留物。功能可能已遷移到其他服務,或從未實現。建議刪除或完成實現。"**

---

### ⚠️ **Tier 4: 最小化服務** (2/16)

| 服務 | Main | 說明 | 評分 |
|------|------|------|------|
| **video-service** | 57行 | 極簡實現,無 handlers | 1/10 |
| **graphql-gateway** | 194行 | 架構完善但端點少 | 6/10 |

**GraphQL Gateway 詳情**:
- ✅ **架構優秀**: DataLoader, Complexity, Backpressure, Pagination
- ✅ **Schema 模塊**: auth, user, content, subscription, loaders
- ❌ **只連接 4 個服務**: auth, user, content, feed
- ❌ **mutations 只有 5 個**

---

## 第二部分:Proto 定義與實現對應

### **Auth Service 分析**

#### **Proto 定義** (`backend/proto/services/auth_service.proto`)

```protobuf
service AuthService {
  rpc Register(RegisterRequest) returns (RegisterResponse);
  rpc Login(LoginRequest) returns (LoginResponse);
  rpc Refresh(RefreshTokenRequest) returns (RefreshTokenResponse);
  rpc VerifyToken(VerifyTokenRequest) returns (VerifyTokenResponse);
  rpc GetUser(GetUserRequest) returns (GetUserResponse);
  rpc GetUsersByIds(GetUsersByIdsRequest) returns (GetUsersByIdsResponse);
  rpc CheckUserExists(CheckUserExistsRequest) returns (CheckUserExistsResponse);
  rpc GetUserByEmail(GetUserByEmailRequest) returns (GetUserByEmailResponse);
  rpc ListUsers(ListUsersRequest) returns (ListUsersResponse);
  rpc CheckPermission(CheckPermissionRequest) returns (CheckPermissionResponse);
  rpc GetUserPermissions(GetUserPermissionsRequest) returns (GetUserPermissionsResponse);
  rpc RecordFailedLogin(RecordFailedLoginRequest) returns (RecordFailedLoginResponse);
  rpc UpdateUserProfile(UpdateUserProfileRequest) returns (UpdateUserProfileResponse);
  rpc UpsertUserPublicKey(UpsertUserPublicKeyRequest) returns (UpsertUserPublicKeyResponse);
}
```

**RPC 統計**: 14 個

#### **Auth Service 實際實現** (`backend/auth-service/src/grpc/mod.rs`)

```rust
// gRPC 實現 (10 個 RPC)
impl AuthService for AuthGrpcService {
    async fn register(...) -> Result<Response<RegisterResponse>, Status>
    async fn login(...) -> Result<Response<LoginResponse>, Status>
    async fn refresh(...) -> Result<Response<RefreshTokenResponse>, Status>
    async fn get_user(...) -> Result<Response<GetUserResponse>, Status>
    async fn get_users_by_ids(...) -> Result<Response<GetUsersByIdsResponse>, Status>
    async fn verify_token(...) -> Result<Response<VerifyTokenResponse>, Status>
    async fn check_user_exists(...) -> Result<Response<CheckUserExistsResponse>, Status>
    async fn get_user_by_email(...) -> Result<Response<GetUserByEmailResponse>, Status>
    async fn list_users(...) -> Result<Response<ListUsersResponse>, Status>
    async fn check_permission(...) -> Result<Response<CheckPermissionResponse>, Status>
}
```

#### **Auth Service REST Handlers** (`backend/auth-service/src/handlers/auth.rs`)

```rust
// REST 端點 (6 個 handlers)
pub async fn register(...)  // ✅ 也有 gRPC
pub async fn login(...)     // ✅ 也有 gRPC
pub async fn logout(...)    // ❌ 沒有 gRPC!
pub async fn refresh_token(...) // ✅ 也有 gRPC
pub async fn request_password_reset(...) // ❌ 沒有 gRPC!
pub async fn reset_password(...) // ❌ 沒有 gRPC!
```

### **關鍵問題**

| 功能 | REST Handler | gRPC Proto | gRPC 實現 | GraphQL Mutation | iOS 可用 |
|------|-------------|-----------|-----------|-----------------|---------|
| Register | ✅ | ✅ | ✅ | ✅ | ✅ |
| Login | ✅ | ✅ | ✅ | ✅ | ✅ |
| Logout | ✅ | ❌ | ❌ | ❌ | ❌ |
| Refresh Token | ✅ | ✅ | ✅ | ❌ | ❌ |
| Verify Email | ❌ | ❌ | ❌ | ❌ | ❌ |
| Request Password Reset | ✅ | ❌ | ❌ | ❌ | ❌ |
| Reset Password | ✅ | ❌ | ❌ | ❌ | ❌ |

**Linus 評價**:
> **"這是典型的架構不一致。Auth service 用 REST handlers 實現了完整功能,但沒有對應的 gRPC proto。GraphQL Gateway 只能調用 gRPC,所以這些功能對 iOS app 不可見。"**
>
> **"要麼把 REST handlers 遷移到 gRPC,要麼讓 GraphQL Gateway 支持直接調用 REST。前者更乾淨。"**

---

## 第三部分:GraphQL Gateway 集成分析

### **ServiceClients 實現** (`backend/graphql-gateway/src/clients.rs`)

```rust
pub struct ServiceClients {
    auth_channel: Arc<Channel>,      // ✅ 連接 auth-service:9083
    user_channel: Arc<Channel>,      // ✅ 連接 user-service:9080
    content_channel: Arc<Channel>,   // ✅ 連接 content-service:9081
    feed_channel: Arc<Channel>,      // ✅ 連接 feed-service:9084
}

impl ServiceClients {
    pub fn auth_client(&self) -> AuthServiceClient<Channel> { ... }
    pub fn user_client(&self) -> UserServiceClient<Channel> { ... }
    pub fn content_client(&self) -> ContentServiceClient<Channel> { ... }
    pub fn feed_client(&self) -> RecommendationServiceClient<Channel> { ... }
}
```

**已連接服務**: 4/16 (25%)

**未連接服務**:
- ❌ messaging-service - **最關鍵!** (私信、群聊)
- ❌ notification-service (推送通知)
- ❌ media-service (圖片、視頻上傳)
- ❌ search-service (搜索用戶、內容)
- ❌ cdn-service (CDN 加速)
- ❌ streaming-service (直播)
- ❌ 其他 9 個服務

### **GraphQL Schema 端點**

#### **AuthMutation** (`backend/graphql-gateway/src/schema/auth.rs`)

```rust
#[Object]
impl AuthMutation {
    async fn login(email, password) -> LoginResponse       // ✅ 已實現
    async fn register(email, password, username) -> RegisterResponse // ✅ 已實現
    // ❌ 以下全部缺失:
    // async fn logout() -> LogoutResponse
    // async fn refresh_token(refresh_token) -> RefreshTokenResponse
    // async fn verify_email(token) -> VerifyEmailResponse
    // async fn request_password_reset(email) -> PasswordResetResponse
    // async fn reset_password(token, password) -> ResetPasswordResponse
}
```

#### **UserMutation** (`backend/graphql-gateway/src/schema/user.rs`)

```rust
#[Object]
impl UserMutation {
    async fn follow_user(followee_id) -> Boolean  // ✅ 已實現
    // ❌ 缺少:
    // async fn unfollow_user(followee_id) -> Boolean
    // async fn update_profile(bio, avatar) -> UserProfile
    // async fn update_preferences(...) -> UserPreferences
}
```

#### **ContentMutation** (`backend/graphql-gateway/src/schema/content.rs`)

```rust
#[Object]
impl ContentMutation {
    async fn create_post(content) -> Post         // ✅ 已實現
    async fn delete_post(id) -> Boolean           // ✅ 已實現
    // ❌ 缺少:
    // async fn update_post(id, content) -> Post
    // async fn create_comment(post_id, content) -> Comment
    // async fn delete_comment(id) -> Boolean
    // async fn like_post(post_id) -> Boolean
    // async fn unlike_post(post_id) -> Boolean
}
```

### **缺失的整個模塊**

- ❌ **MessagingMutation** - 私信、群聊 (messaging-service 有 REST routes)
- ❌ **NotificationMutation** - 推送通知
- ❌ **MediaMutation** - 圖片/視頻上傳
- ❌ **SearchQuery** - 搜索功能

---

## 第四部分:架構問題總結

### **P0 架構問題**

#### 1. **Auth Service 架構分裂** (P0)

**問題**: 關鍵認證功能只有 REST,沒有 gRPC

```
logout()                 → REST only, 無 gRPC
request_password_reset() → REST only, 無 gRPC
reset_password()        → REST only, 無 gRPC
```

**影響**: iOS app 通過 GraphQL 無法調用這些功能

**解決方案**:
1. **選項 A (推薦)**: 添加 Proto 定義並實現 gRPC
   ```protobuf
   // 添加到 auth_service.proto
   rpc Logout(LogoutRequest) returns (LogoutResponse);
   rpc VerifyEmail(VerifyEmailRequest) returns (VerifyEmailResponse);
   rpc RequestPasswordReset(RequestPasswordResetRequest) returns (RequestPasswordResetResponse);
   rpc ResetPassword(ResetPasswordRequest) returns (ResetPasswordResponse);
   ```
   工作量: 4-6 小時

2. **選項 B**: GraphQL Gateway 直接調用 REST
   ```rust
   // 在 GraphQL resolver 中使用 HTTP client
   let response = reqwest::Client::new()
       .post("http://auth-service:8080/api/v1/auth/logout")
       .json(&body)
       .send()
       .await?;
   ```
   工作量: 2-3 小時 (但架構不一致)

---

#### 2. **Messaging Service 完全未集成** (P0)

**問題**: messaging-service 有 11 個 REST routes,但:
- ❌ GraphQL Gateway 沒有連接
- ❌ 沒有 MessagingMutation/MessagingQuery
- ❌ iOS app 無法發送私信

**REST Routes**:
```
POST   /messages               # 發送消息
GET    /messages/:id           # 獲取消息
GET    /conversations          # 獲取會話列表
POST   /conversations          # 創建會話
POST   /key-exchange/complete  # E2EE 密鑰交換
POST   /groups                 # 群聊管理
POST   /calls                  # 語音/視頻通話
WebSocket /ws                  # 實時消息
```

**解決方案**:

**選項 A (推薦)**: 添加 gRPC Proto
```protobuf
// messaging_service.proto
service MessagingService {
  rpc SendMessage(SendMessageRequest) returns (SendMessageResponse);
  rpc GetConversations(GetConversationsRequest) returns (GetConversationsResponse);
  rpc CreateConversation(CreateConversationRequest) returns (CreateConversationResponse);
  // ... 其他 RPC
}
```
然後在 GraphQL Gateway 添加:
```rust
pub struct MessagingMutation;

#[Object]
impl MessagingMutation {
    async fn send_message(&self, ctx: &Context<'_>, ...) -> Message { ... }
    async fn create_conversation(&self, ctx: &Context<'_>, ...) -> Conversation { ... }
}
```
工作量: 12-16 小時

**選項 B**: 保留 REST + WebSocket,GraphQL 只處理查詢
- GraphQL Query: 獲取會話列表、歷史消息
- REST + WebSocket: 實時消息發送/接收
工作量: 6-8 小時

---

#### 3. **空殼服務處理** (P1)

**問題**: 3 個服務只有 1 行代碼

```
communication-service → 1 line
social-service       → 1 line
identity-service     → 209 lines (但無實際功能)
```

**解決方案**:
1. **調查功能分布**: 確認這些功能是否在其他服務實現
   ```bash
   # 查找 likes/shares 實現
   grep -r "like\|favorite\|share" backend/content-service/src/handlers/
   ```

2. **決策**:
   - 如功能已在其他服務 → **刪除空殼**
   - 如功能確實缺失 → **實現或計劃實現**
   - 如 V2 重構中 → **完成遷移或回退 V1**

工作量: 2-4 小時調查 + 8-12 小時實現 (如需要)

---

#### 4. **Service Discovery 缺失** (P1)

**問題**: GraphQL Gateway hardcode 了服務地址

```rust
Self::new(
    "http://auth-service.nova-backend.svc.cluster.local:9083",  // Hardcoded
    "http://user-service.nova-backend.svc.cluster.local:9080",
    "http://content-service.nova-backend.svc.cluster.local:9081",
    "http://feed-service.nova-backend.svc.cluster.local:9084",
)
```

**解決方案**: 使用 Kubernetes Service 名稱解析 (已經在用)
- ✅ 當前設置已經正確 (Kubernetes DNS)
- ⚠️ 建議添加環境變量覆蓋

```rust
let auth_url = env::var("AUTH_SERVICE_URL")
    .unwrap_or_else(|_| "http://auth-service.nova-backend.svc.cluster.local:9083".to_string());
```

工作量: 1 小時

---

## 第五部分:修正後的實現路徑

### **Phase 1: 打通關鍵路徑** (1-2 天)

#### **Day 1: Auth 功能補全** (6-8h)

1. **添加 Auth Proto** (2-3h)
   ```protobuf
   rpc Logout(LogoutRequest) returns (LogoutResponse);
   rpc VerifyEmail(VerifyEmailRequest) returns (VerifyEmailResponse);
   rpc RequestPasswordReset(RequestPasswordResetRequest) returns (RequestPasswordResetResponse);
   rpc ResetPassword(ResetPasswordRequest) returns (ResetPasswordResponse);
   ```

2. **實現 gRPC handlers** (2-3h)
   - 將現有 REST handler 邏輯遷移到 gRPC

3. **GraphQL Schema 添加 mutations** (2-3h)
   ```rust
   async fn logout(&self, ctx: &Context<'_>) -> GraphQLResult<LogoutResponse>
   async fn refresh_token(&self, ctx: &Context<'_>, ...) -> GraphQLResult<RefreshTokenResponse>
   async fn verify_email(&self, ctx: &Context<'_>, ...) -> GraphQLResult<VerifyEmailResponse>
   async fn request_password_reset(&self, ctx: &Context<'_>, ...) -> GraphQLResult<...>
   async fn reset_password(&self, ctx: &Context<'_>, ...) -> GraphQLResult<...>
   ```

**結果**: iOS app 可以完整使用認證功能

---

#### **Day 2: Messaging 集成** (6-8h)

**選項 A (快速)**: GraphQL Query + REST/WebSocket
1. 添加 MessagingQuery (3-4h)
   ```rust
   async fn conversations(&self, ctx: &Context<'_>) -> Vec<Conversation>
   async fn messages(&self, ctx: &Context<'_>, conversation_id: String) -> Vec<Message>
   ```
   使用 HTTP client 調用 messaging-service REST API

2. iOS app 保留 REST + WebSocket 用於實時消息 (2-3h)

**選項 B (標準)**: 完整 gRPC + GraphQL
1. 添加 Messaging Proto (4-6h)
2. 實現 gRPC server (4-6h)
3. GraphQL Mutation + Query (4-6h)

**推薦**: 選項 A (快速),後續優化為選項 B

---

### **Phase 2: 完善核心功能** (3-4 天)

1. **User Mutations 補全** (4-6h)
   - unfollow_user
   - update_profile
   - update_preferences

2. **Content Mutations 補全** (6-8h)
   - update_post
   - create_comment, delete_comment
   - like_post, unlike_post

3. **調查空殼服務** (4-6h)
   - 確認 social-service 功能在哪裡
   - 決定刪除還是實現

4. **添加 Search/Notification Query** (8-10h)

---

### **Phase 3: 生產就緒** (3-5 天)

1. **mTLS 部署** (12-16h)
2. **gRPC 服務認證** (8-10h)
3. **全面測試** (8-12h)
4. **壓力測試** (6-8h)

---

## 第六部分:工作量重新評估

| 階段 | 任務 | 工作量 | 優先級 |
|------|------|--------|--------|
| **Phase 1** | Auth Proto + gRPC + GraphQL | 6-8h | P0 |
| | Messaging 快速集成 | 6-8h | P0 |
| **Phase 2** | User/Content Mutations | 10-14h | P1 |
| | 空殼服務調查 | 4-6h | P1 |
| | Search/Notification | 8-10h | P1 |
| **Phase 3** | mTLS | 12-16h | P0 |
| | gRPC 認證 | 8-10h | P0 |
| | 測試 | 14-20h | P0 |

**總計**: **68-92 小時** (約 9-12 個工作日)

**關鍵路徑**: Phase 1 (12-16h) → Phase 3 Security (20-26h) → Phase 2 (22-30h)

---

## 第七部分:Linus 式最終評語

> **"現在我看清楚了。這不是代碼質量問題,是架構演進問題。"**
>
> **"你有 5 個生產就緒的服務 (auth, user, content, messaging, feed),它們的實現是優秀的。問題是:"**
>
> **1. Auth service 用 REST 實現了 logout/passwordReset,但沒有 gRPC proto。GraphQL Gateway 只認 gRPC,所以這些功能對 iOS 不可見。**
>
> **2. Messaging service 有 11 個 REST routes 和完整的 E2EE,但 GraphQL Gateway 沒有連接它。iOS app 無法發私信。**
>
> **3. 你有 3 個空殼服務 (communication, social, identity),各只有 1 行代碼。這些可能是 V2 重構的遺留物。**
>
> **"解決方案很清楚:添加缺失的 Proto 定義,實現 gRPC handlers,在 GraphQL Gateway 暴露端點。這是 12-16 小時的工作。"**
>
> **"然後是安全層 (mTLS + 認證),這是 20-26 小時。總共 30-40 小時,約 4-5 個工作日。"**
>
> **"你的架構設計是正確的。只是實現還沒完成整合。"**

---

## 立即行動清單

### **今天 (Priority 0)**

1. ✅ **添加 Auth Proto 定義** (2h)
   - Logout, VerifyEmail, RequestPasswordReset, ResetPassword

2. ✅ **實現 Auth gRPC handlers** (2-3h)
   - 遷移現有 REST 邏輯

3. ✅ **GraphQL Auth Mutations** (2-3h)
   - 添加 5 個缺失的 mutations

### **明天 (Priority 1)**

4. ✅ **Messaging 快速集成** (6-8h)
   - 選項 A: GraphQL Query + REST
   - 連接 messaging-service

### **本週 (Priority 2)**

5. ✅ **調查空殼服務** (4h)
6. ✅ **User/Content Mutations** (10-14h)
7. ✅ **mTLS 部署** (12-16h)

---

**預計生產就緒**: **9-12 個工作日** (約 2 週)

**May the Force be with you.**
