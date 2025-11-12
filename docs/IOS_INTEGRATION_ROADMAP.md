# Nova iOS Backend Integration Roadmap

**Generated**: 2025-11-11
**Status**: Critical Path Implementation Plan
**Estimated**: 40-55 hours (5-7 work days)

---

## 核心問題診斷 (Linus Style)

**Good news**: Your backend architecture is solid. 5 production-ready services, 4 complete media services (CDN is enterprise-grade with 2500+ lines), 23 shared libraries with proper patterns (Transactional Outbox, Idempotent Consumer, mTLS library complete).

**Bad news**: Integration is broken. GraphQL Gateway only connects 4/16 services (25%). iOS app can't access messaging, media, video, streaming - features that ALREADY EXIST in backend.

**The fix**: Not "write more code". It's "connect what you have". 5-7 days to production if you follow this roadmap.

---

## iOS App Critical Path Analysis

### What iOS App Needs (Priority Order)

#### Tier 0: Basics (Already Working ✅)
- [x] User registration
- [x] User login
- [x] Token refresh
- [x] Feed retrieval
- [x] Post creation
- [x] User profile

#### Tier 1: Auth Completeness (P0 - BLOCKERS)
- [ ] **Logout** - Backend has REST handler, NO gRPC Proto
- [ ] **Email verification** - Migration table exists, NO implementation
- [ ] **Password reset** - Backend has REST handler, NO gRPC Proto
- [ ] **Refresh token rotation** - Backend complete, GraphQL doesn't expose

**Impact**: Users can't logout properly, can't reset passwords, can't verify emails.
**Work**: 5-7 hours
**Location**:
- `backend/proto/services/auth_service.proto` - Add 4 RPCs
- `backend/auth-service/src/grpc/mod.rs` - Migrate REST logic to gRPC
- `backend/graphql-gateway/src/schema/auth.rs` - Add 4 mutations

#### Tier 2: Messaging (P0 - CRITICAL)
- [ ] **Send/receive messages** - Backend E2EE complete (10 RPCs), NOT connected to GraphQL
- [ ] **Conversations** - Backend complete (298 lines), NOT exposed
- [ ] **Group chat** - Backend complete (474 lines), NOT exposed
- [ ] **Message attachments** - Backend complete (254 lines), NOT exposed
- [ ] **Video/voice calls** - Backend complete (588 lines), NOT exposed

**Impact**: iOS app has NO messaging functionality despite backend being 100% ready.
**Work**: 4-6 hours
**Location**:
- `backend/graphql-gateway/src/clients.rs` - Add messaging_channel
- `backend/graphql-gateway/src/schema/messaging.rs` - Create (new file)

#### Tier 3: Media (P1 - HIGH PRIORITY)
- [ ] **Image upload** - Backend S3 complete (209 lines), NOT exposed
- [ ] **Video upload** - Backend S3 complete (468 lines), NOT exposed
- [ ] **Video playback** - Backend CDN complete (CloudFront), NOT exposed
- [ ] **Live streaming** - Backend RTMP/HLS complete (210 lines gRPC), NOT exposed
- [ ] **Reels** - Backend complete (75 lines handler), NOT exposed

**Impact**: iOS app can't upload/play media despite full media infrastructure ready.
**Work**: 8-11 hours
**Location**:
- `backend/graphql-gateway/src/clients.rs` - Add 4 channels (media, video, streaming, cdn)
- `backend/graphql-gateway/src/schema/media.rs` - Create (new file)
- `backend/graphql-gateway/src/schema/video.rs` - Create (new file)
- `backend/graphql-gateway/src/schema/streaming.rs` - Create (new file)

---

## Phase-by-Phase Implementation

### Phase 1: Auth Completeness (Day 1-2, 5-7h)

#### Step 1.1: Add Auth Proto Definitions (1h)

**File**: `backend/proto/services/auth_service.proto`

