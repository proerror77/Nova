# Nova Backend Comprehensive Service Restructure

**Generated**: 2025-11-11
**Purpose**: Complete service boundary redesign to eliminate ALL overlaps
**Impact**: 16 services → 10 clean services

---

## Critical Discovery: Multiple Overlapping Layers

你說得對!我發現了**三層重疊**:

### Layer 1: Auth 三重重疊 ❌

**auth-service** (419 lines):
- Dependencies: `argon2`, `jsonwebtoken`
- Functions: register, login, logout, password_reset
- Database: `record_successful_login`, `record_failed_login`

**user-service** (1205 lines):
- Dependencies: `argon2.workspace`, `jsonwebtoken.workspace` ❌ 重複!
- Database: `record_successful_login`, `record_failed_login` ❌ 重複!
- Tests: `legacy_auth_tests` feature flag ❌ 歷史遺留

**identity-service V2** (209 lines):
- Dependencies: `argon2 = "0.5"`, `jsonwebtoken = "9.3"` ❌ 再次重複!
- Design: AuthenticationService, SessionService, TokenService
- Status: 空殼但架構完整

**結論**: auth邏輯分散在3個服務中!

---

### Layer 2: Media 三重重疊 ❌

**media-service** (303 lines main + 650 lines gRPC):
- Models: `Video`, `VideoResponse`, `Reel`, `ReelVariant`
- Dependencies: `aws-sdk-s3 = "1.9"`, `image = "0.24"`
- Handlers: uploads.rs (209 lines), videos.rs (128 lines), reels.rs (75 lines)

**video-service** (57 lines main + 468 lines S3 service):
- Models: `UploadVideoPayload`, `TranscodeVideoPayload`, `VideoMetadataResponse`
- Dependencies: `aws-sdk-s3 = "1.11"` ❌ 重複!
- Library: `video-core` (38 lines shared lib)

**streaming-service** (228 lines main + 210 lines gRPC):
- Models: `StreamingConfig`, `StreamListQuery`, `StreamCommentPayload`
- Features: RTMP, HLS/DASH, live chat, WebSocket
- Total code: 8362 lines (最大)

**結論**: Video概念出現在3個服務中,S3 SDK重複3次!

---

### Layer 3: User Profile 功能分散 ❌

**user-service** (1205 lines):
- 包含: profiles, relationships, preferences, moderation
- 但也有: `argon2`, `jsonwebtoken` (應該在auth-service)
- 但也有: `aws-sdk-s3`, Neo4j (社交圖譜)
- 但也有: `post_share_repo.rs` (應該在social-service)
- 禁用測試: `legacy_video_tests`, `legacy_auth_tests`, `legacy_posts_tests`

**結論**: user-service是個"垃圾桶服務",什麼都有!

---

## Root Cause Analysis (Linus Style)

**問題根源**: "微服務拆分太快,沒想清楚邊界"

典型錯誤模式:
1. **Feature creep**: 開發時方便,把功能加到"最近的服務"
2. **Copy-paste**: 多個服務需要同樣功能,直接複製依賴
3. **歷史遺留**: 功能遷移後,舊代碼沒刪乾淨

**證據**:
```toml
# user-service/Cargo.toml line 185-244
# Phase 6: Video System Tests - DISABLED (migrated to media-service)
# All video-related tests below are disabled as video processing moved to media-service
```

Video功能已遷移到media-service,但user-service還保留了video測試框架和依賴!

---

## Proposed Clean Architecture

### 核心原則

1. **單一職責**: 每個服務只做一件事
2. **無重疊依賴**: 不允許兩個服務有相同的核心依賴(如argon2, aws-sdk-s3)
3. **清晰邊界**: Domain concepts不能跨服務重複(如Video, Like, Session)

---

## Final Service Architecture (10 Services)

### Tier 1: Identity & Access (1 service)

#### **identity-service** (Unified Auth)

**Responsibility**:
- Authentication (register, login, logout)
- Authorization (JWT, token management)
- Session management
- OAuth (Google, Apple, Facebook)

**Consolidates**:
- ✅ auth-service (完整遷移)
- ✅ identity-service V2 (實現空殼架構)
- ❌ user-service auth功能 (刪除argon2, jsonwebtoken依賴)

**Key Dependencies**:
- `argon2` ✅ (ONLY here)
- `jsonwebtoken` ✅ (ONLY here)
- `crypto-core` (shared lib)
- `grpc-tls` (mTLS)
- `aws-secrets` (secret management)

**Database Tables**:
- `users` (id, email, username, password_hash)
- `sessions` (id, user_id, device_id, expires_at)
- `token_revocations` (id, token_hash, expires_at)
- `oauth_tokens` (id, user_id, provider, access_token)

