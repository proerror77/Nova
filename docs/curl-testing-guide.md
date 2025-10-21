# cURL Testing Guide for Nova Streaming API

## Overview

This guide provides practical cURL examples for testing the Nova Streaming API. cURL is a command-line tool for making HTTP requests, perfect for quickly testing API endpoints without writing code.

## Prerequisites

1. **cURL installed**: Already available on macOS/Linux. [Windows installation](https://curl.se/download.html)
2. **JWT Token**: Obtain from authentication service
3. **Stream ID**: UUID of active stream (use list active streams endpoint)
4. **jq (optional)**: Pretty-print JSON responses: `brew install jq`

## Setup

### Environment Variables

Create a `.env` file or export variables:

```bash
export NOVA_API_URL="https://api.nova-social.io/api/v1"
export NOVA_TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
export NOVA_STREAM_ID="550e8400-e29b-41d4-a716-446655440000"
```

Or use directly in cURL:

```bash
NOVA_API_URL="https://api.nova-social.io/api/v1"
NOVA_TOKEN="your-jwt-token-here"
NOVA_STREAM_ID="your-stream-uuid-here"
```

### Local Development

For local testing against `localhost:8081`:

```bash
export NOVA_API_URL="http://localhost:8081/api/v1"
```

## REST API Testing

### 1. Create a New Stream

**Endpoint**: `POST /streams`

```bash
curl -X POST "$NOVA_API_URL/streams" \
  -H "Authorization: Bearer $NOVA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "My Live Stream",
    "description": "Testing the Nova Streaming API",
    "region": "us-west-2",
    "tags": ["testing", "streaming"],
    "thumbnail_url": "https://example.com/thumb.jpg"
  }' | jq
```

**Expected Response**: 201 Created

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "broadcaster_id": "user-123",
  "title": "My Live Stream",
  "description": "Testing the Nova Streaming API",
  "status": "active",
  "region": "us-west-2",
  "rtmp_url": "rtmp://ingest.nova-social.io/live/stream-123",
  "rtmp_key": "stream-123",
  "viewer_count": 0,
  "peak_viewers": 0,
  "duration_seconds": 0,
  "created_at": "2025-10-21T10:30:45Z",
  "started_at": null,
  "ended_at": null,
  "hls_playlist_url": "https://cdn.nova-social.io/streams/stream-123/master.m3u8"
}
```

**Save Stream ID for Later**:

```bash
NOVA_STREAM_ID=$(curl -s -X POST "$NOVA_API_URL/streams" \
  -H "Authorization: Bearer $NOVA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title": "Test Stream", "description": ""}' | jq -r '.id')

echo "Stream ID: $NOVA_STREAM_ID"
```

---

### 2. Get Stream Details

**Endpoint**: `GET /streams/{stream_id}`

```bash
curl -X GET "$NOVA_API_URL/streams/$NOVA_STREAM_ID" \
  -H "Authorization: Bearer $NOVA_TOKEN" | jq
```

**Pretty Print Specific Fields**:

```bash
curl -s -X GET "$NOVA_API_URL/streams/$NOVA_STREAM_ID" \
  -H "Authorization: Bearer $NOVA_TOKEN" | jq '.{
    id,
    title,
    status,
    viewer_count,
    peak_viewers,
    duration_seconds
  }'
```

---

### 3. List Active Streams

**Endpoint**: `GET /streams/active`

```bash
curl -X GET "$NOVA_API_URL/streams/active" \
  -H "Authorization: Bearer $NOVA_TOKEN" | jq
```

**With Pagination**:

```bash
curl -X GET "$NOVA_API_URL/streams/active?limit=10&offset=0" \
  -H "Authorization: Bearer $NOVA_TOKEN" | jq '.streams[] | {id, title, viewer_count}'
```

**Filter by Region**:

```bash
curl -X GET "$NOVA_API_URL/streams/active?region=us-west-2" \
  -H "Authorization: Bearer $NOVA_TOKEN" | jq
```

---

### 4. End a Stream

**Endpoint**: `DELETE /streams/{stream_id}`

```bash
curl -X DELETE "$NOVA_API_URL/streams/$NOVA_STREAM_ID" \
  -H "Authorization: Bearer $NOVA_TOKEN" \
  -v
