# Implementation Plan: Video Live Streaming Infrastructure

**Branch**: `001-rtmp-hls-streaming` | **Date**: 2025-10-20 | **Spec**: [spec.md](./spec.md)
**Status**: In Progress | **Completion**: ~65% (aligned with actual code)
**Implementation Location**: `backend/user-service/src/services/streaming/`

## Summary

Build a scalable, pragmatic live streaming infrastructure supporting RTMP ingest, adaptive bitrate output (HLS/DASH), and real-time analytics. Target: <3s viewer startup, <5s ingestion latency, 10k+ concurrent viewers.

**Architecture Decision**: Hybrid approach combining:
- **Nginx-RTMP** container for protocol ingestion (external)
- **user-service streaming module** for coordination/API
- **CloudFront CDN** for HLS/DASH delivery (external)
- **PostgreSQL + Redis** for state management
- **ClickHouse** for analytics

This pragmatic choice prioritizes:
1. **Simplicity**: Single service to maintain (vs 5 microservices)
2. **Speed**: Faster iteration and deployment
3. **Cost**: Lower operational overhead
4. **Scalability**: Can decompose to microservices if needed (>1k streams)

## Technical Context

**Language/Version**: Rust 1.75+ (per Constitution: Microservices Architecture principle)
**Primary Dependencies**: Actix-web (REST API), tokio-tungstenite (WebSocket), tokio-util (async utilities), serde/serde_json (serialization)
**Storage**: PostgreSQL (stream state, viewer sessions, analytics), Redis (real-time metrics cache), Kafka (event streaming)
**Testing**: cargo test (unit + integration), custom RTMP mock clients for protocol testing
**Target Platform**: Linux server (Docker containerized, Kubernetes orchestration)
**Project Type**: Distributed microservices architecture (3 services: ingestion, transcoding, delivery)
**Performance Goals**: <3s viewer startup time, <5s RTMP-to-HLS latency, <2s quality adaptation, 10k+ concurrent viewers/stream
**Constraints**: Must maintain <5% dropped frame rate, 99.9% availability, support geo-distributed CDN
**Scale/Scope**: 100 concurrent broadcast streams, 1M+ viewers daily, 12 functional requirements, P1+P2 user stories

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Compliance | Notes |
|-----------|-----------|-------|
| **I. Microservices** | ✅ PASS | 3 independent Rust services (ingestion, transcoding, delivery) with event-driven via Kafka |
| **II. Cross-Platform** | ⏸ N/A | Backend-only MVP; iOS/Android integration via API comes later |
| **III. TDD** | ✅ PASS | cargo test infrastructure required; RTMP protocol testing via mock clients |
| **IV. Security** | ✅ PASS | Streaming keys for auth; HTTPS/TLS for APIs; Kafka inter-service communication |
| **V. UX Excellence** | ✅ PASS | Performance targets (<3s startup, <5s latency) align with smooth viewer experience |
| **VI. Observability** | ✅ PASS | Real-time metrics via WebSocket/REST API; distributed tracing for stream lifecycle |
| **VII. CI/CD** | ✅ PASS | Docker + Kubernetes ready; health checks for graceful shutdown/restart |

**Gate Status**: ✅ **APPROVED** — All core principles satisfied. No constitution violations.

## Project Structure

### Documentation (this feature)

