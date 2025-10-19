# Reels & Video Feed System (Phase 4) - Design Document

**Status**: Design Phase
**Created**: 2025-10-19
**Last Updated**: 2025-10-19

---

## 1. Overview

### Design Approach

Phase 4 extends the existing Phase 3 personalized feed system with video-specific capabilities:

1. **Layered Architecture**:
   - Video Processing Layer (transcoding, CDN delivery)
   - Deep Learning Layer (embedding generation, similarity search)
   - Feed Ranking Layer (video-specific weights)
   - Streaming Layer (adaptive bitrate selection)

2. **Reuse Strategy**:
   - Leverage Phase 3's feed ranking infrastructure (ClickHouse, Redis, Kafka)
   - Extend existing RankedPost model to include video metadata
   - Reuse error handling, monitoring, and authentication patterns
   - Share cache infrastructure and circuit breakers

3. **New Integrations**:
   - FFmpeg (video transcoding)
   - TensorFlow Serving (deep learning inference)
   - Milvus/Weaviate (vector embeddings)
   - CloudFront/Cloudflare (CDN)
   - HLS.js/ExoPlayer (streaming players)

---

## 2. System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    CLIENT LAYER                              │
│  Web (HLS.js) | iOS (AVPlayer) | Android (ExoPlayer)        │
└────────────────────┬────────────────────────────────────────┘
                     │ Adaptive Bitrate (HLS/DASH)
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                   CDN LAYER                                  │
│  CloudFront / Cloudflare (video chunks, manifest)           │
└────────────────────┬────────────────────────────────────────┘
                     │
    ┌────────────────┼────────────────┐
    ▼                ▼                ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│   API Server │ │    Kafka     │ │   S3/GCS     │
│ (Phase 3+4)  │ │   (events)   │ │ (video orig) │
└──────────────┘ └──────────────┘ └──────────────┘
    │                │                │
    │                ▼                ▼
    │         ┌──────────────────────────────┐
    │         │  Processing Workers          │
    │         │  (FFmpeg, TensorFlow, etc)   │
    │         └──────────────────────────────┘
    │                │      │      │
    │                ▼      ▼      ▼
    │         ┌──────────────────────────────┐
    │         │    ClickHouse (Analytics)    │
    │         │  - videos, video_events      │
    │         │  - video_embeddings          │
    │         │  - watch_history             │
    │         └──────────────────────────────┘
    │
    ├─────────────────────┐
    │                     │
    ▼                     ▼
┌──────────────┐    ┌──────────────┐
│    Redis     │    │   Milvus     │
│ (cache,      │    │ (vector DB)  │
│  rankings)   │    │ (embeddings)  │
└──────────────┘    └──────────────┘
    ▲
    │
    └─────────┬─────────────────────┐
              │                     │
        ┌─────────────────┐  ┌─────────────────┐
        │  Deep Learning  │  │  Ranking Engine │
        │  Layer          │  │  (Phase 3+4)    │
        │ (TF Serving)    │  │                 │
        └─────────────────┘  └─────────────────┘
```

### Data Flow

```
User Upload Video
  ├─ POST /api/v1/reels/upload
  ├─ Store in S3 (original)
  ├─ Produce to Kafka (video.uploaded event)
  │
  └─> Video Processing Worker
      ├─ Fetch from S3
      ├─ FFmpeg Transcode (multiple bitrates)
      ├─ Extract Thumbnails & Preview GIF
      ├─ Generate Embeddings (TensorFlow)
      ├─ Store transcoded videos in CDN
      ├─ Store metadata in PostgreSQL
      ├─ Insert embeddings into Milvus
      └─ Update ClickHouse videos table
         └─> Video now visible in Feed

User Requests Feed
  ├─ GET /api/v1/reels?limit=50
  ├─ Check Redis cache (feed:{user_id})
  │
  ├─ If MISS:
  │  ├─ Query Milvus for similar videos (user embedding)
  │  ├─ Query ClickHouse for trending videos
  │  ├─ Query Phase 3 followee videos
  │  ├─ Combine & rank (deep model scores + engagement)
  │  ├─ Cache in Redis (TTL: 60s)
  │  └─ Return ranked video IDs
  │
  └─> Video streaming
      ├─ Client detects network speed
      ├─ CDN serves appropriate bitrate (HLS manifest)
      ├─ Client switches bitrate as needed (ABR)
      └─ Produce watch events to Kafka
         └─> Events consumed by ClickHouse
```

---

## 3. Component Design

### 3.1 Video Upload Service

**Location**: `src/services/video_upload.rs`

```rust
pub struct VideoUploadService {
    s3_client: Arc<S3Client>,
    kafka_producer: Arc<KafkaProducer>,
    postgres_pool: Arc<PgPool>,
}

