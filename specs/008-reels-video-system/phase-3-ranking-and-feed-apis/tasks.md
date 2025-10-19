# Phase 4 Phase 3: Video Ranking & Feed APIs - Task List

**Status**: Tasks Phase
**Version**: 1.0
**Last Updated**: 2025-10-19

---

## Implementation Tasks

### Phase A: Foundation (Data Models & Configuration)

- [x] **Task 1: Extend ClickHouse Schema with Ranking Signals Tables**
    - [x] 1.1. Create video_ranking_signals_1h table
        - *Goal*: Store hourly aggregated ranking signals for feed ranking
        - *Details*:
          - Create MergeTree table with columns: video_id, hour, completion_rate, engagement_score, affinity_boost, deep_model_score, view_count, like_count, share_count, comment_count
          - Add ORDER BY (hour, video_id) for efficient queries
          - Add TTL policy: 90 days retention
          - Create materialized view from raw events table
        - *Requirements*: Req-1.5.1 (Data Model Extensions), Req-2.1 (Trending Discovery)
        - *Estimated Time*: 1.5 hours
        - *Acceptance Criteria*: Table created, tested via `SELECT COUNT(*) FROM video_ranking_signals_1h`, materialized view auto-populates

    - [x] 1.2. Create user_watch_history_realtime table
        - *Goal*: Track user's watch history for deduplication (last 30 days)
        - *Details*:
          - Create ReplacingMergeTree with columns: user_id, video_id, watched_at, completion_percent
          - PRIMARY KEY (user_id, video_id) for fast lookups
          - ORDER BY (user_id, video_id)
          - Add 30-day TTL
        - *Requirements*: Req-1.5.1, Req-1.1 (Video Feed API - deduplication)
        - *Estimated Time*: 1 hour
        - *Acceptance Criteria*: Dedup queries run in <10ms for typical user (1000 videos)

    - [x] 1.3. Create trending tables (sounds & hashtags)
        - *Goal*: Store hourly trending calculations for 5-minute cache updates
        - *Details*:
          - trending_sounds_hourly: sound_id, hour, video_count, usage_rank
          - trending_hashtags_hourly: hashtag, hour, post_count, trend_rank
          - Both with MergeTree engine, ORDER BY (hour, id)
          - Materialized views aggregate from last 24 hours
        - *Requirements*: Req-2.1 (Trending Discovery)
        - *Estimated Time*: 1.5 hours
        - *Acceptance Criteria*: Trending queries return top 100 items in <100ms

    - [x] 1.4. Create PostgreSQL table for deep learning model versioning
        - *Goal*: Track model deployments and performance metrics
        - *Details*:
          - Table: deep_recall_models (id, model_version, deployed_at, is_active, performance_metrics JSONB, created_at)
          - Create migration script (e.g., 012_deep_learning_models.sql)
          - Add indices on (model_version, is_active)
        - *Requirements*: Req-2.3 (Deep Recall Model Integration)
        - *Estimated Time*: 0.5 hours
        - *Acceptance Criteria*: Migration runs, table queryable, JSONB metrics parseable

    - [x] 1.5. Update ClickHouse init script
        - *Goal*: Automate schema initialization on deployment
        - *Details*:
          - Update backend/clickhouse/init-db.sql to include new tables
          - Add materialized views
          - Ensure idempotence (CREATE TABLE IF NOT EXISTS)
        - *Requirements*: All Phase 3 tables
        - *Estimated Time*: 0.5 hours
        - *Acceptance Criteria*: Docker-compose startup initializes all tables without errors

---

### Phase B: Core Services (Data Access & Business Logic)

