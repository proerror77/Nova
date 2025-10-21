# Implementation Tasks: Phase 2 - Quality Assurance, Observability & Deployment

**Feature**: Video Live Streaming Infrastructure (Phase 2: Testing, Monitoring & Documentation)
**Branch**: `chore/ios-local-docker`
**Date**: 2025-10-21
**Status**: Phase 2 Planning (Target: 65% → 90% completion)
**Total Tasks**: 24 | **Categories**: 4 | **Timeline**: 15 days | **Parallel Opportunities**: 8+

## 📊 Phase 2 Task Categories

| Category | Tasks | Est. Days | Status |
|----------|-------|-----------|--------|
| Compilation Fixes | 1 | 0.5 | ⏳ TODO |
| Integration Testing | 8 | 5 | ⏳ TODO |
| Prometheus Monitoring | 6 | 3 | ⏳ TODO |
| API Documentation | 5 | 2 | ⏳ TODO |
| Deployment Guides | 4 | 4.5 | ⏳ TODO |
| **TOTAL** | **24** | **15** | **⏳ READY** |

## 📋 Overall Project Progress

| Milestone | Completion |
|-----------|------------|
| Phase 1 (WebSocket + Code Alignment) | ✅ 65% |
| Phase 2 (This Sprint - Target) | ⏳ 0% → 90% |
| Phase 3 (Production Ready) | ⏳ TODO |

---

## 🔄 Code Alignment Mapping

### Implementation Status by Component

#### ✅ Already Implemented (Actual Code)
- **T013** Core types → `models.rs` (Stream, StreamKey, ViewerSession, QualityLevel)
- **T014** Error types → `error.rs` in user-service
- **T015** Logging → `main.rs` logging configuration
- **T020** PostgreSQL pool → user-service database module
- **T022** Redis client → `redis_counter.rs`
- **T023** Configuration → `.env` files
- **T024** Stream key repo → `repository.rs` (validate_key, create_key methods)
- **T025** Stream repo → `repository.rs` (create_stream, update_status)
- **T026** DB migrations → `backend/migrations/` directory
- **T030** Streaming key validation → `repository.rs`
- **T032** Bitrate adapter → `stream_service.rs`
- **T033** Graceful shutdown → `stream_service.rs`
- **T041** Viewer session repo → `redis_counter.rs`
- **T042** Metrics repo → `analytics.rs` (ClickHouse queries)
- **T043** Segment cache → Redis integration (implicit)
- **T055** GET /streams/:stream_id → handlers
- **T056** GET /metrics/:stream_id → handlers
- **T057-T059** Session tracking → `redis_counter.rs`
- **T065-T067** Metrics collection → `analytics.rs`
- **T068-T070** Analytics API → `analytics.rs` + handlers

#### ⚠️ Partially Implemented / Externalized
- **T027-T028** RTMP handshake/commands → Handled by Nginx-RTMP (external)
- **T029** Stream manager → `stream_service.rs` (basic version)
- **T031, T035** Kafka events → **NOT IMPLEMENTED** (consider adding)
- **T044-T049** HLS/DASH generation → Nginx-RTMP + CloudFront (external)
- **T050-T052** WebSocket hub → **NOT IMPLEMENTED** (needed for real-time updates)
- **T053-T054** Quality selection → Basic in `stream_service.rs` (can enhance)

#### ❌ Not Yet Implemented (Missing)
- **T016-T018** RTMP/HLS/DASH protocol types (basic models exist, protocol parsing missing)
- **T019** Event types for Kafka (Kafka not used yet)
- **T021** Kafka producer wrapper
- **T034** RTMP server on port 1935 (delegated to Nginx)
- **T036** Error recovery handlers (basic, can enhance)
- **T037-T040** RTMP integration tests (missing)
- **T050-T052** WebSocket real-time hub (critical gap - needed for P1 viewer updates)
- **T060-T064** HLS/DASH/viewer session tests (mostly missing)
- **T071** Prometheus exporter (not implemented)
- **T072** Alerting rules (not implemented)
- **T073-T074** Dashboard frontend (not implemented)
- **T075-T077** Metrics tests (missing)
- **T078-T091** Error handling, timeouts, security, logging enhancements (partial)
- **T092-T106** Load testing, deployment docs, release checklist (partial/missing)

---

## Overview

**Phase 2** focuses on moving from 65% to 90% completion through:
1. Fixing remaining compilation errors
2. Implementing comprehensive integration tests
3. Setting up production-grade monitoring
4. Documenting all deployment procedures

