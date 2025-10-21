# Phase 2 Design: Testing, Monitoring & Documentation

**Date**: 2025-10-21
**Phase**: Design (Post-WebSocket Implementation)
**Status**: Design Phase (Ready for Task Generation)
**Previous Status**: Phase 1 Complete (65% overall, WebSocket blocker resolved)

## Overview

Phase 2 focuses on **Quality Assurance, Observability, and Operability** to move from 65% to 90% completion. After WebSocket implementation, this phase ensures system reliability through integration testing, production monitoring, and operational documentation. Key deliverables: working integration tests, Prometheus metrics, API documentation, and deployment guides.

## Architecture

### Phase 2 Component Map

```
┌─────────────────────────────────────────────────────────┐
│              Quality Assurance Layer                     │
├──────────────┬──────────────────────┬──────────────────┤
│ Integration  │ Mock RTMP Client     │ E2E Test Suite   │
│ Tests        │ (Port 1935)          │ (5 scenarios)    │
└──────────────┴──────────────────────┴──────────────────┘
        ↓                      ↓                    ↓
┌─────────────────────────────────────────────────────────┐
│           Observability & Monitoring Layer              │
├──────────────┬──────────────────────┬──────────────────┤
│ Prometheus   │ Metrics Middleware   │ Kubernetes       │
│ Exporter     │ + 8 Metric Types     │ ServiceMonitor   │
└──────────────┴──────────────────────┴──────────────────┘
        ↓                      ↓                    ↓
┌─────────────────────────────────────────────────────────┐
│       Deployment & Documentation Layer                  │
├──────────────┬──────────────────────┬──────────────────┤
│ OpenAPI Spec │ Deployment Guide     │ Troubleshooting  │
│ (3.0.3)      │ + Checklist          │ Runbook          │
└──────────────┴──────────────────────┴──────────────────┘
        ↓                      ↓                    ↓
┌─────────────────────────────────────────────────────────┐
│    Phase 1 Implementation (WebSocket + Redis Ops)       │
│         [Streaming Service Architecture]               │
└─────────────────────────────────────────────────────────┘
```

## Components and Interfaces

### Component 1: Integration Testing Framework

**Mock RTMP Client** (`tests/integration/mock_rtmp_client.rs`)
- TCP socket connection to Nginx-RTMP (port 1935)
- RTMP handshake protocol + frame streaming
- H.264 frame generation (synthetic)

**Test Suites** (5 integration tests)
1. Broadcaster Lifecycle (connect → stream → disconnect)
2. Viewer WebSocket Connection (real-time updates)
3. End-to-End Viewer Experience (multiple viewers)
4. HLS Playlist Validation (CDN integration)
5. Metrics Collection (analytics pipeline)

**Infrastructure**
- Docker containers for PostgreSQL, Redis, Nginx-RTMP
- Test database + migrations
- Parallel/sequential test execution

### Component 2: Prometheus Monitoring

**Metrics to Export** (8 metric types)
- `nova_streaming_active_streams` (gauge)
- `nova_streaming_viewers_total` (histogram)
- `nova_streaming_peak_viewers` (gauge)
- `nova_streaming_stream_duration_seconds` (histogram)
- `nova_streaming_websocket_connections` (gauge)
- `nova_streaming_broadcast_errors_total` (counter)
- `nova_streaming_rtmp_ingestion_latency_seconds` (histogram)

**Module**: `prometheus_exporter.rs`
- Prometheus metric collectors
- Recording points in handlers
- `/metrics` endpoint (already registered)

**Kubernetes Integration**
- ServiceMonitor (if Prometheus Operator)
- Scrape config (if manual Prometheus)
- Grafana dashboard (5 graphs)
- Alert rules (4 thresholds)

### Component 3: API Documentation

**OpenAPI 3.0.3 Specification**
- 6 main endpoints documented
- Request/response schemas
- Error codes + examples

**Client Examples**
- JavaScript (WebSocket browser)
- Python (Broadcaster)
- cURL (Testing)

### Component 4: Deployment Guide

**Deployment Methods**
1. Local: `make dev` (Docker Compose)
2. Staging: `docker-compose.staging.yml`
3. Production: Kubernetes (Helm or kubectl)