- [x] **Task 2: Implement FeedRankingService**
    - [x] 2.1. Create src/services/feed_ranking.rs with FeedRankingService struct
        - *Goal*: Orchestrate personalized feed generation with caching
        - *Details*:
          - FeedRankingService struct with fields: cache (RedisClient), db (ClickHouseClient), ranker (RankingEngine), deep_learning (DeepLearningService)
          - Implement `get_personalized_feed(user_id, cursor, limit)` method
            - Check Redis cache (key: `feed:u:{user_id}`)
            - On miss: query ClickHouse for ranking signals
            - Call ranker.rank_videos()
            - Apply deduplication (last 30 days)
            - Cache result with 1-hour TTL
            - Return top 30-50 videos with pagination cursor
          - Performance target: P95 ≤ 300ms (cache miss), ≤ 100ms (cache hit)
        - *Requirements*: Req-1.1 (Feed API), Req-3.1.1 (Performance P95)
        - *Estimated Time*: 3 hours
        - *Acceptance Criteria*:
          - Latency measurements confirm targets
          - Cache hit rate ≥ 90%
          - Unit tests pass (100% coverage of main paths)

    - [x] 2.2. Implement record_engagement() for like/share/comment tracking
        - *Goal*: Track user interactions and invalidate caches
        - *Details*:
          - Update Redis counter immediately (optimistic update)
          - Queue engagement event to Kafka/ClickHouse for batch processing
          - Invalidate user's feed cache to refresh ranking
          - Handle concurrent updates gracefully
        - *Requirements*: Req-2.5 (Engagement Tracking), Req-3.2.2 (Counters updated ≤ 1s)
        - *Estimated Time*: 2 hours
        - *Acceptance Criteria*:
          - Like count visible immediately in Redis
          - Engagement events appear in ClickHouse within 5 minutes
          - Feed cache invalidated for affected user

    - [x] 2.3. Implement cache warming for deployment
        - *Goal*: Pre-populate Redis cache before full rollout
        - *Details*:
          - Identify top 1000 active users
          - Async generate feeds for each
          - Store in Redis with 1h TTL
          - Non-blocking to avoid deployment delays
        - *Requirements*: Deployment Strategy
        - *Estimated Time*: 1.5 hours
        - *Acceptance Criteria*: Canary users (1%) see <50ms P95 latency

- [x] **Task 3: Implement RankingEngine**
    - [x] 3.1. Create src/services/ranking_engine.rs with 5-signal scoring
        - *Goal*: Calculate weighted personalized ranking scores
        - *Details*:
          - RankingEngine struct with RankingConfig (weights: 0.15, 0.40, 0.25, 0.15, 0.05)
          - RankingSignals struct: freshness_score, completion_rate, engagement_score, affinity_score, deep_model_score
          - Implement `rank_videos(signals: &[RankingSignals]) -> Vec<(Uuid, f32)>`
          - Weighted score formula: sum of (signal × weight)
          - Handle edge cases: empty list, NaN scores, all-zero signals
        - *Requirements*: Req-1.1 (Ranking Algorithm), Req-2.1.1 (5-signal model)
        - *Estimated Time*: 2 hours
        - *Acceptance Criteria*:
          - Unit tests: freshness decay, engagement normalization, weighted sum
          - Property testing: all scores in [0, 1]
          - Benchmark: rank 10,000 videos in <50ms

    - [x] 3.2. Implement freshness score decay function
        - *Goal*: Score videos based on publish time (30-day window)
        - *Details*:
          - Quadratic decay: decay = (1 - hours_old/720)²
          - New video (0h): score = 1.0
          - 15 days (360h): score ≈ 0.75
          - 30 days (720h): score ≈ 0.0
          - Clamp negative values to 0
        - *Requirements*: Req-2.1.1 (Freshness Signal 0.15 weight)
        - *Estimated Time*: 0.5 hours
        - *Acceptance Criteria*: Unit tests verify decay curve

    - [x] 3.3. Implement engagement score calculation
        - *Goal*: Normalize engagement metrics (likes, shares, comments)
        - *Details*:
          - Formula: (likes × 1 + shares × 2 + comments × 0.5) / total_views
          - Weighted because shares indicate stronger endorsement
          - Clamp result to [0, 1]
          - Handle division by zero (0 views)
        - *Requirements*: Req-2.1.1 (Engagement Signal 0.25 weight)
        - *Estimated Time*: 0.5 hours
        - *Acceptance Criteria*: Unit tests verify weighted calculation

    - [x] 3.4. Implement affinity score (user-creator history)
        - *Goal*: Boost ranking for creators user has engaged with
        - *Details*:
          - Query: user's historical interactions with creator (90-day window)
          - Score = (prior_likes + prior_comments × 0.5) / max_history_score
          - Cold-start handling: 0.5 if no history
          - Query ClickHouse materialized view for performance
        - *Requirements*: Req-2.1.1 (Affinity Signal 0.15 weight)
        - *Estimated Time*: 1.5 hours
        - *Acceptance Criteria*:
          - User's favorite creators ranked higher
          - Cold-start users get baseline score
          - Query latency <100ms for user_author_90d view