This phase builds on Phase 1's WebSocket implementation and addresses the 3 critical gaps identified in the spec alignment analysis.

### 🏗️ Testing Infrastructure Architecture

**重要澄清**: Test simulator 連接到 **真實的生產基礎設施**，不是模擬的：

```
Test Simulator Layer (Automated Testing)
├── Test RTMP Client Simulator
│   └─→ Connects to REAL Nginx-RTMP (port 1935)
│       ├─→ Sends synthetic H.264 frames
│       └─→ Verifies RTMP protocol handling
│
├── Test WebSocket Clients
│   └─→ Connect to REAL user-service WebSocket
│       ├─→ Receive real viewer_count_changed events
│       └─→ Verify real-time broadcasting
│
└── Test Metric Collectors
    └─→ Query REAL Redis + PostgreSQL
        ├─→ Verify real metrics collection
        └─→ Validate real counters

        ↓↓↓ (All connections to real infrastructure) ↓↓↓

Production Infrastructure Layer (Always Real)
├── Nginx-RTMP Server (real RTMP ingest)
├── user-service (real WebSocket handler)
├── PostgreSQL Database (real stream records)
├── Redis Cache (real metrics storage)
└── CloudFront CDN (real HLS/DASH delivery)
```

**關鍵點**:
- ✅ Nginx-RTMP 是**真實的生產級**服務器，每次測試都運行
- ✅ Test simulator 是**自動化工具**，用於在 CI/CD 中無需手動啟動 OBS
- ✅ 真實廣播者仍可使用 OBS/FFmpeg 連接到同一個 Nginx-RTMP
- ✅ 所有測試驗證真實的端到端管道

---

## Priority 0: Compilation Fixes

### Goal
Ensure `cargo build --release` succeeds with zero errors and warnings.

### Success Criteria
- ✅ Zero E0603 private import errors
- ✅ All dependencies resolved
- ✅ Clippy warnings = 0

### Tasks

- [ ] **P0-T001** Fix E0603 private import errors in `backend/user-service/src/handlers/posts.rs` and `password_reset.rs`
  - **File**: `backend/user-service/src/handlers/{posts,password_reset}.rs`
  - **Action**: Expose ErrorResponse, generate_token, hash_token via pub use or refactor visibility
  - **Est. Time**: 0.5 days
  - **Success**: `cargo build --release` shows 0 errors

---

## Priority 1: Integration Testing Framework

### Goal
Build comprehensive test suite with mock RTMP client and 5 end-to-end scenarios covering full streaming pipeline.

### Success Criteria
- ✅ Mock RTMP client connects to Nginx on port 1935
- ✅ All 5 test scenarios pass
- ✅ Test suite runs in <2 minutes
- ✅ 95%+ coverage of streaming paths

### Tasks

- [ ] **P1-T001** Create RTMP test client simulator at `tests/integration/mock_rtmp_client.rs`
  - **Purpose**: Automated testing tool (NOT replacing Nginx-RTMP which is production real)
  - **Connection Target**: Real Nginx-RTMP server (port 1935, already running in docker-compose)
  - **Components**: TCP socket, RTMP handshake parser, synthetic H.264 frame generator
  - **Est. Time**: 2 days
  - **Success**: Test simulator connects to real Nginx-RTMP, authenticates, and sends synthetic frames for automated verification

- [ ] **P1-T002** Implement RTMP handshake protocol in test client simulator
  - **File**: `tests/integration/mock_rtmp_client.rs`
  - **Protocol**: C0 signature, C1/C2 challenge-response (compatible with real Nginx-RTMP)
  - **Target**: Real Nginx-RTMP server (production infrastructure)
  - **Est. Time**: 1 day
  - **Success**: Real Nginx-RTMP server accepts connection from test simulator

- [ ] **P1-T003** Create Scenario 1 test: Broadcaster Lifecycle
  - **File**: `tests/integration/streaming_lifecycle_test.rs`
  - **Flow**: Test simulator connects to real Nginx-RTMP → Streams frames → Verify DB state → Disconnect → Verify cleanup
  - **Infrastructure**: Uses real Nginx-RTMP (from docker-compose), user-service, PostgreSQL
  - **Est. Time**: 1 day
  - **Success**: Stream transitions PENDING → ACTIVE → COMPLETED in DB via real infrastructure

