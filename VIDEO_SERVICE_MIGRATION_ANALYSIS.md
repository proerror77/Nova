# Video Service Migration Analysis - Dependency Graph & Action Plan

**日期**: 2025-10-30
**分析对象**: user-service → video-service 代码迁移
**目标**: 识别强耦合、制定具体迁移策略

---

## 执行摘要

### 关键发现
1. **可直接复制**: `s3_service.rs`, `transcoding_optimizer.rs` - 零内部依赖
2. **中度耦合**: `video_service.rs`, `uploads.rs` - 需要接口适配
3. **强耦合**: `videos.rs`, `transcoding_progress.rs` - 深度依赖多个模块
4. **数据库依赖**: 需要创建新的 video-service 专用 database pool 和 repositories

### 迁移风险评级
- 🟢 **低风险**: S3、transcoding optimizer (可立即迁移)
- 🟡 **中风险**: Upload handlers (需要修改 auth context)
- 🔴 **高风险**: Video handlers (需要重构 database 访问)

---

## 📊 Part 1: 文件依赖关系图

### 1.1 handlers/videos.rs (810行) - 🔴 强耦合

**内部依赖**:
```rust
use crate::config::{video_config::VideoConfig, Config};     // 配置系统
use crate::db::video_repo;                                   // 数据库访问层
use crate::error::{AppError, Result};                        // 错误类型
use crate::middleware::{CircuitBreaker, UserId};             // 认证 + 熔断器
use crate::models::video::*;                                 // 数据模型
use crate::services::deep_learning_inference::DeepLearningInferenceService;
use crate::services::streaming_manifest::StreamingManifestGenerator;
use crate::services::video_transcoding::VideoMetadata;
use crate::services::{s3_service, video_service::VideoService};
```

**外部依赖**:
```rust
actix_web::{web, HttpMessage, HttpRequest, HttpResponse}    // Web 框架
sqlx::PgPool                                                 // 数据库连接池
uuid::Uuid                                                   // UUID 生成
serde_json::json                                             // JSON 序列化
```

**依赖分析**:
- ✅ **可移植**: serde, uuid, actix_web (标准库)
- ⚠️ **需适配**:
  - `UserId` middleware (JWT auth context)
  - `CircuitBreaker` (熔断器状态)
  - `video_repo::*` (数据库访问函数)
- 🔴 **强耦合**:
  - `Config` 结构体 (包含所有服务配置)
  - `AppError` 枚举 (错误类型转换)
  - `DeepLearningInferenceService` (embedding 生成)

**关键端点**:
```
POST   /videos/upload/init         - 初始化上传 (生成 presigned URL)
POST   /videos/upload/complete     - 完成上传验证
POST   /videos/:id/processing/complete - 标记处理完成
POST   /videos                     - 创建视频元数据
GET    /videos/:id                 - 获取视频详情
PATCH  /videos/:id                 - 更新视频元数据
DELETE /videos/:id                 - 软删除视频
GET    /videos/:id/stream          - 获取 HLS/DASH manifest
GET    /videos/:id/progress        - 获取处理进度
POST   /videos/:id/like            - 点赞视频
POST   /videos/:id/share           - 分享视频
GET    /videos/:id/similar         - 获取相似视频 (基于 embedding)
```

---

### 1.2 handlers/uploads.rs (491行) - 🟡 中度耦合

**内部依赖**:
```rust
use crate::config::Config;
use crate::db::{upload_repo, video_repo};
use crate::error::{AppError, Result};
use crate::middleware::UserId;
use crate::models::UploadStatus;
use crate::services::resumable_upload_service::ResumableUploadService;
use crate::services::s3_service;
```

**外部依赖**:
```rust
actix_multipart::Multipart                                   // 文件上传
actix_web::{web, HttpMessage, HttpRequest, HttpResponse}
sqlx::PgPool
uuid::Uuid
```

**依赖分析**:
- ✅ **可移植**: actix_multipart, standard libraries
- ⚠️ **需适配**:
  - `UserId` middleware
  - `upload_repo::*`, `video_repo::*`
  - `Config` (S3 配置)
- 🟢 **低耦合**:
  - `ResumableUploadService` (可整体迁移)
  - `s3_service` (可整体迁移)