impl VideoUploadService {
    pub async fn upload_video(
        &self,
        user_id: Uuid,
        file: web::Bytes,
        metadata: VideoMetadata,
    ) -> Result<Uuid> {
        // 1. Validate file (size ≤500MB, codec check)
        // 2. Store original in S3
        // 3. Create DB record (status: "uploading")
        // 4. Produce Kafka event (video.uploaded)
        // 5. Return video_id
    }

    pub async fn get_upload_status(
        &self,
        video_id: Uuid,
    ) -> Result<UploadStatus> {
        // Query PostgreSQL videos table
        // Return status: uploading/processing/published
    }
}
```

**Endpoints**:
- `POST /api/v1/reels/upload` - Upload video
- `GET /api/v1/reels/{video_id}/status` - Check upload status

---

### 3.2 Video Processing Worker

**Location**: `src/workers/video_processor.rs`

```rust
pub struct VideoProcessor {
    s3_client: Arc<S3Client>,
    ffmpeg_pool: Arc<FFmpegPool>,
    tf_client: Arc<TensorFlowClient>,
    milvus_client: Arc<MilvusClient>,
    clickhouse_client: Arc<ClickHouseClient>,
    kafka_consumer: Arc<KafkaConsumer>,
}

impl VideoProcessor {
    pub async fn process_video(&self, video_id: Uuid) -> Result<()> {
        // 1. Fetch original from S3
        // 2. Run FFmpeg transcode (720p, 480p, 360p)
        // 3. Extract thumbnails
        // 4. Generate video embeddings (TensorFlow)
        // 5. Upload transcoded videos to CDN
        // 6. Store embeddings in Milvus
        // 7. Update PostgreSQL (status: published)
        // 8. Insert into ClickHouse videos table
        // 9. Cache metadata in Redis
    }
}
```

**Job Queue**:
- Triggered by Kafka event (video.uploaded)
- Runs in background worker pool
- Scales based on queue depth

---

### 3.3 Deep Learning Integration

**Location**: `src/services/deep_recall.rs`

```rust
pub struct DeepRecallService {
    tf_serving: Arc<TensorFlowServingClient>,
    milvus_client: Arc<MilvusClient>,
}

impl DeepRecallService {
    pub async fn get_user_embedding(&self, user_id: Uuid) -> Result<Vec<f32>> {
        // Query user watch history from ClickHouse
        // Aggregate video embeddings (weighted by completion_rate)
        // Return user embedding
    }

    pub async fn get_similar_videos(
        &self,
        user_embedding: Vec<f32>,
        limit: usize,
    ) -> Result<Vec<Uuid>> {
        // Query Milvus for top-K similar video embeddings
        // Return video IDs
    }

    pub async fn generate_video_embedding(
        &self,
        video_frames: Vec<Frame>,
    ) -> Result<Vec<f32>> {
        // Send to TensorFlow Serving
        // Return embedding vector (256 or 512 dims)
    }
}
```

---

### 3.4 Video Ranking Service

**Location**: `src/services/video_ranking.rs`

Extends Phase 3's FeedRankingService:

```rust
pub struct VideoRankingService {
    phase3_ranking: Arc<FeedRankingService>,
    deep_recall: Arc<DeepRecallService>,
    ch_client: Arc<ClickHouseClient>,
}

impl VideoRankingService {
    pub async fn rank_video_candidates(
        &self,
        user_id: Uuid,
        candidates: Vec<VideoCandidate>,
    ) -> Result<Vec<RankedVideo>> {
        // For each candidate:
        // 1. Calculate video_completion_score (primary)
        // 2. Calculate engagement_score (likes, shares, comments)
        // 3. Calculate affinity_score (creator affinity from Phase 3)
        // 4. Combine with deep model score from TensorFlow
        // Final score = 0.40*completion + 0.30*engagement + 0.20*affinity + 0.10*deep_model
        // Sort by score, apply dedup & saturation rules
        // Return top-50 videos
    }
}
```

---

### 3.5 Streaming Controller

**Location**: `src/handlers/streaming.rs`

```rust
pub struct StreamingController {
    cdn_client: Arc<CDNClient>,
    ch_client: Arc<ClickHouseClient>,
}

pub async fn get_hls_manifest(
    video_id: Uuid,
    user_agent: String,
) -> Result<HttpResponse> {
    // 1. Detect device (web/iOS/Android)
    // 2. Generate HLS manifest with available bitrates
    // 3. Include bandwidth recommendations
    // 4. Return m3u8 manifest
    // Expected: <100ms latency
}

