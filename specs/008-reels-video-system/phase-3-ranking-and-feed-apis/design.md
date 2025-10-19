# Phase 4 Phase 3: Video Ranking & Feed APIs - Design Document

**Status**: Design Phase
**Version**: 1.0
**Last Updated**: 2025-10-19

---

## Overview

This design implements a **personalized video feed ranking system** that combines multiple ranking signals (freshness, engagement, completion, affinity, deep learning) to generate optimized feeds for each user. The system prioritizes **low latency (P95 ≤300ms)** through aggressive caching and efficient ClickHouse queries, while supporting **real-time engagement tracking** via Redis + async writes to ClickHouse.

**Core Design Philosophy**:
- **Signal-based ranking**: 5-component weighted scoring model instead of heuristics
- **Cache-first architecture**: 95%+ cache hit rate for common feed queries
- **Async-first operations**: Non-blocking engagement tracking with eventual consistency
- **Graceful degradation**: Fallback to simpler models if TensorFlow Serving unavailable
- **Horizontal scalability**: Stateless API layer, shared Redis/ClickHouse backends

---

## Architecture

### System Topology

```
┌─────────────────────────────────────────────────────────────────┐
│                         Client (iOS/Web)                         │
└────────────────────────────┬────────────────────────────────────┘
                             │ HTTP/REST
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                  API Layer (Rust Axum Handlers)                 │
│  ┌──────────┬──────────┬──────────┬──────────┬──────────┐       │
│  │GET /reels│GET /trending-sounds│GET /discover│POST /like│etc. │
│  └────┬─────┴────┬─────┴────┬─────┴────┬─────┴────┬─────┘       │
└───────┼──────────┼──────────┼──────────┼──────────┼──────────────┘
        │          │          │          │          │
        ▼ (check cache first)  │          │          │
┌─────────────────────────────────────────────────────────────────┐
│                         Redis Cache Layer                        │
│  ┌────────────────┬────────────────┬────────────────┐            │
│  │Feed:u:{uid}    │Trending:sounds │Trending:tags  │            │
│  │(TTL: 1h)       │(TTL: 5m)       │(TTL: 5m)      │            │
│  └────────────────┴────────────────┴────────────────┘            │
└──────────┬──────────────────────────────┬──────────────────────┘
           │(miss: query)                 │(write engagement)
           ▼                              ▼
┌─────────────────────┐        ┌──────────────────────┐
│  Ranking Engine     │        │  Redis Queue         │
│  (Rust Service)     │        │  (Engagement Events) │
│  ┌───────────────┐  │        │  - likes             │
│  │Signal Calc    │  │        │  - watches           │
│  │(5-part score) │  │        │  - shares            │
│  └───────────────┘  │        │  - comments          │
└─────────┬───────────┘        └──────────┬───────────┘
          │                               │ (async batch write)
          │ (ClickHouse queries)          ▼
          │                     ┌──────────────────────┐
          │                     │  Kafka Consumer      │
          │                     │  (CDC → ClickHouse)  │
          │                     └──────────────────────┘
          │                               │
          ▼                               ▼
┌──────────────────────────────────────────────────────┐
│              ClickHouse Analytics DB                 │
│  ┌───────────────┬───────────────┬────────────────┐ │
│  │video_ranking_ │trending_sounds│user_watch_     │ │
│  │signals_1h     │_hourly        │history_realtime│ │
│  └───────────────┴───────────────┴────────────────┘ │
└──────────────────────────────────────────────────────┘
          ▲
          │ (deep learning features)
          │
          ▼
┌──────────────────────────────────────────────────────┐
│         Deep Learning Service (Optional)             │
│  ┌─────────────────────────────────────────────────┐ │
│  │TensorFlow Serving (embeddings)                  │ │
│  │  ▼                                              │ │
│  │Milvus Vector DB (similarity search)             │ │
│  └─────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────┘
```

### Request Flow: Feed Generation

