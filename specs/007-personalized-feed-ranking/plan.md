# Implementation Plan: 實時個性化 Feed 排序系統（Phase 3）

**Branch**: `007-personalized-feed-ranking` | **Date**: 2025-10-18 | **Spec**: [spec.md](./spec.md)
**Status**: Ready for Development

## Summary

升級 Feed 從簡單時序流為「個性化排序 + 熱門混排」的混合推薦系統。通過 ClickHouse (OLAP)、Debezium (CDC)、Kafka (事件流)、Redis (快取) 的完整堆棧，實現事件至可見低延遲 ≤ 5 秒。採用三維混合排序：新鮮度 + 參與度 + 親和度，支持關注拉取、熱榜注入、作者親和推薦的混合候選集。14 小時落地計畫，自動故障回退至 PostgreSQL，保障 99.5% 可用性。

---

## Technical Context

**Language/Version**: Rust 1.75+ (Tokio async runtime)  
**Primary Dependencies**: 
- Actix-web (async HTTP server)
- ClickHouse (HTTP client + async driver)
- Kafka (confluent-kafka-rs, async producer)
- Redis (redis-rs, async client)
- sqlx (PostgreSQL async driver)

**Storage**: 
- OLTP: PostgreSQL (existing)
- OLAP: ClickHouse (new)
- Event Stream: Kafka (new)
- Cache: Redis (new)

**Testing**: 
- Unit: cargo test
- Integration: ClickHouse + Kafka Docker Compose
- E2E: latency validation scripts

**Target Platform**: Linux server (AWS/On-prem)  
**Project Type**: Backend service (Rust microservice + ClickHouse OLAP)  
**Performance Goals**: 
- Event-to-visible latency P95 ≤ 5s
- Feed API P95 ≤ 150ms (Redis hit) / ≤ 800ms (CH query)
- 10k concurrent queries support
- 1k events/sec sustained (10k peak)

**Constraints**: 
- CH query ≤ 2s timeout (fallback to PostgreSQL)
- Redis cache TTL 120s (balance freshness + cache hit rate)
- CDC lag < 10s for 99.9% time
- System availability ≥ 99.5%

**Scale/Scope**: 
- ~100k users, 50 followees avg, ~5M follow relations
- ~10M events/day, ~100k posts/day
- Feed cache ~2.5GB total
- ~150–200 implementation tasks

---

## Constitution Check

**GATE**: Must pass Architecture Review before Phase 1 detailed design.

**Stateless API Design**: ✅
- Each request contains full user context (JWT decoded)
- Ranking algorithm deterministic (same user, same time → same score)
- No session affinity or sticky routing needed

**Database Consistency Model**: ✅
- OLTP (PostgreSQL) → eventual consistency → OLAP (ClickHouse, CDC ≤ 30s)
- No strong consistency required; users tolerate ≤ 2min delay for follow changes to reflect in feed
- ReplacingMergeTree + materialized views ensure idempotent aggregation

**Async & Non-Blocking Processing**: ✅
- Event ingestion: async Kafka producer, 202 response before processing
- Feed ranking: async CH queries with timeout + fallback
- Background jobs: Tokio tasks (trending refresh, suggested users computation)

**Error Handling & Resilience**: ✅
- CH query fail → automatic fallback to PostgreSQL time-series (algo=timeline)
- Redis miss → direct CH query (no cascade failures)
- Events loss acceptable (ephemeral data)
- Graceful degradation path clear (CH → PostgreSQL → error)

**No "Needless Complexity"**: ✅
- No ML models in Phase 3 (defer to Phase 4)
- No real-time streaming protocol (Kafka → batch aggregation sufficient)
- No A/B testing framework (manual parameter tuning ok for MVP)
- Single ranking algorithm (not multiple competing algos)

---

## Technology Architecture

### Data Flow Diagram