**Operational Docs**
- Pre/during/post deployment checklist
- Troubleshooting runbook (5 common issues)
- Monitoring verification steps

## Data Models

### Integration Test Data Flow

```
Mock RTMP Client
    ↓ (RTMP frames)
Nginx-RTMP Container
    ↓ (webhook)
PostgreSQL: streams table
    ↓ (update)
Redis: stream:id:viewers (counter)
    ↓ (pub/sub)
StreamingHub (WebSocket)
    ↓ (broadcast JSON)
Connected WebSocket Clients
    ↓ (receive events)
Test Assertions (verify correctness)
```

### Metrics Data Structure

```json
{
  "metric_type": "histogram",
  "metric_name": "nova_streaming_viewers_total",
  "labels": {
    "stream_id": "uuid",
    "region": "us-west-2"
  },
  "value": 42,
  "timestamp": "2025-10-21T10:30:45Z"
}
```

## Error Handling

### Test Failure Scenarios

| Scenario | Handling | Recovery |
|----------|----------|----------|
| RTMP connection fails | Timeout + retry | Check Nginx container |
| WebSocket disconnect | Graceful close | Verify network |
| Database unavailable | Test skip | Restart PostgreSQL |
| Redis missing | Retry with backoff | Check Redis container |
| Metric export failure | Log warning | Check permissions |

### Production Error Handling

- **E0603 Private Import Errors**: Fix visibility/refactor APIs
- **Integration Test Flakiness**: Use deterministic seeds, fixed delays
- **Prometheus Memory**: Set limits per metric type
- **WebSocket Cleanup**: Implement graceful shutdown

## Testing Strategy

### Test Organization

```
tests/
├── integration/
│   ├── mod.rs                          (Test harness setup)
│   ├── mock_rtmp_client.rs             (RTMP simulator)
│   ├── streaming_lifecycle_test.rs     (Scenario 1)
│   ├── websocket_broadcast_test.rs     (Scenario 2)
│   ├── e2e_viewer_test.rs              (Scenario 3)
│   ├── hls_playlist_test.rs            (Scenario 4)
│   └── metrics_collection_test.rs      (Scenario 5)
└── fixtures/
    └── test_streams.sql                (Test data)
```

### Test Execution Strategy

- **Setup**: Spin up Docker containers once per test suite
- **Execution**: Run tests sequentially (avoid race conditions)
- **Cleanup**: Verify container state cleaned between tests
- **Reporting**: Metrics on test duration, memory, pass/fail rates

### Coverage Goals

- Streaming paths: 95%+
- WebSocket handler: 100%
- Error cases: 80%+
- Overall: 80%+

## Implementation Timeline

| Week | Focus | Days | Tasks |
|------|-------|------|-------|
| 1 | Setup & Testing | 5 | E0603 fixes + Integration framework |
| 2 | Monitoring | 5 | Prometheus + Kubernetes setup |
| 3 | Documentation | 5 | API docs + Deployment guides |
| 3 | Validation | 2 | Staging deploy + verification |

**Total Effort**: ~15 days
**Target Completion**: ~2025-11-10

## Acceptance Criteria for Phase 2

- ✅ Code compiles: `cargo build --release` (0 errors)
- ✅ Integration tests: 100% pass rate
- ✅ Prometheus: Metrics exported correctly
- ✅ Kubernetes: ServiceMonitor collecting metrics
- ✅ API docs: Complete OpenAPI spec
- ✅ Deployment: Tested in staging environment
- ✅ Overall completion: 90% (from 65%)

## Dependencies & Risks

### External Dependencies
- Docker/Docker-Compose (testing infrastructure)
- Kubernetes cluster (staging/prod deployment)
- Prometheus + Grafana (monitoring stack)

### Known Risks
1. **E0603 Errors**: May require deeper refactoring
2. **RTMP Protocol**: Mock client complexity
3. **Test Flakiness**: Network/timing issues
4. **Resource Usage**: Container overhead

## References

- Implementation: `STREAMING_WEBSOCKET_COMPLETE.md`
- Code Alignment: `CODE_ALIGNMENT.md`
- Specifications: `spec.md`, `plan.md`, `tasks.md`
- Commits: b68d543f (WebSocket), 53bb4901 (docs)