**关键端点**:
```
POST   /uploads/init                      - 初始化分块上传
PUT    /uploads/:id/chunks/:index         - 上传单个分块
POST   /uploads/:id/complete              - 完成分块上传
GET    /uploads/:id                       - 获取上传状态
DELETE /uploads/:id                       - 取消上传
```

---

### 1.3 handlers/transcoding_progress.rs (60行) - 🟢 低耦合

**内部依赖**:
```rust
use crate::middleware::jwt_auth::UserId;
use crate::services::transcoding_progress_handler::{
    ProgressStreamActor, ProgressStreamRegistry
};
```

**外部依赖**:
```rust
actix_web::{web, HttpMessage, HttpRequest, HttpResponse}
actix_web_actors::ws                                         // WebSocket 支持
uuid::Uuid
```

**依赖分析**:
- ✅ **可移植**: WebSocket 仅依赖 actix_web_actors
- ⚠️ **需适配**: `UserId` middleware
- 🟢 **独立模块**: `ProgressStreamRegistry` 可整体迁移

**关键端点**:
```
GET    /videos/:id/progress/stream        - WebSocket 实时进度推送
```

---

### 1.4 services/video_service.rs (85行) - 🟢 低耦合

**内部依赖**:
```rust
use crate::config::video_config::VideoConfig;
use crate::config::S3Config;
use crate::error::{AppError, Result};
use crate::services::s3_service;
```

**外部依赖**:
```rust
uuid::Uuid
tracing::{info}
```

**依赖分析**:
- ✅ **可直接复制**: 仅依赖配置结构体和 s3_service
- 🟢 **零业务逻辑耦合**: 纯工具函数
- ⚠️ **需适配**: `VideoConfig`, `S3Config` 结构体定义

**核心函数**:
```rust
generate_presigned_upload_url()   - 生成 S3 presigned URL
validate_video_metadata()         - 元数据校验
start_processing()                - 启动处理任务 (placeholder)
parse_hashtags()                  - 解析 hashtags
```

---

### 1.5 services/s3_service.rs (639行) - 🟢 零内部依赖

**内部依赖**:
```rust
use crate::config::S3Config;
use crate::error::AppError;
```

**外部依赖**:
```rust
aws_sdk_s3::presigning::PresigningConfig
aws_sdk_s3::Client
sha2::{Digest, Sha256}
```