```

**Expected Response**: 204 No Content

---

### 5. Get Prometheus Metrics

**Endpoint**: `GET /metrics`

```bash
curl -X GET "$NOVA_API_URL/metrics" | head -50
```

**View Specific Metric**:

```bash
curl -s "$NOVA_API_URL/metrics" | grep nova_streaming_active_streams
```

**Export Metrics to File**:

```bash
curl -s "$NOVA_API_URL/metrics" > metrics.txt
```

---

## WebSocket Testing

### Connect to Stream WebSocket

**Using websocat** (install: `brew install websocat`):

```bash
websocat "wss://api.nova-social.io/api/v1/streams/$NOVA_STREAM_ID/ws?token=$NOVA_TOKEN"
```

Then type messages (JSON) and press Enter.

**Using curl with wscat**:

```bash
npx wscat -c "wss://api.nova-social.io/api/v1/streams/$NOVA_STREAM_ID/ws?token=$NOVA_TOKEN"
```

### Send WebSocket Messages Manually

```bash
# In websocat, send this JSON:
{"event": "get_stream_info", "data": {"request_id": "req-1"}}

# Press Enter to send
# Response:
# {"event": "stream_info", "data": {...}}
```

---

## Error Testing

### Test with Invalid Token

```bash
curl -X GET "$NOVA_API_URL/streams" \
  -H "Authorization: Bearer invalid-token" \
  -w "\nStatus: %{http_code}\n"
```

**Expected**: 401 Unauthorized

---

### Test with Missing Token

```bash
curl -X GET "$NOVA_API_URL/streams" \
  -w "\nStatus: %{http_code}\n"
```

**Expected**: 401 Unauthorized

---

### Test with Non-existent Stream

```bash
curl -X GET "$NOVA_API_URL/streams/00000000-0000-0000-0000-000000000000" \
  -H "Authorization: Bearer $NOVA_TOKEN" \
  -w "\nStatus: %{http_code}\n"
```

**Expected**: 404 Not Found

---

## Useful cURL Options

| Option | Purpose |
|--------|---------|
| `-X` | HTTP method (GET, POST, DELETE, etc.) |
| `-H` | Add header |
| `-d` | Request body (JSON) |
| `-v` | Verbose (shows request/response headers) |
| `-s` | Silent (no progress bar) |
| `-w "\nStatus: %{http_code}\n"` | Show HTTP status code |
| `-i` | Include response headers |
| `-o filename` | Save response to file |
| `-L` | Follow redirects |
| `--data-urlencode` | URL-encode form data |

---

## Advanced Examples

### Monitor Stream in Real-Time

```bash
#!/bin/bash
# watch-stream.sh - Monitor stream updates every 5 seconds

STREAM_ID=$1
TOKEN=$2

while true; do
  clear
  echo "=== Stream Status ==="
  echo "Updated at: $(date)"
  echo ""

  curl -s "http://localhost:8081/api/v1/streams/$STREAM_ID" \
    -H "Authorization: Bearer $TOKEN" | jq '.{
      title,
      status,
      viewer_count,
      peak_viewers,
      duration_seconds,
      quality: .metadata.quality,
      bitrate_kbps: .metadata.bitrate_kbps
    }'

  sleep 5
done
```

**Usage**:

```bash
bash watch-stream.sh $NOVA_STREAM_ID $NOVA_TOKEN
```

---

### Test Stream Creation & Metrics

```bash
#!/bin/bash
# test-stream-lifecycle.sh - Complete stream workflow test

API_URL="${NOVA_API_URL:-http://localhost:8081/api/v1}"
TOKEN=$1

if [ -z "$TOKEN" ]; then
  echo "Usage: $0 <jwt-token>"
  exit 1
fi

echo "1. Creating stream..."
RESPONSE=$(curl -s -X POST "$API_URL/streams" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Test Stream '$(date +%s)'",
    "description": "Automated test"
  }')

STREAM_ID=$(echo "$RESPONSE" | jq -r '.id')
RTMP_KEY=$(echo "$RESPONSE" | jq -r '.rtmp_key')

if [ "$STREAM_ID" = "null" ]; then
  echo "✗ Failed to create stream"
  echo "$RESPONSE" | jq
  exit 1
fi

echo "✓ Stream created: $STREAM_ID"
echo "  RTMP Key: $RTMP_KEY"