- [x] **Task 4: Implement CacheManager with Redis Operations**
    - [x] 4.1. Create src/services/cache_manager.rs
        - *Goal*: Manage Redis cache with TTL and invalidation
        - *Details*:
          - CacheManager struct wrapping RedisClient
          - Methods: get_feed(), set_feed(), invalidate_feed(), increment_engagement()
          - Key prefixes: `feed:u:{user_id}`, `trending:sounds`, `video:{id}:{type}`
          - TTL policies: feeds 1h, trending 5m, engagement counters no expiry
          - Error handling: graceful fallback if Redis unavailable
        - *Requirements*: Req-3.1.1 (Cache hit rate ≥ 95%)
        - *Estimated Time*: 1.5 hours
        - *Acceptance Criteria*:
          - Cache hits verified in integration tests
          - Hit rate measured >90%
          - Fallback to direct query if cache fails

    - [x] 4.2. Implement circuit breaker for cache failures
        - *Goal*: Gracefully degrade when Redis unavailable
        - *Details*:
          - Circuit breaker pattern: CLOSED → OPEN → HALF_OPEN
          - Track failed requests; open if >50% fail in 10-second window
          - Fall back to direct ClickHouse query (slower but works)
          - Emit alerts when circuit opens
        - *Requirements*: Error Handling (Graceful Degradation)
        - *Estimated Time*: 1 hour
        - *Acceptance Criteria*: System remains functional with Redis down (P95 <300ms)

- [x] **Task 5: Implement TrendingService**
    - [x] 5.1. Create src/services/trending_service.rs
        - *Goal*: Calculate and serve trending content (sounds, hashtags, creators)
        - *Details*:
          - TrendingService struct with db: ClickHouseClient, cache: RedisClient
          - Implement `get_trending_sounds(category, limit) -> Vec<TrendingResponse>`
            - Query trending_sounds_hourly table (last 24h)
            - Sort by usage_count DESC
            - Cache result with 5-minute TTL
            - Default limit 100
          - Similar methods for hashtags and creators
        - *Requirements*: Req-2.1 (Trending Discovery), Req-2.1.2 (5min cache)
        - *Estimated Time*: 2 hours
        - *Acceptance Criteria*:
          - Trending queries return in <100ms (cached)
          - Data refreshed every 5 minutes
          - Top 100 items accurate for last 24h

    - [x] 5.2. Implement materialized views for trending calculations
        - *Goal*: Pre-compute trending rankings hourly in ClickHouse
        - *Details*:
          - Materialized view: aggregate video_ranking_signals_1h by sound_id, group by hour
          - Another view: aggregate by hashtag
          - Rank using row_number() window function
          - Update hourly via background job
        - *Requirements*: Req-2.1.2 (5min/1h update)
        - *Estimated Time*: 1.5 hours
        - *Acceptance Criteria*: Views auto-update hourly without manual intervention

---

### Phase C: API Endpoints & Integration