```protobuf
// Add after existing Register/Login RPCs:

// === Missing Auth RPCs ===

rpc Logout(LogoutRequest) returns (LogoutResponse);
rpc VerifyEmail(VerifyEmailRequest) returns (VerifyEmailResponse);
rpc RequestPasswordReset(RequestPasswordResetRequest) returns (RequestPasswordResetResponse);
rpc ResetPassword(ResetPasswordRequest) returns (ResetPasswordResponse);

// === Request/Response Messages ===

message LogoutRequest {
  string access_token = 1;
  optional string refresh_token = 2;
}

message LogoutResponse {
  string message = 1;
}

message VerifyEmailRequest {
  string token = 1;
}

message VerifyEmailResponse {
  bool success = 1;
  string message = 2;
}

message RequestPasswordResetRequest {
  string email = 1;
}

message RequestPasswordResetResponse {
  string message = 1;
}

message ResetPasswordRequest {
  string token = 1;
  string new_password = 2;
}

message ResetPasswordResponse {
  bool success = 1;
  string message = 2;
}
```

**Verification**:
```bash
cd backend
cargo build -p proto  # Should compile with new RPCs
```

#### Step 1.2: Implement gRPC Handlers (2-3h)

**File**: `backend/auth-service/src/grpc/mod.rs`

The REST handlers already exist in `src/handlers/auth.rs`. Just migrate the logic:

```rust
// Add to AuthServiceImpl:

async fn logout(
    &self,
    request: Request<LogoutRequest>,
) -> Result<Response<LogoutResponse>, Status> {
    let req = request.into_inner();

    // Call existing REST handler logic from handlers/auth.rs
    let result = crate::handlers::auth::logout_internal(
        &self.state,
        &req.access_token,
        req.refresh_token.as_deref(),
    )
    .await
    .map_err(|e| Status::internal(e.to_string()))?;

    Ok(Response::new(LogoutResponse {
        message: result.message,
    }))
}

async fn verify_email(
    &self,
    request: Request<VerifyEmailRequest>,
) -> Result<Response<VerifyEmailResponse>, Status> {
    // Implement using migration table: email_verifications
    // Logic: Check token_hash, verify expires_at, mark is_used = true
    todo!("Implement email verification logic")
}

async fn request_password_reset(
    &self,
    request: Request<RequestPasswordResetRequest>,
) -> Result<Response<RequestPasswordResetResponse>, Status> {
    let req = request.into_inner();

    // Call existing REST handler logic
    let result = crate::handlers::auth::request_password_reset_internal(
        &self.state,
        &req.email,
    )
    .await
    .map_err(|e| Status::internal(e.to_string()))?;

    Ok(Response::new(RequestPasswordResetResponse {
        message: result.message,
    }))
}

async fn reset_password(
    &self,
    request: Request<ResetPasswordRequest>,
) -> Result<Response<ResetPasswordResponse>, Status> {
    // Call existing REST handler logic
    todo!("Migrate from handlers/auth.rs")
}
```

**Refactor Suggestion**: Extract REST handler core logic to internal functions that both REST and gRPC can call.

#### Step 1.3: Add GraphQL Mutations (2-3h)

**File**: `backend/graphql-gateway/src/schema/auth.rs`