**gRPC Methods**:
```protobuf
service IdentityService {
  rpc Register(RegisterRequest) returns (RegisterResponse);
  rpc Login(LoginRequest) returns (LoginResponse);
  rpc Logout(LogoutRequest) returns (LogoutResponse);
  rpc RefreshToken(RefreshTokenRequest) returns (RefreshTokenResponse);
  rpc VerifyEmail(VerifyEmailRequest) returns (VerifyEmailResponse);
  rpc RequestPasswordReset(RequestPasswordResetRequest) returns (RequestPasswordResetResponse);
  rpc ResetPassword(ResetPasswordRequest) returns (ResetPasswordResponse);
  rpc OAuthLogin(OAuthLoginRequest) returns (OAuthLoginResponse);
  rpc ValidateToken(ValidateTokenRequest) returns (ValidateTokenResponse);
  rpc GetUserSessions(GetUserSessionsRequest) returns (GetUserSessionsResponse);
  rpc RevokeSession(RevokeSessionRequest) returns (RevokeSessionResponse);
}
```

**Port**: 9090

---

### Tier 2: User & Social (2 services)

#### **user-service** (Clean User Profiles)

**Responsibility**:
- User profiles (avatar, bio, settings)
- Relationships (follow/unfollow)
- Preferences (notification settings, privacy)
- Moderation (block, report)

**REMOVE from current user-service**:
- ❌ `argon2`, `jsonwebtoken` (移到identity-service)
- ❌ `post_share_repo.rs` (移到social-service)
- ❌ `aws-sdk-s3` (avatar upload用media-service)
- ❌ Video相關測試 (已遷移)
- ❌ Auth相關測試 (已遷移)

**KEEP**:
- ✅ Neo4j (social graph)
- ✅ Relationships (follows)
- ✅ User preferences
- ✅ Moderation

**Database Tables**:
- `user_profiles` (user_id, avatar_url, bio, location)
- `relationships` (follower_id, followee_id, created_at)
- `user_preferences` (user_id, notification_enabled, privacy_level)
- `blocked_users` (blocker_id, blocked_id)

**Port**: 9080

---

#### **social-service** (Social Interactions)

**Responsibility**:
- Likes (posts, comments)
- Comments (create, reply, nested)
- Shares (posts to other platforms)
- Tags (user tags in content)
- Mentions (@ mentions)

**Consolidates**:
- ✅ content-service likes/comments (遷移)
- ✅ user-service post_share_repo.rs (遷移)

**Database Tables**:
- `likes` (id, post_id, user_id, created_at)
- `comments` (id, post_id, user_id, content, parent_comment_id)
- `shares` (id, post_id, user_id, share_via, shared_at)
- `tags` (id, object_id, object_type, user_id, tagged_by)
- `mentions` (id, object_id, mentioned_user_id, mentioned_by)

**Port**: 9091

---

### Tier 3: Content (2 services)

#### **content-service** (Clean Content)

**Responsibility**:
- Posts (create, read, update, delete)
- Stories (24-hour content)
- Feed generation (timeline algorithm)

**REMOVE**:
- ❌ `db/like_repo.rs` (移到social-service)
- ❌ `db/comment_repo.rs` (移到social-service)
- ❌ Like/Comment gRPC methods (移到social-service)

**KEEP**:
- ✅ Posts CRUD
- ✅ Stories CRUD
- ✅ Feed algorithm (ClickHouse)

**Port**: 9081

---

#### **feed-service** (Recommendations)

**Responsibility**:
- Personalized feed ranking
- Trending posts
- Discover (explore)
- ClickHouse analytics

**Port**: 9084 (不變)

---

### Tier 4: Media (1 unified service)

#### **media-service** (Unified Media Processing)

**Responsibility**:
- Image upload/processing
- Video upload/transcoding
- Reels (short videos)
- Live streaming (RTMP/HLS)
- S3 storage management
- CloudFront CDN

**Consolidates**:
- ✅ media-service (images + videos + reels)
- ✅ video-service (S3 service + transcoding)
- ✅ streaming-service (live streaming)
- ❌ cdn-service → 功能合併到media-service

**Why consolidate?**:
1. **All use S3**: 3個服務都有`aws-sdk-s3`,重複依賴
2. **同一個domain**: "Media"概念包含image, video, live streaming
3. **共享基礎設施**: 都需要transcoding, storage, CDN
4. **Simpler operations**: 1個服務部署/監控,而不是3個

**Key Dependencies**:
- `aws-sdk-s3` ✅ (ONLY here for media upload)
- `image = "0.24"` (image processing)
- `video-core` (shared lib)
- FFmpeg (transcoding - external)