- [ ] **Task 6: Implement Feed API Endpoints**
    - [x] 6.1. Create GET /api/v1/reels endpoint
        - *Goal*: Return personalized feed for authenticated user
        - *Details*:
          - Query params: cursor (pagination), limit (30-50, default 40)
          - Extract user_id from JWT token
          - Call feed_ranking_service.get_personalized_feed()
          - Return JSON: {videos: [...], next_cursor: "..."}
          - Error handling: 401 (unauthorized), 429 (rate limit), 500 (service error)
          - Rate limit: 100 requests/min per user
        - *Requirements*: Req-1.1 (Feed API), Req-3.4.1 (Rate limiting)
        - *Estimated Time*: 1.5 hours
        - *Acceptance Criteria*:
          - Endpoint responds in P95 ≤ 300ms
          - Pagination works correctly (cursor validity ≥ 1h)
          - Rate limiting enforced

    - [x] 6.2. Create GET /api/v1/reels/stream/:id endpoint
        - *Goal*: Return HLS/DASH manifests for video playback
        - *Details*:
          - Accept Accept-Header: application/vnd.apple.mpegurl (HLS) or application/dash+xml (DASH)
          - Query video quality URLs from database
          - Generate manifest with available quality tiers (720p, 480p, 360p)
          - Support quality parameter in query: ?quality=720p
          - Cache manifests with 1h TTL
        - *Requirements*: Req-1.2 (Video streaming)
        - *Estimated Time*: 1.5 hours
        - *Acceptance Criteria*: HLS/DASH manifests valid, tested with video player

    - [x] 6.3. Create GET /api/v1/reels/progress endpoint
        - *Goal*: Get video processing status
        - *Details*:
          - Query video_processing_pipeline for current stage
          - Return: {stage: "completed", progress_percent: 100, current_step: "..."}
          - Support long-polling or WebSocket for real-time updates (optional)
        - *Requirements*: Req-1.2 (Video processing status)
        - *Estimated Time*: 1 hour
        - *Acceptance Criteria*: Status reflects actual processing stage

- [ ] **Task 7: Implement Engagement Tracking Endpoints**
    - [x] 7.1. Create POST /api/v1/reels/:id/like endpoint
        - *Goal*: Record like action and update engagement metrics
        - *Details*:
          - Extract user_id from JWT, video_id from URL
          - Call feed_ranking_service.record_engagement(user_id, video_id, EngagementType::Like)
          - Return updated like_count (from Redis cache)
          - Support idempotent unlike operation
        - *Requirements*: Req-2.5 (Engagement Tracking), Req-3.2.2 (Counter update ≤ 1s)
        - *Estimated Time*: 1 hour
        - *Acceptance Criteria*: Like count updates in <1 second, visible to all users

    - [x] 7.2. Create POST /api/v1/reels/:id/watch endpoint
        - *Goal*: Track video watch completion
        - *Details*:
          - Record: user_id, video_id, completion_percent (0-100)
          - Aggregate into user_watch_history_realtime
          - Use for deduplication and completion signal
          - Accept batch requests (multiple videos)
        - *Requirements*: Req-2.5, Req-1.1 (Completion rate signal)
        - *Estimated Time*: 1.5 hours
        - *Acceptance Criteria*: Completion rates reflected in ranking within 5 minutes

    - [x] 7.3. Create POST /api/v1/reels/:id/share endpoint
        - *Goal*: Track sharing action with higher weight
        - *Details*:
          - Similar to like, but multiply engagement value by 2x
          - Optional: track share destination (message, story, etc.)
        - *Requirements*: Req-2.5 (Engagement Tracking)
        - *Estimated Time*: 0.5 hours
        - *Acceptance Criteria*: Share engagement weighted 2x vs like in algorithm

