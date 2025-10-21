# Streaming Infrastructure - Terminology Glossary

**Purpose**: Unified terminology reference to maintain consistency across spec.md, plan.md, and tasks.md documentation.

## Core Entities

### Stream
- **Definition**: Represents an active broadcast session with a unique identifier, broadcaster association, and lifecycle state.
- **Usage**:
  - Type reference: `Stream` (Rust struct in `streaming-core/src/models.rs`)
  - Database table: `streams` (lowercase plural)
  - Variable naming: `stream_id`, `stream_obj`, `current_stream`
- **Lifecycle**: PENDING_INGEST → ACTIVE → ENDED_GRACEFULLY | ERROR

### StreamKey
- **Definition**: Authentication credential issued to broadcasters for RTMP connection authorization.
- **Usage**:
  - Type reference: `StreamKey` (Rust struct)
  - Database table: `stream_keys` (lowercase plural with underscore)
  - Variable naming: `key_id`, `stream_key`, `auth_key`

### ViewerSession
- **Definition**: Represents a single viewer's interaction with a live stream, tracking quality selection, buffer events, and session duration.
- **Usage**:
  - Type reference: `ViewerSession` (Rust struct)
  - Database table: `viewer_sessions` (lowercase plural with underscore)
  - Variable naming: `session_id`, `viewer_session`, `current_session`

### StreamMetrics
- **Definition**: Aggregated telemetry snapshot for a stream at a specific timestamp (1-second granularity).
- **Usage**:
  - Type reference: `StreamMetrics` (Rust struct)
  - Database table: `stream_metrics` (lowercase plural with underscore)
  - Variable naming: `metrics`, `stream_metrics`, `metric_snapshot`

### QualityLevel
- **Definition**: Predefined output variant representing a specific resolution, bitrate range, and codec profile.
- **Usage**:
  - Type reference: `QualityLevel` (Rust struct)
  - Database table: `quality_levels` (lowercase plural with underscore)
  - Variable naming: `quality_level`, `output_quality`, `target_quality`
  - Values: "480p", "720p", "1080p" (string identifiers)

## Protocol & Format Terms

### RTMP (Real-Time Messaging Protocol)
- **Definition**: Binary protocol used for broadcaster ingestion (OBS, FFmpeg → streaming server).
- **Usage**: Port 1935, TLS optional for broadcast security
- **In code**: `rtmp`, `RTMP`, `RtmpHandshake`, `RtmpMessage`, `RtmpCommand`

### HLS (HTTP Live Streaming)
- **Definition**: Adaptive bitrate protocol for viewer playback via HTTP (Safari, Chrome, Firefox native support).
- **Components**:
  - Master playlist: `index.m3u8` (lists quality variants)
  - Quality playlists: `480p.m3u8`, `720p.m3u8`, etc. (lists segments per quality)
  - Segments: `segment-N.ts` (MPEG-2 Transport Stream files, typically 2-10s duration)
- **In code**: `hls`, `HLS`, `HlsPlaylist`, `HlsSegment`, `HlsVariant`

### DASH (Dynamic Adaptive Streaming over HTTP)
- **Definition**: Adaptive bitrate protocol for viewer playback via HTTP (XML-based manifest).
- **Components**:
  - Manifest: `manifest.mpd` (XML, lists adaptation sets and periods)
  - Segments: `segment-N.m4s` (ISO BMFF files)
- **In code**: `dash`, `DASH`, `DashMpd`, `DashPeriod`, `DashAdaptationSet`

## Quality & Bitrate Terms

### Quality Level / Quality Variant
- **Definition**: A specific combination of resolution and bitrate for output.
- **Standard ladder (MVP)**:
  - 480p @ 2 Mbps
  - 720p @ 5 Mbps
  - 1080p @ 8 Mbps
- **Notation**: Use "480p" (display), `quality_480p` (internal enum variant), `QualityLevel::P480` (type reference)
- **In database**: Store as string identifier "480p", "720p", "1080p" for human readability

### Adaptive Bitrate (ABR)
- **Definition**: Algorithm and mechanism to automatically adjust output quality based on viewer bandwidth and network conditions.
- **Client-side ABR**: Viewer player (HLS.js, dash.js) selects quality based on available bandwidth
- **Server-side ABR**: Ingestion service adapts incoming broadcast to standard quality levels
- **In code**: `abr`, `ABR`, `adaptive_bitrate`, `quality_adaptation`

## Data Flow Terms

### Ingestion / Ingest
- **Definition**: Process of receiving RTMP stream from broadcaster and parsing frames.
- **Service**: `streaming-ingest` (Rust crate)
- **Output**: Raw H.264 video + AAC audio frames → Kafka topic `stream-frames`
- **In code**: `ingest`, `ingestion`, `ingest_service`, `RtmpHandler`

### Transcoding / Transcode
- **Definition**: Process of converting ingested stream to multiple quality levels using FFmpeg.
- **Service**: `streaming-transcode` (Rust crate)
- **Input**: Kafka topic `stream-frames` (raw frames)
- **Output**: HLS/DASH segments (3 quality levels) → Redis cache + S3 storage
- **In code**: `transcode`, `transcoding`, `transcode_service`, `Transcoder`