```
╔═══════════════════════════════════════════════════════════════════════╗
║                        PRODUCTION FLOW                              ║
╚═══════════════════════════════════════════════════════════════════════╝

┌─ PostgreSQL (OLTP) ──────────────────────────────────────────────────┐
│  users, follows, posts, comments, likes (from Phase 001–006)        │
└────┬─────────────────────────────────────────────────────────────────┘
     │ Debezium CDC (logical decoding, ≤ 10s lag)
     ▼
┌─ Kafka Topics ───────────────────────────────────────────────────────┐
│  cdc.posts, cdc.follows, cdc.comments, cdc.likes (retention: 7d)    │
│  events (impression/view/like/comment/share, retention: 3d)         │
└────┬────────────────────────────────────┬──────────────────────────┘
     │                                    │
     │ Materialized Views                 │ Mobile App
     ▼                                    ▼
┌─ ClickHouse (OLAP) ────┐    ┌─ Events API ────────────┐
│  events (TTL 30d)      │    │  POST /events (batch)   │
│  posts (CDC)           │    │  - Validate             │
│  follows (CDC)         │    │  - Deduplicate          │
│  comments (CDC)        │    │  - Kafka produce        │
│  likes (CDC)           │    └─────────────────────────┘
│  post_metrics_1h ──────┼─▶ Hourly aggregation
│  user_author_90d ──────┼─▶ Affinity scoring
└────┬─────┬─────────────┘
     │     │
     │ Ranking Query
     │ (Freshness + Engagement + Affinity)
     │
     ▼     ▼
┌─ Feed Service ──────────────────────────────────────┐
│  GET /api/v1/feed                                   │
│  1. Check Redis cache (feed:v1:{user})              │
│  2. If hit: return cached result                    │
│  3. If miss: query ClickHouse ranking               │
│  4. Compute final_score, deduplicate                │
│  5. Cache in Redis (TTL 120s)                       │
│  6. Return top 50                                   │
│                                                     │
│  Fallback: If CH fails → PostgreSQL time-series    │
└────┬────────────────────────────────────────────────┘
     ▼
┌─ Redis Cache ─────────────────────────────────────┐
│  feed:v1:{user} (ZSET, TTL 120s)                  │
│  hot:posts:1h (ZSET, TTL 60s)                     │
│  suggest:users:{user} (ZSET, TTL 10m)             │
│  seen:{user}:{post} (bloom/hash, TTL 24h)         │
└───────────────────────────────────────────────────┘
```

### Ranking Algorithm

```
final_score = 0.30 * freshness + 0.40 * engagement + 0.30 * affinity

Where:
  freshness = exp(-λ * age_hours)        [λ = 0.1, exponential decay]
  engagement = log1p((L + 2*C + 3*S) / max(1, E))
              [L=likes, C=comments, S=shares, E=exposures]
  affinity = log1p(user_author_interactions_90d)

Weights rationale:
  - Engagement (40%): Primary signal of content quality
  - Freshness (30%): Encourage recent content, but old viral posts still visible
  - Affinity (30%): Personalization based on user's past interactions
```

### Candidate Set Strategy

| Source | Window | Limit | Purpose |
|--------|--------|-------|---------|
| F1: Followees | 72h | ≤500 | Core social graph posts |
| F2: Trending | 24h | Top 200 | Viral/trending discovery |
| F3: Author Affinity | 90d | ≤200 | Personalized based on history |
| **Union** | - | **50 final** | Deduplicate → Rank → Top 50 |

### Deduplication & Saturation

```
Dedup Strategy:
  seen:{user}:{post} bloom filter (TTL 24h)
  - Remove posts user already viewed/interacted
  - 100% dedup rate = 0% repeated posts within 24h

Author Saturation:
  - Max 1 post per author in top-5 results
  - Min distance between same-author posts ≥ 3
  - Prevents feed spam from prolific authors
```

---

## Phase 0: Research & Decisions *(if clarifications needed)*

No [NEEDS CLARIFICATION] markers in spec. All technical decisions documented:

✅ **Technology Stack**: Rust/Actix + ClickHouse + Debezium + Kafka + Redis  
✅ **Consistency Model**: Eventual (≤ 30s), acceptable for feed use case  
✅ **Ranking Weights**: 0.30/0.40/0.30 (freshness/engagement/affinity) based on typical recommendation systems  
✅ **Fallback Strategy**: CH → PostgreSQL time-series, clearly documented  
✅ **Scale Assumptions**: 100k users, 50 followees avg, ~10M events/day (reasonable for Instagram-like app)

---

## Phase 1: Data Model & API Contracts

### ClickHouse DDL

See [data-model.md](./data-model.md) for complete DDL including:
- Events table (immutable, TTL 30d, PARTITION BY month)
- CDC tables (posts, follows, comments, likes) via ReplacingMergeTree
- Aggregated metrics (post_metrics_1h, user_author_90d) via SummingMergeTree
- Materialized Views (auto-consume from Kafka, aggregate hourly)

### API Contracts

See [contracts/](./contracts/) directory:
- `GET /api/v1/feed` → personalized ranking (50 posts)
- `GET /api/v1/feed/trending` → top 200 trending posts
- `GET /api/v1/discover/suggested-users` → 10–20 collaborative filtered users
- `POST /api/v1/events` → batch event ingestion (≤100 events)
- `GET /api/v1/feed/metrics` → daily performance metrics

### Redis Schema

| Key | Type | TTL | Size Estimate |
|-----|------|-----|---|
| `feed:v1:{user_id}` | ZSET | 120s | 50 posts * 500B ≈ 25KB per user |
| `hot:posts:1h` | ZSET | 60s | 200 posts * 500B ≈ 100KB |
| `suggest:users:{user_id}` | ZSET | 10m | 20 users * 100B ≈ 2KB per user |
| `seen:{user_id}:{post_id}` | STRING (bloom) | 24h | ~1-5 bits per seen post |
| **Total Cache Size** | - | - | ~2.5GB (100k users, 50 posts/user) |

---

## Phase 2: Implementation Strategy

### Stage 1: Foundation (H1–H5)

**Debezium CDC Setup**:
- Deploy Debezium PostgreSQL connector
- Configure publication: users, follows, posts, comments, likes
- Snapshot mode for initial sync
- Kafka topics: `cdc.posts`, `cdc.follows`, `cdc.comments`, `cdc.likes`

**ClickHouse Initialization**:
- Create CH instance (single-node for dev, 3-node cluster for prod)
- Execute DDL: events, posts, follows, comments, likes tables
- Create Kafka table engines + materialized views
- Verify MV auto-consumption, TTL policies

**Data Sync Validation**:
- Compare PostgreSQL row counts ↔ ClickHouse (should match)
- Sample data validation: posts, follows, comments, likes
- Confirm PARTITION cleanup, TTL effectiveness

### Stage 2: Ranking & Caching (H6–H8)

**Ranking Query Development**:
- Implement candidate set SQL (F1+F2+F3 UNION)
- Implement ranking query (freshness + engagement + affinity)
- Performance testing: target ≤ 800ms for 10k concurrent
- Index optimization if needed

**Background Jobs**:
- Hourly: Refresh `hot:posts:1h` (top 200 trending) → Redis
- Hourly: Compute suggested users → Redis

**Feed Service**:
- GET /api/v1/feed:
  1. Check Redis cache (feed:v1:{user})
  2. If hit (TTL valid): return cached result ≤ 50ms
  3. If miss: query ClickHouse ranking
  4. Compute final_score, sort DESC, deduplicate
  5. Cache in Redis, return top 50
- Fallback: CH timeout/failure → PostgreSQL time-series feed

### Stage 3: Events & Monitoring (H9–H12)