- [ ] **Task 8: Implement Trending & Discovery Endpoints**
    - [x] 8.1. Create GET /api/v1/reels/trending-sounds endpoint
        - *Goal*: Return top trending audio clips
        - *Details*:
          - Query params: category (optional, e.g., "music", "comedy"), limit (default 100)
          - Return: {sounds: [{id, name, usage_count, video_samples: [...]}, ...]}
          - Filter by category if provided
          - Cache result 5 minutes
        - *Requirements*: Req-2.1 (Trending Discovery)
        - *Estimated Time*: 1 hour
        - *Acceptance Criteria*: Trending list updates every 5 minutes, accurate rankings

    - [x] 8.2. Create GET /api/v1/reels/trending-hashtags endpoint
        - *Goal*: Return top trending hashtags
        - *Details*:
          - Similar to sounds, but hashtag-based
          - Include post count, trend rank, sample videos
          - Filter by category
        - *Requirements*: Req-2.1 (Trending Discovery)
        - *Estimated Time*: 1 hour
        - *Acceptance Criteria*: Hashtags match real trending data

    - [x] 8.3. Create GET /api/v1/discover/creators endpoint
        - *Goal*: Recommend creators based on follower growth
        - *Details*:
          - Rank creators by follower growth rate (last 24h)
          - Return top 20 with preview videos
          - Exclude already-followed creators
          - Cache 1 hour
        - *Requirements*: Req-2.1.3 (Recommended creators)
        - *Estimated Time*: 1.5 hours
        - *Acceptance Criteria*: Recommended creators reflect actual growth trends

    - [x] 8.4. Create GET /api/v1/reels/search endpoint
        - *Goal*: Full-text search videos by title, description, tags
        - *Details*:
          - Query param: q (search query)
          - Optional filters: creator_id, category, date_range
          - Use ClickHouse full-text search
          - Return top 50 results sorted by relevance
          - P95 latency ≤ 200ms
        - *Requirements*: Req-2.6 (Search & Discovery)
        - *Estimated Time*: 2 hours
        - *Acceptance Criteria*: Search results relevant, latency <200ms, fuzzy matching works

- [ ] **Task 9: Integrate Deep Learning Service**
    - [x] 9.1. Integrate TensorFlow Serving for embeddings
        - *Goal*: Call existing deep_learning_inference_service to generate video embeddings
        - *Details*:
          - In ranking pipeline: call deep_learning_service.generate_embeddings() for each video
          - Batch requests to TensorFlow Serving (limit 100 videos/batch)
          - Use 0.05 weight in ranking formula
          - Handle unavailability gracefully (fallback to 0)
          - Cache embeddings in Milvus vector DB
        - *Requirements*: Req-2.3 (Deep Recall Model Integration), Req-1.2.1 (Inference <200ms)
        - *Estimated Time*: 2 hours
        - *Acceptance Criteria*:
          - Embeddings improve ranking quality by +20% (A/B test)
          - Inference latency <200ms
          - Graceful fallback when TensorFlow unavailable

    - [x] 9.2. Implement similar video recommendation (Milvus search)
        - *Goal*: Use embeddings to find similar videos
        - *Details*:
          - Create GET /api/v1/reels/:id/similar endpoint
          - Query Milvus for top 10 similar videos
          - Return ranked by similarity_score
          - Use existing deep_learning_service.find_similar_videos()
        - *Requirements*: Req-2.6 (Similar video recommendation)
        - *Estimated Time*: 1.5 hours
        - *Acceptance Criteria*: Similar videos are genuinely similar (manual review)

---

### Phase D: Testing & Quality Assurance

- [ ] **Task 10: Implement Unit Tests**
    - [x] 10.1. Test RankingEngine (100% coverage)
        - *Goal*: Verify ranking signal calculations
        - *Details*:
          - Test freshness decay: 0h → 1.0, 360h → 0.75, 720h → ~0
          - Test engagement scoring: normalized formula correct
          - Test affinity calculation: cold-start vs. warm-start
          - Test weighted ranking: output sorted DESC
          - Edge cases: empty list, NaN, division by zero
        - *Estimated Time*: 1.5 hours
        - *Acceptance Criteria*: 100% code coverage, all edge cases covered

    - [x] 10.2. Test CacheManager operations
        - *Goal*: Verify Redis cache behavior
        - *Details*:
          - Test set/get/delete/increment operations
          - Test TTL expiration
          - Test error handling when Redis unavailable
          - Test concurrent access patterns
        - *Estimated Time*: 1 hour
        - *Acceptance Criteria*: All operations idempotent, thread-safe

    - [x] 10.3. Test API endpoint request/response formats
        - *Goal*: Verify API contracts match design
        - *Details*:
          - Test GET /api/v1/reels response structure
          - Test pagination (cursor validity)
          - Test error responses (401, 429, 500)
          - Test rate limiting
          - Use `serde_json` for response validation
        - *Estimated Time*: 2 hours
        - *Acceptance Criteria*: All endpoints return correct JSON schema

