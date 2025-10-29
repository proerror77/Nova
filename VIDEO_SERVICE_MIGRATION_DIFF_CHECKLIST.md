# Video Service Migration - Detailed Diff Checklist

**目标**: 为每个文件提供精确的修改位置和代码差异

---

## 📝 文件 1: services/s3_service.rs

### 修改位置 1: 导入语句 (行 1-2)
**原代码**:
```rust
use crate::config::S3Config;
use crate::error::AppError;
```

**修改后**:
```rust
use crate::config::S3Config;
use crate::error::VideoServiceError as AppError;
```

**原因**: video-service 使用独立的错误类型

---

### 修改位置 2: 测试导入 (行 323-325)
**原代码**:
```rust
#[cfg(test)]
mod tests {
    use super::*;
```

**修改后**:
```rust
#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::S3Config;
```

**原因**: 确保测试能访问配置类型

---

### ✅ 验证命令
```bash
cd backend/video-service
cargo test s3_service
# 预期: 22 tests passed
```

---

## 📝 文件 2: services/transcoding_optimizer.rs

### 修改位置 1: 导入语句 (行 6-7)
**原代码**:
```rust
use crate::config::video_config::VideoProcessingConfig;
use crate::error::{AppError, Result};
```

**修改后**:
```rust
use crate::config::video_config::VideoProcessingConfig;
use crate::error::{VideoServiceError as AppError, Result};
```

**原因**: 统一错误类型

---

### 修改位置 2: 错误返回 (行 295)
**原代码**:
```rust
Err(AppError::NotFound(format!("Job not found: {}", job_id)))
```

**保持不变** (VideoServiceError 也有 NotFound variant)

---

### ✅ 验证命令
```bash
cargo test transcoding_optimizer
# 预期: 7 tests passed
```

---

## 📝 文件 3: services/video_service.rs

### 修改位置 1: 导入语句 (行 4-7)
**原代码**:
```rust
use crate::config::video_config::VideoConfig;
use crate::config::S3Config;
use crate::error::{AppError, Result};
use crate::services::s3_service;
```

**修改后**:
```rust
use crate::config::video_config::VideoConfig;
use crate::config::S3Config;
use crate::error::{VideoServiceError as AppError, Result};
use crate::services::s3_service;
```

---

### ✅ 验证命令
```bash
cargo build --package video-service
# 预期: Compiled successfully
```

---

## 📝 文件 4: handlers/transcoding_progress.rs

### 修改位置 1: 导入语句 (行 1-6)
**原代码**:
```rust
use crate::middleware::jwt_auth::UserId;
use crate::services::transcoding_progress_handler::{ProgressStreamActor, ProgressStreamRegistry};
use actix_web::{web, HttpMessage, HttpRequest, HttpResponse};
use actix_web_actors::ws;
use std::sync::Arc;
use uuid::Uuid;
```

**修改后**:
```rust
use auth_middleware::UserId;  // 使用共享 auth middleware
use crate::services::transcoding_progress_handler::{ProgressStreamActor, ProgressStreamRegistry};
use actix_web::{web, HttpMessage, HttpRequest, HttpResponse};
use actix_web_actors::ws;
use std::sync::Arc;
use uuid::Uuid;
```

**原因**: UserId 现在来自共享库

---

### 修改位置 2: 添加权限检查 (行 44-48)
**原代码**:
```rust
// Extract user from JWT (middleware already validated, optional for public videos)
let _user_id = req.extensions().get::<UserId>().map(|id| id.0);

// TODO: Verify user has permission to access this video
// For now, allow any authenticated user
```

**修改后**:
```rust
// Extract user from JWT - REQUIRED for progress stream
let user_id = req.extensions()
    .get::<UserId>()
    .map(|id| id.0)
    .ok_or_else(|| actix_web::error::ErrorUnauthorized("Authentication required"))?;

// TODO: Verify user owns this video or has permission
// Query video_repo::get_video() and check creator_id == user_id
```

**原因**: 增强安全性，确保只有视频所有者能看到处理进度

---

### ✅ 验证命令
```bash
# WebSocket 测试
wscat -c "ws://localhost:8081/api/v1/videos/123e4567-e89b-12d3-a456-426614174000/progress/stream?token=$JWT_TOKEN"
# 预期: 连接成功，收到进度更新
```

