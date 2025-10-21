# Implementation Tasks: Video Live Streaming Infrastructure

**Feature**: Video Live Streaming Infrastructure (RTMP + HLS/DASH + Analytics)
**Branch**: `001-rtmp-hls-streaming`
**Date**: 2025-10-20
**Total Tasks**: 106 | **Phases**: 6 | **Parallel Opportunities**: 25+

---

## Overview

This document contains all implementation tasks organized by phase and user story. Each task is independently actionable and includes file paths, dependencies, and success criteria.

### User Story Priorities

- **P1 (Critical MVP)**: Broadcaster initiates stream + Viewer watches stream
- **P2 (Important)**: Analytics and monitoring

### Execution Strategy

**MVP Scope (Weeks 1-2)**: Complete P1 stories only
- Users can broadcast via RTMP
- Users can watch via HLS/DASH
- Basic error handling + graceful shutdown

**Phase 2 (Weeks 3-4)**: Add P2 (Analytics)
- Real-time metrics via WebSocket
- Historical analytics queries
- Dashboard support

**Recommended Parallelization**: Within each story, run tests in parallel with implementation

---

## Phase 1: Project Setup & Infrastructure

### Goal
Initialize Rust workspace, configure development environment, set up databases and containers.

### Independent Test Criteria
- Workspace compiles without errors (`cargo build --all`)
- Docker Compose services start successfully
- Database migrations run successfully
- All services can be launched individually

### Tasks

- [X] T001 Create Cargo workspace structure at `streaming/Cargo.toml` with members: core, ingest, transcode, delivery, api
- [X] T002 [P] Initialize `streaming/crates/streaming-core/Cargo.toml` with serde, tokio, uuid dependencies
- [X] T003 [P] Initialize `streaming/crates/streaming-ingest/Cargo.toml` with tokio-util, bytes, tracing dependencies
- [X] T004 [P] Initialize `streaming/crates/streaming-transcode/Cargo.toml` with process, std::command dependencies
- [X] T005 [P] Initialize `streaming/crates/streaming-delivery/Cargo.toml` with actix-web, tokio-tungstenite dependencies
- [X] T006 [P] Initialize `streaming/crates/streaming-api/Cargo.toml` with actix-web, sqlx, serde_json dependencies
- [X] T007 Create `streaming/docker-compose.yml` with PostgreSQL, Redis, Kafka, Zookeeper services
- [X] T008 Create `streaming/k8s/namespace.yaml` for Kubernetes namespace
- [X] T009 Create PostgreSQL migration file `streaming/migrations/001_init_schema.sql` with Stream, StreamKey, ViewerSession, StreamMetrics, QualityLevel tables
- [X] T010 [P] Create `streaming/Makefile` with targets: build, test, run, clean, docker-up, docker-down
- [X] T011 Create `.env.example` with DATABASE_URL, REDIS_URL, KAFKA_BROKERS, RUST_LOG configuration
- [X] T012 [P] Add GitHub Actions CI workflow at `.github/workflows/test.yml` for build + test on each commit

---

## Phase 2: Foundational Infrastructure & Shared Code

### Goal
Build shared libraries, error handling, logging, and database abstractions used by all services.

### Independent Test Criteria
- `streaming-core` compiles and passes unit tests
- Shared types can be imported by all 4 service crates
- Database pool initialization works
- Kafka producer/consumer clients initialize without errors

### Tasks