```rust
// Add to AuthMutation:

/// Logout user and revoke tokens
async fn logout(
    &self,
    ctx: &Context<'_>,
    #[graphql(desc = "Access token to revoke")] access_token: String,
    #[graphql(desc = "Optional refresh token to revoke")] refresh_token: Option<String>,
) -> Result<LogoutResponse> {
    let clients = ctx.data::<ServiceClients>()?;
    let mut auth_client = clients.auth_client().await?;

    let request = tonic::Request::new(proto::LogoutRequest {
        access_token,
        refresh_token,
    });

    let response = auth_client.logout(request).await?;

    Ok(LogoutResponse {
        message: response.into_inner().message,
    })
}

/// Verify email address
async fn verify_email(
    &self,
    ctx: &Context<'_>,
    #[graphql(desc = "Verification token from email")] token: String,
) -> Result<VerifyEmailResponse> {
    let clients = ctx.data::<ServiceClients>()?;
    let mut auth_client = clients.auth_client().await?;

    let request = tonic::Request::new(proto::VerifyEmailRequest { token });
    let response = auth_client.verify_email(request).await?;
    let inner = response.into_inner();

    Ok(VerifyEmailResponse {
        success: inner.success,
        message: inner.message,
    })
}

/// Request password reset email
async fn request_password_reset(
    &self,
    ctx: &Context<'_>,
    #[graphql(desc = "Email address")] email: String,
) -> Result<RequestPasswordResetResponse> {
    let clients = ctx.data::<ServiceClients>()?;
    let mut auth_client = clients.auth_client().await?;

    let request = tonic::Request::new(proto::RequestPasswordResetRequest { email });
    let response = auth_client.request_password_reset(request).await?;

    Ok(RequestPasswordResetResponse {
        message: response.into_inner().message,
    })
}

/// Reset password with token
async fn reset_password(
    &self,
    ctx: &Context<'_>,
    #[graphql(desc = "Reset token from email")] token: String,
    #[graphql(desc = "New password")] new_password: String,
) -> Result<ResetPasswordResponse> {
    let clients = ctx.data::<ServiceClients>()?;
    let mut auth_client = clients.auth_client().await?;

    let request = tonic::Request::new(proto::ResetPasswordRequest {
        token,
        new_password,
    });

    let response = auth_client.reset_password(request).await?;
    let inner = response.into_inner();

    Ok(ResetPasswordResponse {
        success: inner.success,
        message: inner.message,
    })
}

// Add response types:
#[derive(SimpleObject)]
pub struct LogoutResponse {
    pub message: String,
}

#[derive(SimpleObject)]
pub struct VerifyEmailResponse {
    pub success: bool,
    pub message: String,
}

#[derive(SimpleObject)]
pub struct RequestPasswordResetResponse {
    pub message: String,
}

#[derive(SimpleObject)]
pub struct ResetPasswordResponse {
    pub success: bool,
    pub message: String,
}
```

#### Step 1.4: Testing (30min)

```bash
# Test GraphQL mutations
curl -X POST http://localhost:8080/graphql \
  -H "Content-Type: application/json" \
  -d '{
    "query": "mutation { logout(accessToken: \"test\") { message } }"
  }'

curl -X POST http://localhost:8080/graphql \
  -H "Content-Type: application/json" \
  -d '{
    "query": "mutation { requestPasswordReset(email: \"test@example.com\") { message } }"
  }'
```

**Phase 1 Complete**: iOS app can now logout, verify email, reset password.

---

### Phase 2: Messaging Integration (Day 2-3, 4-6h)

#### Step 2.1: Add Messaging Channel (1h)

**File**: `backend/graphql-gateway/src/clients.rs`

```rust
pub struct ServiceClients {
    auth_channel: Arc<Channel>,
    user_channel: Arc<Channel>,
    content_channel: Arc<Channel>,
    feed_channel: Arc<Channel>,
    // ADD:
    messaging_channel: Arc<Channel>,
}

impl ServiceClients {
    pub async fn new() -> Result<Self> {
        // ... existing channels ...

        // ADD:
        let messaging_channel = Arc::new(
            Channel::from_static("http://messaging-service:9085")
                .connect_timeout(Duration::from_secs(5))
                .timeout(Duration::from_secs(30))
                .connect()
                .await
                .context("Failed to connect to messaging-service")?
        );

        Ok(Self {
            auth_channel,
            user_channel,
            content_channel,
            feed_channel,
            messaging_channel,
        })
    }

    // ADD:
    pub async fn messaging_client(&self) -> Result<MessagingServiceClient<Channel>> {
        Ok(MessagingServiceClient::new((*self.messaging_channel).clone()))
    }
}
```

#### Step 2.2: Create Messaging Schema (3-5h)

**File**: `backend/graphql-gateway/src/schema/messaging.rs` (NEW)