---

## 📝 文件 5: handlers/uploads.rs

### 修改位置 1: 导入语句 (行 16-23)
**原代码**:
```rust
use crate::config::Config;
use crate::db::upload_repo;
use crate::db::video_repo;
use crate::error::{AppError, Result};
use crate::middleware::UserId;
use crate::models::UploadStatus;
use crate::services::resumable_upload_service::ResumableUploadService;
use crate::services::s3_service;
```

**修改后**:
```rust
use auth_middleware::UserId;
use crate::config::Config;
use crate::db::{upload_repo, video_repo};
use crate::error::{VideoServiceError as AppError, Result};
use crate::models::UploadStatus;
use crate::services::{
    resumable_upload_service::ResumableUploadService,
    s3_service,
};
```

**原因**: 使用共享 auth middleware + 统一错误类型

---

### 修改位置 2: 错误处理 (行 104-114)
**原代码**:
```rust
// Validate inputs
if req.file_name.is_empty() {
    return Err(AppError::BadRequest("file_name required".into()));
}

if req.file_size <= 0 {
    return Err(AppError::BadRequest("file_size must be positive".into()));
}

if req.chunk_size <= 0 {
    return Err(AppError::BadRequest("chunk_size must be positive".into()));
}
```

**保持不变** (VideoServiceError 也有 BadRequest variant)

---

### 修改位置 3: 添加日志 (行 90-95)
**原代码**:
```rust
pub async fn upload_init(
    http_req: HttpRequest,
    pool: web::Data<PgPool>,
    config: web::Data<Config>,
    req: web::Json<UploadInitRequest>,
) -> Result<HttpResponse> {
```

**修改后**:
```rust
pub async fn upload_init(
    http_req: HttpRequest,
    pool: web::Data<PgPool>,
    config: web::Data<Config>,
    req: web::Json<UploadInitRequest>,
) -> Result<HttpResponse> {
    tracing::info!(
        "Upload init request: file_name={}, file_size={}, chunk_size={}",
        req.file_name,
        req.file_size,
        req.chunk_size
    );
```

**原因**: 增强可观测性

---

### ✅ 验证命令
```bash
# 测试上传初始化
curl -X POST http://localhost:8081/api/v1/uploads/init \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "file_name": "test.mp4",
    "file_size": 10485760,
    "chunk_size": 5242880,
    "title": "Test Video"
  }'
# 预期: 返回 upload_id 和 chunks_total
```

---

## 📝 文件 6: handlers/videos.rs (最复杂)

### 修改位置 1: 导入语句 (行 10-20)
**原代码**:
```rust
use crate::config::{video_config::VideoConfig, Config};
use crate::db::video_repo;
use crate::error::{AppError, Result};
use crate::middleware::{CircuitBreaker, UserId};
use crate::models::video::*;
use crate::services::deep_learning_inference::DeepLearningInferenceService;
use crate::services::streaming_manifest::StreamingManifestGenerator;
use crate::services::video_transcoding::VideoMetadata;
use crate::services::{s3_service, video_service::VideoService};
use tokio::io::AsyncWriteExt;
use tracing::{debug, error, info, warn};
```

**修改后**:
```rust
use auth_middleware::UserId;
use crate::config::{video_config::VideoConfig, Config};
use crate::db::video_repo;
use crate::error::{VideoServiceError as AppError, Result};
use crate::middleware::CircuitBreaker;
use crate::models::video::*;
use crate::services::{
    deep_learning_inference::DeepLearningInferenceService,
    streaming_manifest::StreamingManifestGenerator,
    video_transcoding::VideoMetadata,
    s3_service,
    video_service::VideoService,
};
use tokio::io::AsyncWriteExt;
use tracing::{debug, error, info, warn};
```

**原因**: 使用共享 auth middleware

---

### 修改位置 2: video_upload_init() 认证提取 (行 109-116)
**原代码**:
```rust
let user_id = match http_req.extensions().get::<UserId>() {
    Some(user_id_wrapper) => user_id_wrapper.0,
    None => {
        return Err(AppError::Authentication(
            "User ID not found in request. JWT middleware may not be active.".into(),
        ))
    }
};
```