- [ ] **P1-T004** Create Scenario 2 test: Viewer WebSocket Connection
  - **File**: `tests/integration/websocket_broadcast_test.rs`
  - **Flow**: Test simulator connects to real Nginx-RTMP, streams frames → Test client connects to real user-service WebSocket → Receive viewer updates
  - **Infrastructure**: Real Nginx-RTMP + real user-service WebSocket handler
  - **Est. Time**: 1.5 days
  - **Success**: Test client receives viewer_count_changed events within 2 seconds from real infrastructure

- [ ] **P1-T005** Create Scenario 3 test: E2E Multi-Viewer Experience
  - **File**: `tests/integration/e2e_viewer_test.rs`
  - **Flow**: 1 test simulator → real Nginx-RTMP + 5 test clients → real user-service WebSocket
  - **Infrastructure**: Real streaming pipeline (RTMP → Nginx → WebSocket → clients)
  - **Est. Time**: 1.5 days
  - **Success**: All 5 test clients maintain real-time connection, receive consistent data from real infrastructure

- [ ] **P1-T006** Create Scenario 4 test: HLS Playlist Validation
  - **File**: `tests/integration/hls_playlist_test.rs`
  - **Flow**: Test simulator streams to real Nginx-RTMP → Verify real HLS m3u8 generation → Validate playlist format
  - **Infrastructure**: Real Nginx-RTMP HLS output
  - **Est. Time**: 1 day
  - **Success**: Real Nginx-RTMP generates valid m3u8 files with correct quality variants

- [ ] **P1-T007** Create Scenario 5 test: Metrics Collection E2E
  - **File**: `tests/integration/metrics_collection_test.rs`
  - **Flow**: Test simulator streams to real Nginx-RTMP → real user-service collects metrics → Verify counters → Query via real Redis
  - **Infrastructure**: Real Nginx-RTMP + real user-service metrics collection + real Redis
  - **Est. Time**: 1 day
  - **Success**: Real infrastructure accurately tracks viewers, bitrate, errors in real Redis

- [ ] **P1-T008** Setup Docker test infrastructure
  - **File**: `docker-compose.test.yml` (extends existing `docker-compose.yml`)
  - **Services**: PostgreSQL, Redis, real Nginx-RTMP server, user-service
  - **Purpose**: Provides real production services for automated test clients to connect to
  - **Est. Time**: 0.5 days
  - **Success**: `docker-compose -f docker-compose.test.yml up` launches all production services ready for test client connections

---

## Priority 2: Prometheus Monitoring & Observability

### Goal
Implement production-grade metrics collection, Prometheus export, and Kubernetes integration for monitoring streaming health.

### Success Criteria
- ✅ 8 metric types exported to Prometheus
- ✅ ServiceMonitor auto-discovers metrics in Kubernetes
- ✅ Prometheus scrapes metrics successfully every 30 seconds
- ✅ Grafana dashboard displays live data

### Tasks

- [ ] **P2-T001** Create prometheus_exporter.rs module in user-service
  - **File**: `backend/user-service/src/prometheus_exporter.rs`
  - **Metrics** (8 types):
    1. `nova_streaming_active_streams` (gauge) - current active streams
    2. `nova_streaming_viewers_total` (histogram) - total viewer count
    3. `nova_streaming_peak_viewers` (gauge) - peak viewers this stream
    4. `nova_streaming_stream_duration_seconds` (histogram) - stream uptime
    5. `nova_streaming_websocket_connections` (gauge) - active WebSocket clients
    6. `nova_streaming_broadcast_errors_total` (counter) - broadcast failures
    7. `nova_streaming_rtmp_ingestion_latency_seconds` (histogram) - RTMP processing delay
    8. `nova_streaming_hls_segment_generation_seconds` (histogram) - segment creation time
  - **Est. Time**: 1.5 days
  - **Success**: `/metrics` endpoint returns Prometheus-format metrics

- [ ] **P2-T002** Integrate metrics collection in handlers
  - **Files**: `handlers/streaming_websocket.rs`, `handlers/feed.rs`, main.rs
  - **Action**: Call metric collectors on WebSocket connect/disconnect, stream start/end, segment generation
  - **Est. Time**: 0.5 days
  - **Success**: Metrics updated in real-time as streams and viewers connect

- [ ] **P2-T003** Create Kubernetes ServiceMonitor
  - **File**: `k8s/prometheus-service-monitor.yaml`
  - **Config**: Scrape /metrics endpoint every 30 seconds
  - **Est. Time**: 0.5 days
  - **Success**: Prometheus discovers and scrapes metrics from user-service pods