- [ ] T013 [P] Create core types module at `streaming/crates/streaming-core/src/models.rs` with Stream, StreamKey, ViewerSession, StreamMetrics, QualityLevel structs (use serde, derive Clone, Debug)
- [ ] T014 [P] Create error types at `streaming/crates/streaming-core/src/errors.rs` with StreamError enum covering: InvalidKey, NetworkError, TranscodingError, DatabaseError, NotFound
- [ ] T015 [P] Implement logger initialization at `streaming/crates/streaming-core/src/logging.rs` using tracing subscriber with structured JSON output
- [ ] T016 Create RTMP protocol types at `streaming/crates/streaming-core/src/rtmp.rs` with RtmpHandshake, RtmpMessage, RtmpCommand, RtmpData structs
- [ ] T017 Create HLS types at `streaming/crates/streaming-core/src/hls.rs` with HlsPlaylist, HlsSegment, HlsVariant structs
- [ ] T018 Create DASH types at `streaming/crates/streaming-core/src/dash.rs` with DashMpd, DashPeriod, DashAdaptationSet structs
- [ ] T019 Create event types at `streaming/crates/streaming-core/src/events.rs` with StreamEvent enum (StreamStarted, StreamEnded, BitrateAdapted, QualitySwitched, etc.) using serde for Kafka serialization
- [ ] T020 [P] Implement PostgreSQL connection pool module at `streaming/crates/streaming-core/src/db.rs` using sqlx with connection pooling
- [ ] T021 [P] Implement Kafka producer wrapper at `streaming/crates/streaming-core/src/kafka_producer.rs` for event publishing with Avro serialization support
- [ ] T022 [P] Implement Redis client wrapper at `streaming/crates/streaming-core/src/redis_client.rs` for segment caching with TTL support
- [ ] T023 Create configuration module at `streaming/crates/streaming-core/src/config.rs` using config crate to load from .env files
 - [X] T013 [P] Create core types module at `streaming/crates/streaming-core/src/models.rs` with Stream, StreamKey, ViewerSession, StreamMetrics, QualityLevel structs (use serde, derive Clone, Debug)
 - [X] T014 [P] Create error types at `streaming/crates/streaming-core/src/errors.rs` with StreamError enum covering: InvalidKey, NetworkError, TranscodingError, DatabaseError, NotFound
 - [X] T015 [P] Implement logger initialization at `streaming/crates/streaming-core/src/logging.rs` using tracing subscriber with structured JSON output
 - [X] T016 Create RTMP protocol types at `streaming/crates/streaming-core/src/rtmp.rs` with RtmpHandshake, RtmpMessage, RtmpCommand, RtmpData structs
 - [X] T017 Create HLS types at `streaming/crates/streaming-core/src/hls.rs` with HlsPlaylist, HlsSegment, HlsVariant structs
 - [X] T018 Create DASH types at `streaming/crates/streaming-core/src/dash.rs` with DashMpd, DashPeriod, DashAdaptationSet structs
 - [X] T019 Create event types at `streaming/crates/streaming-core/src/events.rs` with StreamEvent enum (StreamStarted, StreamEnded, BitrateAdapted, QualitySwitched, etc.) using serde for Kafka serialization
 - [X] T020 [P] Implement PostgreSQL connection pool module at `streaming/crates/streaming-core/src/db.rs` using sqlx with connection pooling
 - [X] T021 [P] Implement Kafka producer wrapper at `streaming/crates/streaming-core/src/kafka_producer.rs` for event publishing with Avro serialization support
 - [X] T022 [P] Implement Redis client wrapper at `streaming/crates/streaming-core/src/redis_client.rs` for segment caching with TTL support
 - [X] T023 Create configuration module at `streaming/crates/streaming-core/src/config.rs` using config crate to load from .env files

---

## Phase 3: User Story 1 - Broadcaster Initiates Live Stream (P1)

### User Story Description
A content creator connects their encoder (OBS, FFmpeg) via RTMP to the streaming server and begins streaming. The system accepts the connection, validates the streaming key, normalizes the bitrate, and makes the stream available to viewers.

### Acceptance Scenarios
1. Broadcaster with valid streaming key connects RTMP encoder → server accepts connection → stream ingested
2. RTMP stream with fluctuating bitrate → system adapts output streams to available quality levels
3. Broadcaster stops streaming → connection closes → system notifies all viewers within 2 seconds

### Independent Test Criteria (US1 MVP)
- RTMP server accepts connections on port 1935
- Streaming key validation works (valid key accepted, invalid key rejected)
- Bitrate adaptation produces 3 quality levels (480p, 720p, 1080p)
- Stream transitions to ACTIVE state in database within 1 second
- Stream cleanup completes within 2 seconds after encoder disconnects
- Test with FFmpeg RTMP encoder, verify segment production

### Tasks

**US1 Infrastructure & Database**:

- [X] T024 [US1] Create streaming key repository at `streaming/crates/streaming-core/src/repositories/stream_key_repo.rs` with methods: create_key, validate_key, revoke_key, get_by_id
- [X] T025 [US1] Create stream repository at `streaming/crates/streaming-core/src/repositories/stream_repo.rs` with methods: create_stream, update_status, get_by_id, get_active_streams
- [X] T026 [P] [US1] Create database migrations for StreamKey and Stream tables at `streaming/migrations/002_stream_tables.sql`