**修改后**:
```rust
let user_id = http_req
    .extensions()
    .get::<UserId>()
    .map(|u| u.0)
    .ok_or_else(|| {
        tracing::error!("JWT middleware failed to extract user_id");
        AppError::Authentication("User ID not found in request".into())
    })?;
```

**原因**: 更简洁的 Option 处理 + 添加日志

---

### 修改位置 3: 错误日志增强 (行 134-137)
**原代码**:
```rust
.map_err(|e| {
    tracing::error!("Failed to create video record: {:?}", e);
    AppError::Internal("Database error".into())
})?;
```

**修改后**:
```rust
.map_err(|e| {
    tracing::error!(
        "Failed to create video record for user {}: {:?}",
        user_id,
        e
    );
    AppError::Database(e)  // 保留原始错误信息
})?;
```

**原因**: 更详细的错误追踪

---

### 修改位置 4: video_upload_complete() 认证提取 (行 196-210)
**原代码**:
```rust
pub async fn video_upload_complete(
    pool: web::Data<PgPool>,
    config: web::Data<Config>,
    job_sender: web::Data<crate::services::video_job_queue::VideoJobSender>,
    req: web::Json<VideoUploadCompleteRequest>,
) -> Result<HttpResponse> {
```

**修改后**:
```rust
pub async fn video_upload_complete(
    http_req: HttpRequest,  // 添加 HttpRequest 参数
    pool: web::Data<PgPool>,
    config: web::Data<Config>,
    job_sender: web::Data<crate::services::video_job_queue::VideoJobSender>,
    req: web::Json<VideoUploadCompleteRequest>,
) -> Result<HttpResponse> {
    // 提取 user_id 用于验证
    let requesting_user_id = http_req
        .extensions()
        .get::<UserId>()
        .map(|u| u.0)
        .ok_or_else(|| AppError::Authentication("User ID not found".into()))?;
```

**原因**: 需要验证上传者身份

---

### 修改位置 5: 添加权限验证 (行 338-350)
**新增代码** (在 line 337 之后):
```rust
// j. Get user_id from video record
let creator_id: Uuid = sqlx::query_scalar("SELECT creator_id FROM videos WHERE id = $1")
    .bind(video_id)
    .fetch_one(pool.get_ref())
    .await
    .map_err(|e| {
        tracing::error!("Failed to fetch creator_id for video {}: {:?}", video_id, e);
        AppError::Database(e)
    })?;

// Verify requesting user is the creator
if requesting_user_id != creator_id {
    tracing::warn!(
        "User {} attempted to complete upload for video {} owned by {}",
        requesting_user_id,
        video_id,
        creator_id
    );
    return Err(AppError::Authorization(
        "You do not have permission to complete this upload".into()
    ));
}
```

**原因**: 安全性 - 防止用户完成他人的上传

---

### 修改位置 6: processing_complete() 添加认证 (行 403-410)
**原代码**:
```rust
pub async fn processing_complete(
    path: web::Path<String>,
    pool: web::Data<sqlx::PgPool>,
    dl: web::Data<DeepLearningInferenceService>,
    body: web::Json<ProcessingCompleteRequest>,
) -> Result<HttpResponse> {
```

**修改后**:
```rust
pub async fn processing_complete(
    http_req: HttpRequest,  // 添加认证
    path: web::Path<String>,
    pool: web::Data<sqlx::PgPool>,
    dl: web::Data<DeepLearningInferenceService>,
    body: web::Json<ProcessingCompleteRequest>,
) -> Result<HttpResponse> {
    // 验证是否为内部服务调用 (或管理员权限)
    let _user_id = http_req
        .extensions()
        .get::<UserId>()
        .map(|u| u.0)
        .ok_or_else(|| AppError::Authentication("Internal service call required".into()))?;

    // TODO: 添加 service-to-service authentication token 验证
```

**原因**: 防止外部直接调用内部 API

---