- [ ] **P2-T004** Create Grafana dashboard
  - **File**: `monitoring/grafana-dashboard.json`
  - **Panels** (5 graphs):
    1. Active Streams (gauge)
    2. Concurrent Viewers (line chart, real-time)
    3. Quality Distribution (stacked bar)
    4. Error Rate (line chart)
    5. Latency Percentiles (heatmap)
  - **Est. Time**: 1 day
  - **Success**: Dashboard displays live data when connected to Prometheus

- [ ] **P2-T005** Create alerting rules
  - **File**: `monitoring/prometheus-alerts.yaml`
  - **Alerts** (4 critical thresholds):
    1. Error rate >1%
    2. WebSocket connection failures >5/min
    3. HLS segment generation >5 seconds
    4. Peak viewers drop >50% in 1 minute
  - **Est. Time**: 0.5 days
  - **Success**: Prometheus fires alerts when thresholds exceeded

- [ ] **P2-T006** Document metrics collection and dashboarding
  - **File**: `docs/MONITORING.md`
  - **Content**: Metrics definitions, dashboard setup, alert interpretation
  - **Est. Time**: 0.5 days
  - **Success**: Operators can understand and troubleshoot all metrics

---

## Priority 3: API Documentation & OpenAPI Spec

### Goal
Create comprehensive OpenAPI 3.0.3 specification and client examples for streaming API.

### Success Criteria
- ✅ OpenAPI spec covers all 6 endpoints
- ✅ Spec includes request/response schemas
- ✅ 3 working client examples (JS, Python, cURL)
- ✅ Spec validates with Swagger/Redoc

### Tasks

- [ ] **P3-T001** Create OpenAPI 3.0.3 specification
  - **File**: `docs/streaming-api.openapi.yaml`
  - **Endpoints** (6 total):
    1. GET /api/v1/streams/{stream_id}/ws - WebSocket upgrade
    2. GET /api/v1/streams/{stream_id} - Stream status
    3. GET /api/v1/streams/{stream_id}/metrics - Historical metrics
    4. GET /api/v1/streams - List active streams
    5. POST /api/v1/streams - Create stream (for testing)
    6. DELETE /api/v1/streams/{stream_id} - End stream
  - **Est. Time**: 1 day
  - **Success**: Spec validates with swagger-cli

- [ ] **P3-T002** Document WebSocket message schema
  - **File**: `docs/streaming-api.openapi.yaml`
  - **Content**: JSON message format, event types, example payloads
  - **Est. Time**: 0.5 days
  - **Success**: Schema covers all 4 event types with examples

- [ ] **P3-T003** Create JavaScript client example
  - **File**: `docs/examples/client-js.html`
  - **Features**: Connect, receive updates, handle disconnection
  - **Est. Time**: 0.5 days
  - **Success**: Example connects to real WebSocket and displays viewer count

- [ ] **P3-T004** Create Python broadcaster example
  - **File**: `docs/examples/broadcaster.py`
  - **Features**: RTMP connection simulation, error handling
  - **Est. Time**: 0.5 days
  - **Success**: Script can connect to RTMP server and stream test frames

- [ ] **P3-T005** Create cURL testing guide
  - **File**: `docs/examples/curl-tests.sh`
  - **Commands**: Test each endpoint, WebSocket upgrade
  - **Est. Time**: 0.5 days
  - **Success**: All curl commands return expected responses

---

## Priority 4: Deployment Guides & Runbooks

### Goal
Document complete deployment procedures for local, staging, and production environments.

### Success Criteria
- ✅ Local setup guide (works for new developers)
- ✅ Staging deployment checklist (pre-deployment verification)
- ✅ Production deployment guide (zero-downtime deployment)
- ✅ Troubleshooting runbook (5 common issues + solutions)

### Tasks

- [ ] **P4-T001** Create local development setup guide
  - **File**: `docs/DEVELOPMENT.md`
  - **Content**: Prerequisites, environment setup, Docker Compose, running tests
  - **Est. Time**: 1 day
  - **Success**: New developer can `make dev` and run full test suite

- [ ] **P4-T002** Create staging deployment checklist
  - **File**: `docs/STAGING_DEPLOYMENT.md`
  - **Checklist** (pre-deployment):
    1. Code review completed
    2. All tests pass locally
    3. Dependencies updated
    4. Security scan passed
    5. Performance benchmarks acceptable
  - **Est. Time**: 0.5 days
  - **Success**: Checklist prevents staging deploys with known issues