- [ ] **Task 11: Implement Integration Tests**
    - [x] 11.1. End-to-end feed generation test
        - *Goal*: Verify full flow from user request to ranked feed
        - *Details*:
          - Create test users and videos in fixtures
          - Record engagement (likes, watches) for some videos
          - Request feed and verify:
            - Videos ranked by score
            - Deduplication works (no repeats in 30 days)
            - Cache populated after first request
            - Second request uses cache (<100ms)
        - *Estimated Time*: 2 hours
        - *Acceptance Criteria*: Full integration test passes, performance targets met

    - [x] 11.2. Test cache invalidation on engagement
        - *Goal*: Verify feed cache refreshes when engagement changes
        - *Details*:
          - Get feed for user
          - Record like for one video
          - Get feed again (should be different)
          - Verify cache invalidated and regenerated
        - *Estimated Time*: 1 hour
        - *Acceptance Criteria*: Cache invalidation propagates correctly

    - [x] 11.3. Test trending calculations
        - *Goal*: Verify trending service returns accurate results
        - *Details*:
          - Create test data with known trending patterns
          - Query trending service
          - Verify rankings match calculation
          - Test cache refresh on interval
        - *Estimated Time*: 1.5 hours
        - *Acceptance Criteria*: Trending results accurate and timely

- [ ] **Task 12: Performance & Load Testing**
    - [x] 12.1. Benchmark feed generation latency
        - *Goal*: Measure P50/P95/P99 latencies
        - *Details*:
          - Generate 1000 concurrent requests
          - Measure latency distribution
          - Verify: P50 <50ms, P95 <300ms, P99 <1s
          - Test both cache hit and miss scenarios
          - Document results
        - *Estimated Time*: 2 hours
        - *Acceptance Criteria*: P95 ≤ 300ms consistently achieved

    - [x] 12.2. Load test trending service
        - *Goal*: Verify trending endpoints handle 100k requests/hour
        - *Details*:
          - Simulate load with Apache JMeter or Rust load test
          - Target: 100k requests/hour = ~28 rps sustained
          - Measure latency, error rate, throughput
          - Verify <0.1% errors
        - *Estimated Time*: 1.5 hours
        - *Acceptance Criteria*: 100k rph sustained with <0.1% errors

    - [x] 12.3. Test graceful degradation scenarios
        - *Goal*: Verify system remains functional with failures
        - *Details*:
          - Test with Redis down: should fallback to direct ClickHouse
          - Test with TensorFlow unavailable: should use 4-signal ranking
          - Test with ClickHouse slow: should use yesterday's cache
          - Measure performance impact
        - *Estimated Time*: 2 hours
        - *Acceptance Criteria*: All failure scenarios handled gracefully

---

### Phase E: Deployment & Operations

- [ ] **Task 13: Implement Monitoring & Alerting**
    - [x] 13.1. Add Prometheus metrics to FeedRankingService
        - *Goal*: Export key metrics for monitoring
        - *Details*:
          - Histogram: feed_generation_duration_ms (with labels: cache_hit, user_segment)
          - Gauge: cache_hit_rate (rolling 5-minute window)
          - Counter: api_requests_total, api_errors_total
          - Gauge: deep_learning_availability
          - Export via Prometheus /metrics endpoint
        - *Estimated Time*: 1.5 hours
        - *Acceptance Criteria*: Metrics visible in Prometheus, dashboards display data

    - [x] 13.2. Create alerting rules in Prometheus
        - *Goal*: Alert on service degradation
        - *Details*:
          - Alert if feed_p95_latency > 500ms for 5 min
          - Alert if cache_hit_rate < 85% for 10 min
          - Alert if error_rate > 0.1% for 5 min
          - Alert if deep_learning unavailable
          - Escalate to on-call via webhook
        - *Estimated Time*: 1 hour
        - *Acceptance Criteria*: Alerts fire correctly when thresholds breached

    - [x] 13.3. Create monitoring dashboards (Grafana)
        - *Goal*: Visualize system health
        - *Details*:
          - Dashboard 1: User Experience (latency, cache hit rate, CTR)
          - Dashboard 2: System Health (ClickHouse, Redis, TensorFlow status)
          - Dashboard 3: Ranking Quality (completion rate, engagement by signal)
          - Dashboard 4: Incident Response (error rates, service statuses)
        - *Estimated Time*: 2 hours
        - *Acceptance Criteria*: Dashboards provide quick system overview