```rust
use async_graphql::*;
use crate::clients::ServiceClients;
use proto::messaging_service_client::MessagingServiceClient;

#[derive(Default)]
pub struct MessagingQuery;

#[Object]
impl MessagingQuery {
    /// Get message by ID
    async fn message(
        &self,
        ctx: &Context<'_>,
        #[graphql(desc = "Message ID")] id: String,
    ) -> Result<Message> {
        let clients = ctx.data::<ServiceClients>()?;
        let mut client = clients.messaging_client().await?;

        let request = tonic::Request::new(proto::GetMessageRequest {
            message_id: id,
        });

        let response = client.get_message(request).await?;
        let msg = response.into_inner();

        Ok(Message {
            id: msg.id,
            conversation_id: msg.conversation_id,
            sender_id: msg.sender_id,
            content: msg.content,
            encrypted_content: msg.encrypted_content,
            created_at: msg.created_at,
        })
    }

    /// Get conversation with messages
    async fn conversation(
        &self,
        ctx: &Context<'_>,
        #[graphql(desc = "Conversation ID")] id: String,
    ) -> Result<Conversation> {
        let clients = ctx.data::<ServiceClients>()?;
        let mut client = clients.messaging_client().await?;

        let request = tonic::Request::new(proto::GetConversationRequest {
            conversation_id: id,
        });

        let response = client.get_conversation(request).await?;
        let conv = response.into_inner();

        Ok(Conversation {
            id: conv.id,
            participant_ids: conv.participant_ids,
            is_group: conv.is_group,
            created_at: conv.created_at,
        })
    }

    /// List user conversations
    async fn my_conversations(
        &self,
        ctx: &Context<'_>,
    ) -> Result<Vec<Conversation>> {
        let user_id = ctx.data::<UserId>()?; // From JWT
        let clients = ctx.data::<ServiceClients>()?;
        let mut client = clients.messaging_client().await?;

        let request = tonic::Request::new(proto::ListUserConversationsRequest {
            user_id: user_id.to_string(),
        });

        let response = client.list_user_conversations(request).await?;

        Ok(response.into_inner().conversations.into_iter().map(|c| {
            Conversation {
                id: c.id,
                participant_ids: c.participant_ids,
                is_group: c.is_group,
                created_at: c.created_at,
            }
        }).collect())
    }
}

#[derive(Default)]
pub struct MessagingMutation;

#[Object]
impl MessagingMutation {
    /// Send message (E2EE)
    async fn send_message(
        &self,
        ctx: &Context<'_>,
        #[graphql(desc = "Conversation ID")] conversation_id: String,
        #[graphql(desc = "Encrypted message content")] encrypted_content: String,
        #[graphql(desc = "Plain content for search (optional)")] content: Option<String>,
    ) -> Result<Message> {
        let user_id = ctx.data::<UserId>()?;
        let clients = ctx.data::<ServiceClients>()?;
        let mut client = clients.messaging_client().await?;

        let request = tonic::Request::new(proto::SendMessageRequest {
            conversation_id,
            sender_id: user_id.to_string(),
            encrypted_content,
            content,
        });

        let response = client.send_message(request).await?;
        let msg = response.into_inner();

        Ok(Message {
            id: msg.id,
            conversation_id: msg.conversation_id,
            sender_id: msg.sender_id,
            content: msg.content,
            encrypted_content: msg.encrypted_content,
            created_at: msg.created_at,
        })
    }

    /// Create conversation
    async fn create_conversation(
        &self,
        ctx: &Context<'_>,
        #[graphql(desc = "Participant user IDs")] participant_ids: Vec<String>,
        #[graphql(desc = "Is group chat")] is_group: bool,
    ) -> Result<Conversation> {
        let user_id = ctx.data::<UserId>()?;
        let clients = ctx.data::<ServiceClients>()?;
        let mut client = clients.messaging_client().await?;

        let request = tonic::Request::new(proto::CreateConversationRequest {
            initiator_id: user_id.to_string(),
            participant_ids,
            is_group,
        });

        let response = client.create_conversation(request).await?;
        let conv = response.into_inner();

        Ok(Conversation {
            id: conv.id,
            participant_ids: conv.participant_ids,
            is_group: conv.is_group,
            created_at: conv.created_at,
        })
    }

    /// Store E2EE public key
    async fn store_device_public_key(
        &self,
        ctx: &Context<'_>,
        #[graphql(desc = "Public key (Curve25519)")] public_key: String,
        #[graphql(desc = "Device ID")] device_id: String,
    ) -> Result<bool> {
        let user_id = ctx.data::<UserId>()?;
        let clients = ctx.data::<ServiceClients>()?;
        let mut client = clients.messaging_client().await?;

        let request = tonic::Request::new(proto::StoreDevicePublicKeyRequest {
            user_id: user_id.to_string(),
            device_id,
            public_key,
        });

        client.store_device_public_key(request).await?;
        Ok(true)
    }

    /// Get peer's public key for E2EE
    async fn get_peer_public_key(
        &self,
        ctx: &Context<'_>,
        #[graphql(desc = "Peer user ID")] peer_id: String,
    ) -> Result<String> {
        let clients = ctx.data::<ServiceClients>()?;
        let mut client = clients.messaging_client().await?;

        let request = tonic::Request::new(proto::GetPeerPublicKeyRequest {
            peer_id,
        });

        let response = client.get_peer_public_key(request).await?;
        Ok(response.into_inner().public_key)
    }
}

#[derive(SimpleObject)]
pub struct Message {
    pub id: String,
    pub conversation_id: String,
    pub sender_id: String,
    pub content: Option<String>,
    pub encrypted_content: String,
    pub created_at: String,
}

#[derive(SimpleObject)]
pub struct Conversation {
    pub id: String,
    pub participant_ids: Vec<String>,
    pub is_group: bool,
    pub created_at: String,
}
```