```
1. User requests: GET /api/v1/reels?cursor=X
    ↓
2. Check Redis cache for Feed:u:{user_id}
    ├─ HIT (95% case): Return cached videos + new cursor
    │
    └─ MISS (5% case):
        ↓
3. Query user profile (follow list, preferences)
    ↓
4. Parallel queries to ClickHouse:
    ├─ Recent published videos (last 30 days)
    ├─ Completion rates (last 24h aggregation)
    ├─ Engagement scores (likes, shares, comments)
    ├─ User-creator affinity scores
    └─ User's watch history (dedup)
    ↓
5. For each video: CALCULATE_RANK_SCORE(video)
    score = (0.15 × freshness)
          + (0.40 × completion_rate)
          + (0.25 × engagement_score)
          + (0.15 × affinity_score)
          + (0.05 × deep_model_score)  [optional, fallback to 0]
    ↓
6. Sort videos by score (DESC)
    ↓
7. Apply deduplication (user's last 30 days)
    ↓
8. Return top 30-50 videos + next_cursor
    ↓
9. Cache result in Redis (TTL: 1h)
    ↓
10. Return to client: {videos: [...], next_cursor: "..."}
```

### Component Interactions

```
┌─────────────┐
│  FeedService│ (Orchestrates feed generation)
└──────┬──────┘
       │ depends on
       ├──────────────────┬──────────────────┬────────────────────┐
       ▼                  ▼                  ▼                    ▼
┌─────────────┐  ┌────────────────┐  ┌──────────────┐  ┌──────────────────┐
│RankingEngine│  │CacheManager    │  │ClickHouseDB  │  │DeepLearningService│
│             │  │                │  │              │  │                  │
│- 5-signal   │  │- Redis ops     │  │- Video query │  │- Embeddings      │
│  scoring    │  │- Cache warming │  │- Signals agg │  │- Similarity      │
│             │  │- TTL mgmt      │  │- History     │  │- Health checks   │
└─────────────┘  └────────────────┘  └──────────────┘  └──────────────────┘
```

---

## Components and Interfaces

### 1. FeedRankingService

**Responsibility**: Orchestrate feed generation with caching

```rust
pub struct FeedRankingService {
    cache: Redis,
    db: ClickHouse,
    ranker: RankingEngine,
    deep_learning: DeepLearningService,
}

pub async fn get_personalized_feed(
    &self,
    user_id: Uuid,
    cursor: Option<String>,
    limit: u32,  // 30-50
) -> Result<FeedResponse> {
    // 1. Try cache first
    let cache_key = format!("feed:u:{}", user_id);
    if let Ok(cached) = self.cache.get(&cache_key).await {
        return Ok(cached);
    }

    // 2. Query signals from ClickHouse
    let signals = self.db.query_ranking_signals(user_id).await?;

    // 3. Rank videos
    let ranked = self.ranker.rank_videos(&signals).await?;

    // 4. Apply dedup (last 30 days)
    let deduped = self.dedup_videos(&ranked, user_id, 30).await?;

    // 5. Cache and return
    let result = FeedResponse { videos: deduped[0..limit] };
    self.cache.set(&cache_key, &result, TTL::Hours(1)).await?;
    Ok(result)
}

pub async fn record_engagement(
    &self,
    user_id: Uuid,
    video_id: Uuid,
    event_type: EngagementType,  // Like, Watch, Share, Comment
) -> Result<()> {
    // 1. Update Redis counter (optimistic)
    self.cache.increment(&format!("video:{}:{}", video_id, event_type)).await?;

    // 2. Queue for ClickHouse (async)
    self.db.queue_engagement_event(user_id, video_id, event_type).await?;

    // 3. Invalidate feed cache for user
    self.cache.delete(&format!("feed:u:{}", user_id)).await?;

    Ok(())
}
```

**API Endpoints**:
```
GET /api/v1/reels
  Query params:
    - cursor (optional): pagination cursor
    - limit (optional, default: 40): 30-50 videos
  Response:
    {
      "videos": [
        {
          "id": "uuid",
          "creator_id": "uuid",
          "title": "string",
          "duration_seconds": 15,
          "thumbnail_url": "https://...",
          "view_count": 1523,
          "like_count": 245,
          "comment_count": 18,
          "share_count": 42,
          "completion_rate": 0.87,
          "url_720p": "https://...",
          "url_480p": "https://...",
          "url_360p": "https://..."
        }
      ],
      "next_cursor": "next_pagination_token"
    }
  Performance: P95 ≤ 300ms (≤100ms if cached)
```