**Modules**:
```
media-service/
├── src/
│   ├── modules/
│   │   ├── images/      (from old media-service)
│   │   ├── videos/      (from old video-service + media-service)
│   │   ├── reels/       (from old media-service)
│   │   ├── streaming/   (from old streaming-service)
│   │   └── cdn/         (from old cdn-service)
│   ├── services/
│   │   ├── s3_service.rs          (unified S3 operations)
│   │   ├── transcoding_service.rs (video processing)
│   │   ├── streaming_manifest.rs  (HLS/DASH generation)
│   │   └── cdn_manager.rs         (CloudFront management)
```

**Database Tables**:
- `media_assets` (id, user_id, type, s3_key, url, metadata)
- `videos` (id, media_asset_id, duration, resolution, codec)
- `reels` (id, media_asset_id, thumbnail_url)
- `live_streams` (id, user_id, status, rtmp_url, hls_url)
- `transcode_jobs` (id, video_id, status, progress)

**gRPC Methods**:
```protobuf
service MediaService {
  // Images
  rpc UploadImage(UploadImageRequest) returns (UploadImageResponse);
  rpc GetImage(GetImageRequest) returns (GetImageResponse);

  // Videos
  rpc UploadVideo(UploadVideoRequest) returns (UploadVideoResponse);
  rpc GetVideo(GetVideoRequest) returns (GetVideoResponse);
  rpc TranscodeVideo(TranscodeVideoRequest) returns (TranscodeVideoResponse);

  // Reels
  rpc CreateReel(CreateReelRequest) returns (CreateReelResponse);
  rpc ListReels(ListReelsRequest) returns (ListReelsResponse);

  // Live Streaming
  rpc StartStream(StartStreamRequest) returns (StartStreamResponse);
  rpc StopStream(StopStreamRequest) returns (StopStreamResponse);
  rpc GetStreamStatus(GetStreamStatusRequest) returns (GetStreamStatusResponse);
  rpc GetStreamingManifest(GetStreamingManifestRequest) returns (GetStreamingManifestResponse);

  // CDN
  rpc GenerateSignedUrl(GenerateSignedUrlRequest) returns (GenerateSignedUrlResponse);
  rpc InvalidateCdnCache(InvalidateCdnCacheRequest) returns (InvalidateCdnCacheResponse);
}
```

**Port**: 9085

---

### Tier 5: Communication (1 unified service)

#### **communication-service** (Unified Communications)

**Responsibility**:
- E2EE messaging
- Push notifications (FCM, APNs)
- WebSocket real-time
- Email sending
- SMS (future)
- Event bus (Kafka)

**Consolidates**:
- ✅ messaging-service (E2EE + conversations)
- ✅ notification-service (FCM + APNs + WebSocket)
- ✅ events-service (Kafka event processing)

**Port**: 9092

---

### Tier 6: Infrastructure (3 services)

#### **search-service** (Full-text Search)

**Responsibility**: Elasticsearch/PostgreSQL full-text search

**Port**: 9086 (不變)

---

#### **graphql-gateway** (API Gateway)

**Responsibility**: Unified GraphQL API for iOS/Web

**Connects to**:
1. identity-service (auth)
2. user-service (profiles)
3. social-service (likes/comments)
4. content-service (posts)
5. feed-service (recommendations)
6. media-service (upload/streaming)
7. communication-service (messaging)
8. search-service (search)

**Port**: 8080 (不變)

---

#### **analytics-service** (Optional - Future)

**Responsibility**:
- User behavior tracking
- Business intelligence
- ClickHouse queries

**Note**: Currently ClickHouse是embedded在feed-service和streaming-service中,可以考慮未來統一。

---

## Service Comparison Matrix

| Service | Before | After | Change | Reason |
|---------|--------|-------|--------|--------|
| **auth-service** | ✅ Active | ❌ Deleted | → identity-service | Consolidate auth |
| **identity-service** | 🔲 Empty | ✅ Unified Auth | Implement | DDD architecture ready |
| **user-service** | ✅ Bloated | ✅ Clean Profiles | Slim down | Remove auth/media/social |
| **social-service** | 🔲 Empty | ✅ Social Interactions | Implement | Extract from content/user |
| **content-service** | ✅ Active | ✅ Clean Content | Slim down | Remove likes/comments |
| **feed-service** | ✅ Active | ✅ Keep | No change | Already clean |
| **media-service** | ✅ Active | ✅ Unified Media | Expand | Merge video/streaming/cdn |
| **video-service** | ✅ Active | ❌ Deleted | → media-service | Consolidate media |
| **streaming-service** | ✅ Active | ❌ Deleted | → media-service | Consolidate media |
| **cdn-service** | ✅ Active | ❌ Deleted | → media-service | Consolidate media |
| **messaging-service** | ✅ Active | ❌ Deleted | → communication-service | Consolidate comms |
| **notification-service** | ✅ Active | ❌ Deleted | → communication-service | Consolidate comms |
| **events-service** | 🔲 Empty | ❌ Deleted | → communication-service | Consolidate comms |
| **search-service** | ✅ Active | ✅ Keep | No change | Already clean |
| **graphql-gateway** | ✅ Active | ✅ Keep | Update clients | Connect new services |