pub async fn get_video_chunk(
    video_id: Uuid,
    bitrate: String,
    segment_id: u32,
) -> Result<HttpResponse> {
    // 1. Redirect to CDN URL
    // 2. CDN handles actual content delivery
    // 3. Produce watch event (segment watched)
    // 4. Return 302 redirect
}
```

---

### 3.6 Video Analytics Service

**Location**: `src/services/video_analytics.rs`

```rust
pub struct VideoAnalyticsService {
    ch_client: Arc<ClickHouseClient>,
}

pub async fn get_video_analytics(
    video_id: Uuid,
) -> Result<VideoAnalytics> {
    // Query ClickHouse video_events table
    // Calculate:
    // - Total views, likes, shares, comments
    // - Completion rate distribution
    // - Average watch time
    // - Trending trajectory
    // - Audience demographics
    // Return analytics object
}
```

**Endpoint**:
- `GET /api/v1/reels/{video_id}/analytics`

---

## 4. Data Models

### PostgreSQL Schema Extensions

```sql
-- Videos (authoritative source)
CREATE TABLE videos (
    id UUID PRIMARY KEY,
    creator_id UUID REFERENCES users(id),
    title VARCHAR(255) NOT NULL,
    description TEXT,
    duration_seconds INT,
    upload_url VARCHAR(512),
    status VARCHAR(50), -- 'uploading', 'processing', 'published', 'failed'
    processing_started_at TIMESTAMP,
    processing_completed_at TIMESTAMP,
    published_at TIMESTAMP,
    deleted_at TIMESTAMP,
    content_type VARCHAR(50), -- 'original', 'challenge', 'duet', 'reaction'
    hashtags JSONB, -- ["music", "dance", "trending"]
    audio_attribution_url VARCHAR(512),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_creator_published (creator_id, published_at),
    INDEX idx_status (status)
);

-- Video engagement (denormalized from events)
CREATE TABLE video_engagement (
    video_id UUID PRIMARY KEY REFERENCES videos(id),
    view_count BIGINT DEFAULT 0,
    like_count BIGINT DEFAULT 0,
    share_count BIGINT DEFAULT 0,
    comment_count BIGINT DEFAULT 0,
    watch_complete_count BIGINT DEFAULT 0,
    completion_rate NUMERIC(3,2),
    avg_watch_seconds INT,
    last_updated TIMESTAMP
);
```

### ClickHouse Schema Extensions

```sql
-- Video metadata (replicated from PostgreSQL via CDC)
CREATE TABLE videos (
    video_id UUID,
    creator_id UUID,
    title String,
    description String,
    duration_seconds UInt32,
    status String,
    published_at DateTime,
    hashtags Array(String),
    created_at DateTime
) ENGINE = ReplacingMergeTree(_version)
ORDER BY (creator_id, published_at);

