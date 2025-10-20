# Quickstart Guide: Video Live Streaming Infrastructure

**Date**: 2025-10-20
**Target Audience**: Developers, QA testers, DevOps engineers
**Goal**: Get the streaming system running locally in <30 minutes

---

## Prerequisites

- Docker & Docker Compose installed
- Rust 1.75+ toolchain (for local development)
- OBS or FFmpeg for testing RTMP ingestion
- Modern web browser (Safari 15+, Chrome/Edge 90+, Firefox 88+) for HLS/DASH playback

---

## Part 1: Local Development Environment (10 min)

### 1. Start Infrastructure Services

```bash
cd streaming/
docker-compose up -d
```

**Services Started**:
- PostgreSQL (port 5432) — Stream state, viewer sessions
- Redis (port 6379) — Metrics cache, segment cache
- Kafka (port 9092) — Event streaming
- Nginx RTMP (port 1935) — RTMP listener (temporary, replaced by Rust service)

**Verify**:
```bash
docker ps
# Should see: postgres, redis, kafka, nginx running

docker exec postgres psql -U streaming -d streaming -c "SELECT 1"
# Should return: 1
```

### 2. Build Rust Services

```bash
# Build all services
cargo build --release --all

# Expected output:
# Compiling streaming-core v0.1.0
# Compiling streaming-ingest v0.1.0
# Compiling streaming-transcode v0.1.0
# Compiling streaming-delivery v0.1.0
# Compiling streaming-api v0.1.0
# Finished release [optimized] target(s) in 45s
```

### 3. Initialize Database

```bash
# Run migrations
sqlx migrate run --database-url postgres://streaming:password@localhost:5432/streaming

# Expected: "Migrating [2025-10-20-000001_init_schema]"
```

### 4. Start Services (Terminal Windows)

Open 5 terminal tabs:

**Tab 1 - Ingestion Service**:
```bash
RUST_LOG=info cargo run --release -p streaming-ingest
# Expected: "RTMP server listening on 0.0.0.0:1935"
```

**Tab 2 - Transcoding Service**:
```bash
RUST_LOG=info cargo run --release -p streaming-transcode
# Expected: "Kafka consumer listening on stream-frames topic"
```

**Tab 3 - Delivery Service**:
```bash
RUST_LOG=info cargo run --release -p streaming-delivery
# Expected: "Server running on http://0.0.0.0:8080"
```

**Tab 4 - Management API**:
```bash
RUST_LOG=info cargo run --release -p streaming-api
# Expected: "Management API listening on http://0.0.0.0:8081"
```

**Tab 5 - Tail Logs**:
```bash
docker-compose logs -f
```

---

## Part 2: Create a Test Stream (5 min)

### Step 1: Generate Streaming Key

```bash
# In another terminal, create a test user and streaming key
curl -X POST http://localhost:8081/stream-keys \
  -H "Content-Type: application/json" \
  -d '{
    "broadcaster_id": "test-broadcaster-001",
    "description": "OBS Home"
  }'

# Response:
{
  "key_id": "550e8400-e29b-41d4-a716-446655440000",
  "key_value": "rtmp://localhost:1935/live/test-key-abc123xyz",
  "is_active": true
}

# Save this URL for the next step
```

### Step 2: Start Broadcasting (OBS)

**Option A: Using OBS GUI**:
1. Open OBS Studio
2. Settings → Stream
3. Service: Custom...
4. Server: `rtmp://localhost:1935/live`
5. Stream Key: `test-key-abc123xyz` (from step 1)
6. Click "Start Streaming"

**Option B: Using FFmpeg CLI**:
```bash
ffmpeg -f lavfi -i testsrc=s=1920x1080:d=3600 \
  -f lavfi -i sine=f=1000:d=3600 \
  -c:v libx264 -preset fast -b:v 5M \
  -c:a aac -b:a 128k \
  -rtmp_live live \
  -f flv rtmp://localhost:1935/live/test-key-abc123xyz
```

**Verify Stream Started**:
```bash
# Check logs for:
# [streaming-ingest] RTMP connection established: stream_id=...
# [streaming-transcode] Started transcoding stream_id=...
```

---

## Part 3: Watch the Stream (3 min)

### Open in Browser

**Option A: HLS Playback (Recommended for most browsers)**

Open http://localhost:8080/viewer.html?stream=test-stream-001 (create this HTML file):

```html
<!DOCTYPE html>
<html>
<head>
  <script src="https://cdn.jsdelivr.net/npm/hls.js@latest"></script>
</head>
<body>
  <video id="video" controls autoplay style="width:100%"></video>
  <script>
    const video = document.getElementById('video');
    const src = new URLSearchParams(location.search).get('stream');
    const hls = new Hls();
    hls.loadSource(`http://localhost:8080/hls/${src}/index.m3u8`);
    hls.attachMedia(video);
    hls.on(Hls.Events.MANIFEST_PARSED, () => video.play());
  </script>
</body>
</html>
```

**Option B: DASH Playback**

Use dash.js library:
```html
<video id="video" controls style="width:100%"></video>
<script src="https://cdn.dashjs.org/latest/dash.all.min.js"></script>
<script>
  const video = document.getElementById('video');
  const dash = dashjs.MediaPlayer().create();
  dash.attachView(video);
  dash.attachSource('http://localhost:8080/dash/test-stream-001/manifest.mpd');
