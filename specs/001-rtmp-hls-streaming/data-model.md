# Data Model: Video Live Streaming Infrastructure

**Date**: 2025-10-20
**Entities**: 5 core entities with relationships and state machines
**Schema**: PostgreSQL + Redis + Kafka

---

## Entity Definitions

### 1. Stream (Active Broadcast Session)

**Purpose**: Represents a live broadcast from start to end, tracking status and metrics.

**Primary Key**: `stream_id` (UUID)

**Fields**:
| Field | Type | Description |
|-------|------|-------------|
| stream_id | UUID | Unique identifier |
| broadcaster_id | UUID | User initiating the stream |
| stream_key_id | UUID | Foreign key to StreamKey used |
| status | ENUM | Current state: PENDING_INGEST, ACTIVE, ENDED_GRACEFULLY, ERROR |
| created_at | Timestamp | When stream record created (before RTMP connection) |
| started_at | Timestamp | When RTMP connection established (status→ACTIVE) |
| ended_at | Timestamp | When stream ended or error occurred |
| error_reason | TEXT | If ERROR, reason for failure |
| duration_seconds | INTEGER | Total stream duration |
| concurrent_viewers | INTEGER | Current viewer count (real-time, from Redis) |
| total_viewers | INTEGER | All unique viewers who joined during stream |
| total_bytes_ingested | BIGINT | Bytes received from encoder |
| total_bytes_delivered | BIGINT | Bytes sent to viewers |
| ingress_bitrate_mbps | FLOAT | Average input bitrate |
| dropped_frames | INTEGER | Total frames lost during transcoding |
| buffering_events_count | INTEGER | Total buffering events across all viewers |
| title | TEXT | Broadcast title (optional) |
| description | TEXT | Broadcast description (optional) |
| tags | JSON | Metadata tags for discovery |

**Relationships**:
- FK: `broadcaster_id` → User (from auth system, external)
- FK: `stream_key_id` → StreamKey
- HAS MANY: ViewerSession (one stream → many viewers)
- HAS MANY: StreamMetrics (one stream → many metric records)

**Indexes**:
- PRIMARY KEY (stream_id)
- UNIQUE (broadcaster_id, created_at) — prevent duplicate broadcasts
- INDEX (status, created_at) — query active streams
- INDEX (started_at) — chronological queries

---

### 2. StreamKey (Broadcaster Authentication)

**Purpose**: Credentials used by broadcasters to authenticate RTMP connections.

**Primary Key**: `key_id` (UUID)

**Fields**:
| Field | Type | Description |
|-------|------|-------------|
| key_id | UUID | Unique key identifier |
| broadcaster_id | UUID | Owner of this key |
| key_value | TEXT | Secret key (bcrypt hashed) |
| is_active | BOOLEAN | Revocation flag |
| created_at | Timestamp | When key was generated |
| revoked_at | Timestamp | When key was revoked (NULL if active) |
| last_used_at | Timestamp | Last successful RTMP connection |
| last_used_ip | INET | IP address of last connection |
| description | TEXT | Human-readable label (e.g., "OBS Home") |

**Relationships**:
- FK: `broadcaster_id` → User (external)
- HAS MANY: Stream (one key → many streams)

**Indexes**:
- PRIMARY KEY (key_id)
- UNIQUE (key_value) — prevent duplicate key values
- INDEX (broadcaster_id, is_active) — active keys per broadcaster
- INDEX (last_used_at) — identify stale keys

**Security Note**: Key values stored bcrypt-hashed; never stored in plaintext. Comparison via bcrypt verify.

---

### 3. ViewerSession (Viewer Engagement)

**Purpose**: Track individual viewer connections, quality history, and engagement metrics.

**Primary Key**: `session_id` (UUID)

**Fields**:
| Field | Type | Description |
|-------|------|-------------|
| session_id | UUID | Unique viewer session |
| viewer_id | UUID | Viewer identifier (from client, can be anonymous) |
| stream_id | UUID | Stream being watched (FK) |
| quality_level | ENUM | Current quality: 480P, 720P, 1080P |
| joined_at | Timestamp | When viewer opened stream |
| left_at | Timestamp | When viewer closed stream (NULL if ongoing) |
| duration_seconds | INTEGER | Total watch duration |
| bytes_transferred | BIGINT | Data downloaded by viewer |
| buffer_events | INTEGER | Number of times playback buffered |
| total_buffer_time_ms | FLOAT | Total buffering duration |
| quality_switches | INTEGER | Number of ABR quality changes |
| final_quality | ENUM | Quality when viewer left |
| device_type | TEXT | Browser/device identifier (from User-Agent) |
| geo_location | POINT | Geographic location (optional, from GeoIP) |
| session_token | UUID | Unique identifier for distributed tracing |

**Relationships**:
- FK: `stream_id` → Stream
- MANY-TO-ONE: Stream (many viewers per stream)

**Indexes**:
- PRIMARY KEY (session_id)
- INDEX (stream_id, joined_at) — viewers per stream, chronological
- INDEX (viewer_id, joined_at) — viewer history
- INDEX (left_at) — query completed sessions