**US1 RTMP Ingestion Service**:

- [X] T027 [US1] Implement RTMP handshake parser at `streaming/crates/streaming-ingest/src/rtmp_handler.rs` (parse C0, C1, C2 messages)
- [X] T028 [US1] Implement RTMP command handler at `streaming/crates/streaming-ingest/src/rtmp_handler.rs` to process connect, releaseStream, createStream, publish commands
- [X] T029 [US1] Create stream manager at `streaming/crates/streaming-ingest/src/stream_manager.rs` to track active RTMP connections and map to Stream entities
- [X] T030 [US1] Implement streaming key validation at `streaming/crates/streaming-ingest/src/auth.rs` querying PostgreSQL for valid keys
- [X] T031 [US1] Create Kafka producer for stream events at `streaming/crates/streaming-ingest/src/kafka_producer.rs` to emit StreamStarted, BitrateAdapted events
- [X] T032 [US1] Implement bitrate adapter at `streaming/crates/streaming-ingest/src/quality_adapter.rs` to normalize input streams to standard bitrates (2M, 5M, 8M)
- [X] T033 [US1] Create graceful shutdown handler at `streaming/crates/streaming-ingest/src/shutdown.rs` to close all RTMP connections and emit StreamEnded events
- [X] T034 [US1] Implement main RTMP server at `streaming/crates/streaming-ingest/src/main.rs` using Tokio TcpListener on port 1935, spawning tasks per connection

**US1 Integration & Frame Forwarding**:

- [X] T035 [US1] Create raw frame forwarding to Kafka at `streaming/crates/streaming-ingest/src/frame_forwarder.rs` to send H.264/AAC frames to stream-frames Kafka topic
- [X] T036 [US1] Implement error recovery at `streaming/crates/streaming-ingest/src/error_handler.rs` to handle network errors, malformed RTMP messages, and invalid bitrates

**US1 Testing Tasks**:

- [X] T037 [US1] Create RTMP protocol tests at `streaming/tests/rtmp_protocol_test.rs` (handshake parsing, command parsing)
- [X] T038 [P] [US1] Create mock RTMP encoder at `streaming/tests/mock_encoder.rs` using bytes crate to simulate OBS/FFmpeg RTMP stream
- [X] T039 [US1] Create integration test at `streaming/tests/integration/broadcaster_connect_test.rs` to verify full RTMP ingest flow (connect→authenticate→stream→disconnect)
- [X] T040 [US1] Create bitrate adaptation tests at `streaming/tests/unit/quality_adapter_test.rs` for input/output bitrate mapping

---

## Phase 4: User Story 2 - Viewer Watches Live Stream (P1)

### User Story Description
A viewer discovers an active live stream and opens the HLS/DASH URL in their browser. The system begins serving segments, supports quality selection, adapts to bandwidth changes, and maintains real-time status via WebSocket. Target: <3 second startup, <2 second quality switches.

### Acceptance Scenarios
1. Viewer opens HLS/DASH stream URL → playback begins within 3 seconds
2. Viewer network conditions change → stream quality adapts without interruption (buffer <2s)
3. Multiple concurrent viewers (10k+) join simultaneously → all viewers maintain stable playback quality

### Independent Test Criteria (US2 MVP)
- HLS master playlist downloads successfully with quality variants
- HLS segments playable in modern browsers (Safari, Chrome, Firefox)
- DASH manifest valid XML, playable with dash.js library
- Viewer startup time <3 seconds (from URL open to first frame display)
- Concurrent viewer count tracked accurately in metrics
- WebSocket delivers status updates within 1-2 seconds
- Test with 10+ concurrent viewers using HLS.js or dash.js

### Tasks

**US2 Database & Repositories**:

- [X] T041 [US2] Create viewer session repository at `streaming/crates/streaming-core/src/repositories/viewer_session_repo.rs` with methods: create_session, update_session, end_session, get_by_stream
- [X] T042 [US2] Create stream metrics repository at `streaming/crates/streaming-core/src/repositories/metrics_repo.rs` with methods: record_metrics, query_range, get_latest

**US2 Segment Storage & Caching**:

- [X] T043 [US2] Create segment cache manager at `streaming/crates/streaming-delivery/src/cache_manager.rs` to read segments from Redis with TTL fallback to S3

**US2 HLS Delivery Service**:

- [X] T044 [US2] Implement HLS master playlist generator at `streaming/crates/streaming-delivery/src/hls_handler.rs` (m3u8 format with variant streams for 480p/720p/1080p)
- [X] T045 [US2] Implement HLS quality playlist handler at `streaming/crates/streaming-delivery/src/hls_handler.rs` to serve quality-specific m3u8 files with segment references
- [X] T046 [US2] Implement HLS segment serving endpoint at `streaming/crates/streaming-delivery/src/hls_handler.rs` (GET /hls/:stream_id/:quality/segment-N.ts)
- [ ] T047 [US2] Create HTTP cache headers manager at `streaming/crates/streaming-delivery/src/cache_headers.rs` to set appropriate Cache-Control, ETag, Last-Modified for segment delivery

**US2 CDN Integration**:

- [X] T047a [US2] Implement CDN origin URL rewriter at `streaming/crates/streaming-delivery/src/cdn_url_rewriter.rs` to transform segment URLs in playlists from direct server URLs to CDN-prefixed URLs (e.g., https://cdn.example.com/hls/...)
- [X] T047b [US2] Create CDN edge authentication at `streaming/crates/streaming-delivery/src/cdn_auth.rs` to generate signed CDN tokens (if using Cloudflare, Akamai) for private streams
- [X] T047c [US2] Implement CDN cache configuration at `streaming/crates/streaming-delivery/src/cdn_config.rs` to set Cache-Control headers: 10min TTL for segments, 1min for manifests, bypass for non-200 responses

**US2 DASH Delivery Service**:

- [X] T048 [US2] Implement DASH MPD manifest generator at `streaming/crates/streaming-delivery/src/dash_handler.rs` (XML format with adaptation sets for quality levels)
- [X] T049 [US2] Implement DASH segment serving endpoint at `streaming/crates/streaming-delivery/src/dash_handler.rs` (GET /dash/:stream_id/:quality/segment-N.m4s)

**US2 WebSocket Real-Time Status**:

- [X] T050 [US2] Create WebSocket hub at `streaming/crates/streaming-delivery/src/websocket_hub.rs` to manage per-stream subscriptions and broadcasts
- [X] T051 [US2] Implement WebSocket connection handler at `streaming/crates/streaming-delivery/src/websocket_handler.rs` (GET /ws/stream/:stream_id)
- [X] T052 [US2] Create stream status publisher at `streaming/crates/streaming-delivery/src/status_publisher.rs` to emit stream state changes (ACTIVE, ENDED, ERROR) to WebSocket clients

**US2 Adaptive Bitrate & Quality Selection**:

- [X] T053 [US2] Implement quality level repository at `streaming/crates/streaming-core/src/repositories/quality_level_repo.rs` to load predefined quality profiles
- [X] T054 [US2] Create client-side quality selection logic at `streaming/crates/streaming-delivery/src/quality_selector.rs` (recommend quality based on available bandwidth, client preference)

**US2 REST API Endpoints**:

- [X] T055 [US2] Implement GET /streams/:stream_id endpoint at `streaming/crates/streaming-api/src/handlers/stream_handler.rs` to return stream status, concurrent viewers, quality options
- [X] T056 [US2] Implement GET /metrics/:stream_id endpoint at `streaming/crates/streaming-api/src/handlers/metrics_handler.rs` to return historical analytics (viewership, quality distribution, buffering)

**US2 Viewer Session Tracking**:

- [X] T057 [US2] Implement session creation on stream join at `streaming/crates/streaming-delivery/src/session_manager.rs` to record viewer_id, quality_level, joined_at
- [X] T058 [US2] Implement session update on quality switch at `streaming/crates/streaming-delivery/src/session_manager.rs` to track quality_switches, buffer_events
- [X] T059 [US2] Implement session finalization on disconnect at `streaming/crates/streaming-delivery/src/session_manager.rs` to record left_at, total duration, bytes_transferred

**US2 Testing Tasks**:

- [X] T060 [P] [US2] Create HLS playlist parser test at `streaming/tests/hls_playlist_test.rs` (verify m3u8 format, variant streams, segment count)
- [X] T061 [P] [US2] Create DASH manifest validator test at `streaming/tests/dash_manifest_test.rs` (verify XML structure, adaptation sets, period duration)
- [X] T062 [US2] Create WebSocket integration test at `streaming/tests/integration/websocket_test.rs` (connect, receive status updates, quality switch notifications)
- [X] T063 [US2] Create viewer session test at `streaming/tests/integration/viewer_session_test.rs` (create→update quality→finalize, verify database records)
- [X] T064 [US2] Create end-to-end test at `streaming/tests/integration/e2e_broadcaster_viewer_test.rs` (broadcaster connects→viewer opens stream→receives video→quality switches)

---

## Phase 5: User Story 3 - Analytics and Monitoring (P2)

### User Story Description
Platform operators and broadcasters monitor stream health, viewer engagement, and performance metrics in real-time. They access a dashboard showing concurrent viewers, bandwidth, quality distribution, error rates, and can query historical analytics.

### Acceptance Scenarios
1. Active stream metrics (viewers, bitrate, quality) collected every 1 second → available via WebSocket within 1-2 seconds
2. Viewer quality switch logged → reflected in analytics immediately (quality_distribution updated)
3. Platform operator views dashboard → sees current metrics (concurrent viewers, health score, bandwidth) updated in real-time

### Independent Test Criteria (P2)
- Metrics collected at 1-second intervals without performance degradation
- WebSocket metrics push latency <2 seconds
- Historical metrics queryable for any time range
- Metrics API returns accurate concurrent viewer count matching WebSocket subscriptions
- Dashboard loads within 2 seconds with live data
- Test with load generator (simulate 100 concurrent viewers + metrics collection)

### Tasks

**US3 Metrics Collection & Aggregation**:

- [ ] T065 [US3] Create metrics collector at `streaming/crates/streaming-delivery/src/metrics_collector.rs` to aggregate concurrent_viewers, ingress_bitrate, egress_bitrate, quality_distribution every 1 second
- [ ] T066 [US3] Implement metrics persistence at `streaming/crates/streaming-delivery/src/metrics_writer.rs` to write StreamMetrics records to PostgreSQL with 1-second granularity
- [ ] T067 [US3] Create real-time metrics broadcaster at `streaming/crates/streaming-delivery/src/metrics_broadcaster.rs` to publish metrics to WebSocket clients and update Redis cache

**US3 Analytics API**:

- [ ] T068 [US3] Implement GET /metrics/:stream_id endpoint (historical query) at `streaming/crates/streaming-api/src/handlers/analytics_handler.rs` with time range filtering
- [ ] T069 [US3] Implement GET /streams/:stream_id/viewers endpoint at `streaming/crates/streaming-api/src/handlers/viewers_handler.rs` to list active viewer sessions
- [ ] T070 [US3] Create analytics aggregation service at `streaming/crates/streaming-api/src/services/analytics_service.rs` to compute health score, recommendations, trends

**US3 Monitoring & Alerting**:

- [ ] T071 [US3] Create Prometheus metrics exporter at `streaming/crates/streaming-delivery/src/prometheus_exporter.rs` to expose Prometheus-compatible metrics (concurrent_viewers, stream_errors, buffering_rate)
- [ ] T072 [US3] Create alerting rules at `streaming/monitoring/prometheus-alerts.yaml` for critical thresholds (error rate >1%, buffering >5%, viewer drop >50%)

**US3 Dashboard (Frontend Template)**:

- [ ] T073 [US3] Create HTML dashboard template at `streaming/web/dashboard.html` with real-time metrics display (concurrent viewers gauge, quality distribution pie chart, bitrate graph)
- [ ] T074 [US3] Implement dashboard WebSocket client at `streaming/web/dashboard.js` to subscribe to metrics and update DOM in real-time

**US3 Testing Tasks**:

- [ ] T075 [P] [US3] Create metrics collection test at `streaming/tests/unit/metrics_collector_test.rs` (verify aggregation accuracy, 1-second granularity)
- [ ] T076 [P] [US3] Create analytics query test at `streaming/tests/integration/analytics_query_test.rs` (query historical metrics by time range, verify accuracy)
- [ ] T077 [US3] Create dashboard integration test at `streaming/tests/integration/dashboard_test.rs` (verify WebSocket pushes update DOM correctly, load time <2s)
- [ ] T077a [US2] Create buffering rate test at `streaming/tests/integration/buffering_rate_test.rs` to measure and verify SC-006 (95% of viewers experience zero buffering); simulate network throttling and variable bandwidth
- [ ] T077b [US2] Create CDN performance benchmark at `streaming/tests/integration/cdn_performance_test.rs` to validate SC-010 (30% latency reduction); compare direct server delivery vs. CDN-prefixed URLs, measure edge latency

---

## Phase 6: Polish, Optimization & Cross-Cutting Concerns

### Goal
Finalize implementation with performance optimization, security hardening, error handling, monitoring, documentation, and deployment preparation.

### Independent Test Criteria
- All services compile with zero warnings (clippy)
- All tests pass (unit + integration)
- Load test passes: 100 concurrent streams, 10k concurrent viewers
- Security audit passes: no hardcoded credentials, TLS configured
- Documentation complete for deployment

### Tasks

**Error Handling & Resilience**:

- [ ] T077x [P] Implement distributed stream state consistency at `streaming/crates/streaming-core/src/state_consistency.rs` using PostgreSQL advisory locks for atomic state transitions (PENDING_INGEST → ACTIVE → ENDED) across all service replicas; ensure eventual consistency within 500ms via Kafka event ordering by stream_id
- [ ] T077y [P] Create stream state synchronization checker at `streaming/crates/streaming-delivery/src/state_verifier.rs` to periodically validate state consistency across ingestion, transcoding, and delivery services; alert on divergence >5 seconds
- [ ] T078 Create circuit breaker for Kafka producer at `streaming/crates/streaming-core/src/circuit_breaker.rs` (fail-open on producer errors, retry with exponential backoff)
- [ ] T079 Implement graceful degradation at `streaming/crates/streaming-delivery/src/graceful_degradation.rs` (serve lower quality if transcoding fails, notify viewers)
- [ ] T080 Create timeout handlers at `streaming/crates/streaming-core/src/timeouts.rs` for RTMP (30s idle), transcoding (5m), segment delivery (10s)

**Performance Optimization**:

- [ ] T081 [P] Implement connection pooling at `streaming/crates/streaming-core/src/db.rs` with optimal pool size (20-30 connections)
- [ ] T082 [P] Add Redis connection pooling at `streaming/crates/streaming-core/src/redis_client.rs` with pool size 10
- [ ] T083 Implement segment caching strategy at `streaming/crates/streaming-delivery/src/cache_strategy.rs` (hot: Redis 10min TTL, warm: S3 30days)
- [ ] T084 Create buffer size optimization at `streaming/crates/streaming-ingest/src/buffer_tuning.rs` for RTMP frame buffers

**Security Hardening**:

- [ ] T085 [P] Implement TLS for HTTPS at `streaming/crates/streaming-delivery/src/tls_config.rs` (load certificates from secure storage)
- [ ] T086 Create rate limiter at `streaming/crates/streaming-api/src/middleware/rate_limiter.rs` (100 req/min per IP, 10k concurrent sessions)
- [ ] T087 Implement CORS headers at `streaming/crates/streaming-delivery/src/cors.rs` (restrict to approved origins)
- [ ] T088 Create secret management at `streaming/crates/streaming-core/src/secrets.rs` (load API keys, database passwords from environment, never log)

**Logging & Monitoring**:

- [ ] T089 [P] Add structured logging at `streaming/crates/streaming-ingest/src/logging.rs` for: connection events, authentication, errors (JSON format)
- [ ] T090 [P] Add distributed tracing at `streaming/crates/streaming-core/src/tracing.rs` using OpenTelemetry (trace RTMP→Kafka→Transcoding→HLS flow)
- [ ] T091 Implement health check endpoints at `streaming/crates/streaming-api/src/handlers/health_handler.rs` (GET /health, returns service status + dependencies)

**Load Testing & Performance Validation**:

- [ ] T092 Create load test at `streaming/tests/load_test.rs` (simulate 100 concurrent broadcasters, 10k concurrent viewers, 1M total events/second)
- [ ] T093 Create benchmarks at `streaming/benches/` for RTMP parsing, HLS generation, metrics aggregation (use criterion crate)

**Deployment & Operations**:

- [ ] T094 Create Kubernetes deployment manifests at `streaming/k8s/` (ingestion-deployment.yaml, transcode-deployment.yaml, delivery-deployment.yaml, api-deployment.yaml)
- [ ] T095 Create Helm chart at `streaming/helm/Chart.yaml` for easy cluster deployment
- [ ] T096 Implement health checks at `streaming/crates/streaming-*/src/health.rs` for Kubernetes liveness/readiness probes
- [ ] T097 Create Docker images at `streaming/crates/streaming-*/Dockerfile` with multi-stage builds (small final size)
- [ ] T098 Create database migration scripts at `streaming/scripts/migrate.sh` for production deployments

**Documentation**:

- [ ] T099 [P] Create deployment guide at `streaming/docs/DEPLOYMENT.md` (local dev, Docker Compose, Kubernetes)
- [ ] T100 [P] Create API documentation at `streaming/docs/API.md` (OpenAPI, WebSocket messages, error codes)
- [ ] T101 [P] Create troubleshooting guide at `streaming/docs/TROUBLESHOOTING.md` (common issues, debugging)
- [ ] T102 Create CONTRIBUTING.md at `streaming/CONTRIBUTING.md` (dev setup, testing, code review process)

**Final Integration & Validation**:

- [ ] T103 Run full integration test suite (`cargo test --all --release`) and verify 100% pass rate
- [ ] T104 Run security scan (`cargo audit`, `clippy`, OWASP analysis) and resolve findings
- [ ] T105 Run performance validation (`cargo bench`) and verify targets met (<3s startup, <5s latency)
- [ ] T106 Create release checklist at `streaming/RELEASE_CHECKLIST.md` (versioning, tag, deployment steps)

---

## Dependency Graph

### Critical Path (Must Complete in Order)

```
Phase 1 (Setup)
    ↓
Phase 2 (Foundational)
    ↓
Phase 3 (US1: Broadcaster) + Phase 4 (US2: Viewer) [Can run in parallel]
    ↓
Phase 5 (US3: Analytics)
    ↓
Phase 6 (Polish & Ops)
```

### Within-Phase Parallelization

**Phase 3 (US1) Parallel Tasks**: T024, T025, T026 (database), T027-T036 (ingestion service) can start once T024-T026 complete

**Phase 4 (US2) Parallel Tasks**: T041-T042 (database), T044-T049 (HLS/DASH), T050-T052 (WebSocket) can run concurrently

**Phase 5 (US3) Parallel Tasks**: T065-T067 (metrics collection), T068-T070 (API), T071-T074 (monitoring/dashboard) can run concurrently

**Phase 6 Parallel Tasks**: All T078-T101 except those with explicit dependencies

---

## Implementation Strategy

### MVP Scope (First 2 Weeks)
**Target**: Complete P1 user stories (Broadcaster + Viewer)

**Weekly Breakdown**:
- **Week 1**: Phases 1-2 (Setup + Foundational) + Phase 3 (US1) database & RTMP infrastructure
- **Week 2**: Phase 3 completion (RTMP ingest) + Phase 4 (HLS/DASH delivery) + integration tests

**Success Criteria**:
- RTMP ingest works (FFmpeg → streaming server)
- HLS/DASH delivery works (browser → playback)
- 100 concurrent streams sustainable
- 10k concurrent viewers with <3s startup
- Zero data loss during delivery

### Phase 2 Scope (Weeks 3-4)
**Target**: Add P2 user story (Analytics)

**Tasks**:
- Phase 5 complete (metrics collection, WebSocket, API)
- Dashboard functional
- Historical analytics queryable
- Prometheus metrics exposed

### Polish & Launch (Week 5)
**Target**: Phase 6 (error handling, security, monitoring, documentation)

**Deliverables**:
- Production-ready Kubernetes manifests
- Security audit passed
- Performance benchmarks met
- Documentation complete
- Deployment runbook ready

---

## Format Validation Checklist

✅ **All tasks follow strict format**:
- [x] Each task starts with `- [ ]`
- [x] Each task has unique ID (T001 → T106)
- [x] Setup/Foundational phases have NO story label
- [x] User Story phases have [US#] label
- [x] Parallelizable tasks marked with [P]
- [x] All tasks include file paths
- [x] No task has vague descriptions
- [x] All 106 tasks sequentially numbered

✅ **Organizational structure**:
- [x] 6 phases (Setup, Foundational, US1, US2, US3, Polish)
- [x] Each phase has independent test criteria
- [x] User stories P1, P1, P2 prioritized correctly
- [x] Dependencies documented
- [x] Parallelization examples provided

---

**Generated**: 2025-10-20
**Next Command**: Begin implementation with Phase 1
**Estimated Effort**: 300-350 hours (6-8 weeks, 5-6 engineers, aggressive parallelization)
**Success Criteria**: All 106 tasks completed with zero critical bugs, performance targets met, security audit passed