**Events API**:
- POST /api/v1/events:
  1. Validate batch (≤ 100 events, required fields)
  2. Generate idempotent_key (hash of user_id+post_id+action+ts)
  3. Deduplicate against last 5s
  4. Produce to Kafka `events` topic (acks=all)
  5. Return 202 Accepted (deferred processing)

**Metrics & Alerting**:
- Prometheus: Kafka lag, CH query time, Redis hit rate, API latency
- Grafana: Live dashboards (CDC lag, CH performance, cache hit rate, CTR, dwell time)
- Alertmanager: Rules for Kafka lag > 30s, CH P95 > 800ms, Redis hit < 80%, API P95 > 500ms

### Stage 4: Rollout (H13–H14)

**Quality Gates**:
- E2E test: event→CH→user visible ≤ 5s (continuous 30min)
- Cache hit rate ≥ 90%
- Fallback mechanism verified
- Dedup rate ≤ 10%

**Canary Deployment**:
- Route 10% traffic to algo=ch (vs. algo=timeline)
- Monitor: latency, cache hit, errors, user complaints (2–4 hours)

**Ramp-up**:
- 50% traffic if canary healthy
- 100% traffic after verification
- Fallback mechanism always available

---

## Project Structure

```
src/
├── models/
│   ├── feed.rs            # Feed response DTOs
│   ├── event.rs           # Event model
│   └── user_author.rs     # Affinity model
├── services/
│   ├── feed_service.rs    # Ranking + caching + fallback logic
│   ├── events_service.rs  # Event validation + dedup
│   ├── ranking.rs         # Ranking algorithm implementation
│   ├── redis_cache.rs     # Redis operations
│   └── clickhouse.rs      # ClickHouse queries
├── handlers/
│   ├── feed.rs            # GET /feed, GET /trending, GET /suggested-users
│   ├── events.rs          # POST /events
│   └── metrics.rs         # GET /metrics
├── jobs/
│   ├── trending_refresh.rs    # Hourly trending cache
│   ├── suggested_users.rs     # Hourly suggestions
│   └── scheduled.rs           # Job orchestration
├── db/
│   ├── migrations/
│   │   ├── clickhouse_init.sql    # CH DDL
│   │   └── pg_migrations.rs       # PostgreSQL migrations (if needed)
│   └── queries/
│       ├── feed_ranking.sql       # Main ranking query
│       └── ch_aggregations.sql    # MV definitions
├── middleware/
│   └── auth.rs            # JWT validation
├── errors/
│   └── mod.rs             # Error types + handling
└── main.rs

tests/
├── integration/
│   ├── feed_tests.rs      # E2E feed ranking tests
│   ├── events_tests.rs    # Event ingestion tests
│   ├── cache_tests.rs     # Redis cache tests
│   └── fallback_tests.rs  # CH failure → fallback tests
├── unit/
│   ├── ranking_tests.rs   # Ranking algorithm tests
│   └── dedup_tests.rs     # Deduplication tests
└── docker-compose.yml     # Local dev stack (PostgreSQL, Kafka, CH, Redis)

docs/
├── phase3-architecture.md  # Architecture overview
├── phase3-runbook.md       # Operational runbook
└── ch-query-guide.md       # ClickHouse query optimization
```

---

## Key Metrics & Success Criteria

| Metric | Target | SLO | Monitoring |
|--------|--------|-----|-----------|
| Event-to-visible latency P95 | ≤ 5s | 99% | Kafka lag + CH lag + API latency |
| Feed API response (Redis hit) | ≤ 150ms P95 | 99% | Redis latency histogram |
| Feed API response (CH query) | ≤ 800ms P95 | 99% | ClickHouse query histogram |
| Redis cache hit rate | ≥ 90% | 99.9% | Redis stats |
| Kafka consumer lag | < 10s | 99.9% | Kafka metrics |
| ClickHouse query concurrency | 10k concurrent | 99% | CH system.part_log |
| System availability | ≥ 99.5% | 99% | API uptime + fallback rate |
| Dedup rate | ≤ 10% | 100% | Custom metrics |