**Total**: 16 services → 10 services (減少6個)

---

## Dependency Ownership Matrix

| Dependency | Who Can Use | Current Violators |
|------------|-------------|-------------------|
| `argon2` | identity-service ONLY | ❌ auth-service, user-service, identity-service (3個) |
| `jsonwebtoken` | identity-service ONLY | ❌ auth-service, user-service, identity-service (3個) |
| `aws-sdk-s3` | media-service ONLY | ❌ media/video/cdn/user (4個) |
| `image` | media-service ONLY | ✅ media-service (OK) |
| `rdkafka` | communication-service + services that publish events | ✅ Multiple (acceptable) |
| `redis` | All services (caching) | ✅ All (acceptable) |
| `sqlx` | All services (database) | ✅ All (acceptable) |
| `tonic` | All services (gRPC) | ✅ All (acceptable) |

---

## Implementation Phases

### Phase 0: Cleanup Current Mess (3-4h)

**Goal**: Remove dead code and clarify what exists

#### Step 0.1: Clean user-service (2h)

```bash
cd backend/user-service

# Remove auth dependencies
sed -i '' '/argon2/d' Cargo.toml
sed -i '' '/jsonwebtoken/d' Cargo.toml

# Remove video tests (already disabled)
rm -rf tests/unit/video/
rm -rf tests/integration/video/
rm -rf tests/performance/video/

# Remove legacy feature flags
sed -i '' '/legacy_auth_tests/d' Cargo.toml
sed -i '' '/legacy_video_tests/d' Cargo.toml
sed -i '' '/legacy_posts_tests/d' Cargo.toml

# Remove post_share_repo.rs (will move to social-service)
# Keep for now, mark as deprecated in comments
```

#### Step 0.2: Document current service responsibilities (1-2h)

Create `SERVICE_BOUNDARIES.md` with clear ownership:
- identity-service: Authentication ONLY
- user-service: Profiles ONLY (no auth, no media)
- media-service: All media (images + videos + streaming)

---

### Phase 1: identity-service Implementation (20-25h)

**See V2_SERVICE_CONSOLIDATION_PLAN.md Phase 1**

**Key Steps**:
1. Implement Domain layer (User, Session, TokenRevocation)
2. Migrate auth-service logic (register, login, logout, password_reset)
3. Implement gRPC server (11 RPCs)
4. Update GraphQL Gateway to use identity-service
5. Deprecate auth-service

**Deliverable**: identity-service完全替代auth-service

---

### Phase 2: social-service Implementation (15-18h)

**See V2_SERVICE_CONSOLIDATION_PLAN.md Phase 2**

**Key Steps**:
1. Domain model (Like, Comment, Share, Tag, Mention)
2. Migrate like_repo.rs from content-service
3. Migrate comment_repo.rs from content-service
4. Migrate post_share_repo.rs from user-service
5. Event-driven integration (Transactional Outbox)
6. Update GraphQL Gateway

**Deliverable**: 所有社交互動統一在social-service

---

### Phase 3: media-service Consolidation (25-30h)

**Goal**: 合併4個media相關服務成1個

#### Step 3.1: Module Structure Design (3-4h)

**File**: `backend/media-service/src/modules/mod.rs` (REDESIGN)

```rust
pub mod images;      // From old media-service
pub mod videos;      // From old media-service + video-service
pub mod reels;       // From old media-service
pub mod streaming;   // From old streaming-service (8362 lines!)
pub mod cdn;         // From old cdn-service (2500+ lines)
```

#### Step 3.2: Unified S3 Service (5-6h)

**File**: `backend/media-service/src/services/s3_service.rs` (NEW)