**Temporal Data**: Use PostgreSQL RANGE type for quality_history (quality change timeline):
```sql
quality_history: RANGE[tstzrange][] -- array of (timestamp_range, quality)
```

---

### 4. StreamMetrics (Real-Time Telemetry)

**Purpose**: Time-series metrics for stream health and performance analysis.

**Primary Key**: `metrics_id` (UUID)

**Fields**:
| Field | Type | Description |
|-------|------|-------------|
| metrics_id | UUID | Unique metric record |
| stream_id | UUID | Stream being measured (FK) |
| timestamp | Timestamp | When metrics were captured (1-second granularity) |
| concurrent_viewers | INTEGER | Current active viewers at this moment |
| ingress_bitrate_mbps | FLOAT | Current input bitrate |
| egress_bitrate_mbps | FLOAT | Current output bitrate (sum all viewers) |
| quality_distribution | JSON | {480p: 30%, 720p: 50%, 1080p: 20%} |
| dropped_frames_rate | FLOAT | Frames lost per second |
| buffering_events | INTEGER | New buffering events this second |
| avg_buffer_time_ms | FLOAT | Average buffer time across viewers |
| storage_used_mb | FLOAT | Segment storage size on disk |
| error_count | INTEGER | Errors logged this second |

**Relationships**:
- FK: `stream_id` → Stream
- ONE-TO-MANY: Stream (one stream → many metric records)

**Indexes**:
- PRIMARY KEY (metrics_id)
- INDEX (stream_id, timestamp DESC) — time-series queries

**Data Retention**:
- Hot data (last 24h): PostgreSQL (real-time queries)
- Warm data (1 month): PostgreSQL (analytics)
- Cold data (>1 month): Archived to S3 (long-term retention)

**Storage Note**: 1 second granularity × 1M streams × 30 days = ~2.6B records. Use PostgreSQL partitioning (PARTITION BY RANGE (timestamp)) to keep queries fast.

---

### 5. QualityLevel (Output Format Preset)

**Purpose**: Define available video quality options, transcoding profiles, and fallback rules.

**Primary Key**: `level_id` (UUID)

**Fields**:
| Field | Type | Description |
|-------|------|-------------|
| level_id | UUID | Unique quality identifier |
| name | TEXT | Human-readable name (e.g., "720p") |
| display_name | TEXT | User-facing label (e.g., "HD") |
| resolution_width | INTEGER | Video width in pixels |
| resolution_height | INTEGER | Video height in pixels |
| bitrate_min_mbps | FLOAT | Minimum bitrate for this quality |
| bitrate_target_mbps | FLOAT | Recommended bitrate |
| bitrate_max_mbps | FLOAT | Maximum bitrate allowed |
| codec_video | TEXT | Video codec (always "h264" for MVP) |
| codec_audio | TEXT | Audio codec (always "aac" for MVP) |
| frame_rate | INTEGER | Frames per second (typically 30 or 60) |
| segment_duration_seconds | INTEGER | HLS segment length (typically 2-10) |
| priority | INTEGER | Selection priority (1 = highest, 3 = fallback) |
| enabled | BOOLEAN | Activate/deactivate quality option |

**Relationships**:
- NONE (lookup table, no foreign keys)

**Indexes**:
- PRIMARY KEY (level_id)
- UNIQUE (name)
- INDEX (priority, enabled) — ABR selection

**Presets (Hardcoded for MVP)**:
```
1. 480p (Low)    - 1920x1080 → 720x480  - 2 Mbps - Priority 3 (fallback)
2. 720p (HD)     - 1920x1080 → 1280x720 - 5 Mbps - Priority 2 (default)
3. 1080p (Full)  - 1920x1080 → 1920x1080 - 8 Mbps - Priority 1 (premium)
```

---

## State Machines

### Stream Lifecycle

```
┌─────────────┐
│  CREATED    │  (stream_id generated, awaiting RTMP connection)
│ (no data)   │
└──────┬──────┘
       │ RTMP.connect(stream_key)
       ▼
┌─────────────────────┐
│  PENDING_INGEST     │  (key validated, waiting for first frame)
│ (created_at set)    │
└──────┬──────────────┘
       │ receive H.264/AAC frame
       ▼
┌─────────────────────┐
│  ACTIVE             │  (streaming normally)
│ (started_at set)    │ ◄─────────┐
└────┬────────┬───────┘           │
     │        │                   │
     │ (error)│ (graceful close)  │ (auto-recovery)
     │        │                   │
     ▼        ▼                   │
┌──────────────────────┐      ┌───┴─────────┐
│  ERROR               │      │ RECONNECTING│
│ (error_reason set)   │      └──────┬──────┘
└──────────────────────┘             │
                                     └─ (connection re-established)

FINAL_STATES: ENDED_GRACEFULLY, ERROR
TIMEOUT: If no frame received for 30 seconds → ERROR
```