</script>
```

**Verify Playback**:
- Video appears within 3 seconds ✓
- Smooth playback (no stuttering) ✓
- Quality selector shows 480p, 720p, 1080p ✓

---

## Part 4: Test Real-Time Metrics (2 min)

### Connect WebSocket for Metrics

```javascript
// In browser console:
const ws = new WebSocket('ws://localhost:8080/ws/stream/test-stream-001');
ws.onmessage = (e) => {
  console.log('Metrics:', JSON.parse(e.data));
};
```

**Expected output every 1 second**:
```json
{
  "type": "metrics",
  "data": {
    "streamId": "test-stream-001",
    "concurrentViewers": 1,
    "ingressBitrateMbps": 5.2,
    "egressBitrateMbps": 5.2,
    "qualityDistribution": {"720p": 100},
    "droppedFrames": 0,
    "bufferingEvents": 0
  }
}
```

### Query Historical Metrics (REST API)

```bash
curl http://localhost:8081/metrics/test-stream-001?since=2025-10-20T00:00:00Z

# Response: Array of metrics records with 1-second granularity
[
  {
    "timestamp": "2025-10-20T12:30:01Z",
    "concurrentViewers": 1,
    "ingressBitrateMbps": 5.1,
    ...
  },
  ...
]
```

---

## Part 5: Test Quality Adaptation (3 min)

### Simulate Bandwidth Changes

**Using browser DevTools**:
1. Open DevTools (F12)
2. Network tab → Settings ⚙️
3. Select throttling profile: "Slow 3G"

**Expected Result**:
- Stream quality drops to 480p automatically
- WebSocket emits `quality_changed` event
- Console log shows: `[streaming-delivery] Quality adapted: 720p → 480p`

**Reset to Fast 3G**:
- Quality upgrades back to 720p within 2 seconds ✓

---

## Testing Checklist

Use this checklist to validate MVP readiness:

- [ ] **RTMP Ingestion**
  - [ ] OBS connects successfully to RTMP server
  - [ ] FFmpeg can stream to RTMP endpoint
  - [ ] Ingestion logs show "Connection established"
  - [ ] Stream transitions to ACTIVE state in DB

- [ ] **HLS Playback**
  - [ ] Master playlist (m3u8) downloads successfully
  - [ ] Quality variant playlists are valid
  - [ ] Segments (.ts files) are playable
  - [ ] Startup time <3 seconds

- [ ] **DASH Playback**
  - [ ] MPD manifest is valid XML
  - [ ] Segments (.m4s) are readable
  - [ ] Playback works in dash.js

- [ ] **Adaptive Bitrate**
  - [ ] Quality dropdown shows all 3 options (480p, 720p, 1080p)
  - [ ] Switching to different quality works immediately
  - [ ] No playback interruption during switch

- [ ] **Real-Time Metrics**
  - [ ] WebSocket connects without errors
  - [ ] Metrics update every 1-2 seconds
  - [ ] Concurrent viewer count accurate
  - [ ] Quality distribution shows correct percentages

- [ ] **Stream Lifecycle**
  - [ ] Stopping OBS closes stream gracefully
  - [ ] Stream status changes to ENDED_GRACEFULLY
  - [ ] All viewers are notified within 2 seconds
  - [ ] Historical metrics are queryable

- [ ] **Edge Cases**
  - [ ] Dropping OBS connection → Stream → ERROR → recovery works
  - [ ] Multiple concurrent viewers (simulate with multiple browsers/tabs)
  - [ ] Buffering events logged and visible in metrics
  - [ ] Viewer leave events recorded with session duration

---

## Performance Targets Validation

Run this performance test:

```bash
# Spin up 100 concurrent viewers (using curl + HLS.js in headless browsers)
for i in {1..100}; do
  chromium-browser --headless --disable-gpu \
    file:///$(pwd)/viewer.html?stream=test-stream-001 &
done

# Monitor metrics:
watch 'curl -s http://localhost:8081/metrics/test-stream-001 | jq .data | head -1'

# Expected:
# - concurrentViewers: 100
# - droppedFrames: 0
# - bufferingEvents: <5 (minimal)
# - playback continues smoothly
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| RTMP connection refused | Check port 1935 is open: `netstat -tlnp \| grep 1935` |
| "No segments available" | Verify transcoding service is running and consuming Kafka events |
| Video plays but buffers frequently | Reduce quality to 480p, increase Redis memory, check network |
| Metrics not updating | Check WebSocket connection: `ws.readyState` should be 1 (OPEN) |
| High CPU usage | Limit concurrent streams, reduce resolution, use FFmpeg hardware acceleration |
| Stream ends unexpectedly | Check logs for errors: `docker-compose logs streaming-ingest` |

---

## Next Steps

1. **Run Full Integration Test**:
   ```bash
   cargo test --release --all -- --test-threads=1
   ```

2. **Load Test** (100+ concurrent streams):
   ```bash
   cargo run --release -p streaming-load-test -- --streams 100 --duration 600
   ```

3. **Monitor Production Metrics**:
   - Prometheus scrape endpoint: http://localhost:9090/metrics
   - Grafana dashboard: http://localhost:3000 (admin/admin)

4. **Deploy to Kubernetes**:
   ```bash
   kubectl apply -f k8s/
   ```

---

**Status**: ✅ Ready to proceed with Phase 2 task generation

**Next Command**: `/speckit.tasks` to generate implementation tasks