```rust
use aws_sdk_s3::Client as S3Client;
use aws_config::BehaviorVersion;

pub struct S3Service {
    client: S3Client,
    bucket_images: String,
    bucket_videos: String,
    bucket_streams: String,
    cloudfront_domain: String,
}

impl S3Service {
    pub async fn new() -> Result<Self> {
        let config = aws_config::defaults(BehaviorVersion::latest())
            .load()
            .await;

        let client = S3Client::new(&config);

        Ok(Self {
            client,
            bucket_images: std::env::var("S3_BUCKET_IMAGES")?,
            bucket_videos: std::env::var("S3_BUCKET_VIDEOS")?,
            bucket_streams: std::env::var("S3_BUCKET_STREAMS")?,
            cloudfront_domain: std::env::var("CLOUDFRONT_DOMAIN")?,
        })
    }

    /// Upload image to S3
    pub async fn upload_image(
        &self,
        key: &str,
        data: Vec<u8>,
        content_type: &str,
    ) -> Result<String> {
        self.upload_to_bucket(&self.bucket_images, key, data, content_type).await
    }

    /// Upload video to S3
    pub async fn upload_video(
        &self,
        key: &str,
        data: Vec<u8>,
        content_type: &str,
    ) -> Result<String> {
        self.upload_to_bucket(&self.bucket_videos, key, data, content_type).await
    }

    /// Upload stream segment to S3
    pub async fn upload_stream_segment(
        &self,
        key: &str,
        data: Vec<u8>,
    ) -> Result<String> {
        self.upload_to_bucket(&self.bucket_streams, key, data, "video/MP2T").await
    }

    /// Internal: Upload to any bucket
    async fn upload_to_bucket(
        &self,
        bucket: &str,
        key: &str,
        data: Vec<u8>,
        content_type: &str,
    ) -> Result<String> {
        self.client
            .put_object()
            .bucket(bucket)
            .key(key)
            .body(data.into())
            .content_type(content_type)
            .send()
            .await?;

        Ok(format!("https://{}/{}", self.cloudfront_domain, key))
    }

    /// Generate presigned URL for direct upload
    pub async fn generate_presigned_upload_url(
        &self,
        bucket: &str,
        key: &str,
        expires_in_secs: u64,
    ) -> Result<String> {
        let presigning_config = PresigningConfig::expires_in(
            Duration::from_secs(expires_in_secs)
        )?;

        let presigned_request = self.client
            .put_object()
            .bucket(bucket)
            .key(key)
            .presigned(presigning_config)
            .await?;

        Ok(presigned_request.uri().to_string())
    }

    /// Verify S3 object exists
    pub async fn verify_object_exists(
        &self,
        bucket: &str,
        key: &str,
    ) -> Result<bool> {
        match self.client
            .head_object()
            .bucket(bucket)
            .key(key)
            .send()
            .await
        {
            Ok(_) => Ok(true),
            Err(_) => Ok(false),
        }
    }

    /// Delete S3 object
    pub async fn delete_object(
        &self,
        bucket: &str,
        key: &str,
    ) -> Result<()> {
        self.client
            .delete_object()
            .bucket(bucket)
            .key(key)
            .send()
            .await?;

        Ok(())
    }

    /// Generate CloudFront signed URL
    pub fn generate_cloudfront_url(&self, key: &str) -> String {
        format!("https://{}/{}", self.cloudfront_domain, key)
    }
}
```

#### Step 3.3: Merge Video Module (6-8h)

**Copy from**:
- `media-service/src/handlers/videos.rs` (128 lines)
- `media-service/src/services/mod.rs` VideoService
- `video-service/src/grpc.rs` (153 lines)
- `video-service/src/services/s3_service.rs` (468 lines)

**Merge into**: `media-service/src/modules/videos/`

```
media-service/src/modules/videos/
├── mod.rs          (public interface)
├── models.rs       (Video, VideoMetadata)
├── repository.rs   (database operations)
├── upload.rs       (upload logic)
├── transcoding.rs  (FFmpeg integration)
└── grpc.rs         (gRPC handlers)
```

#### Step 3.4: Merge Streaming Module (8-10h)

**Copy from**:
- `streaming-service/src/grpc.rs` (210 lines)
- `streaming-service/src/handlers/streams.rs` (307 lines)
- `streaming-service/src/services/streaming/` (entire directory, 8362 lines total)

**Merge into**: `media-service/src/modules/streaming/`

**Key files**:
- `rtmp_handler.rs` - RTMP ingest
- `hls_generator.rs` - HLS manifest generation
- `ws_handler.rs` - WebSocket for live chat
- `stream_analytics.rs` - ClickHouse analytics

#### Step 3.5: Merge CDN Module (4-5h)

**Copy from**:
- `cdn-service/src/grpc.rs` (340 lines)
- `cdn-service/src/services/` (7 files, 2500+ lines)

**Merge into**: `media-service/src/modules/cdn/`

**Key services**:
- `cdn_service.rs` (514 lines) - Core CDN logic
- `cdn_failover.rs` (404 lines) - Failover mechanism
- `origin_shield.rs` (406 lines) - Origin protection
- `cache_invalidator.rs` (205 lines) - Cache invalidation
- `url_signer.rs` (218 lines) - Signed URLs

#### Step 3.6: Unified gRPC Server (2-3h)