### Delivery
- **Definition**: Process of serving HLS/DASH segments and playlists to viewers via HTTP.
- **Service**: `streaming-delivery` (Rust crate)
- **Input**: Segments from Redis/S3 cache
- **Output**: HTTP responses for GET /hls/*, GET /dash/*, WebSocket /ws/stream/*
- **In code**: `delivery`, `delivery_service`, `HlsHandler`, `DashHandler`

### CDN Integration
- **Definition**: Routing viewer requests through geographically distributed edge nodes for reduced latency.
- **Mechanism**: Delivery service rewrites segment URLs in playlists to point to CDN origin (e.g., `https://cdn.example.com/hls/...`)
- **Cache TTL**: 10 minutes for segments, 1 minute for manifests
- **In code**: `cdn`, `CDN`, `cdn_url_rewriter`, `cdn_auth`, `cdn_config`

## Performance Metric Terms

### Startup Time / Stream Startup
- **Definition**: Time from viewer clicking "play" to first video frame displayed.
- **Target**: <3 seconds
- **Measurement**: User action time → HTTP request → segment download → decoder → first frame → display
- **In code**: `startup_time`, `time_to_first_frame`, `initial_load_latency`

### Ingestion Latency / RTMP-to-HLS Latency
- **Definition**: Time from RTMP frame arrival at server to segment availability in HLS playlist.
- **Target**: <5 seconds
- **Components**: RTMP parse → H.264 extraction → FFmpeg transcoding → segment mux → playlist update
- **In code**: `ingestion_latency`, `rtmp_to_hls_latency`, `end_to_end_delay`

### Concurrent Viewers / Concurrent Viewer Count
- **Definition**: Number of active viewer sessions connected to a stream at a given moment.
- **Target**: 10,000+ per stream
- **Measurement**: Count of active `ViewerSession` records for a stream
- **In code**: `concurrent_viewers`, `active_viewer_count`, `viewer_count`

### Buffering / Buffer Events
- **Definition**: Playback stalls due to insufficient segment buffer, indicating network congestion or transcoding lag.
- **Target**: <0.5% of playback time, or 95% of viewers experience zero buffering
- **Measurement**: Player reports buffer underruns (SDK/player library logs)
- **In code**: `buffering_events`, `buffer_underrun`, `stall_count`, `buffering_rate`

### Quality Switch / Quality Adaptation
- **Definition**: Automatic change of output quality level due to bandwidth change or explicit user selection.
- **Target**: <2 seconds from bandwidth detection to quality change completion
- **Measurement**: Time from bandwidth measurement → quality selection decision → segment download at new quality
- **In code**: `quality_switch`, `quality_adaptation`, `quality_level_change`, `bitrate_switch`

## State & Lifecycle Terms

### Stream State / Stream Status
- **Definition**: Current operational state of a broadcast session.
- **Values**:
  - `PENDING_INGEST`: Stream created, awaiting RTMP connection
  - `ACTIVE`: RTMP connected, frames flowing, segments being produced
  - `ENDED_GRACEFULLY`: Broadcaster disconnected cleanly, stream finalized
  - `ERROR`: Unexpected failure (transcoding crash, Kafka failure, etc.)
- **In code**: Use Rust enum `StreamState { PendingIngest, Active, EndedGracefully, Error }`
- **In database**: Store as string "PENDING_INGEST", "ACTIVE", "ENDED_GRACEFULLY", "ERROR"

### Eventual Consistency / State Consistency
- **Definition**: All service replicas (ingestion, transcoding, delivery) converge to the same stream state within a defined time window.
- **Target**: <500ms divergence tolerance
- **Mechanism**: PostgreSQL advisory locks for atomic transitions, Kafka event ordering by `stream_id` partition
- **In code**: `state_consistency`, `eventual_consistency`, `state_sync`, `StateVerifier`

## Database & Infrastructure Terms

### Repository Pattern
- **Definition**: Data access abstraction layer for stream entities.
- **Usage**: `StreamRepository`, `StreamKeyRepository`, `ViewerSessionRepository`, `MetricsRepository`
- **Location**: `streaming-core/src/repositories/`
- **In code**: `stream_repo`, `key_repo`, `session_repo`, `metrics_repo`

### Connection Pooling
- **Definition**: Reusable pool of database connections to optimize resource usage.
- **PostgreSQL Pool**: Typically 20-30 connections
- **Redis Connection Pool**: Typically 10 connections
- **In code**: `ConnectionPool`, `db_pool`, `redis_pool`, `pool_size`

### Kafka Topic / Kafka Partition
- **Definition**: Message queue topic for inter-service communication.
- **Topics in use**:
  - `stream-frames`: Raw H.264/AAC frames from ingestion → transcoding
  - `stream-events`: State change events (StreamStarted, BitrateAdapted, StreamEnded) for all services
- **Partitioning**: By `stream_id` to ensure ordering per stream
- **In code**: `topic`, `partition`, `kafka_producer`, `kafka_consumer`

---

## Version History

| Date | Author | Changes |
|------|--------|---------|
| 2025-10-20 | Spec Team | Initial glossary created during specification analysis |