- [ ] **Task 14: Deployment & Rollout**
    - [x] 14.1. Prepare canary deployment (1% of users)
        - *Goal*: Test in production with minimal risk
        - *Details*:
          - Deploy to canary fleet (1 instance)
          - Route 1% of traffic via feature flag
          - Monitor: latency, errors, ranking quality
          - Success criteria: P95 <300ms, errors <0.1%
          - Run for 1 hour before proceeding
        - *Estimated Time*: 1 hour (monitoring only)
        - *Acceptance Criteria*: Canary metrics pass thresholds

    - [x] 14.2. Implement feature flags for gradual rollout
        - *Goal*: Control feed ranking algorithm rollout
        - *Details*:
          - Feature flag: use_new_feed_ranking (default false)
          - Flag controls: which users get new algorithm
          - Gradual ramp: 1% → 10% → 50% → 100%
          - Rollback plan: flip flag back to false
          - Integration with monitoring/alerts
        - *Estimated Time*: 1 hour
        - *Acceptance Criteria*: Feature flag controls rollout cleanly

    - [x] 14.3. Execute full deployment to production
        - *Goal*: Roll out to all users after validation
        - *Details*:
          - Deploy to all 4 Axum instances
          - Warm cache for top 1000 users
          - Ramp feature flag: 10% → 50% → 100% over 4 hours
          - Monitor all metrics continuously
          - Prepare rollback plan
        - *Estimated Time*: 4 hours (monitoring + ramp)
        - *Acceptance Criteria*: 100% of users on new feed ranking, all metrics healthy

---

## Task Dependencies

```
Phase A (Foundation) - Must complete first
├── Tasks 1-5 (data models) can run in parallel
└── Required before: Phase B, Phase C

Phase B (Core Services) - Depends on Phase A
├── Tasks 2-5 (services) can run in parallel
│   └── Task 2 (FeedRankingService) - critical path
│   └── Task 3 (RankingEngine) - critical path
│   └── Task 4 (CacheManager) - depends on Redis
│   └── Task 5 (TrendingService) - depends on ClickHouse
└── Required before: Phase C

Phase C (API Endpoints) - Depends on Phase B
├── Tasks 6-9 (endpoints) can run mostly in parallel
│   └── Task 6 depends on Tasks 2-3
│   └── Task 7 depends on Task 2
│   └── Task 8 depends on Task 5
│   └── Task 9 depends on Task 3
└── Required before: Phase D

Phase D (Testing) - Depends on Phase C
├── Tasks 10-12 (testing) can run in parallel
└── Required before: Phase E

Phase E (Deployment) - Depends on Phase D
├── Tasks 13-14 (monitoring + deployment)
└── Can proceed after Task 12 passes

Critical Path: Task 1 → Task 2 → Task 6 → Task 10 → Task 12 → Task 14
```

---

## Estimated Timeline

| Phase | Tasks | Estimated Hours | Parallel |
|-------|-------|-----------------|----------|
| A: Foundation | 1-5 | 7.5 | Yes (5h parallel, 2.5h serial) |
| B: Core Services | 2-5 | 12 | Yes (8h parallel, 4h serial) |
| C: API Endpoints | 6-9 | 13 | Yes (7h parallel, 6h serial) |
| D: Testing | 10-12 | 12 | Yes (8h parallel, 4h serial) |
| E: Deployment | 13-14 | 6 | Sequential |
| **TOTAL** | **14 tasks** | **~35 hours** | **~22 hours critical path** |

**Recommended Schedule**:
- Day 1-2 (16h): Phase A + Phase B (parallel: foundation + services)
- Day 2-3 (16h): Phase C (API endpoints) + Phase D (testing in parallel)
- Day 3-4 (8h): Phase E (monitoring + canary + full rollout)
- **Total: 3-4 days with proper parallelization**

---

**文件版本**: 1.0
**最後更新**: 2025-10-19
**狀態**: Tasks Phase Complete - Awaiting Approval
