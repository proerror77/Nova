# Reels & Video Feed System (Phase 4) - Requirements Document

**Feature**: Reels & Video Feed System (Phase 4)
**Status**: In Planning
**Created**: 2025-10-19
**Dependencies**: Phase 3 (Personalized Feed Ranking System)

---

## 目標與邊界

- **目標**：將 Feed 從圖片貼文擴展到短視頻 (Reels)，集成深度學習召回模型，支持自適應流媒體質量，實現視頻內容的個性化排序。
- **邊界**：僅支持短視頻 (≤10 分鐘)；直播、長視頻另起後續 Phase；版權審核和內容安全由第三方服務負責。

---

## Core Features

### 1. 視頻特定的排序算法
- 支持視頻完成率 (watch-through rate) 作為核心指標
- 視頻觀看時長 (engagement depth) 權重調整
- 視頻分享和互動數據集成
- 視頻內容類型分類 (music, comedy, dance, tutorial, etc.)

### 2. 深度召回模型集成
- 集成預訓練的深度學習模型 (推薦用 TensorFlow/PyTorch)
- 向量相似度搜索 (使用 Milvus/Weaviate)
- 實時特徵提取 (user features, video features)
- 在線學習能力 (A/B 測試支持)

### 3. 視頻處理管道
- 上傳時自動轉碼 (HEVC/H.264, 多比率率)
- 縮略圖提取 (首幀 + 預覽 GIF)
- 字幕/OCR 處理 (元數據提取)
- 檔案存儲到 CDN (S3/Cloudflare)

### 4. 自適應質量流 (ABR)
- 根據網絡速度自動選擇碼率 (720p/480p/360p)
- 支持 HLS/DASH 流媒體協議
- 播放進度本地緩存 (斷點續播)
- 預加載下一個視頻 (seamless experience)

### 5. 社交發現功能
- 推薦用戶 (creator recommendation)
- 熱門聲音/音樂 (trending audios)
- 視頻標籤雲 (hashtag trending)
- 參與挑戰 (challenge/trend participation)

### 6. 分析與監測
- 視頻完成度分佈 (completion rate histogram)
- 跳轉分析 (where users drop off)
- 互動漏斗 (like → share → comment)
- 推薦效果指標 (CTR, engagement lift)

---

## User Stories

### User Story 1: 觀看個性化視頻 Feed (Priority: P0)
**As a** content consumer,
**I want to** browse a personalized feed of short videos (Reels),
**So that** I can discover and enjoy content tailored to my interests with minimal scrolling friction.

**Acceptance Criteria:**
- GET /api/v1/reels returns 30-50 video IDs ranked by relevance
- P95 latency ≤ 300ms (using deep recall model)
- Video metadata includes: video_id, creator_id, view_count, like_count, completion_rate, duration
- Cache hit rate ≥95% (Redis TTL: 60s)

---

### User Story 2: 上傳和發佈短視頻 (Priority: P0)
**As a** content creator,
**I want to** upload a short video, add metadata, and publish it to the feed,
**So that** my content is discoverable by the community.

**Acceptance Criteria:**
- POST /api/v1/reels/upload accepts video file (≤500MB)
- Auto-transcoding completes within 5 minutes
- Video appears in feed within 10 seconds of publish
- Metadata editable: title, description, hashtags, audio attribution

---

### User Story 3: 互動與發現 (Priority: P1)
**As a** user,
**I want to** like, share, comment on videos and discover trending creators/sounds,
**So that** I can engage with content and find new creators.

**Acceptance Criteria:**
- Like/comment/share actions tracked and increment engagement counters
- GET /api/v1/reels/trending-sounds returns top 100 sounds
- GET /api/v1/reels/trending-hashtags returns trending tags
- Trending lists update every 5 minutes

---

### User Story 4: 自適應流媒體播放 (Priority: P1)
**As a** user on mobile with variable network,
**I want** videos to stream smoothly at appropriate quality,
**So that** I have a seamless viewing experience without buffering.

**Acceptance Criteria:**
- Automatic bitrate switching based on network speed
- Support HLS/DASH protocols
- Fallback to 360p if network degrades
- Buffering < 2 seconds at startup

---

### User Story 5: 數據分析與優化 (Priority: P2)
**As a** creator/analytics team,
**I want to** see video performance metrics and audience insights,
**So that** I can optimize content and understand viewer behavior.

**Acceptance Criteria:**
- GET /api/v1/reels/:id/analytics returns: views, likes, shares, completion_rate, avg_watch_time
- Audience demographics (age, location, interests) when available
- Trending trajectory tracking (growth over time)
- Benchmarking against similar videos

---

## Acceptance Criteria (System Level)

### Functional Requirements
- [ ] Video upload processing pipeline handles 100+ concurrent uploads
- [ ] Deep recall model inference latency <200ms per request
- [ ] Video ranking combines deep model scores + engagement signals
- [ ] Streaming supports adaptive bitrate selection
- [ ] Social discovery endpoints (trending sounds/hashtags/creators) functional
- [ ] Full-text search on video metadata (title, description, hashtags)

### Non-Functional Requirements