---

## Timeline

**14 小時分階段計畫**（2 人小組，可並行）：

| Phase | Hours | Task | Output | Owner |
|-------|-------|------|--------|-------|
| Foundation | H1–H2 | Debezium + Kafka + ClickHouse 基建 | Connectors online, topics created | Eng-A |
| - | H3–H4 | CH 表 + MV + 物化視圖驗證 | DDL deployed, data flowing | Eng-A |
| - | H5 | 全量回填 & 一致性驗證 | OLTP ↔ CH count match | Eng-A |
| Ranking | H6–H7 | 排序 SQL + 熱榜生成 | Query ≤ 800ms, hot:posts:1h working | Eng-B |
| - | H8 | Feed Service 接入 | GET /api/v1/feed live, fallback tested | Eng-B |
| Events | H9 | 建議用戶 + Events API | GET /discover/suggested-users, POST /events OK | Eng-A/B |
| - | H10 | 客戶端集成 + 負載測試 | 1k RPS events capacity verified | Eng-A |
| Monitoring | H11 | Grafana + 告警 | Dashboards live, alerts active | Eng-A |
| QA | H12 | 質量關卡 (E2E ≤ 5s) | 30min continuous test pass | Eng-A/B |
| Tuning | H13 | 參數調優 + 權重固定 | fresh/eng/aff = 0.3/0.4/0.3 | Eng-B |
| Rollout | H14 | 文檔 + 灰度開關 (10%) | Runbook done, rollout ready | Eng-A/B |

---

## Risk Mitigation

| Risk | Impact | Mitigation |
|------|--------|-----------|
| CH query slow (> 5s) | Feed unavailable | Aggressive CH index; materialized view pre-compute; immediate fallback |
| Kafka lag > 30s | Stale personalization | Monitor lag; alert threshold; increase consumer parallelism |
| Redis OOM | Cache eviction / fallback | Capacity planning (2.5GB); TTL tuning; eviction policy LRU |
| CDC snapshot blocking OLTP | Write performance hit | Offline snapshot (2:00–4:00 AM); or logical replication approach |
| Events dedup false positives | Missed user actions | Bloom filter with low FP rate (~0.1%); short TTL (5s) for hash dedup |
| New user cold-start | No personalization | Rely on F2 (trending) + suggested users (collaborative filter) |
| Author spam (10+ posts/min) | Feed quality | Author saturation rule (max 1 in top-5, distance ≥ 3) |

---

## Next Phase

**Upon Completion**: All artifacts (DDL, APIs, jobs, metrics) ready.

**Execute**: `/speckit.tasks` to generate 150–200 actionable implementation tasks with:
- Task breakdown by stage (H1–H14)
- Parallel execution opportunities
- Testing strategy per feature
- Quality gates before each milestone

---

## Assumptions & Constraints

✅ PostgreSQL + ClickHouse eventual consistency (≤ 30s) acceptable for feed  
✅ Debezium snapshot can run offline (2:00–4:00 AM window)  
✅ Kafka 3-node cluster, RF=3, available  
✅ Redis single-node or small cluster (2.5GB capacity)  
✅ ClickHouse 4+ GB memory, 2+ vCPU minimum  
✅ iOS/Android App supports background event batching  
✅ Initial data: 100k users, 50 followees avg, ≤ 5M follows  

---

## Definition of Done (DoD)

- ✅ Event→ClickHouse→Feed visible latency P95 ≤ 5s (continuous 30min test)
- ✅ /feed?algo=ch cache hit rate ≥ 90%, P95 ≤ 150ms
- ✅ Automatic fallback to algo=timeline works on CH failure
- ✅ Runbook reviewed, on-call procedures verified
- ✅ Canary (10%) traffic successfully routed and monitored
- ✅ All alerts configured + tested in staging
- ✅ Grafana dashboards live + baseline metrics established