**依赖分析**:
- ✅ **可立即迁移**: 仅依赖 `S3Config` 和 `AppError`
- ✅ **完整测试覆盖**: 22个单元测试 (#[cfg(test)])
- 🟢 **零耦合**: 纯 S3 操作封装

**核心函数**:
```rust
generate_presigned_url()          - 生成上传 URL
verify_s3_object_exists()         - 验证对象存在
verify_file_hash()                - SHA256 完整性校验
get_s3_client()                   - 创建 S3 客户端
upload_image_to_s3()              - 上传图片到 S3
delete_s3_object()                - 删除 S3 对象
generate_cloudfront_url()         - 生成 CDN URL
health_check()                    - S3 健康检查
```

---

### 1.6 services/transcoding_optimizer.rs (522行) - 🟢 零内部依赖

**内部依赖**:
```rust
use crate::config::video_config::VideoProcessingConfig;
use crate::error::{AppError, Result};
```

**外部依赖**:
```rust
tokio::sync::{Mutex, RwLock}
std::collections::VecDeque
tracing::{debug, error, info}
```

**依赖分析**:
- ✅ **可立即迁移**: 仅依赖配置和错误类型
- ✅ **完整测试**: 7个单元测试
- 🟢 **独立调度器**: 优先级队列 + 并行任务管理

**核心功能**:
```rust
QualityTier enum                  - 4K/1080p/720p/480p 质量层级
PrioritizedTranscodingJob         - 带优先级的转码任务
TranscodingOptimizer              - 并行转码调度器
  - queue_all_qualities()         - 为所有质量层级创建任务
  - process_next_job()            - 按优先级处理下一个任务
  - update_progress()             - 更新任务进度
  - mark_completed/failed()       - 标记任务状态
  - get_statistics()              - 获取调度器统计信息
  - get_ffmpeg_command()          - 生成 FFmpeg 命令
```

---

## 📝 Part 2: 数据库依赖分析

### 2.1 video_repo.rs (150+ lines) - 🔴 强耦合

**依赖的表**:
```sql
videos                            -- 视频元数据
video_engagement                  -- 互动数据 (like, share, view)
video_processing_pipeline_status  -- 处理流程状态
video_upload_sessions             -- 上传会话
video_embeddings                  -- ML embedding vectors
```

**迁移策略**:
1. **复制整个 repository 到 video-service**
2. **修改**: 将 `use crate::models::video::*` 改为本地模型
3. **新增**: video-service 独立的 database pool

### 2.2 upload_repo.rs (100+ lines) - 🔴 强耦合

**依赖的表**:
```sql
uploads                           -- 分块上传会话
upload_chunks                     -- 上传分块记录
```

**迁移策略**:
1. **复制到 video-service**
2. **保持接口不变**: 函数签名和返回类型
3. **测试**: 上传流程端到端测试

---

## 🛠️ Part 3: 错误处理与认证

### 3.1 AppError 枚举

**user-service 定义** (error.rs):
```rust
pub enum AppError {
    Database(#[from] sqlx::Error),
    Redis(#[from] redis::RedisError),
    Authentication(String),
    NotFound(String),
    BadRequest(String),
    Internal(String),
    // ... 12+ variants
}
```

**迁移策略**:
- ✅ **方案 1 (推荐)**: 在 video-service 创建独立的 `VideoServiceError` 枚举
- ⚠️ **方案 2**: 复用 user-service 的 `AppError` (通过共享 error-types crate)

**新 VideoServiceError 示例**:
```rust
#[derive(Debug, Error)]
pub enum VideoServiceError {
    #[error("Database error: {0}")]
    Database(#[from] sqlx::Error),

    #[error("S3 error: {0}")]
    S3(String),

    #[error("Transcoding error: {0}")]
    Transcoding(String),

    #[error("Video not found: {0}")]
    NotFound(String),

    #[error("Invalid video format: {0}")]
    InvalidFormat(String),

    #[error("Authentication required")]
    Unauthorized,
}
```

### 3.2 UserId Middleware

**user-service 实现** (middleware/jwt_auth.rs):
```rust
pub struct UserId(pub Uuid);

impl FromRequest for UserId {
    // 从 JWT token 提取 user_id
    // 插入到 HttpRequest.extensions()
}
```

**迁移策略**:
- 🔴 **必须保留**: video-service 需要验证用户身份
- ✅ **方案 1**: 复制 JWT middleware 到 video-service
- ✅ **方案 2**: 创建 auth-middleware shared library
- ⚠️ **方案 3**: 使用 API Gateway 验证 JWT，传递 user_id via header

**推荐方案 2**: 创建 `libs/auth-middleware`
```rust
// libs/auth-middleware/src/lib.rs
pub struct UserId(pub Uuid);
pub struct JwtAuthMiddleware { /* ... */ }

// video-service/Cargo.toml
[dependencies]
auth-middleware = { path = "../../libs/auth-middleware" }
```

---

## 🎯 Part 4: 迁移行动清单

### Phase 1: 准备阶段 (Day 1-2)

#### 1.1 创建 video-service 基础结构
```bash
mkdir -p backend/video-service/src/{handlers,services,db,models,config,middleware}
cd backend/video-service
cargo init
```

#### 1.2 配置 Cargo.toml
```toml
[dependencies]
actix-web = "4.4"
actix-multipart = "0.6"
actix-web-actors = "4.3"
sqlx = { version = "0.7", features = ["postgres", "uuid", "chrono", "runtime-tokio-native-tls"] }
aws-sdk-s3 = "1.9"
tokio = { version = "1.35", features = ["full"] }
uuid = { version = "1.6", features = ["v4", "serde"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
tracing = "0.1"
thiserror = "1.0"
sha2 = "0.10"
hex = "0.4"

# 共享库
error-types = { path = "../libs/error-types" }
auth-middleware = { path = "../libs/auth-middleware" }  # 待创建
```

#### 1.3 创建共享 auth-middleware library
```bash
mkdir -p backend/libs/auth-middleware/src
cd backend/libs/auth-middleware
cargo init --lib
```

**实现 auth-middleware** (`libs/auth-middleware/src/lib.rs`):
```rust
use actix_web::{dev::Payload, Error, FromRequest, HttpRequest};
use actix_web::error::ErrorUnauthorized;
use futures_util::future::{ready, Ready};
use uuid::Uuid;
use std::ops::Deref;

/// Wrapper for authenticated user ID extracted from JWT
#[derive(Debug, Clone, Copy)]
pub struct UserId(pub Uuid);

impl Deref for UserId {
    type Target = Uuid;
    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl FromRequest for UserId {
    type Error = Error;
    type Future = Ready<Result<Self, Self::Error>>;

    fn from_request(req: &HttpRequest, _: &mut Payload) -> Self::Future {
        // 从 JWT middleware 注入的 extensions 中提取 user_id
        ready(
            req.extensions()
                .get::<UserId>()
                .copied()
                .ok_or_else(|| ErrorUnauthorized("User ID not found in request"))
        )
    }
}
```

---

### Phase 2: 零依赖模块迁移 (Day 3-4)

#### 2.1 迁移 s3_service.rs
**步骤**:
1. 复制 `services/s3_service.rs` → `video-service/src/services/s3_service.rs`
2. 修改 imports:
```rust
// Before
use crate::config::S3Config;
use crate::error::AppError;

// After
use crate::config::S3Config;
use crate::error::VideoServiceError as AppError;
```
3. 运行测试: `cargo test s3_service`
4. ✅ **验证**: 所有 22 个测试通过

#### 2.2 迁移 transcoding_optimizer.rs
**步骤**:
1. 复制 `services/transcoding_optimizer.rs`
2. 修改 imports:
```rust
use crate::config::video_config::VideoProcessingConfig;
use crate::error::VideoServiceError as AppError;
```
3. 运行测试: `cargo test transcoding_optimizer`
4. ✅ **验证**: 所有 7 个测试通过

#### 2.3 迁移 video_service.rs
**步骤**:
1. 复制 `services/video_service.rs`
2. 更新依赖:
```rust
use crate::config::video_config::VideoConfig;
use crate::config::S3Config;
use crate::error::VideoServiceError as AppError;
use crate::services::s3_service;
```
3. ✅ **验证**: 编译通过

---

### Phase 3: 数据库层迁移 (Day 5-7)

#### 3.1 创建 video-service database pool

**video-service/src/main.rs**:
```rust
use sqlx::postgres::PgPoolOptions;

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    // 初始化配置
    let config = Config::from_env().expect("Failed to load config");

    // 创建 database pool
    let pool = PgPoolOptions::new()
        .max_connections(config.database.max_connections)
        .connect(&config.database.url)
        .await
        .expect("Failed to connect to Postgres");

    // 运行数据库迁移
    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .expect("Failed to run migrations");

    // 启动服务器...
}
```

#### 3.2 迁移 video_repo.rs
**步骤**:
1. 复制 `db/video_repo.rs` → `video-service/src/db/video_repo.rs`
2. 复制数据模型: `models/video.rs` → `video-service/src/models/video.rs`
3. 修改导入:
```rust
use crate::models::video::{VideoEntity, VideoEngagementEntity, VideoUploadSession};
```
4. ✅ **验证**: 编译通过

#### 3.3 迁移 upload_repo.rs
**步骤**:
1. 复制 `db/upload_repo.rs`
2. 复制模型: `models/video.rs` (ResumableUpload, UploadChunk)
3. ✅ **验证**: 编译通过

#### 3.4 数据库迁移文件处理
```bash
# 复制相关的 migration 文件
cp backend/user-service/migrations/030_create_videos.sql \
   backend/video-service/migrations/001_create_videos.sql

cp backend/user-service/migrations/034_create_resumable_uploads.sql \
   backend/video-service/migrations/002_create_resumable_uploads.sql

# 其他相关 migrations...
```

---

### Phase 4: Handler 层迁移 (Day 8-10)

#### 4.1 迁移 transcoding_progress.rs (最简单)
**步骤**:
1. 复制 `handlers/transcoding_progress.rs`
2. 修改 imports:
```rust
use auth_middleware::UserId;  // 使用共享 auth middleware
use crate::services::transcoding_progress_handler::{
    ProgressStreamActor, ProgressStreamRegistry
};
```
3. 复制 `services/transcoding_progress_handler.rs` (if exists)
4. ✅ **验证**: WebSocket 连接测试

#### 4.2 迁移 uploads.rs (中等复杂度)
**步骤**:
1. 复制 `handlers/uploads.rs`
2. 修改 imports:
```rust
use auth_middleware::UserId;
use crate::config::Config;
use crate::db::{upload_repo, video_repo};
use crate::error::VideoServiceError as AppError;
use crate::services::{s3_service, resumable_upload_service::ResumableUploadService};
```
3. ✅ **验证**: 上传流程测试
```bash
# 测试分块上传流程
curl -X POST http://localhost:8081/api/v1/uploads/init \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"file_name":"test.mp4","file_size":10485760,"chunk_size":5242880}'
```

#### 4.3 迁移 videos.rs (最复杂)
**步骤**:
1. 复制 `handlers/videos.rs`
2. 修改所有 imports:
```rust
use auth_middleware::UserId;
use crate::config::{video_config::VideoConfig, Config};
use crate::db::video_repo;
use crate::error::VideoServiceError as AppError;
use crate::middleware::CircuitBreaker;  // 需要迁移熔断器
use crate::models::video::*;
use crate::services::{
    deep_learning_inference::DeepLearningInferenceService,
    streaming_manifest::StreamingManifestGenerator,
    video_transcoding::VideoMetadata,
    s3_service,
    video_service::VideoService,
};
```
3. **处理 CircuitBreaker**:
   - 选项 A: 复制 `middleware/circuit_breaker.rs` 到 video-service
   - 选项 B: 创建共享 `libs/resilience` library
4. **处理 DeepLearningInferenceService**:
   - 选项 A: 通过 gRPC 调用 user-service 的 inference API
   - 选项 B: 迁移整个 ML inference 到 video-service
   - 选项 C (推荐): 创建独立的 `ml-service`
5. ✅ **验证**: 所有 12 个端点测试

---

### Phase 5: 配置与环境 (Day 11)

#### 5.1 创建 video-service .env
```bash
# video-service/.env
APP_ENV=development
APP_HOST=0.0.0.0
APP_PORT=8081

DATABASE_URL=postgresql://user:pass@localhost:5432/nova_videos
DATABASE_MAX_CONNECTIONS=20

REDIS_URL=redis://localhost:6379
REDIS_POOL_SIZE=10

# S3 配置
S3_BUCKET_NAME=nova-videos
S3_REGION=us-east-1
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
CLOUDFRONT_URL=https://d1234567890.cloudfront.net
S3_PRESIGNED_URL_EXPIRY_SECS=900

# JWT 配置 (用于验证 token)
JWT_SECRET=same_secret_as_user_service
JWT_PUBLIC_KEY_PEM=...

# Kafka (事件发布)
KAFKA_BROKERS=localhost:9092
KAFKA_EVENTS_TOPIC=video-events

# ML Service (可选)
ML_SERVICE_URL=http://localhost:8082
MILVUS_ENABLED=true
MILVUS_HOST=localhost
MILVUS_PORT=19530
```

#### 5.2 配置 NGINX 路由
```nginx
# nginx/nginx.conf

upstream user_service {
    server user-service:8080;
}

upstream video_service {
    server video-service:8081;
}

server {
    listen 80;

    # User service 路由
    location ~ ^/api/v1/(auth|users|posts|followers) {
        proxy_pass http://user_service;
    }

    # Video service 路由
    location ~ ^/api/v1/(videos|uploads) {
        proxy_pass http://video_service;
    }
}
```

#### 5.3 Docker Compose 配置
```yaml
# docker-compose.yml
services:
  video-service:
    build:
      context: ./backend/video-service
      dockerfile: Dockerfile
    ports:
      - "8081:8081"
    environment:
      DATABASE_URL: postgresql://postgres:postgres@postgres:5432/nova_videos
      REDIS_URL: redis://redis:6379
      KAFKA_BROKERS: kafka:9092
    depends_on:
      - postgres
      - redis
      - kafka
```

---

### Phase 6: 测试与验证 (Day 12-14)

#### 6.1 单元测试
```bash
cd backend/video-service

# 测试所有模块
cargo test

# 测试特定模块
cargo test s3_service
cargo test transcoding_optimizer
cargo test video_repo
```

#### 6.2 集成测试
**创建** `video-service/tests/integration_test.rs`:
```rust
#[actix_web::test]
async fn test_video_upload_flow() {
    // 1. 初始化上传
    let init_resp = client.post("/api/v1/videos/upload/init")
        .json(&json!({
            "filename": "test.mp4",
            "file_size": 10485760,
            "content_type": "video/mp4",
            "title": "Test Video"
        }))
        .send()
        .await
        .unwrap();

    assert_eq!(init_resp.status(), 201);

    // 2. 上传到 presigned URL
    // ... (实际 S3 上传)

    // 3. 完成上传
    let complete_resp = client.post("/api/v1/videos/upload/complete")
        .json(&json!({
            "video_id": video_id,
            "upload_token": token,
            "file_hash": computed_sha256,
            "file_size": 10485760
        }))
        .send()
        .await
        .unwrap();

    assert_eq!(complete_resp.status(), 200);
}
```

#### 6.3 端到端测试
```bash
# 启动所有服务
docker-compose up -d

# 运行 E2E 测试脚本
./scripts/test_video_e2e.sh
```

**test_video_e2e.sh**:
```bash
#!/bin/bash
set -e

BASE_URL="http://localhost:8081/api/v1"
TOKEN=$(./scripts/login_get_token.sh)

# 1. 初始化上传
VIDEO_ID=$(curl -X POST "$BASE_URL/videos/upload/init" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"filename":"test.mp4","file_size":10485760,"content_type":"video/mp4","title":"E2E Test"}' \
  | jq -r '.video_id')

echo "✅ Video upload initialized: $VIDEO_ID"

# 2. 模拟上传到 S3
# ... (使用 presigned URL)

# 3. 完成上传
curl -X POST "$BASE_URL/videos/upload/complete" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"video_id":"'$VIDEO_ID'","upload_token":"'$TOKEN'","file_hash":"abc123","file_size":10485760}'

echo "✅ Video upload completed"

# 4. 获取视频详情
curl -X GET "$BASE_URL/videos/$VIDEO_ID" \
  -H "Authorization: Bearer $TOKEN"

echo "✅ Video details retrieved"
```

#### 6.4 性能测试
```bash
# 使用 wrk 进行压力测试
wrk -t4 -c100 -d30s --latency \
  -H "Authorization: Bearer $TOKEN" \
  http://localhost:8081/api/v1/videos/123e4567-e89b-12d3-a456-426614174000
```

---

## 🚨 Part 5: 关键风险与缓解措施

### Risk 1: Database Migration 失败
**风险**: 迁移脚本执行失败导致数据不一致

**缓解**:
1. ✅ 在 staging 环境先测试所有 migrations
2. ✅ 备份数据库: `pg_dump nova > backup_$(date +%Y%m%d).sql`
3. ✅ 使用 sqlx migration rollback 机制
4. ✅ 准备回滚脚本: `./scripts/rollback_migrations.sh`

### Risk 2: JWT Token 验证不一致
**风险**: video-service 无法正确验证 user-service 签发的 token

**缓解**:
1. ✅ 使用相同的 JWT_SECRET 和 JWT_PUBLIC_KEY_PEM
2. ✅ 编写 JWT 验证集成测试
3. ✅ 使用 shared auth-middleware library (推荐)
4. ✅ 文档化 token 格式要求

### Risk 3: S3 Presigned URL 冲突
**风险**: 两个服务生成相同的 S3 key

**缓解**:
1. ✅ 使用不同的 S3 bucket: `nova-videos` (video-service) vs `nova-images` (user-service)
2. ✅ 或者使用不同的 prefix: `videos/` vs `posts/`
3. ✅ 在 S3Config 中明确配置

### Risk 4: 循环依赖
**风险**: video-service 调用 user-service，user-service 又调用 video-service

**缓解**:
1. ✅ 明确服务边界: user-service → video-service (单向依赖)
2. ✅ 使用事件驱动架构: video-service 通过 Kafka 通知 user-service
3. ✅ 禁止 video-service 直接调用 user-service HTTP API

### Risk 5: DeepLearningInferenceService 依赖
**风险**: video embedding 生成依赖 user-service

**缓解**:
1. ✅ **方案 A (推荐)**: 创建独立的 ml-service
2. ⚠️ **方案 B**: video-service 通过 gRPC 调用 user-service ML API
3. ⚠️ **方案 C**: 迁移整个 ML inference 到 video-service

**推荐 ml-service 架构**:
```
video-service → gRPC call → ml-service (port 8082)
                              ├── Milvus integration
                              ├── ONNX runtime
                              └── Embedding generation
```

---

## ✅ Part 6: 验收标准 (Definition of Done)

### 功能完整性
- [ ] 所有 12 个 video endpoints 正常工作
- [ ] 所有 5 个 upload endpoints 正常工作
- [ ] WebSocket progress streaming 正常
- [ ] S3 presigned URL 生成和验证成功
- [ ] 分块上传 (resumable upload) 流程完整

### 质量保证
- [ ] 单元测试覆盖率 > 80%
- [ ] 所有集成测试通过
- [ ] E2E 测试 script 运行成功
- [ ] 性能测试: p99 延迟 < 500ms (GET /videos/:id)
- [ ] 压力测试: 支持 100 并发请求

### 运维就绪
- [ ] Docker image 构建成功
- [ ] docker-compose 启动成功
- [ ] Kubernetes manifests 准备完毕
- [ ] Health check endpoint `/health` 返回 200
- [ ] Metrics endpoint `/metrics` 返回 Prometheus 格式
- [ ] Logging 输出到 stdout (structured JSON)

### 文档完整
- [ ] API 文档 (OpenAPI/Swagger)
- [ ] 部署文档 (README.md)
- [ ] 运维手册 (troubleshooting guide)
- [ ] 架构决策记录 (ADR)

---

## 📋 Part 7: 最终检查清单

### 代码迁移
```
✅ services/s3_service.rs                  → video-service/src/services/s3_service.rs
✅ services/transcoding_optimizer.rs       → video-service/src/services/transcoding_optimizer.rs
✅ services/video_service.rs               → video-service/src/services/video_service.rs
✅ handlers/uploads.rs                     → video-service/src/handlers/uploads.rs
✅ handlers/videos.rs                      → video-service/src/handlers/videos.rs
✅ handlers/transcoding_progress.rs        → video-service/src/handlers/transcoding_progress.rs
✅ db/video_repo.rs                        → video-service/src/db/video_repo.rs
✅ db/upload_repo.rs                       → video-service/src/db/upload_repo.rs
✅ models/video.rs                         → video-service/src/models/video.rs
```

### 配置文件
```
✅ .env                                     → video-service/.env
✅ Cargo.toml                               → video-service/Cargo.toml
✅ Dockerfile                               → video-service/Dockerfile
✅ docker-compose.yml (add video-service)
✅ nginx.conf (add video routes)
```

### 数据库
```
✅ migrations/030_create_videos.sql         → video-service/migrations/001_create_videos.sql
✅ migrations/034_create_resumable_uploads.sql → video-service/migrations/002_create_resumable_uploads.sql
✅ (复制其他相关 migrations)
```

### 测试
```
✅ tests/unit/s3_service_test.rs
✅ tests/unit/transcoding_optimizer_test.rs
✅ tests/integration/video_upload_test.rs
✅ tests/e2e/video_e2e_test.sh
```

### 部署
```
✅ k8s/video-service-deployment.yaml
✅ k8s/video-service-service.yaml
✅ k8s/video-service-configmap.yaml
✅ k8s/video-service-secret.yaml
```

---

## 🎉 总结

### 可立即迁移 (零风险)
1. ✅ `s3_service.rs` - 完整测试覆盖，零内部依赖
2. ✅ `transcoding_optimizer.rs` - 独立调度器，仅依赖配置

### 需要适配 (中风险)
1. ⚠️ `video_service.rs` - 修改配置导入
2. ⚠️ `uploads.rs` - 修改 auth middleware
3. ⚠️ `transcoding_progress.rs` - WebSocket 依赖

### 需要重构 (高风险)
1. 🔴 `videos.rs` - 深度依赖 CircuitBreaker, DeepLearningInferenceService
2. 🔴 `video_repo.rs` + `upload_repo.rs` - 需要独立 database pool
3. 🔴 `AppError` → `VideoServiceError` - 全局错误类型迁移

### 推荐的共享库
1. ✅ `libs/auth-middleware` - JWT authentication
2. ✅ `libs/error-types` - 标准化错误响应
3. ⚠️ `libs/resilience` (可选) - CircuitBreaker, retry logic
4. ⚠️ `ml-service` (推荐) - 独立的 ML inference service

### 预估工作量
- **Phase 1-2**: 2-3 天 (基础设施 + 零依赖模块)
- **Phase 3**: 3-4 天 (数据库层)
- **Phase 4**: 3-4 天 (Handler 层)
- **Phase 5-6**: 3-4 天 (配置 + 测试)
- **总计**: 11-15 天 (约 2-3 周)

---

**生成日期**: 2025-10-30
**分析工具**: Linus Code Review
**下一步**: 创建 Phase 1 的详细实施 PR