#### Performance
- Feed API P95 latency: ≤300ms (deep model) vs ≤100ms (cached)
- Video upload: ≤5 minutes to transcoded state
- Transcoding: ≤2x realtime speed (1 hour video = 30 min to transcode)
- Streaming startup: <2 seconds to first frame

#### Reliability
- Video availability: ≥99.9% (SLA)
- Deep recall model uptime: ≥99.5%
- Transcoding job completion rate: ≥99.5%
- Fallback to image-based feed if video service down

#### Scalability
- Support 1M+ concurrent video streams
- Handle 10k+ video uploads/hour
- Deep model inference: 100k+ requests/hour
- ClickHouse ingestion: 1M+ events/hour

#### Security
- Video DRM/encryption (optional, for premium content)
- Malware scanning on uploads (VirusTotal/ClamAV)
- Content moderation API integration
- Rate limiting: 100 uploads per user per day

#### Compatibility
- Codecs: H.264, HEVC (VP9 optional)
- Container: MP4, WebM, MKV
- Protocols: HTTP/2, QUIC (for CDN)
- Players: Web (HLS.js), iOS (AVPlayer), Android (ExoPlayer)

---

## Data Model Extensions (Phase 3 → Phase 4)

### New Tables in ClickHouse
```sql
-- Video metadata
CREATE TABLE videos (
  video_id UUID,
  creator_id UUID,
  title String,
  description String,
  duration_seconds UInt32,
  created_at DateTime,
  published_at DateTime,
  views UInt64,
  likes UInt64,
  shares UInt64,
  comments UInt64,
  completion_rate Float32,
  average_watch_time UInt32
) ENGINE = MergeTree
ORDER BY (creator_id, created_at);

-- Video engagement events (watch, like, share, comment)
CREATE TABLE video_events (
  event_id UUID,
  video_id UUID,
  user_id UUID,
  action String, -- 'watch_complete', 'like', 'share', 'comment', 'skip'
  watch_duration_seconds UInt32,
  event_time DateTime
) ENGINE = MergeTree
PARTITION BY toYYYYMM(event_time)
ORDER BY (video_id, event_time);

-- Video embeddings (from deep recall model)
CREATE TABLE video_embeddings (
  video_id UUID,
  embedding Array(Float32), -- 256 or 512 dimensions
  model_version String,
  generated_at DateTime
) ENGINE = ReplacingMergeTree(_version)
ORDER BY video_id;

-- User watch history (for next video prediction)
CREATE TABLE watch_history (
  user_id UUID,
  video_id UUID,
  watched_at DateTime,
  completion_rate Float32
) ENGINE = MergeTree
ORDER BY (user_id, watched_at);
```

### PostgreSQL Extensions
```sql
-- Video metadata (authoritative source)
CREATE TABLE videos (
  id UUID PRIMARY KEY,
  creator_id UUID REFERENCES users(id),
  title VARCHAR(255),
  description TEXT,
  duration_seconds INT,
  upload_url VARCHAR(512),
  status VARCHAR(50), -- 'uploading', 'processing', 'published', 'deleted'
  created_at TIMESTAMP,
  published_at TIMESTAMP,
  deleted_at TIMESTAMP,
  content_type VARCHAR(50), -- 'original', 'challenge', 'duet', 'reaction'
  hashtags JSONB
);

-- Engagement (normalized from events)
CREATE TABLE video_engagement (
  video_id UUID PRIMARY KEY,
  view_count BIGINT,
  like_count BIGINT,
  share_count BIGINT,
  comment_count BIGINT,
  completion_rate NUMERIC(3,2),
  avg_watch_seconds INT,
  last_updated TIMESTAMP
);
```

---

## Integration Points

### With Phase 3 (Personalized Feed Ranking)
- Use existing ranking infrastructure (freshness, engagement, affinity)
- Extend RankedPost model to support video metadata
- Reuse ranking weights, but video-specific tuning needed
- Share cache infrastructure (Redis, ClickHouse)

### New External Integrations
- **Video Processing**: FFmpeg (transcoding), ImageMagick (thumbnails)
- **CDN**: Cloudflare, AWS CloudFront (video delivery)
- **Deep Learning**: TensorFlow Serving, Triton Inference Server
- **Vector DB**: Milvus, Weaviate (embeddings search)
- **Content Moderation**: Clarity AI, Azure Content Moderator

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Feed Engagement (videos) | CTR ≥20% vs images 15% | Events/feed API call |
| Video Completion Rate | P50 ≥70%, P95 ≥50% | Events table aggregation |
| Deep Model Effectiveness | +15% engagement lift vs baseline | A/B test results |
| Transcoding SLA | ≤5 min 99.9% of uploads | Job queue metrics |
| Stream Quality | ≥95% viewers see ≥720p | CDN metrics |
| Daily Active Viewers | 50% of feed users view reels | Analytics |

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Deep model inference latency | Feed slow | Batch processing + caching |
| Video storage costs | Budget overrun | Tiered storage (hot/cold), compression |
| Transcoding bottleneck | Video queue buildup | Auto-scaling transcoding workers |
| Inappropriate content | Brand risk | Integration with content moderation API |
| CDN costs | Budget overrun | Regional caching, video lifecycle cleanup |
| Model staleness | Suboptimal recommendations | Online retraining pipeline |