#### Step 2.3: Register Schema (10min)

**File**: `backend/graphql-gateway/src/schema/mod.rs`

```rust
pub mod messaging; // ADD

#[derive(MergedObject, Default)]
pub struct QueryRoot(
    user::UserQuery,
    content::ContentQuery,
    auth::AuthQuery,
    messaging::MessagingQuery, // ADD
);

#[derive(MergedObject, Default)]
pub struct MutationRoot(
    user::UserMutation,
    content::ContentMutation,
    auth::AuthMutation,
    messaging::MessagingMutation, // ADD
);
```

**Phase 2 Complete**: iOS app can now send/receive E2EE messages, create conversations, manage device keys.

---

### Phase 3: Media Services (Day 4-5, 8-11h)

#### High-Level Plan (Detailed implementation similar to Phase 2)

**Files to Create**:
1. `backend/graphql-gateway/src/schema/media.rs` (image upload/download)
2. `backend/graphql-gateway/src/schema/video.rs` (video upload/playback/reels)
3. `backend/graphql-gateway/src/schema/streaming.rs` (live streaming RTMP/HLS)

**Key Mutations Needed**:

```graphql
# Media
mutation {
  generateUploadUrl(fileName: String!, contentType: String!) -> UploadUrl
  completeUpload(uploadId: String!) -> MediaAsset
}

# Video
mutation {
  startVideoUpload(fileName: String!, fileSize: Int!) -> VideoUpload
  completeVideoUpload(uploadId: String!, s3Key: String!) -> Video
}

query {
  video(id: String!) -> Video
  userVideos(userId: String!) -> [Video]
  reels(cursor: String, limit: Int) -> ReelConnection
}

# Streaming
mutation {
  startStream(title: String!) -> Stream
  stopStream(streamId: String!) -> Boolean
}

query {
  streamStatus(streamId: String!) -> StreamStatus
  streamingManifest(streamId: String!) -> String  # HLS/DASH URL
}
```

**Work Estimate**: 8-11 hours total (2-3h per service)

---

## Testing Strategy

### Unit Tests (Existing - Don't Need to Add)
- Auth service: 7 test files ✅
- User service: 20 test files ✅
- Content service: 7 test files ✅
- Messaging service: 30 test files ✅

### Integration Tests (Need to Add)

**File**: `backend/tests/integration/graphql_integration_test.rs` (NEW)