### 2. RankingEngine

**Responsibility**: Calculate personalized ranking scores

```rust
pub struct RankingEngine {
    config: RankingConfig,
}

pub struct RankingConfig {
    pub freshness_weight: f32,      // 0.15
    pub completion_weight: f32,     // 0.40
    pub engagement_weight: f32,     // 0.25
    pub affinity_weight: f32,       // 0.15
    pub deep_model_weight: f32,     // 0.05
}

#[derive(Debug)]
pub struct RankingSignals {
    pub video_id: Uuid,
    pub freshness_score: f32,       // (1 - hours_old / 720) clamped [0, 1]
    pub completion_rate: f32,       // 0.0-1.0
    pub engagement_score: f32,      // normalized (likes + shares*2 + comments*0.5) / total_views
    pub affinity_score: f32,        // user's prior interaction with creator
    pub deep_model_score: f32,      // embedding similarity [0, 1]
}

impl RankingEngine {
    pub async fn rank_videos(
        &self,
        signals: &[RankingSignals],
    ) -> Result<Vec<(Uuid, f32)>> {
        // Calculate weighted score
        let mut scored: Vec<_> = signals.iter().map(|s| {
            let score = (
                s.freshness_score * self.config.freshness_weight +
                s.completion_rate * self.config.completion_weight +
                s.engagement_score * self.config.engagement_weight +
                s.affinity_score * self.config.affinity_weight +
                s.deep_model_score * self.config.deep_model_weight
            );
            (s.video_id, score)
        }).collect();

        scored.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
        Ok(scored)
    }

    pub fn calculate_freshness_score(&self, hours_old: f32) -> f32 {
        // Decay function: videos lose relevance over time
        // After 30 days (720h), score approaches 0
        let decay = 1.0 - (hours_old / 720.0).min(1.0);
        decay.powi(2)  // Quadratic decay for steeper falloff
    }

    pub fn calculate_engagement_score(
        &self,
        likes: u32,
        shares: u32,
        comments: u32,
        total_views: u32,
    ) -> f32 {
        if total_views == 0 { return 0.0; }

        // Weighted engagement: shares = 2x value, comments = 0.5x
        let weighted_engagement = (likes as f32) + (shares as f32 * 2.0) + (comments as f32 * 0.5);
        (weighted_engagement / (total_views as f32)).min(1.0)
    }
}
```

### 3. CacheManager

**Responsibility**: Redis cache operations with TTL management

```rust
pub struct CacheManager {
    redis: RedisClient,
}

impl CacheManager {
    pub async fn get_feed(&self, user_id: Uuid) -> Result<Option<FeedResponse>> {
        let key = format!("feed:u:{}", user_id);
        self.redis.get(&key).await
    }

    pub async fn set_feed(
        &self,
        user_id: Uuid,
        feed: &FeedResponse,
        ttl_secs: u64,
    ) -> Result<()> {
        let key = format!("feed:u:{}", user_id);
        self.redis.set_ex(&key, feed, ttl_secs).await
    }

    pub async fn invalidate_feed(&self, user_id: Uuid) -> Result<()> {
        let key = format!("feed:u:{}", user_id);
        self.redis.del(&key).await
    }

    pub async fn warm_cache(&self, top_users: Vec<Uuid>) -> Result<()> {
        // Pre-populate cache for active users
        for user_id in top_users {
            // Query and cache (non-blocking)
            tokio::spawn(async move {
                // Warm feed cache
            });
        }
        Ok(())
    }
}
```

### 4. TrendingService

**Responsibility**: Calculate and serve trending content