### 修改位置 7: get_video() CircuitBreaker 处理 (行 654-676)
**原代码**:
```rust
// Fetch video with Circuit Breaker protection
let video_result = state
    .postgres_cb
    .call(|| {
        let pool_clone = pool.clone();
        async move {
            video_repo::get_video(pool_clone.get_ref(), id)
                .await
                .map_err(|e| AppError::Internal(e.to_string()))
        }
    })
    .await
    .map_err(|e| {
        match &e {
            AppError::Internal(msg) if msg.contains("Circuit breaker is OPEN") => {
                warn!("PostgreSQL circuit is OPEN for video lookup");
                AppError::Internal("Database service is experiencing issues - circuit breaker OPEN".to_string())
            }
            _ => {
                error!("Failed to fetch video: {}", e);
                AppError::Internal("Database error".to_string())
            }
        }
    })?;
```

**修改后**:
```rust
// Fetch video with Circuit Breaker protection
let video_result = state
    .postgres_cb
    .call(|| {
        let pool_clone = pool.clone();
        async move {
            video_repo::get_video(pool_clone.get_ref(), id)
                .await
                .map_err(|e| AppError::Database(e))  // 保留原始错误
        }
    })
    .await
    .map_err(|e| {
        match &e {
            AppError::Internal(msg) if msg.contains("Circuit breaker is OPEN") => {
                tracing::warn!(
                    "PostgreSQL circuit is OPEN for video {} lookup",
                    id
                );
                AppError::Internal(
                    "Database service temporarily unavailable".to_string()
                )
            }
            _ => {
                tracing::error!("Failed to fetch video {}: {}", id, e);
                e
            }
        }
    })?;
```

**原因**: 更精确的错误处理 + 保留错误上下文

---

### 修改位置 8: DeepLearningInferenceService 调用 (行 468-490)
**原代码**:
```rust
let res = dl
    .generate_embeddings_from_file(&video_id.to_string(), probe_path.as_path())
    .await;
```

**修改后 (如果使用独立 ml-service)**:
```rust
// 通过 gRPC 调用 ml-service
let ml_client = MlServiceClient::connect("http://ml-service:8082").await?;
let res = ml_client
    .generate_embeddings(GenerateEmbeddingsRequest {
        video_id: video_id.to_string(),
        file_url: body.file_url.clone(),
        metadata: Some(VideoMetadataProto {
            duration_seconds: body.duration_seconds,
            width: body.width,
            height: body.height,
            bitrate_kbps: body.bitrate_kbps,
            fps: body.fps,
            video_codec: body.video_codec.clone(),
        }),
    })
    .await?;
```

**原因**: 解耦 ML 推理逻辑

---

### 修改位置 9: Milvus 配置检查 (行 492-504)
**原代码**:
```rust
let milvus_enabled =
    std::env::var("MILVUS_ENABLED").unwrap_or_else(|_| "false".into()) == "true";
if milvus_enabled && dl.check_milvus_health().await.unwrap_or(false) {
```

**修改后**:
```rust
let milvus_config = config.milvus.clone();  // 从 Config 读取
if milvus_config.enabled && dl.check_milvus_health().await.unwrap_or(false) {
```

**原因**: 统一配置管理，避免直接读取环境变量

---

### ✅ 验证命令
```bash
# 测试所有 video endpoints
./scripts/test_video_endpoints.sh

# 单个端点测试
curl -X POST http://localhost:8081/api/v1/videos/upload/init \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"filename":"test.mp4","file_size":10485760,"content_type":"video/mp4","title":"Test"}'

curl -X GET http://localhost:8081/api/v1/videos/123e4567-e89b-12d3-a456-426614174000 \
  -H "Authorization: Bearer $TOKEN"
```

---

## 📝 文件 7: db/video_repo.rs

### 修改位置 1: 导入语句 (行 1-4)
**原代码**:
```rust
use crate::models::video::{VideoEngagementEntity, VideoEntity, VideoUploadSession};
use chrono::{Duration, Utc};
use sqlx::{PgPool, Row};
use uuid::Uuid;
```

**保持不变** (video-service 会创建自己的 models/video.rs)

---

### 修改位置 2: 添加错误日志 (所有数据库查询)
**示例 - create_video() (行 6-37)**:
```rust
pub async fn create_video(
    pool: &PgPool,
    creator_id: Uuid,
    title: &str,
    description: Option<&str>,
    hashtags: &serde_json::Value,
    visibility: &str,
) -> Result<VideoEntity, sqlx::Error> {
    tracing::info!(
        "Creating video: creator_id={}, title={}",
        creator_id,
        title
    );

    let result = sqlx::query_as::<_, VideoEntity>(
        r#"
        INSERT INTO videos (...)
        VALUES (...)
        RETURNING ...
        "#,
    )
    .bind(creator_id)
    .bind(title)
    // ... 其他 bind
    .fetch_one(pool)
    .await;

    match &result {
        Ok(video) => tracing::info!("Created video: id={}", video.id),
        Err(e) => tracing::error!("Failed to create video: {:?}", e),
    }

    result
}
```