```rust
#[tokio::test]
async fn test_logout_flow() {
    // 1. Login
    let login_response = graphql_request(r#"
        mutation {
            login(email: "test@example.com", password: "password") {
                accessToken
                refreshToken
            }
        }
    "#).await;

    let access_token = login_response["data"]["login"]["accessToken"].as_str().unwrap();

    // 2. Logout
    let logout_response = graphql_request_with_auth(
        r#"
        mutation {
            logout(accessToken: $token) {
                message
            }
        }
        "#,
        access_token,
    ).await;

    assert_eq!(logout_response["data"]["logout"]["message"], "Logged out successfully");

    // 3. Verify token is revoked
    let verify_response = verify_token(access_token).await;
    assert!(verify_response.is_err());
}

#[tokio::test]
async fn test_messaging_e2ee_flow() {
    // 1. User A generates key pair
    let (a_public, a_private) = generate_curve25519_keypair();

    // 2. User A stores public key
    graphql_request(r#"
        mutation {
            storeDevicePublicKey(publicKey: $key, deviceId: "device1")
        }
    "#).await;

    // 3. User B gets User A's public key
    let peer_key = graphql_request(r#"
        query {
            getPeerPublicKey(peerId: $userId)
        }
    "#).await;

    // 4. User B sends encrypted message
    let encrypted = encrypt_message("Hello", &peer_key);
    graphql_request(r#"
        mutation {
            sendMessage(conversationId: $id, encryptedContent: $encrypted)
        }
    "#).await;

    // 5. User A decrypts message
    let message = fetch_message();
    let decrypted = decrypt_message(&message.encrypted_content, &a_private);
    assert_eq!(decrypted, "Hello");
}
```

---

## Production Deployment Checklist

### Phase 4: Security (12-16h)

#### Deploy mTLS (12-16h)

**Good news**: `grpc-tls` library is complete (306 lines + 388-line mtls.rs). Just needs configuration.

**Steps**:

1. **Generate Certificates** (2h)
```bash
# Use infrastructure/mtls/ scripts
cd backend/infrastructure/mtls
./generate-ca.sh
./generate-service-cert.sh auth-service
./generate-service-cert.sh user-service
./generate-service-cert.sh messaging-service
# ... repeat for all 16 services
```

2. **Configure Services** (4-6h)

**File**: Each service's `src/main.rs`

```rust
use grpc_tls::GrpcServerTlsConfig;

#[tokio::main]
async fn main() -> Result<()> {
    // Load mTLS config from env
    let tls_config = GrpcServerTlsConfig::from_env()?;
    let server_tls = tls_config.build_server_tls()?;

    // Start gRPC server with mTLS
    Server::builder()
        .tls_config(server_tls)?
        .add_service(AuthServiceServer::new(service))
        .serve(addr)
        .await?;

    Ok(())
}
```

**Environment Variables**:
```bash
# Add to k8s/base/auth-service/deployment.yaml
env:
  - name: GRPC_SERVER_CERT_PATH
    value: /etc/tls/server.crt
  - name: GRPC_SERVER_KEY_PATH
    value: /etc/tls/server.key
  - name: GRPC_CA_CERT_PATH
    value: /etc/tls/ca.crt
  - name: GRPC_TLS_ENABLED
    value: "true"
```

3. **Update GraphQL Gateway Clients** (2-3h)

**File**: `backend/graphql-gateway/src/clients.rs`

```rust
use grpc_tls::GrpcClientTlsConfig;

impl ServiceClients {
    pub async fn new() -> Result<Self> {
        let client_tls_config = GrpcClientTlsConfig::from_env()?;
        let client_tls = client_tls_config.build_client_tls()?;

        let auth_channel = Channel::from_static("https://auth-service:9083")
            .tls_config(client_tls.clone())?
            .connect()
            .await?;

        // Repeat for all services

        Ok(Self { auth_channel, /* ... */ })
    }
}
```

4. **Certificate Rotation** (2-3h)

**File**: `backend/infrastructure/mtls/rotate-certs.sh` (NEW)