-- Video engagement events (real-time)
CREATE TABLE video_events (
    event_id UUID,
    video_id UUID,
    user_id UUID,
    action String, -- 'watch_start', 'watch_25%', 'watch_50%', 'watch_75%', 'watch_complete', 'like', 'share', 'comment'
    watch_duration_seconds UInt32,
    bitrate_selected String, -- '720p', '480p', '360p'
    device String, -- 'web', 'ios', 'android'
    event_time DateTime
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (video_id, event_time);

-- Video embeddings (for similarity search)
CREATE TABLE video_embeddings (
    video_id UUID,
    embedding Array(Float32), -- 256 or 512 dimensions
    model_version String, -- e.g., 'resnet-v2', 'efficientnet-b7'
    generated_at DateTime,
    _version UInt64
) ENGINE = ReplacingMergeTree(_version)
ORDER BY video_id;

-- Watch history (for user embedding aggregation)
CREATE TABLE watch_history (
    user_id UUID,
    video_id UUID,
    watched_at DateTime,
    completion_rate Float32,
    avg_watch_seconds UInt32
) ENGINE = MergeTree()
ORDER BY (user_id, watched_at);
```

---

## 5. API Contracts

### Video Upload
```
POST /api/v1/reels/upload
Content-Type: multipart/form-data

{
  "video": <binary>,
  "title": "My awesome dance",
  "description": "Check this out!",
  "hashtags": ["dance", "music"],
  "audio_url": "/api/v1/sounds/123"
}

Response 202 Accepted:
{
  "video_id": "uuid-123",
  "status": "uploading",
  "upload_progress": 45
}
```

### Get Reels Feed
```
GET /api/v1/reels?limit=30&cursor=base64_offset

Response 200:
{
  "videos": [
    {
      "video_id": "uuid-1",
      "creator_id": "uuid-creator",
      "title": "My dance",
      "duration_seconds": 45,
      "view_count": 1000,
      "like_count": 250,
      "completion_rate": 0.85,
      "thumbnail_url": "https://cdn.com/thumb.jpg",
      "streaming_url": "https://cdn.com/manifest.m3u8",
      "score": 0.95,
      "reason": "deep_recall"
    }
  ],
  "cursor": "base64_next_offset",
  "has_more": true,
  "cache_hit": true,
  "response_time_ms": 145
}
```

### Video Analytics
```
GET /api/v1/reels/{video_id}/analytics

Response 200:
{
  "video_id": "uuid-123",
  "view_count": 5000,
  "like_count": 1200,
  "share_count": 300,
  "comment_count": 450,
  "completion_rate": 0.78,
  "avg_watch_seconds": 35,
  "trending_score": 0.92,
  "audience": {
    "top_countries": ["US", "BR", "IN"],
    "top_interests": ["music", "dance"],
    "age_distribution": {"18-25": 0.45, "25-35": 0.35}
  }
}
```

---

## 6. Error Handling Strategy

### Video Processing Errors
```rust
pub enum VideoProcessingError {
    InvalidFormat,           // Unsupported codec
    TranscodingFailed,       // FFmpeg error
    EmbeddingGenerationFailed, // TensorFlow error
    StorageError,            // S3/CDN error
    DatabaseError,           // ClickHouse/PostgreSQL error
    MilvusError,             // Vector DB error
}

// Retry Strategy:
// - Transient errors (network): Exponential backoff (3 retries, 5s-30s)
// - Permanent errors (invalid format): Move to DLQ (dead letter queue)
// - Partial failures: Store in Redis with TTL for manual review
```

### Streaming Errors
```rust
// If CDN unavailable: Serve from backup CDN
// If video not found in CDN: Fetch from S3 (slower but works)
// If adaptive bitrate selection fails: Default to 480p
// If HLS manifest generation fails: Return 503 Service Unavailable
```

---

## 7. Testing Strategy

### Unit Tests (Fast, <100ms each)
- Video metadata validation
- Ranking score calculation
- Embedding similarity computation
- HLS manifest generation

### Integration Tests (Moderate, <1s each)
- Video upload → transcoding → CDN → feed (E2E)
- Milvus similarity search accuracy
- Redis caching behavior
- ClickHouse event aggregation

### Performance Tests (Slow, <5min each)
- 1000 concurrent video uploads
- 100k video ranking requests/sec
- Deep model inference latency (P95 <200ms)
- Streaming bitrate switching latency (<500ms)

### Chaos Tests
- CDN unavailable → fallback to S3
- Deep model timeout → use rule-based ranking
- ClickHouse down → serve cached results
- Milvus unavailable → use trending fallback

---

## 8. Deployment Strategy

### Phase 4 Rollout

**Week 1: Infrastructure Setup**
- Deploy TensorFlow Serving cluster
- Set up Milvus vector DB
- Configure CDN for video delivery
- Create ClickHouse tables

**Week 2: Feature Rollout (Canary)**
- 5% traffic: Video upload + transcoding
- 10% traffic: Video feed ranking (mixed with Phase 3)
- Monitor: Processing latency, embedding quality, ranking diversity

**Week 3: Full Rollout**
- 50% traffic: Full video feed (50/50 with images)
- Optimize: Ranking weights, cache TTLs, model hyperparams
- Monitor: User engagement, completion rate, CTR

**Week 4: Stabilization**
- 100% traffic: Video-first feed (images as fallback)
- A/B tests: Ranking algorithms, deep model versions, UI variations
- Optimize: Cost (CDN, compute), user experience

---

## 9. Monitoring & Observability

### Key Metrics
```
video.upload_duration_seconds (P50, P95, P99)
video.transcoding_duration_seconds (P50, P95)
deep_model.inference_duration_ms (P50, P95)
feed.ranking_latency_ms (P50, P95)
cdn.bitrate_switch_count (per 1k views)
watch.completion_rate_distribution (P25, P50, P75, P95)
```

### Alerts
```
- Video processing queue depth > 10,000
- Deep model inference latency P95 > 500ms
- CDN bitrate 360p > 30% (indicates poor network)
- Video completion rate P50 < 60% (indicates content quality issue)
- Transcoding job failure rate > 1%
```

---

## 10. Security Considerations

### Video Content
- Malware scanning on upload (ClamAV)
- Content moderation API (Clarity AI)
- DRM encryption for premium content (optional)
- Copyright detection (Content ID)

### User Data
- Video watch history encrypted at rest
- User embeddings stored securely
- Rate limiting: 100 uploads/user/day
- IP-based geo-blocking for regional content

### API Security
- JWT authentication on all endpoints
- Rate limiting per user/IP
- CORS configured for frontend domains
- SQL injection prevention (parameterized queries)

---