**原因**: 增强可观测性

---

### ✅ 验证命令
```bash
# 数据库集成测试
cargo test --test integration_video_repo
# 预期: All tests passed
```

---

## 📝 文件 8: db/upload_repo.rs

### 修改位置 1: 导入语句 (行 4-7)
**原代码**:
```rust
use crate::models::video::{ResumableUpload, UploadChunk};
use chrono::{Duration, Utc};
use sqlx::PgPool;
use uuid::Uuid;
```

**保持不变**

---

### 修改位置 2: 添加日志 (create_upload_session)
**原代码 (行 14-71)**:
```rust
pub async fn create_upload_session(
    pool: &PgPool,
    video_id: Uuid,
    user_id: Uuid,
    // ... 其他参数
) -> Result<ResumableUpload, sqlx::Error> {
    let chunks_total = ((file_size + chunk_size as i64 - 1) / chunk_size as i64) as i32;
    let expires_at = Utc::now() + Duration::days(7);

    sqlx::query_as::<_, ResumableUpload>(...)
```

**修改后**:
```rust
pub async fn create_upload_session(
    pool: &PgPool,
    video_id: Uuid,
    user_id: Uuid,
    // ... 其他参数
) -> Result<ResumableUpload, sqlx::Error> {
    let chunks_total = ((file_size + chunk_size as i64 - 1) / chunk_size as i64) as i32;
    let expires_at = Utc::now() + Duration::days(7);

    tracing::info!(
        "Creating upload session: video_id={}, user_id={}, chunks_total={}",
        video_id,
        user_id,
        chunks_total
    );

    let result = sqlx::query_as::<_, ResumableUpload>(...)
        // ...
        .fetch_one(pool)
        .await;

    match &result {
        Ok(upload) => tracing::info!("Upload session created: id={}", upload.id),
        Err(e) => tracing::error!("Failed to create upload session: {:?}", e),
    }

    result
}
```

**原因**: 追踪上传会话创建

---

### ✅ 验证命令
```bash
cargo test --test integration_upload_repo
# 预期: All tests passed
```

---

## 📝 文件 9: models/video.rs

### 修改位置: 无需修改
**原因**: 数据模型定义保持不变，直接复制到 video-service

**验证**:
```bash
# 确保模型可以正确序列化/反序列化
cargo test models::video
```

---

## 📝 文件 10: config/mod.rs

### 修改位置 1: 移除不需要的配置 (行 8-21)
**原代码**:
```rust
pub struct Config {
    pub app: AppConfig,
    pub database: DatabaseConfig,
    pub redis: RedisConfig,
    pub jwt: JwtConfig,
    pub email: EmailConfig,
    pub rate_limit: RateLimitConfig,
    pub s3: S3Config,
    pub cors: CorsConfig,
    pub clickhouse: ClickHouseConfig,
    pub kafka: KafkaConfig,
    pub graph: GraphConfig,
}
```

**修改后 (video-service)**:
```rust
pub struct Config {
    pub app: AppConfig,
    pub database: DatabaseConfig,
    pub redis: RedisConfig,        // 用于缓存
    pub jwt: JwtConfig,             // 用于验证 token
    pub s3: S3Config,               // 核心功能
    pub cors: CorsConfig,
    pub kafka: KafkaConfig,         // 发布事件
    pub milvus: MilvusConfig,       // ML embedding 存储
    pub video: VideoConfig,         // 视频处理配置
}
```

**删除**:
- `email: EmailConfig` (不需要发邮件)
- `rate_limit: RateLimitConfig` (由 API Gateway 处理)
- `clickhouse: ClickHouseConfig` (不需要分析)
- `graph: GraphConfig` (不需要社交图谱)

---