```rust
pub struct TrendingService {
    db: ClickHouse,
    cache: Redis,
}

pub struct TrendingResponse {
    pub sound_id: String,
    pub name: String,
    pub usage_count: u32,
    pub video_samples: Vec<Uuid>,  // Top 3 videos using this sound
}

impl TrendingService {
    pub async fn get_trending_sounds(
        &self,
        category: Option<String>,
        limit: u32,  // Default 100
    ) -> Result<Vec<TrendingResponse>> {
        let cache_key = format!("trending:sounds:{}", category.unwrap_or_default());

        // Try cache (5min TTL)
        if let Ok(cached) = self.cache.get(&cache_key).await {
            return Ok(cached);
        }

        // Query last 24h data
        let results = self.db.query(
            "SELECT sound_id, COUNT(*) as usage_count
             FROM video_ranking_signals_1h
             WHERE hour >= now() - INTERVAL 24 HOUR
             GROUP BY sound_id
             ORDER BY usage_count DESC
             LIMIT ?",
            &[limit],
        ).await?;

        // Cache result
        self.cache.set(&cache_key, &results, TTL::Minutes(5)).await?;
        Ok(results)
    }

    pub async fn get_trending_hashtags(
        &self,
        category: Option<String>,
        limit: u32,
    ) -> Result<Vec<TrendingResponse>> {
        // Similar logic to sounds
        todo!()
    }

    pub async fn get_trending_creators(
        &self,
        limit: u32,  // Default 20
    ) -> Result<Vec<CreatorResponse>> {
        // Based on follower growth rate in last 24h
        todo!()
    }
}
```

### 5. SearchService

**Responsibility**: Full-text video search

```rust
pub struct SearchService {
    db: ClickHouse,
}

pub async fn search_videos(
    &self,
    query: String,
    filters: SearchFilters,
) -> Result<Vec<VideoResponse>> {
    // ClickHouse full-text search
    let sql = "SELECT * FROM videos
              WHERE (title LIKE ? OR description LIKE ? OR tags LIKE ?)
              AND status = 'published'
              AND created_at > ?";

    let results = self.db.query(sql, &[
        &query,
        &query,
        &query,
        &filters.date_from,
    ]).await?;

    Ok(results)
}
```

---

## Data Models

### ClickHouse Tables (Extensions)

```sql
-- 1. Hourly aggregated ranking signals
CREATE TABLE video_ranking_signals_1h (
    video_id UUID,
    hour DateTime,
    completion_rate Float32,      -- avg completion percentage
    engagement_score Float32,     -- (likes*1 + shares*2 + comments*0.5) / views
    affinity_boost Float32,       -- creator relationship boost
    deep_model_score Float32,     -- embedding similarity score
    view_count UInt32,
    like_count UInt32,
    share_count UInt32,
    comment_count UInt32
) ENGINE = MergeTree()
ORDER BY (hour, video_id);

-- 2. Real-time watch history (for deduplication)
CREATE TABLE user_watch_history_realtime (
    user_id UUID,
    video_id UUID,
    watched_at DateTime,
    completion_percent UInt8,
    PRIMARY KEY (user_id, video_id)
) ENGINE = ReplacingMergeTree()
ORDER BY (user_id, video_id);

-- 3. Trending sounds calculation (hourly)
CREATE TABLE trending_sounds_hourly (
    sound_id String,
    hour DateTime,
    video_count UInt32,
    usage_rank UInt32,
    PRIMARY KEY (hour, sound_id)
) ENGINE = MergeTree()
ORDER BY (hour, sound_id);

-- 4. Trending hashtags calculation (hourly)
CREATE TABLE trending_hashtags_hourly (
    hashtag String,
    hour DateTime,
    post_count UInt32,
    trend_rank UInt32,
    PRIMARY KEY (hour, hashtag)
) ENGINE = MergeTree()
ORDER BY (hour, hashtag);
```

### PostgreSQL Tables (Metadata)

```sql
-- Deep learning model versioning
CREATE TABLE deep_recall_models (
    id UUID PRIMARY KEY,
    model_version STRING NOT NULL,
    deployed_at TIMESTAMP NOT NULL,
    is_active BOOLEAN DEFAULT FALSE,
    performance_metrics JSONB,  -- {accuracy, f1_score, latency_ms}
    created_at TIMESTAMP DEFAULT NOW()
);

-- Feed cache metadata (optional)
CREATE TABLE feed_cache_stats (
    user_id UUID NOT NULL,
    cache_hit_at TIMESTAMP,
    cache_size INT,
    PRIMARY KEY (user_id, cache_hit_at)
);
```