**File**: `backend/media-service/src/grpc/server.rs` (REDESIGN)

```rust
use tonic::{Request, Response, Status};

pub struct MediaServiceImpl {
    s3_service: Arc<S3Service>,
    image_service: Arc<ImageService>,
    video_service: Arc<VideoService>,
    reel_service: Arc<ReelService>,
    streaming_service: Arc<StreamingService>,
    cdn_service: Arc<CdnService>,
}

#[tonic::async_trait]
impl media_service_server::MediaService for MediaServiceImpl {
    // Images
    async fn upload_image(
        &self,
        request: Request<UploadImageRequest>,
    ) -> Result<Response<UploadImageResponse>, Status> {
        self.image_service.upload_image(request).await
    }

    // Videos
    async fn upload_video(
        &self,
        request: Request<UploadVideoRequest>,
    ) -> Result<Response<UploadVideoResponse>, Status> {
        self.video_service.upload_video(request).await
    }

    async fn transcode_video(
        &self,
        request: Request<TranscodeVideoRequest>,
    ) -> Result<Response<TranscodeVideoResponse>, Status> {
        self.video_service.transcode_video(request).await
    }

    // Reels
    async fn create_reel(
        &self,
        request: Request<CreateReelRequest>,
    ) -> Result<Response<CreateReelResponse>, Status> {
        self.reel_service.create_reel(request).await
    }

    // Streaming
    async fn start_stream(
        &self,
        request: Request<StartStreamRequest>,
    ) -> Result<Response<StartStreamResponse>, Status> {
        self.streaming_service.start_stream(request).await
    }

    async fn stop_stream(
        &self,
        request: Request<StopStreamRequest>,
    ) -> Result<Response<StopStreamResponse>, Status> {
        self.streaming_service.stop_stream(request).await
    }

    async fn get_streaming_manifest(
        &self,
        request: Request<GetStreamingManifestRequest>,
    ) -> Result<Response<GetStreamingManifestResponse>, Status> {
        self.streaming_service.get_streaming_manifest(request).await
    }

    // CDN
    async fn generate_signed_url(
        &self,
        request: Request<GenerateSignedUrlRequest>,
    ) -> Result<Response<GenerateSignedUrlResponse>, Status> {
        self.cdn_service.generate_signed_url(request).await
    }

    async fn invalidate_cdn_cache(
        &self,
        request: Request<InvalidateCdnCacheRequest>,
    ) -> Result<Response<InvalidateCdnCacheResponse>, Status> {
        self.cdn_service.invalidate_cdn_cache(request).await
    }
}
```

---

### Phase 4: communication-service Implementation (18-22h)

**See V2_SERVICE_CONSOLIDATION_PLAN.md Phase 3**

---

### Phase 5: GraphQL Gateway Updates (10-12h)

#### Step 5.1: Update Service Clients

**File**: `backend/graphql-gateway/src/clients.rs` (MAJOR UPDATE)

```rust
pub struct ServiceClients {
    // NEW services
    identity_channel: Arc<Channel>,      // 9090 (replaces auth)
    social_channel: Arc<Channel>,        // 9091 (new)
    communication_channel: Arc<Channel>, // 9092 (replaces messaging/notification)

    // UPDATED services
    user_channel: Arc<Channel>,          // 9080 (slimmed down)
    content_channel: Arc<Channel>,       // 9081 (slimmed down)
    media_channel: Arc<Channel>,         // 9085 (expanded, replaces video/streaming/cdn)

    // UNCHANGED services
    feed_channel: Arc<Channel>,          // 9084
    search_channel: Arc<Channel>,        // 9086
}

impl ServiceClients {
    pub async fn new() -> Result<Self> {
        // Remove old channels
        // let auth_channel = ...;          // DELETE
        // let messaging_channel = ...;     // DELETE
        // let video_channel = ...;         // DELETE
        // let streaming_channel = ...;     // DELETE
        // let cdn_channel = ...;           // DELETE

        // Add new channels
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

        // Update media_channel to handle all media types
        let media_channel = Arc::new(
            Channel::from_static("http://media-service:9085")
                .connect()
                .await?
        );

        Ok(Self {
            identity_channel,
            user_channel,
            social_channel,
            content_channel,
            feed_channel,
            media_channel,
            communication_channel,
            search_channel,
        })
    }

    // Client getters
    pub async fn identity_client(&self) -> Result<IdentityServiceClient<Channel>> {
        Ok(IdentityServiceClient::new((*self.identity_channel).clone()))
    }

    pub async fn social_client(&self) -> Result<SocialServiceClient<Channel>> {
        Ok(SocialServiceClient::new((*self.social_channel).clone()))
    }

    pub async fn communication_client(&self) -> Result<CommunicationServiceClient<Channel>> {
        Ok(CommunicationServiceClient::new((*self.communication_channel).clone()))
    }

    pub async fn media_client(&self) -> Result<MediaServiceClient<Channel>> {
        Ok(MediaServiceClient::new((*self.media_channel).clone()))
    }
}
```

