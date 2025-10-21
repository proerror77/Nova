# WebSocket Protocol Documentation

## Overview

The Nova Streaming WebSocket protocol provides real-time, bidirectional communication between the Nova server and streaming viewers. Viewers connect to receive live updates about stream state, viewer counts, quality changes, and other streaming events.

## Connection Details

### Endpoint

```
WebSocket URL: ws[s]://api.nova-social.io/api/v1/streams/{stream_id}/ws
Query Parameters:
  - token: JWT authentication token (required)
  - protocol: Protocol version (optional, default: 1.0)
```

### Example Connection

```javascript
// JavaScript client
const streamId = "550e8400-e29b-41d4-a716-446655440000";
const token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...";
const ws = new WebSocket(
  `wss://api.nova-social.io/api/v1/streams/${streamId}/ws?token=${token}`
);

ws.onopen = () => console.log("Connected");
ws.onmessage = (event) => handleMessage(JSON.parse(event.data));
ws.onerror = (error) => console.error("Error:", error);
ws.onclose = () => console.log("Disconnected");
```

## Message Format

All WebSocket messages are JSON objects with the following structure:

```json
{
  "event": "<event_type>",
  "data": {
    // Event-specific data
  }
}
```

## Message Types

### 1. Initial Connection Messages

#### Server → Client: `connection_established`

Sent immediately after WebSocket upgrade succeeds.

```json
{
  "event": "connection_established",
  "data": {
    "stream_id": "550e8400-e29b-41d4-a716-446655440000",
    "viewer_id": "a1b2c3d4-e5f6-g7h8-i9j0-k1l2m3n4o5p6",
    "session_id": "session_abc123xyz",
    "protocol_version": "1.0",
    "timestamp": "2025-10-21T10:30:45.123Z"
  }
}
```

**Fields:**
- `stream_id`: UUID of the stream being watched
- `viewer_id`: UUID of the viewer
- `session_id`: Unique WebSocket session identifier
- `protocol_version`: WebSocket protocol version
- `timestamp`: Server timestamp when connection established

---

### 2. Stream State Messages

#### Server → Client: `stream_started`

Sent when a stream begins broadcasting.

```json
{
  "event": "stream_started",
  "data": {
    "stream_id": "550e8400-e29b-41d4-a716-446655440000",
    "broadcaster_id": "user-123",
    "title": "Live Gaming Session",
    "description": "Playing competitive games with viewers",
    "quality": "1080p",
    "fps": 60,
    "bitrate_kbps": 5000,
    "timestamp": "2025-10-21T10:30:45.123Z"
  }
}
```

**Fields:**
- `stream_id`: UUID of the stream
- `broadcaster_id`: ID of the broadcaster
- `title`: Stream title
- `description`: Stream description
- `quality`: Initial stream quality
- `fps`: Frames per second
- `bitrate_kbps`: Initial bitrate in kilobits per second
- `timestamp`: Stream start timestamp

---

#### Server → Client: `stream_ended`

Sent when a stream ends broadcasting.

```json
{
  "event": "stream_ended",
  "data": {
    "stream_id": "550e8400-e29b-41d4-a716-446655440000",
    "duration_seconds": 3600,
    "peak_viewers": 1500,
    "final_viewer_count": 250,
    "reason": "broadcaster_ended",
    "timestamp": "2025-10-21T11:30:45.123Z"
  }
}
```

**Fields:**
- `stream_id`: UUID of the stream
- `duration_seconds`: How long the stream was active
- `peak_viewers`: Maximum concurrent viewers reached
- `final_viewer_count`: Viewers still connected when stream ended
- `reason`: Why stream ended:
  - `broadcaster_ended`: Broadcaster manually ended stream
  - `connection_lost`: RTMP connection dropped
  - `session_timeout`: Idle timeout
  - `error`: Stream ended due to error
- `timestamp`: Stream end timestamp

**Client Action**: WebSocket typically closes after this message.

---

### 3. Viewer Count Messages

#### Server → Client: `viewer_count_changed`

Sent whenever the viewer count for the stream changes.

```json
{
  "event": "viewer_count_changed",
  "data": {
    "stream_id": "550e8400-e29b-41d4-a716-446655440000",
    "viewer_count": 1250,
    "peak_viewers": 1500,
    "change": 5,
    "timestamp": "2025-10-21T10:35:20.456Z"
  }
}
```

**Fields:**
- `stream_id`: UUID of the stream
- `viewer_count`: Current number of connected viewers
- `peak_viewers`: Highest viewer count reached this session
- `change`: Number of viewers added (positive) or removed (negative)
- `timestamp`: When the change occurred

**Frequency**: Sent after each viewer join/leave (typically 10-100ms delay for batching)

---

### 4. Quality and Bitrate Messages

#### Server → Client: `quality_changed`

Sent when the broadcaster changes stream quality or encoder switches quality.

```json
{
  "event": "quality_changed",
  "data": {
    "stream_id": "550e8400-e29b-41d4-a716-446655440000",
    "previous_quality": "1080p",
    "new_quality": "720p",
    "previous_bitrate_kbps": 5000,
    "new_bitrate_kbps": 3000,
    "fps": 60,
    "reason": "adaptive_bitrate",
    "timestamp": "2025-10-21T10:40:15.789Z"
  }
}
```

**Fields:**
- `stream_id`: UUID of the stream
- `previous_quality`: Former quality level
- `new_quality`: New quality level (720p, 1080p, 4k, auto)
- `previous_bitrate_kbps`: Former bitrate
- `new_bitrate_kbps`: New bitrate in kbps
- `fps`: Frames per second
- `reason`: Reason for change:
  - `adaptive_bitrate`: Server adaptation based on network
  - `broadcaster_changed`: Broadcaster manually changed
  - `network_congestion`: Network issue detected
  - `quality_degradation`: Temporary network issue
- `timestamp`: When quality changed

---

#### Server → Client: `bitrate_update`

Sent periodically to report current bitrate (optional, for statistics).

```json
{
  "event": "bitrate_update",
  "data": {
    "stream_id": "550e8400-e29b-41d4-a716-446655440000",
    "current_bitrate_kbps": 4850,
    "quality": "1080p",
    "health": "good",
    "timestamp": "2025-10-21T10:40:30.000Z"
  }
}
```

**Fields:**
- `current_bitrate_kbps`: Current bitrate measurement
- `quality`: Current quality setting
- `health`: Stream health status:
  - `excellent`: > 90% of max bitrate
  - `good`: 70-90% of max bitrate
  - `fair`: 50-70% of max bitrate
  - `poor`: < 50% of max bitrate
- `timestamp`: Measurement timestamp

**Frequency**: Every 5-10 seconds (optional)

---

### 5. Error Messages

#### Server → Client: `error`

Sent when an error occurs during streaming.

```json
{
  "event": "error",
  "data": {
    "error_code": "RTMP_CONNECTION_LOST",
    "error_message": "RTMP broadcaster connection lost",
    "severity": "critical",
    "recoverable": false,
    "suggested_action": "Refresh page or try again later",
    "timestamp": "2025-10-21T10:45:12.345Z"
  }
}
```

**Fields:**
- `error_code`: Machine-readable error code
- `error_message`: Human-readable error description
- `severity`: Error severity:
  - `info`: Informational only
  - `warning`: Warning, may affect experience
  - `error`: Error, stream may be unavailable
  - `critical`: Critical error, stream unavailable
- `recoverable`: Whether viewer can recover without reconnecting
- `suggested_action`: Recommended action for viewer
- `timestamp`: When error occurred

**Common Error Codes:**
```
STREAM_NOT_FOUND           - Stream doesn't exist
STREAM_ENDED               - Stream has ended
CONNECTION_REJECTED        - Invalid token or permissions
PROTOCOL_ERROR             - Malformed message or invalid state
SERVER_ERROR               - Internal server error
RTMP_CONNECTION_LOST       - Broadcaster connection dropped
RTMP_HANDSHAKE_FAILED      - RTMP protocol error
BUFFER_OVERFLOW            - Ingestion buffer overflow
UNAUTHORIZED               - Not authorized to watch
RATE_LIMITED               - Too many requests
```

---

### 6. Heartbeat/Keepalive

#### Server → Client: `ping`

Sent periodically to keep connection alive and detect dead connections.

```json
{
  "event": "ping",
  "data": {
    "sequence": 42,
    "timestamp": "2025-10-21T10:50:00.000Z"
  }
}
```

**Fields:**
- `sequence`: Message sequence number
- `timestamp`: Server time

**Client Response**: Should respond with `pong` message (see below)

**Frequency**: Every 30 seconds

---

#### Client → Server: `pong`

Client response to `ping` message.

```json
{
  "event": "pong",
  "data": {
    "sequence": 42,
    "timestamp": "2025-10-21T10:50:00.500Z"
  }
}
```

**Fields:**
- `sequence`: Echo of received ping sequence number
- `timestamp`: Client timestamp (for latency calculation)

**Server Uses**: To detect dead connections, calculate latency to viewer

---

### 7. Client-Initiated Messages

#### Client → Server: `get_stream_info`

Client requests current stream information.

```json
{
  "event": "get_stream_info",
  "data": {
    "request_id": "req-12345"
  }
}
```

**Server Response**:
```json
{
  "event": "stream_info",
  "data": {
    "request_id": "req-12345",
    "stream_id": "550e8400-e29b-41d4-a716-446655440000",
    "status": "active",
    "viewer_count": 1250,
    "peak_viewers": 1500,
    "quality": "1080p",
    "bitrate_kbps": 5000,
    "fps": 60,
    "duration_seconds": 3600,
    "broadcaster_name": "Streamer123",
    "timestamp": "2025-10-21T10:55:00.000Z"
  }
}
```

---

#### Client → Server: `report_issue`

Client reports a playback issue.

```json
{
  "event": "report_issue",
  "data": {
    "issue_type": "buffering|lag|quality|playback_error|other",
    "severity": "low|medium|high",
    "description": "Stream is constantly buffering",
    "client_info": {
      "player": "video.js",
      "browser": "Chrome 120",
      "os": "macOS 14.1",
      "network": "wifi",
      "bandwidth_estimate_kbps": 8000
    }
  }
}
```

**Server Logging**: Issues logged for quality monitoring and diagnostics

---

## Connection Lifecycle

```
┌─ Client initiates connection ─┐
│                               │
↓                               │
WebSocket Upgrade               │
↓                               │
Server accepts, validates token │
↓                               │
connection_established ────────→
↓
stream_started (if active)──────→
↓
Real-time events:              ↔
  - viewer_count_changed
  - quality_changed
  - bitrate_update
  - ping/pong
  - error (if occurs)