---

## Error Handling

### Graceful Degradation Strategy

```
Request Flow with Error Handling:

GET /api/v1/reels
  │
  ├─ Cache miss → Query ClickHouse
  │   │
  │   ├─ ClickHouse timeout (>500ms)
  │   │  → USE YESTERDAY'S CACHED SIGNALS (materialized view)
  │   │  → Return videos ranked with stale data (P95: ~50ms)
  │   │
  │   ├─ Deep learning service DOWN
  │   │  → SKIP deep_model_score (0.05 weight)
  │   │  → Use 4-signal ranking instead
  │   │  → Performance impact: ~5% engagement lift reduction
  │   │
  │   └─ Redis down
  │      → Query directly from ClickHouse every time
  │      → P95 latency: ~300ms instead of 100ms
  │
  └─ Success → Cache result (1h TTL)
```

### Circuit Breaker Pattern

```rust
pub struct ServiceHealthCheck {
    tf_serving_health: Arc<AtomicBool>,
    milvus_health: Arc<AtomicBool>,
    clickhouse_health: Arc<AtomicBool>,
}

impl FeedRankingService {
    pub async fn get_personalized_feed(&self, user_id: Uuid) -> Result<FeedResponse> {
        let signals = self.db.query_ranking_signals(user_id).await?;

        // Only use deep learning if healthy
        let deep_scores = if self.health.tf_serving_health.load(Relaxed) {
            self.deep_learning.get_scores(&signals).await.unwrap_or_default()
        } else {
            // Fallback: no deep learning
            vec![0.0; signals.len()]
        };

        // Proceed with 4-signal ranking
        self.ranker.rank_with_fallback(&signals, &deep_scores).await
    }
}
```

### Error Types

```rust
pub enum FeedError {
    // Retriable errors
    ClickHouseTimeout,           // Retry with exponential backoff
    CacheConnectionLost,         // Fall back to direct DB query

    // Non-retriable errors
    InvalidUser,                 // Return 400
    PermissionDenied,           // Return 403
    RankingAlgorithmError,      // Return 500 (circuit break)

    // Degradation errors
    DeepLearningUnavailable,    // Use 4-signal ranking instead
}
```

---

## Testing Strategy

### Unit Tests

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ranking_signal_calculation() {
        let engine = RankingEngine::new(RankingConfig::default());

        // Test freshness decay
        assert_eq!(engine.calculate_freshness_score(0.0), 1.0);      // New
        assert_eq!(engine.calculate_freshness_score(360.0), 0.75);   // 15 days
        assert!(engine.calculate_freshness_score(720.0) < 0.1);     // 30 days
    }

    #[test]
    fn test_engagement_scoring() {
        let engine = RankingEngine::new(RankingConfig::default());

        let score = engine.calculate_engagement_score(100, 10, 5, 1000);
        assert!(score > 0.1 && score < 0.15);  // ~12.5%
    }

    #[test]
    fn test_weighted_ranking() {
        let engine = RankingEngine::new(RankingConfig::default());

        let signals = vec![
            RankingSignals { freshness: 1.0, completion: 0.8, engagement: 0.1, affinity: 0.5, deep_model: 0.0 },
            RankingSignals { freshness: 0.5, completion: 0.9, engagement: 0.2, affinity: 0.5, deep_model: 0.0 },
        ];

        let ranked = engine.rank_videos(&signals);
        assert_eq!(ranked[0].1 > ranked[1].1, true);  // Higher score first
    }
}
```

### Integration Tests

```rust
#[tokio::test]
async fn test_end_to_end_feed_generation() {
    let service = setup_test_service().await;
    let user_id = Uuid::new_v4();

    // 1. Create test videos
    create_test_videos(5).await;

    // 2. Record engagement
    service.record_engagement(user_id, video_1_id, EngagementType::Like).await.unwrap();

    // 3. Get feed
    let feed = service.get_personalized_feed(user_id, None, 40).await.unwrap();

    assert!(feed.videos.len() > 0);
    assert_eq!(feed.videos[0].id, video_1_id);  // Most recently liked
}