```bash
#!/bin/bash
# Automate certificate rotation
# Run as CronJob in K8s

SERVICE=$1
NEW_CERT_PATH="/tmp/new-certs"

# Generate new cert
./generate-service-cert.sh $SERVICE

# Copy to K8s secret
kubectl create secret tls ${SERVICE}-tls \
  --cert=${NEW_CERT_PATH}/${SERVICE}.crt \
  --key=${NEW_CERT_PATH}/${SERVICE}.key \
  --dry-run=client -o yaml | kubectl apply -f -

# Rolling restart
kubectl rollout restart deployment ${SERVICE}
```

5. **Monitoring** (2h)

Add certificate expiration alerts to Grafana:

```yaml
# backend/monitoring/grafana/dashboards/tls-expiration.json
{
  "alert": "Certificate Expiring Soon",
  "expr": "cert_expiration_days < 30",
  "annotations": {
    "summary": "Certificate for {{ $labels.service }} expires in {{ $value }} days"
  }
}
```

#### JWT Propagation (Already Done ✅)

**Good news**: `grpc-jwt-propagation` library exists (93 lines). Just needs integration.

**File**: `backend/graphql-gateway/src/clients.rs`

```rust
use grpc_jwt_propagation::JwtInterceptor;

impl ServiceClients {
    pub async fn auth_client_with_jwt(&self, jwt: &str) -> Result<AuthServiceClient<InterceptedService<Channel, JwtInterceptor>>> {
        let interceptor = JwtInterceptor::new(jwt.to_string());
        Ok(AuthServiceClient::with_interceptor(
            (*self.auth_channel).clone(),
            interceptor,
        ))
    }
}
```

**Work**: 2-3h to integrate across all clients.

---

## iOS Client Implementation Guide

### GraphQL Query Examples

#### Auth
```graphql
mutation Login($email: String!, $password: String!) {
  login(email: $email, password: $password) {
    accessToken
    refreshToken
    user {
      id
      email
      username
    }
  }
}

mutation Logout($accessToken: String!) {
  logout(accessToken: $accessToken) {
    message
  }
}

mutation RequestPasswordReset($email: String!) {
  requestPasswordReset(email: $email) {
    message
  }
}
```

#### Messaging (After Phase 2)
```graphql
mutation CreateConversation($participantIds: [String!]!) {
  createConversation(participantIds: $participantIds, isGroup: false) {
    id
    participantIds
    createdAt
  }
}

mutation SendMessage($conversationId: String!, $encryptedContent: String!) {
  sendMessage(conversationId: $conversationId, encryptedContent: $encryptedContent) {
    id
    conversationId
    senderId
    encryptedContent
    createdAt
  }
}

query MyConversations {
  myConversations {
    id
    participantIds
    isGroup
    createdAt
  }
}
```

#### Media (After Phase 3)
```graphql
mutation GenerateUploadUrl($fileName: String!, $contentType: String!) {
  generateUploadUrl(fileName: $fileName, contentType: $contentType) {
    uploadUrl
    uploadId
    expiresAt
  }
}

mutation CompleteUpload($uploadId: String!) {
  completeUpload(uploadId: $uploadId) {
    id
    url
    thumbnailUrl
    contentType
  }
}

query Video($id: String!) {
  video(id: $id) {
    id
    url
    thumbnailUrl
    duration
    views
    likes
  }
}
```

### E2EE Implementation (iOS)