### 修改位置 2: 添加 MilvusConfig (新增)
```rust
#[derive(Debug, Clone, Deserialize)]
pub struct MilvusConfig {
    #[serde(default = "default_milvus_enabled")]
    pub enabled: bool,

    #[serde(default = "default_milvus_host")]
    pub host: String,

    #[serde(default = "default_milvus_port")]
    pub port: u16,

    pub collection_name: String,
}

fn default_milvus_enabled() -> bool {
    false
}

fn default_milvus_host() -> String {
    "localhost".to_string()
}

fn default_milvus_port() -> u16 {
    19530
}
```

---

### 修改位置 3: 添加 VideoConfig (引用现有的)
```rust
use video_config::VideoConfig;

// 在 impl Config 中添加
impl Config {
    pub fn from_env() -> Result<Self, envy::Error> {
        // ... 其他配置加载

        let video = VideoConfig::from_env();

        let milvus = MilvusConfig {
            enabled: env::var("MILVUS_ENABLED")
                .unwrap_or_else(|_| "false".to_string())
                .parse()
                .unwrap_or(false),
            host: env::var("MILVUS_HOST")
                .unwrap_or_else(|_| "localhost".to_string()),
            port: env::var("MILVUS_PORT")
                .unwrap_or_else(|_| "19530".to_string())
                .parse()
                .unwrap_or(19530),
            collection_name: env::var("MILVUS_COLLECTION")
                .unwrap_or_else(|_| "video_embeddings".to_string()),
        };

        Ok(Config {
            app,
            database,
            redis,
            jwt,
            s3,
            cors,
            kafka,
            milvus,
            video,
        })
    }
}
```

---

### ✅ 验证命令
```bash
# 测试配置加载
cargo test config::tests
# 预期: All tests passed

# 手动验证
cargo run --bin config-test
```

---

## 📝 文件 11: middleware/mod.rs

### 修改位置: 移除不需要的中间件
**原代码**:
```rust
pub mod circuit_breaker;
pub mod global_rate_limit;
pub mod jwt_auth;
pub mod metrics;
pub mod rate_limit;
pub mod token_revocation;

pub use circuit_breaker::{CircuitBreaker, CircuitBreakerConfig, CircuitState};
pub use global_rate_limit::GlobalRateLimitMiddleware;
pub use jwt_auth::{JwtAuthMiddleware, UserId};
pub use metrics::MetricsMiddleware;
pub use rate_limit::RateLimiter;
pub use token_revocation::{TokenRevocationMiddleware, TokenRevocationMiddlewareService};
```

**修改后 (video-service)**:
```rust
pub mod circuit_breaker;
pub mod metrics;

pub use circuit_breaker::{CircuitBreaker, CircuitBreakerConfig, CircuitState};
pub use metrics::MetricsMiddleware;

// JWT auth 和 UserId 来自共享库
pub use auth_middleware::{JwtAuthMiddleware, UserId};
```

**删除**:
- `global_rate_limit` (由 API Gateway 处理)
- `rate_limit` (由 API Gateway 处理)
- `token_revocation` (由 user-service 处理)

---

## 📝 文件 12: error.rs