#[tokio::test]
async fn test_cache_hit_performance() {
    let service = setup_test_service().await;
    let user_id = Uuid::new_v4();

    // First call: cache miss
    let start = Instant::now();
    let _feed1 = service.get_personalized_feed(user_id, None, 40).await.unwrap();
    let first_duration = start.elapsed();

    // Second call: cache hit
    let start = Instant::now();
    let _feed2 = service.get_personalized_feed(user_id, None, 40).await.unwrap();
    let second_duration = start.elapsed();

    // Cache hit should be 5-10x faster
    assert!(second_duration < first_duration / 5);
}
```

### Performance Tests

```rust
#[tokio::test]
async fn test_p95_latency_with_cache() {
    // Generate 1000 requests
    // Measure latency percentiles

    let latencies = generate_feed_requests(1000).await;
    let p95 = percentile(&latencies, 95);

    assert!(p95 < Duration::from_millis(100));  // Target: 100ms with cache
}

#[tokio::test]
async fn test_deep_learning_fallback() {
    let service = setup_test_service().await;

    // Disable TensorFlow Serving
    service.health.tf_serving_health.store(false, Relaxed);

    // Feed should still work
    let feed = service.get_personalized_feed(Uuid::new_v4(), None, 40).await;
    assert!(feed.is_ok());
}
```

### Load Testing

- Target: 100k concurrent feed requests/hour
- Tool: Apache JMeter or custom Rust load test
- Metrics:
  - P50 latency < 50ms
  - P95 latency < 300ms (cache miss) or < 100ms (cache hit)
  - P99 latency < 1s
  - Error rate < 0.1%

---

## Deployment Strategy

### Phased Rollout

```
Phase 1: Canary (1% of users, 1 hour)
  ├─ Monitor: latency, errors, ranking quality
  └─ Success criteria: P95 < 300ms, errors < 0.1%

Phase 2: Ramp (10% of users, 4 hours)
  └─ Monitor: same metrics at 10x scale

Phase 3: Full (100% of users)
  └─ Maintain SLA monitoring
```

### Infrastructure

- **Compute**: 4 Axum handler instances (auto-scaling 2-8)
- **Cache**: Redis cluster (3 nodes, 128GB total)
- **DB**: ClickHouse cluster (3 nodes for HA)
- **Deep Learning**: TensorFlow Serving (2-4 GPU instances)

### Cache Warming

```rust
pub async fn warm_cache_before_deployment() {
    let top_1000_users = fetch_active_users_by_engagement(1000).await;

    for user_id in top_1000_users {
        cache_manager.warm_feed(user_id).await;
    }
}
```

---

## Monitoring & Alerting

### Key Metrics

| Metric | Target | Alert Threshold |
|--------|--------|-----------------|
| Feed P95 latency | ≤300ms | >500ms |
| Cache hit rate | ≥95% | <85% |
| Deep learning availability | ≥99.5% | <99% |
| ClickHouse query time | <500ms | >1000ms |
| Ranking signal freshness | <10min | >30min |
| Trending data staleness | <5min | >15min |

### Dashboards

1. **User Experience Dashboard**
   - Feed latency (P50/P95/P99)
   - Cache hit rate
   - CTR by ranking signal weight

2. **System Health Dashboard**
   - ClickHouse query performance
   - Redis memory usage
   - TensorFlow Serving inference latency
   - Kafka event processing lag

3. **Ranking Quality Dashboard**
   - Average completion rate
   - Engagement rate by signal weight
   - A/B test results (if enabled)

### Alerting Rules

```
if feed_p95_latency > 500ms for 5 minutes
  → alert: "Feed latency degradation"
  → action: check ClickHouse performance

if cache_hit_rate < 85% for 10 minutes
  → alert: "Cache hit rate low"
  → action: investigate Redis or check for deployment change

if deep_learning_latency > 200ms
  → alert: "TensorFlow Serving slow"
  → action: scale up GPU instances or failover to simpler model
```

---

**文件版本**: 1.0
**最後更新**: 2025-10-19
**狀態**: Design Phase Complete - Awaiting Approval