↓
stream_ended ─────────────────→
↓
Connection closes
```

## Error Handling

### Connection Refused

**Causes:**
- Invalid token
- Stream ID doesn't exist
- Viewer not authorized
- Server at capacity

**Response:** HTTP 401/403/404, connection closes

### Message Parsing Error

**Causes:**
- Invalid JSON
- Missing required fields
- Unknown event type

**Response:** Server closes connection with code 1003 (unsupported data)

### Timeout

**Default:** 60 seconds of inactivity (no ping/pong exchange)

**Recovery:** Client reconnects, server assigns new session ID

## Message Ordering Guarantees

- **Messages from server**: Guaranteed in-order delivery (TCP ordering)
- **Quick successive events**: May be batched into single frame
- **Timestamps**: Server-generated, use for ordering if needed

## Connection Parameters

| Parameter | Default | Configurable |
|-----------|---------|--------------|
| Ping Interval | 30s | No |
| Ping Timeout | 10s | No |
| Idle Timeout | 60s | No |
| Max Message Size | 256 KB | No |
| Backlog Buffer | 100 messages | No |

## Client Implementation Example

### JavaScript (Vanilla)

```javascript
class NovaStreamViewer {
  constructor(streamId, token) {
    this.streamId = streamId;
    this.token = token;
    this.messageHandlers = {};
  }