### 创建新的 VideoServiceError
**新文件**: `video-service/src/error.rs`
```rust
use actix_web::{error::ResponseError, http::StatusCode, HttpResponse};
use error_types::ErrorResponse;
use thiserror::Error;

pub type Result<T> = std::result::Result<T, VideoServiceError>;

#[derive(Debug, Error)]
pub enum VideoServiceError {
    #[error("Database error: {0}")]
    Database(#[from] sqlx::Error),

    #[error("Redis error: {0}")]
    Redis(#[from] redis::RedisError),

    #[error("S3 error: {0}")]
    S3(String),

    #[error("Transcoding error: {0}")]
    Transcoding(String),

    #[error("Video processing error: {0}")]
    VideoProcessing(String),

    #[error("Invalid video format: {0}")]
    InvalidFormat(String),

    #[error("Video not found: {0}")]
    NotFound(String),

    #[error("Bad request: {0}")]
    BadRequest(String),

    #[error("Authentication error: {0}")]
    Authentication(String),

    #[error("Authorization error: {0}")]
    Authorization(String),

    #[error("Internal server error: {0}")]
    Internal(String),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
}

impl ResponseError for VideoServiceError {
    fn status_code(&self) -> StatusCode {
        match self {
            VideoServiceError::Database(_) => StatusCode::INTERNAL_SERVER_ERROR,
            VideoServiceError::Redis(_) => StatusCode::INTERNAL_SERVER_ERROR,
            VideoServiceError::S3(_) => StatusCode::INTERNAL_SERVER_ERROR,
            VideoServiceError::Transcoding(_) => StatusCode::INTERNAL_SERVER_ERROR,
            VideoServiceError::VideoProcessing(_) => StatusCode::INTERNAL_SERVER_ERROR,
            VideoServiceError::InvalidFormat(_) => StatusCode::BAD_REQUEST,
            VideoServiceError::NotFound(_) => StatusCode::NOT_FOUND,
            VideoServiceError::BadRequest(_) => StatusCode::BAD_REQUEST,
            VideoServiceError::Authentication(_) => StatusCode::UNAUTHORIZED,
            VideoServiceError::Authorization(_) => StatusCode::FORBIDDEN,
            VideoServiceError::Internal(_) => StatusCode::INTERNAL_SERVER_ERROR,
            VideoServiceError::Io(_) => StatusCode::INTERNAL_SERVER_ERROR,
        }
    }

    fn error_response(&self) -> HttpResponse {
        let status_code = self.status_code();
        let error_type = match self {
            VideoServiceError::Database(_) => "database_error",
            VideoServiceError::S3(_) => "s3_error",
            VideoServiceError::Transcoding(_) => "transcoding_error",
            VideoServiceError::VideoProcessing(_) => "video_processing_error",
            VideoServiceError::InvalidFormat(_) => "validation_error",
            VideoServiceError::NotFound(_) => "not_found_error",
            VideoServiceError::BadRequest(_) => "validation_error",
            VideoServiceError::Authentication(_) => "authentication_error",
            VideoServiceError::Authorization(_) => "authorization_error",
            _ => "server_error",
        };

        let response = ErrorResponse::new(
            &format!("{:?}", status_code),
            &self.to_string(),
            status_code.as_u16(),
            error_type,
            error_type,  // code = type (简化)
        );

        HttpResponse::build(status_code).json(response)
    }
}
```

---

## ✅ 最终验证清单

### 编译验证
```bash
cd backend/video-service
cargo build --release
# 预期: Compilation successful
```

### 单元测试
```bash
cargo test
# 预期: All tests passed
```

### 集成测试
```bash
cargo test --test integration
# 预期: All integration tests passed
```

### 端到端测试
```bash
./scripts/test_video_e2e.sh
# 预期: All endpoints working
```

### 性能测试
```bash
wrk -t4 -c100 -d30s http://localhost:8081/api/v1/videos/123
# 预期: p99 latency < 500ms
```

---

## 📊 修改统计

| 文件 | 修改行数 | 新增行数 | 删除行数 | 复杂度 |
|-----|---------|---------|---------|-------|
| s3_service.rs | 2 | 0 | 0 | 🟢 低 |
| transcoding_optimizer.rs | 1 | 0 | 0 | 🟢 低 |
| video_service.rs | 1 | 0 | 0 | 🟢 低 |
| transcoding_progress.rs | 10 | 5 | 2 | 🟡 中 |
| uploads.rs | 15 | 10 | 5 | 🟡 中 |
| videos.rs | 50+ | 30+ | 10 | 🔴 高 |
| video_repo.rs | 20 | 15 | 0 | 🟡 中 |
| upload_repo.rs | 15 | 10 | 0 | 🟡 中 |
| config/mod.rs | 30 | 40 | 20 | 🟡 中 |
| middleware/mod.rs | 5 | 0 | 10 | 🟢 低 |
| error.rs | 0 | 100+ | 0 | 🟡 中 |
| **总计** | **150+** | **210+** | **47** | 🟡 中 |

---

## 🎯 下一步

1. ✅ 复制本文档到项目根目录
2. ✅ 创建 Phase 1 实施分支: `git checkout -b feature/video-service-migration-phase1`
3. ✅ 按照清单逐文件修改
4. ✅ 每完成一个文件，运行对应的验证命令
5. ✅ 所有验证通过后，提交 PR

**预估时间**: 2-3 周 (11-15 工作日)

---

**生成日期**: 2025-10-30
**工具**: Linus Code Review - Diff Checklist Generator