**Transitions**:
- PENDING_INGEST → ACTIVE: First H.264 frame received
- ACTIVE → ENDED_GRACEFULLY: Broadcaster closes connection cleanly
- ACTIVE → ERROR: Network error, codec error, or timeout (30s no data)
- ERROR → ACTIVE: Broadcaster reconnects with same stream_id (recovery)
- Any → ENDED_GRACEFULLY: Admin manual stop (future)

**Broadcast Events**:
- `StreamStarted` (PENDING_INGEST → ACTIVE)
- `StreamEnded` (ACTIVE → ENDED_GRACEFULLY)
- `StreamError` (ACTIVE → ERROR)
- `StreamRecovering` (ERROR → ACTIVE)

---

### ViewerSession Lifecycle

```
┌──────────────┐
│  JOINED      │  (viewer_id generated, connected to HLS/DASH)
└──────┬───────┘
       │ start playback
       ▼
┌─────────────────────┐
│  PLAYING            │  (data flowing to viewer)
│ (quality_level set) │  ◄─────────┬──────────┐
└────┬────────┬───────┘            │          │
     │        │                    │          │
     │ (error)│ (disconnect)       │ (buffering)
     │        │                    │          │
     ▼        ▼                    │          │
┌──────────┐┌─────────┐        ┌───┴──────┐
│  ERROR   ││ LEFT    │        │ BUFFERING│
└──────────┘└─────────┘        └──────────┘
                                    │
                                    └─ (buffer filled)
FINAL_STATES: LEFT, ERROR
TIMEOUT: If no heartbeat for 60s → LEFT
```

**Quality Switch Trigger**:
- Client detects buffer fill rate declining → requests lower quality via playlist selection
- Metrics emitted: `QualitySwitched { viewer_session_id, old_quality, new_quality }`

---

## Relationships Diagram

```
User (external)
  ├── HAS MANY StreamKey (pk: broadcaster_id)
  │     └── HAS MANY Stream (fk: stream_key_id)
  │            ├── HAS MANY ViewerSession (fk: stream_id)
  │            │     └── viewer_id (anonymous viewer identifier)
  │            └── HAS MANY StreamMetrics (fk: stream_id, timestamp series)
  │
  └── ViewerSession.viewer_id (can be anonymous)

QualityLevel (lookup table, no FK)
  └── Referenced by ViewerSession.quality_level (denormalized for performance)
```

---

## Data Integrity Rules

1. **Immutable Stream Creation**: Once `stream_id` created, cannot be deleted (audit trail)
2. **Stream Isolation**: One stream per `stream_key_id` at a time (prevent key reuse)
3. **ViewerSession Integrity**: `left_at ≥ joined_at` (temporal consistency)
4. **Metrics Granularity**: `StreamMetrics.timestamp` increments by 1 second minimum
5. **Quality Constraints**: `bitrate_min ≤ bitrate_target ≤ bitrate_max`

---

## Performance Considerations

### Indexes & Query Patterns

**Query 1: Active Streams (for Dashboard)**
```sql
SELECT * FROM Stream
WHERE status = 'ACTIVE'
  AND started_at > NOW() - INTERVAL '1 hour'
ORDER BY concurrent_viewers DESC
LIMIT 10;
-- Uses INDEX (status, created_at)
```

**Query 2: Viewer Metrics (for Analytics)**
```sql
SELECT
  SUM(bytes_transferred) as total_bytes,
  AVG(buffer_events) as avg_buffers,
  COUNT(*) as viewer_count
FROM ViewerSession
WHERE stream_id = $1
  AND joined_at > NOW() - INTERVAL '1 day';
-- Uses INDEX (stream_id, joined_at)
```

**Query 3: Time-Series Metrics (for Graphs)**
```sql
SELECT timestamp, concurrent_viewers, ingress_bitrate_mbps
FROM StreamMetrics
WHERE stream_id = $1
  AND timestamp BETWEEN $2 AND $3
ORDER BY timestamp ASC;
-- Uses INDEX (stream_id, timestamp DESC) with partitioning
```

### Caching Strategy (Redis)

**Cache Keys**:
- `stream:{stream_id}:metrics` — Current metrics (TTL: 5 seconds)
- `stream:{stream_id}:concurrent` — Viewer count (ZSET, TTL: 1 minute)
- `viewer:{session_id}:history` — Quality history (TTL: session duration)

**Invalidation**: Metrics cache invalidated every 1 second; concurrent viewer count updated on JOIN/LEAVE events.

---

## Schema DDL (PostgreSQL)

**Tables created by migration scripts** (not detailed here, but include):
- Stream (with PARTITION BY RANGE on started_at)
- StreamKey (with btree indexes)
- ViewerSession (with btree indexes)
- StreamMetrics (with PARTITION BY RANGE on timestamp)
- QualityLevel (static lookup)

**Additional Considerations**:
- Enable UUID extension: `CREATE EXTENSION IF NOT EXISTS "uuid-ossp"`
- Enable PostGIS for geo_location: `CREATE EXTENSION IF NOT EXISTS "postgis"`
- Set up logical replication for Kafka connector (audit events to external log)

---

**Approved**: Architecture Review
**Last Updated**: 2025-10-20