#### Step 5.2: Update GraphQL Schemas

**Changes**:
1. `schema/auth.rs` → Use identity_client instead of auth_client
2. `schema/social.rs` → Create (new file)
3. `schema/communication.rs` → Rename from messaging.rs, expand
4. `schema/media.rs` → Expand to include video/streaming/cdn

---

### Phase 6: Database Migrations & Cleanup (8-10h)

#### Step 6.1: social-service Database

```sql
-- backend/social-service/migrations/001_initial_schema.sql
-- See V2_SERVICE_CONSOLIDATION_PLAN.md Phase 5.1
```

#### Step 6.2: media-service Database

```sql
-- backend/media-service/migrations/001_unified_media_schema.sql

-- Unified media assets table
CREATE TABLE media_assets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    type VARCHAR(20) NOT NULL CHECK (type IN ('image', 'video', 'reel', 'stream')),
    s3_key VARCHAR(500) NOT NULL,
    s3_bucket VARCHAR(100) NOT NULL,
    url VARCHAR(1000) NOT NULL,
    cloudfront_url VARCHAR(1000),
    size_bytes BIGINT NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    INDEX idx_media_assets_user_id (user_id),
    INDEX idx_media_assets_type (type),
    INDEX idx_media_assets_created_at (created_at DESC)
);

-- Videos table (extends media_assets)
CREATE TABLE videos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    media_asset_id UUID NOT NULL REFERENCES media_assets(id) ON DELETE CASCADE,
    duration_seconds INT,
    width INT,
    height INT,
    codec VARCHAR(50),
    bitrate INT,
    is_transcoded BOOLEAN NOT NULL DEFAULT FALSE,
    transcode_status VARCHAR(20) CHECK (transcode_status IN ('pending', 'processing', 'completed', 'failed')),

    UNIQUE(media_asset_id)
);

-- Reels table (extends videos)
CREATE TABLE reels (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    video_id UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    thumbnail_url VARCHAR(1000),
    view_count BIGINT NOT NULL DEFAULT 0,
    like_count BIGINT NOT NULL DEFAULT 0,

    UNIQUE(video_id)
);

-- Live streams table
CREATE TABLE live_streams (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    status VARCHAR(20) NOT NULL CHECK (status IN ('starting', 'live', 'ended', 'error')),
    rtmp_url VARCHAR(500),
    hls_url VARCHAR(500),
    viewer_count INT NOT NULL DEFAULT 0,
    started_at TIMESTAMP WITH TIME ZONE,
    ended_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    INDEX idx_live_streams_user_id (user_id),
    INDEX idx_live_streams_status (status),
    INDEX idx_live_streams_started_at (started_at DESC)
);

-- Transcode jobs table
CREATE TABLE transcode_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    video_id UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    progress INT NOT NULL DEFAULT 0,
    error_message TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,

    INDEX idx_transcode_jobs_video_id (video_id),
    INDEX idx_transcode_jobs_status (status)
);
```

#### Step 6.3: Data Migration

**Strategy**: Online migration with dual-write

1. Deploy new services alongside old
2. Enable dual-write (write to both old and new)
3. Backfill historical data
4. Switch reads to new services
5. Deprecate old services

**Migration Script**: `backend/scripts/migrate_media_data.sh`

```bash
#!/bin/bash

echo "Migrating media data from old services to unified media-service"

# Step 1: Migrate images from old media-service
psql $DATABASE_URL <<EOF
INSERT INTO media_service_new.media_assets (id, user_id, type, s3_key, s3_bucket, url, size_bytes, mime_type, created_at)
SELECT id, user_id, 'image', s3_key, s3_bucket, url, size_bytes, mime_type, created_at
FROM media_service_old.images;
EOF

# Step 2: Migrate videos from old video-service + media-service
psql $DATABASE_URL <<EOF
-- From video-service
INSERT INTO media_service_new.media_assets (id, user_id, type, s3_key, s3_bucket, url, size_bytes, mime_type, created_at)
SELECT id, user_id, 'video', s3_key, s3_bucket, url, size_bytes, mime_type, created_at
FROM video_service_old.videos;

-- Video metadata
INSERT INTO media_service_new.videos (media_asset_id, duration_seconds, width, height, codec, bitrate, is_transcoded)
SELECT id, duration_seconds, width, height, codec, bitrate, is_transcoded
FROM video_service_old.videos;
EOF

# Step 3: Migrate streams from old streaming-service
psql $DATABASE_URL <<EOF
INSERT INTO media_service_new.live_streams (id, user_id, title, description, status, rtmp_url, hls_url, started_at, ended_at, created_at)
SELECT id, user_id, title, description, status, rtmp_url, hls_url, started_at, ended_at, created_at
FROM streaming_service_old.live_streams;
EOF

echo "Migration complete"
```