  connect() {
    const url = `wss://api.nova-social.io/api/v1/streams/${this.streamId}/ws`;
    const fullUrl = new URL(url);
    fullUrl.searchParams.append('token', this.token);

    this.ws = new WebSocket(fullUrl.toString());

    this.ws.addEventListener('open', () => this.onOpen());
    this.ws.addEventListener('message', (e) => this.onMessage(e));
    this.ws.addEventListener('error', (e) => this.onError(e));
    this.ws.addEventListener('close', () => this.onClose());
  }

  onOpen() {
    console.log('Connected to stream');
    this.setupPingInterval();
  }

  onMessage(event) {
    const message = JSON.parse(event.data);
    const handler = this.messageHandlers[message.event];
    if (handler) {
      handler(message.data);
    }
  }

  onError(error) {
    console.error('WebSocket error:', error);
  }

  onClose() {
    console.log('Disconnected from stream');
    clearInterval(this.pingInterval);
  }

  setupPingInterval() {
    this.pingInterval = setInterval(() => {
      if (this.ws.readyState === WebSocket.OPEN) {
        this.ws.send(JSON.stringify({
          event: 'pong',
          data: { timestamp: new Date().toISOString() }
        }));
      }
    }, 30000);
  }

  on(event, callback) {
    this.messageHandlers[event] = callback;
  }

  send(message) {
    if (this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(message));
    }
  }

  disconnect() {
    if (this.ws) {
      this.ws.close();
    }
  }
}

// Usage
const viewer = new NovaStreamViewer(streamId, token);
viewer.on('connection_established', (data) => {
  console.log('Connected as viewer:', data.viewer_id);
});
viewer.on('viewer_count_changed', (data) => {
  console.log('Viewers:', data.viewer_count);
});
viewer.on('stream_ended', (data) => {
  console.log('Stream ended after', data.duration_seconds, 'seconds');
});
viewer.connect();
```

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Connection refused | Invalid token | Get new token, check expiration |
| Stream not found | Wrong stream ID | Verify stream ID format |
| Constant disconnects | Network issues | Check bandwidth, reduce quality |
| No ping responses | Network lag | May indicate slow connection |
| Messages out of order | Client-side buffering | Check WebSocket handling |

## Performance Optimization

### Message Batching
- Multiple `viewer_count_changed` events batched into single message
- Reduces message overhead under high viewer churn

### Message Size Limits
- Individual messages limited to 256 KB
- Prevents memory exhaustion attacks

### Backpressure Handling
- Server maintains queue of up to 100 pending messages per client
- Older messages dropped if client falls behind
- Client notified if messages were dropped