- [ ] **P4-T003** Create production deployment guide
  - **File**: `docs/PRODUCTION_DEPLOYMENT.md`
  - **Procedures**: Rolling updates, database migrations, rollback procedures
  - **Est. Time**: 1.5 days
  - **Success**: Deployment team can follow guide without manual intervention

- [ ] **P4-T004** Create troubleshooting runbook
  - **File**: `docs/TROUBLESHOOTING.md`
  - **Issues** (5 common scenarios):
    1. "Viewers not receiving WebSocket updates" → Check Redis, WebSocket connections
    2. "HLS segments not generating" → Check Nginx-RTMP, disk space
    3. "Metrics not appearing in Prometheus" → Check scrape config, endpoint connectivity
    4. "RTMP connection rejected" → Check streaming key, firewall rules
    5. "High latency (>3 seconds)" → Check network, resource utilization
  - **Est. Time**: 1 day
  - **Success**: Runbook resolves 90% of production issues

---

## Task Dependencies & Parallelization

### Critical Path
```
P0 (Compilation Fixes - 0.5 days)
    ↓
[P1 Tests ∥ P2 Monitoring ∥ P3 Documentation ∥ P4 Deployment] (Can run in parallel)
    ↓
Final validation (compilation + full test suite)
```

### Parallelizable Tasks
- P1-T001, P1-T002 (mock client development) - independent
- P1-T003 → P1-T007 (5 test scenarios) - can start once mock client ready
- P2-T001 → P2-T006 (monitoring setup) - independent
- P3-T001 → P3-T005 (documentation) - independent
- P4-T001 → P4-T004 (deployment guides) - independent

### Suggested Parallelization for 3-Engineer Team
- **Engineer 1**: P0 fixes → P1 integration tests (critical path)
- **Engineer 2**: P2 Prometheus monitoring + P3 API documentation
- **Engineer 3**: P4 deployment guides + operational docs

---

## Timeline & Milestones

| Week | Day | Focus | Deliverables |
|------|-----|-------|--------------|
| 1 | 1 | P0 Fixes | ✅ Compilation errors resolved |
| 1 | 2-3 | P1 Mock Client | ✅ Mock RTMP client complete |
| 1 | 4-5 | P1 Tests | ✅ First 2-3 test scenarios passing |
| 2 | 1-3 | P1 Final Tests + P2 Start | ✅ All 5 test scenarios + Prometheus setup |
| 2 | 4-5 | P2 Monitoring + P3 Docs | ✅ Grafana dashboard + OpenAPI spec |
| 3 | 1-2 | P4 Deployment Guides | ✅ All deployment docs complete |
| 3 | 3 | Validation | ✅ Full test suite passes, build clean, staging verification |

**Total: 15 days (3 weeks)**
**Target Completion**: ~2025-11-10

---

## Acceptance Criteria for Phase 2 Completion

- ✅ **Code Quality**: `cargo build --release` succeeds with 0 errors and 0 warnings
- ✅ **Integration Tests**: All 5 end-to-end scenarios pass with 100% pass rate
- ✅ **Prometheus Export**: 8 metrics types exported and scraped successfully
- ✅ **Kubernetes Integration**: ServiceMonitor discovers metrics, Grafana displays data
- ✅ **API Documentation**: OpenAPI spec complete with 3 client examples
- ✅ **Deployment**: Tested in staging, deployment guide written and validated
- ✅ **Overall Completion**: Project moves from 65% → 90%

---

## Known Risks & Mitigation

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Mock RTMP client complexity | May delay P1 | Start early, use reference implementations (nginx-rtmp source code) |
| Test flakiness (timing issues) | May require reruns | Use deterministic test seeds, fixed delays, Docker container health checks |
| Prometheus memory overhead | May impact staging | Set metric cardinality limits, implement metric pruning |
| WebSocket cleanup on disconnect | May cause memory leaks | Implement graceful shutdown, connection timeout handlers |

---

## Success Metrics

Upon completion of Phase 2, the system should demonstrate:
1. **Reliability**: 99%+ test pass rate, zero data loss during streaming
2. **Performance**: <3 second viewer startup, <2 second quality switches, <2 second metric updates
3. **Observability**: All operations visible via Prometheus/Grafana, full audit trail
4. **Operability**: Deployment, scaling, and troubleshooting fully documented

---

**Generated**: 2025-10-21
**Status**: Ready for implementation
**Est. Effort**: 15 days (120 hours)
**Recommended Team Size**: 3 engineers
**Estimated Completion**: 2025-11-10

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