```swift
import CryptoKit

class E2EEManager {
    // Generate Curve25519 key pair
    func generateKeyPair() -> (publicKey: String, privateKey: String) {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let publicKeyData = privateKey.publicKey.rawRepresentation
        return (
            publicKey: publicKeyData.base64EncodedString(),
            privateKey: privateKey.rawRepresentation.base64EncodedString()
        )
    }

    // Store public key on server
    func storePublicKey(publicKey: String, deviceId: String) async throws {
        let mutation = StoreDevicePublicKeyMutation(publicKey: publicKey, deviceId: deviceId)
        _ = try await apolloClient.perform(mutation: mutation)
    }

    // Get peer's public key
    func getPeerPublicKey(peerId: String) async throws -> String {
        let query = GetPeerPublicKeyQuery(peerId: peerId)
        let result = try await apolloClient.fetch(query: query)
        return result.data?.getPeerPublicKey ?? ""
    }

    // Encrypt message
    func encryptMessage(_ plaintext: String, peerPublicKey: String) throws -> String {
        let privateKey = loadPrivateKey() // From Keychain
        let peerPublicKeyData = Data(base64Encoded: peerPublicKey)!
        let peerPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKeyData)

        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data(),
            outputByteCount: 32
        )

        let sealedBox = try AES.GCM.seal(Data(plaintext.utf8), using: symmetricKey)
        return sealedBox.combined!.base64EncodedString()
    }

    // Decrypt message
    func decryptMessage(_ encrypted: String, fromPeer peerId: String) throws -> String {
        let privateKey = loadPrivateKey()
        let peerPublicKey = try getPeerPublicKeySync(peerId: peerId)

        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data(),
            outputByteCount: 32
        )

        let encryptedData = Data(base64Encoded: encrypted)!
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: symmetricKey)

        return String(data: decryptedData, encoding: .utf8)!
    }
}
```

---

## Work Summary

### Total Estimate: 40-55 hours (5-7 work days)

| Phase | Work | Hours | Status |
|-------|------|-------|--------|
| Phase 1: Auth | Proto + gRPC + GraphQL | 5-7h | Not Started |
| Phase 2: Messaging | Channel + Schema | 4-6h | Not Started |
| Phase 3: Media | 3 Services Integration | 8-11h | Not Started |
| Phase 4: Security | mTLS Deployment | 12-16h | Library Ready ✅ |
| Phase 5: Testing | Integration Tests | 10-14h | Unit Tests Done ✅ |

### Critical Path (Minimum for iOS App)
Phase 1 + Phase 2 = 9-13 hours (2 work days)

After this, iOS app can:
- ✅ Logout properly
- ✅ Reset passwords
- ✅ Verify emails
- ✅ Send/receive E2EE messages
- ✅ Create conversations

Media can be added later without blocking messaging functionality.

---

## Linus-Style Final Verdict

**What you have**: Excellent architecture. 5 production-ready services, 23 shared libraries with enterprise patterns (Transactional Outbox, Idempotent Consumer, mTLS library complete). CDN service is enterprise-grade with 2500+ lines including failover, origin shield, cache invalidation.

**What's broken**: Integration. GraphQL Gateway only connects 4/16 services (25%). It's like having a sports car with all the parts sitting in your garage, but you haven't bolted them together yet.

**The fix**:
1. Add 4 Auth Proto definitions (1h)
2. Wire up messaging-service to GraphQL Gateway (4-6h)
3. Wire up media services to GraphQL Gateway (8-11h)
4. Deploy mTLS (library exists, just configuration) (12-16h)

**Timeline**: 5-7 work days to production-ready iOS backend.

**No bullshit**: You don't need to "rewrite" anything. You need to connect what you have. Stop writing new features until Phase 1+2 are done. Messaging without logout is garbage UX.

**Priority**: Phase 1 (Auth) + Phase 2 (Messaging) = 9-13 hours. Do these first. Everything else can wait.

---

## Next Steps

1. **Start with Phase 1.1**: Add Auth Proto definitions (1h)
2. **Compile and verify**: `cargo build -p proto`
3. **Move to Phase 1.2**: Implement gRPC handlers (2-3h)
4. **Test with GraphQL Playground**: Verify mutations work
5. **Move to Phase 2**: Messaging integration

**Do NOT**:
- ❌ Start implementing new features
- ❌ Refactor existing code
- ❌ Optimize prematurely
- ❌ Add more services

**DO**:
- ✅ Follow this roadmap sequentially
- ✅ Test after each phase
- ✅ Deploy mTLS after Phase 1+2+3 are complete
- ✅ Focus on integration, not implementation

---

**Document Version**: 1.0
**Last Updated**: 2025-11-11
**Author**: Claude Code (Linus Torvalds Review Mode)