---

## Final Service Count

**Before**: 16 services
```
1.  auth-service           ❌ Delete
2.  identity-service       ✅ Implement (empty → full)
3.  user-service           ✅ Slim down
4.  social-service         ✅ Implement (empty → full)
5.  content-service        ✅ Slim down
6.  feed-service           ✅ Keep
7.  media-service          ✅ Expand
8.  video-service          ❌ Delete
9.  streaming-service      ❌ Delete
10. cdn-service            ❌ Delete
11. messaging-service      ❌ Delete
12. notification-service   ❌ Delete
13. events-service         ❌ Delete
14. communication-service  ✅ Implement (empty → full)
15. search-service         ✅ Keep
16. graphql-gateway        ✅ Update
```

**After**: 10 services
```
1. identity-service       ✅ (Auth unified)
2. user-service           ✅ (Profiles only)
3. social-service         ✅ (Social interactions unified)
4. content-service        ✅ (Content only)
5. feed-service           ✅ (Recommendations)
6. media-service          ✅ (All media unified)
7. communication-service  ✅ (All comms unified)
8. search-service         ✅ (Search)
9. graphql-gateway        ✅ (API gateway)
10. (Optional) analytics-service ⏳ (Future)
```

**Reduction**: 16 → 10 = **37.5% fewer services**

---

## Work Estimate

| Phase | Task | Hours | Days |
|-------|------|-------|------|
| Phase 0 | Cleanup current mess | 3-4h | 0.5d |
| Phase 1 | identity-service | 20-25h | 3-4d |
| Phase 2 | social-service | 15-18h | 2-3d |
| Phase 3 | media-service consolidation | 25-30h | 4-5d |
| Phase 4 | communication-service | 18-22h | 3-4d |
| Phase 5 | GraphQL Gateway updates | 10-12h | 2d |
| Phase 6 | Database migrations | 8-10h | 1-2d |
| **Total** | **Complete restructure** | **99-121h** | **15-20 work days** |

---

## Risk Mitigation

### Risk 1: Data Loss During Migration

**Mitigation**: Dual-write strategy
- Run old and new services in parallel
- Write to both during transition
- Compare data consistency before cutover

### Risk 2: Service Downtime

**Mitigation**: Blue-green deployment
- Deploy new services without removing old
- Switch traffic gradually (10% → 50% → 100%)
- Instant rollback capability

### Risk 3: Breaking Changes

**Mitigation**: GraphQL schema compatibility
- All GraphQL queries remain the same
- Internal gRPC changes are transparent
- iOS app requires zero changes

---

## Success Criteria

### Technical
- [ ] All 16 services deployed → 10 services running
- [ ] Zero duplicate dependencies (argon2, aws-sdk-s3)
- [ ] Clean service boundaries (no overlapping domains)
- [ ] All tests passing
- [ ] API latency < 100ms (p95)

### Business
- [ ] Zero downtime deployment
- [ ] Zero data loss
- [ ] iOS app works without changes
- [ ] Easier operations (37.5% fewer services to monitor)

---

## Linus-Style Final Verdict

**What's wrong with current architecture**:
- Auth邏輯分散在3個服務 (auth-service, user-service, identity-service)
- Media邏輯分散在4個服務 (media, video, streaming, cdn) - 全都用S3!
- Social功能split在content-service和user-service之間
- user-service是垃圾桶服務,什麼都有

**Why this matters**:
- 37.5%的服務是重複的
- 開發者不知道"新功能應該加到哪裡"
- 部署/監控/debug要處理16個服務

**The fix**:
1. **identity-service**: 只做auth,刪除其他2個auth實現
2. **media-service**: 統一所有media (S3只在這裡)
3. **social-service**: 統一所有社交互動
4. **communication-service**: 統一所有通訊渠道
5. Clean up user-service: 只做profiles

**Timeline**: 15-20 work days (3-4 weeks)

**Benefit**:
- 清晰的服務邊界
- 沒有功能重疊
- 更容易維護
- 更容易onboard新開發者("Like功能在哪?"→"social-service")

**No bullshit**: 現在的架構是"先拆分後思考"的結果。正確的順序應該是"先思考邊界,再拆分服務"。這個restructure就是把順序糾正過來。

---

**Document Version**: 2.0
**Author**: Claude Code (Complete Restructure Mode)
**Last Updated**: 2025-11-11