```
specs/[###-feature]/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```
# Rust microservices workspace for streaming infrastructure
streaming/
├── Cargo.workspace.toml              # Workspace definition
│
├── crates/
│   ├── streaming-core/               # Shared types, protocols, utilities
│   │   ├── src/
│   │   │   ├── lib.rs
│   │   │   ├── rtmp.rs              # RTMP protocol parser
│   │   │   ├── hls.rs               # HLS segment generation
│   │   │   ├── dash.rs              # DASH manifest generation
│   │   │   ├── models.rs            # Stream, Quality, Metrics entities
│   │   │   └── errors.rs            # Error types
│   │   └── tests/
│   │
│   ├── streaming-ingest/            # RTMP ingestion service
│   │   ├── src/
│   │   │   ├── main.rs
│   │   │   ├── rtmp_handler.rs      # RTMP protocol handler
│   │   │   ├── stream_manager.rs    # Stream state management
│   │   │   ├── quality_adapter.rs   # Bitrate adaptation logic
│   │   │   └── kafka_producer.rs    # Event publishing
│   │   ├── tests/
│   │   └── Dockerfile
│   │
│   ├── streaming-transcode/         # Transcoding service
│   │   ├── src/
│   │   │   ├── main.rs
│   │   │   ├── transcoder.rs        # H.264 → multi-bitrate
│   │   │   ├── segment_writer.rs    # HLS/DASH segment output
│   │   │   ├── kafka_consumer.rs    # Event consumption
│   │   │   └── cache_manager.rs     # Redis segment caching
│   │   ├── tests/
│   │   └── Dockerfile
│   │
│   ├── streaming-delivery/          # Delivery service (HLS/DASH)
│   │   ├── src/
│   │   │   ├── main.rs              # Actix-web REST API
│   │   │   ├── hls_handler.rs       # HLS playlist/segment serving
│   │   │   ├── dash_handler.rs      # DASH MPD/segment serving
│   │   │   ├── websocket_hub.rs     # Real-time notifications
│   │   │   ├── analytics.rs         # Metrics aggregation
│   │   │   └── cdn_integration.rs   # CDN header/routing
│   │   ├── tests/
│   │   └── Dockerfile
│   │
│   └── streaming-api/               # Management API
│       ├── src/
│       │   ├── main.rs              # Actix-web REST API
│       │   ├── stream_controller.rs # Start/stop streams
│       │   ├── auth.rs              # Streaming key validation
│       │   ├── metrics_api.rs       # Metrics endpoints
│       │   └── db.rs                # PostgreSQL pool
│       ├── tests/
│       └── Dockerfile
│
├── tests/
│   ├── integration/
│   │   ├── rtmp_ingest_test.rs
│   │   ├── transcoding_test.rs
│   │   ├── delivery_test.rs
│   │   └── end_to_end_test.rs
│   └── contract/
│       ├── rest_api_test.rs
│       └── kafka_events_test.rs
│
├── k8s/
│   ├── namespace.yaml
│   ├── streaming-ingest-deployment.yaml
│   ├── streaming-transcode-deployment.yaml
│   ├── streaming-delivery-deployment.yaml
│   ├── streaming-api-deployment.yaml
│   └── services.yaml
│
├── docker-compose.yml               # Local development
└── Makefile                         # Build/test targets
```

**Structure Decision**: Microservices workspace model (Option 3 adapted) — 5 independent Rust crates organized by service responsibility. Each service has its own Dockerfile and Kubernetes manifests. Shared code in `streaming-core`. Integration tests validate cross-service contracts. Aligns with Constitution Principle I (Microservices Architecture).

## Phase 0: Outline & Research

**Status**: Ready to execute | **Deliverable**: `research.md`

### Research Tasks

1. **RTMP Protocol Implementation**
   - Task: Research Rust RTMP server libraries (rrtmp, media-rs, custom parser)
   - Decision Required: Use existing crate vs. implement parser
   - Impact: Affects ingestion service architecture

2. **HLS/DASH Segment Generation**
   - Task: Research segment generation libraries, timing, and playlist format specs
   - Decision Required: Library (mp4, hls) vs. manual implementation
   - Impact: Affects transcoding service output quality

3. **Adaptive Bitrate Strategy**
   - Task: Research ABR algorithms (bandwidth estimation, quality ladder sizing)
   - Decision Required: Standard ladder (480p, 720p, 1080p) vs. dynamic
   - Impact: Affects transcoding load and viewer experience

4. **Kafka Event Schema**
   - Task: Research stream event schema design for system-wide tracing
   - Decision Required: Event format, partitioning strategy
   - Impact: Affects inter-service communication reliability

5. **Real-Time Metrics Infrastructure**
   - Task: Research WebSocket broadcasting patterns and metric aggregation
   - Decision Required: Per-stream metrics vs. global aggregation
   - Impact: Affects analytics API design

**Research Execution**: Will dispatch agents to research each decision, consolidate findings into `research.md` with rationale for each choice.

## Phase 1: Design & Contracts

**Prerequisite**: `research.md` complete with all clarifications resolved

### 1. Data Model Design

**Deliverable**: `data-model.md`

**Entities to generate**:
- Stream (with state machine: pending→active→ended)
- StreamKey (auth credential lifecycle)
- ViewerSession (viewer tracking with quality history)
- StreamMetrics (real-time aggregated metrics)
- QualityLevel (predefined output variants)

**State Machines**:
- Stream states: PENDING_INGEST → ACTIVE → ENDED_GRACEFULLY | ERROR
- Quality transitions: triggered by bandwidth events with debouncing

### 2. API Contracts

**Deliverable**: OpenAPI schemas in `/contracts/`

**Ingestion Service**:
- RTMP server (port 1935) — no REST API, binary protocol
- Kafka producer for stream events

**Delivery Service**:
- GET /hls/:stream_id/index.m3u8 (HLS master playlist)
- GET /hls/:stream_id/:quality/segment-N.ts (HLS segments)
- GET /dash/:stream_id/manifest.mpd (DASH manifest)
- GET /dash/:stream_id/:quality/segment-N.m4s (DASH segments)
- WebSocket /ws/stream/:stream_id (real-time notifications + metrics)

**Management API**:
- POST /streams (start broadcast with auth key)
- GET /streams/:stream_id (stream status)
- DELETE /streams/:stream_id (stop broadcast)
- GET /metrics/:stream_id (analytics data)

### 3. Agent Context Update

**Deliverable**: Update agent-specific context file

**Execution**: Run `.specify/scripts/bash/update-agent-context.sh claude` to register streaming technology choices with the AI agent for future development.

### 4. Quickstart Guide

**Deliverable**: `quickstart.md`

Contains:
- Service startup sequence (Docker Compose for local dev)
- Sample broadcaster flow (connect via OBS, stream starts)
- Sample viewer flow (open URL, HLS/DASH playback begins)
- Testing checklist

## Phase 2: Tasks (NOT Generated by /speckit.plan)

**Next Command**: `/speckit.tasks`

Will generate:
- Detailed implementation tasks with dependencies
- Estimated time per task
- Test requirements per task
- Success criteria for each task