echo ""
echo "2. Getting stream details..."
curl -s -X GET "$API_URL/streams/$STREAM_ID" \
  -H "Authorization: Bearer $TOKEN" | jq '.{id, title, status, viewer_count}'

echo ""
echo "3. Getting metrics..."
curl -s "$API_URL/metrics" | grep nova_streaming_active_streams | head -3

echo ""
echo "4. Ending stream..."
curl -s -X DELETE "$API_URL/streams/$STREAM_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -w "Status: %{http_code}\n"

echo "✓ Test complete"
```

**Usage**:

```bash
bash test-stream-lifecycle.sh "$NOVA_TOKEN"
```

---

### Load Test - Create Multiple Streams

```bash
#!/bin/bash
# load-test.sh - Create N streams simultaneously

API_URL="${NOVA_API_URL:-http://localhost:8081/api/v1}"
TOKEN=$1
NUM_STREAMS=${2:-5}

echo "Creating $NUM_STREAMS streams..."

for i in $(seq 1 $NUM_STREAMS); do
  (
    curl -s -X POST "$API_URL/streams" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d "{
        \"title\": \"Load Test Stream $i\",
        \"description\": \"Load test $i of $NUM_STREAMS\"
      }" | jq -r '.id' > "/tmp/stream_$i.txt"

    echo "✓ Stream $i created: $(cat /tmp/stream_$i.txt)"
  ) &
done

wait
echo "All streams created"
```

---

### Parse Response and Use in Next Request

```bash
#!/bin/bash
# chain-requests.sh - Create stream and get metrics

TOKEN=$1
API_URL="http://localhost:8081/api/v1"

# Create stream and extract ID
echo "Creating stream..."
STREAM_ID=$(curl -s -X POST "$API_URL/streams" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title": "Test", "description": ""}' | jq -r '.id')

if [ "$STREAM_ID" != "null" ]; then
  echo "Stream ID: $STREAM_ID"

  # Wait a moment
  sleep 2

  # Get stream details
  echo "Stream details:"
  curl -s -X GET "$API_URL/streams/$STREAM_ID" \
    -H "Authorization: Bearer $TOKEN" | jq '.title, .status, .viewer_count'
else
  echo "Failed to create stream"
  exit 1
fi
```

---

## Troubleshooting

### "Command not found: curl"

Install cURL:
```bash
# macOS
brew install curl

# Ubuntu/Debian
sudo apt-get install curl

# Windows
# Download from https://curl.se/download.html
```

---

### "JSON parse error" from jq

Check if response is actually JSON:

```bash
curl -s "$NOVA_API_URL/metrics"  # Not JSON, this is prometheus format
curl -s "$NOVA_API_URL/streams" -H "Authorization: Bearer $TOKEN" | jq  # JSON
```

---

### SSL Certificate Errors

In development/self-signed certificates:

```bash
curl -k (insecure flag for https)  # or
curl --insecure
```

---

### Timeout Issues

Add timeout:

```bash
curl --connect-timeout 5 --max-time 10 "$NOVA_API_URL/streams"
```

---

## Performance Testing

### Measure Response Time

```bash
curl -w "\n\nTime stats:\n  Total: %{time_total}s\n  DNS: %{time_namelookup}s\n  Connect: %{time_connect}s\n  Transfer: %{time_starttransfer}s\n" \
  "$NOVA_API_URL/streams" \
  -H "Authorization: Bearer $NOVA_TOKEN"
```

---

### Concurrent Requests

```bash
# Test 100 concurrent requests
for i in {1..100}; do
  (curl -s "$NOVA_API_URL/metrics" > /dev/null &)
done
wait
echo "All requests completed"
```

---

## Security Considerations

### Never commit tokens to version control

```bash
# Bad: token in script
TOKEN="eyJ..." curl ...

# Good: use environment variables
TOKEN=$(cat ~/.nova_token)  # Read from secure file
```

### Rotate tokens regularly

```bash
# Update your token:
export NOVA_TOKEN="new-token-here"
```

---

## References

- [cURL Official Manual](https://curl.se/docs/manpage.html)
- [cURL Tutorial](https://curl.se/docs/manual.html)
- [jq Manual](https://stedolan.github.io/jq/manual/)
- [Nova Streaming API Docs](./openapi-streaming.yaml)
- [WebSocket Protocol](./websocket-protocol.md)
