# Feed Ranking API Documentation

**Version**: 1.0
**Last Updated**: 2025-10-18
**Service**: Nova User Service - Feed Ranking Module

---

## Overview

The Feed Ranking API provides personalized, real-time content feeds using a three-dimensional ranking algorithm (freshness + engagement + affinity). The system leverages ClickHouse for analytical queries, Redis for caching, and falls back to PostgreSQL for reliability.

**Key Features**:
- **Sub-150ms P95 latency** (cache hit)
- **Sub-800ms P95 latency** (ClickHouse query)
- **>95% deduplication accuracy**
- **<5s event-to-visible latency**
- **Circuit breaker** for automatic fallback

---

## Authentication

All endpoints require JWT authentication via the `Authorization` header:

```http
Authorization: Bearer <jwt_token>
```

**Error Response** (401 Unauthorized):
```json
{
  "error": "Unauthorized",
  "message": "Invalid or missing JWT token"
}
```

---

## Endpoints

### 1. Get Personalized Feed

**Endpoint**: `GET /api/v1/feed`

Retrieve a personalized feed ranked by the three-dimensional algorithm.

#### Query Parameters

| Parameter | Type   | Required | Default | Description                                    |
|-----------|--------|----------|---------|------------------------------------------------|
| `algo`    | string | No       | `ch`    | Algorithm: `ch` (ClickHouse) or `time` (fallback) |
| `limit`   | int    | No       | 50      | Number of posts (1-100)                        |
| `cursor`  | string | No       | -       | Pagination cursor (base64-encoded timestamp)   |

#### Response (200 OK)

```json
{
  "posts": [
    "550e8400-e29b-41d4-a716-446655440001",
    "550e8400-e29b-41d4-a716-446655440002"
  ],
  "cursor": "MTY5ODM3MjAwMA==",
  "has_more": true,
  "cache_hit": true,
  "algorithm": "ch",
  "latency_ms": 127
}
```

**Response Fields**:
- `posts`: Array of post UUIDs ranked by the algorithm
- `cursor`: Opaque pagination token (use for next request)
- `has_more`: Whether more posts are available
- `cache_hit`: Whether response came from Redis cache
- `algorithm`: Algorithm used (`ch` or `time`)
- `latency_ms`: Query execution time (excluding cache)

#### Error Responses

**400 Bad Request** (Invalid parameters):
```json
{
  "error": "BadRequest",
  "message": "limit must be between 1 and 100",
  "field": "limit"
}
```

**503 Service Unavailable** (ClickHouse + PostgreSQL down):
```json
{
  "error": "ServiceUnavailable",
  "message": "Feed service temporarily unavailable",
  "retry_after": 60
}
```

#### Example Request

```bash
# Get first page (50 posts)
curl -X GET \
  'https://api.nova.com/api/v1/feed?algo=ch&limit=50' \
  -H 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...'

# Get next page with cursor
curl -X GET \
  'https://api.nova.com/api/v1/feed?algo=ch&limit=50&cursor=MTY5ODM3MjAwMA==' \
  -H 'Authorization: Bearer <token>'

# Force fallback to PostgreSQL (for testing)
curl -X GET \
  'https://api.nova.com/api/v1/feed?algo=time&limit=20' \
  -H 'Authorization: Bearer <token>'
```

---

### 2. Get Trending Posts

**Endpoint**: `GET /api/v1/feed/trending`

Retrieve trending posts based on recent engagement metrics (generated every 10 minutes).

#### Query Parameters

| Parameter | Type   | Required | Default | Description                        |
|-----------|--------|----------|---------|------------------------------------|
| `window`  | string | No       | `1h`    | Time window: `1h`, `6h`, `24h`     |
| `limit`   | int    | No       | 200     | Number of trending posts (1-500)   |

#### Response (200 OK)

```json
{
  "posts": [
    {
      "post_id": "550e8400-e29b-41d4-a716-446655440010",
      "score": 127.5,
      "likes": 342,
      "comments": 89,
      "shares": 45,
      "impressions": 12450,
      "engagement_rate": 0.0382
    }
  ],
  "window": "1h",
  "generated_at": "2025-10-18T10:15:00Z",
  "total_posts": 200
}
```

**Response Fields**:
- `posts`: Array of trending posts with metrics
- `window`: Time window used for calculation
- `generated_at`: When trending data was last computed
- `total_posts`: Number of posts in response

#### Example Request

```bash
# Get 1-hour trending posts
curl -X GET \
  'https://api.nova.com/api/v1/feed/trending?window=1h&limit=50' \
  -H 'Authorization: Bearer <token>'

# Get daily trending posts
curl -X GET \
  'https://api.nova.com/api/v1/feed/trending?window=24h&limit=100' \
  -H 'Authorization: Bearer <token>'
```

---

### 3. Get Suggested Users

**Endpoint**: `GET /api/v1/discover/suggested-users`

Discover users to follow based on network analysis and content affinity.

#### Query Parameters

| Parameter | Type | Required | Default | Description                  |
|-----------|------|----------|---------|------------------------------|
| `limit`   | int  | No       | 20      | Number of users (1-100)      |

#### Response (200 OK)

```json
{
  "users": [
    {
      "user_id": "550e8400-e29b-41d4-a716-446655440020",
      "username": "alice_dev",
      "display_name": "Alice Johnson",
      "avatar_url": "https://cdn.nova.com/avatars/alice.jpg",
      "affinity_score": 0.85,
      "mutual_followers": 12,
      "common_interests": ["rust", "distributed-systems"]
    }
  ],
  "total_suggestions": 20,
  "generated_at": "2025-10-18T10:15:00Z"
}
```

**Response Fields**:
- `users`: Array of suggested users with affinity scores
- `total_suggestions`: Number of suggestions in response
- `generated_at`: When suggestions were last computed

#### Example Request

```bash
curl -X GET \
  'https://api.nova.com/api/v1/discover/suggested-users?limit=20' \
  -H 'Authorization: Bearer <token>'
```

---

### 4. Batch Event Ingestion

**Endpoint**: `POST /api/v1/events`

Ingest user interaction events for feed ranking (batch endpoint).

#### Request Body

```json
{
  "events": [
    {
      "event_id": "evt_550e8400_1698372000",
      "event_time": "2025-10-18T10:15:30Z",
      "user_id": "550e8400-e29b-41d4-a716-446655440001",
      "post_id": "550e8400-e29b-41d4-a716-446655440010",
      "author_id": "550e8400-e29b-41d4-a716-446655440020",
      "action": "like",
      "dwell_ms": 5000,
      "device": "ios",
      "app_ver": "1.2.3"
    }
  ]
}
```

**Event Fields**:
- `event_id`: Unique event identifier (use for idempotency)
- `event_time`: ISO8601 timestamp
- `user_id`: User performing action
- `post_id`: Post being interacted with
- `author_id`: Author of the post
- `action`: Event type: `like`, `comment`, `share`, `view`, `click`
- `dwell_ms`: Time spent on post (milliseconds)
- `device`: Device type: `ios`, `android`, `web`
- `app_ver`: Application version

#### Response (200 OK)

```json
{
  "received": 150,
  "deduped": 148,
  "rejected": 2,
  "latency_ms": 42
}
```

**Response Fields**:
- `received`: Total events received
- `deduped`: Events accepted (after deduplication)
- `rejected`: Events rejected (invalid/duplicate)
- `latency_ms`: Processing time

#### Error Response (400 Bad Request)

```json
{
  "error": "BadRequest",
  "message": "Invalid event format",
  "invalid_events": [
    {
      "event_id": "evt_invalid_123",
      "reason": "missing required field: post_id"
    }
  ]
}
```

#### Example Request

```bash
curl -X POST \
  'https://api.nova.com/api/v1/events' \
  -H 'Authorization: Bearer <token>' \
  -H 'Content-Type: application/json' \
  -d '{
    "events": [
      {
        "event_id": "evt_123_1698372000",
        "event_time": "2025-10-18T10:15:30Z",
        "user_id": "550e8400-e29b-41d4-a716-446655440001",
        "post_id": "550e8400-e29b-41d4-a716-446655440010",
        "author_id": "550e8400-e29b-41d4-a716-446655440020",
        "action": "like",
        "dwell_ms": 3200,
        "device": "ios",
        "app_ver": "1.2.3"
      }
    ]
  }'
```

---

### 5. Cache Invalidation (Admin)

**Endpoint**: `POST /api/v1/feed/invalidate`

Manually invalidate feed cache for specific users (admin only).

#### Request Body

```json
{
  "user_ids": [
    "550e8400-e29b-41d4-a716-446655440001"
  ],
  "scope": "feed"
}
```

**Fields**:
- `user_ids`: Array of user UUIDs to invalidate
- `scope`: Invalidation scope: `feed`, `trending`, `all`

#### Response (200 OK)

```json
{
  "invalidated": 1,
  "scope": "feed",
  "timestamp": "2025-10-18T10:20:00Z"
}
```

#### Example Request

```bash
curl -X POST \
  'https://api.nova.com/api/v1/feed/invalidate' \
  -H 'Authorization: Bearer <admin_token>' \
  -H 'Content-Type: application/json' \
  -d '{
    "user_ids": ["550e8400-e29b-41d4-a716-446655440001"],
    "scope": "feed"
  }'
```

---

## Rate Limiting

All endpoints are rate-limited to prevent abuse:

| Endpoint                   | Limit          | Window |
|----------------------------|----------------|--------|
| `GET /api/v1/feed`         | 60 requests    | 1 min  |
| `GET /api/v1/feed/trending`| 30 requests    | 1 min  |
| `GET /api/v1/discover/*`   | 20 requests    | 1 min  |
| `POST /api/v1/events`      | 100 requests   | 1 min  |

**Rate Limit Response** (429 Too Many Requests):
```json
{
  "error": "RateLimitExceeded",
  "message": "Too many requests",
  "retry_after": 42,
  "limit": 60,
  "window": "1m"
}
```

---

## Performance SLOs

| Metric                        | Target          | Measurement          |
|-------------------------------|-----------------|----------------------|
| Feed P95 latency (cache hit)  | ≤150ms          | End-to-end           |
| Feed P95 latency (cache miss) | ≤800ms          | ClickHouse query     |
| Event-to-visible latency      | ≤5s             | End-to-end pipeline  |
| Deduplication accuracy        | ≥95%            | Event consumer       |
| Cache hit rate                | ≥80%            | Redis cache          |
| Availability                  | ≥99.5%          | Uptime (monthly)     |

---

## Error Codes Reference

| Code | Error                | Meaning                                  |
|------|----------------------|------------------------------------------|
| 400  | BadRequest           | Invalid parameters or request format     |
| 401  | Unauthorized         | Missing or invalid JWT token             |
| 403  | Forbidden            | Insufficient permissions (admin only)    |
| 404  | NotFound             | Resource not found                       |
| 429  | RateLimitExceeded    | Too many requests                        |
| 500  | InternalServerError  | Unexpected server error                  |
| 503  | ServiceUnavailable   | Feed service temporarily down            |

---

## Monitoring & Observability

All API calls are instrumented with Prometheus metrics:

**Metrics Exported**:
- `feed_requests_total{endpoint, status, algorithm}` - Request count
- `feed_latency_seconds{endpoint, algorithm}` - Latency histogram
- `feed_cache_hit_rate{algorithm}` - Cache effectiveness
- `events_ingested_total{status}` - Event ingestion count
- `events_deduped_total` - Deduplication effectiveness

**Tracing**:
- All requests include `X-Request-ID` header for distributed tracing
- OpenTelemetry spans exported to monitoring system

---

## Client Integration Examples

### JavaScript/TypeScript (Fetch API)

```typescript
async function getPersonalizedFeed(token: string, limit = 50, cursor?: string) {
  const params = new URLSearchParams({
    algo: 'ch',
    limit: limit.toString()
  });
  if (cursor) params.append('cursor', cursor);

  const response = await fetch(`https://api.nova.com/api/v1/feed?${params}`, {
    headers: {
      'Authorization': `Bearer ${token}`,
      'Accept': 'application/json'
    }
  });

  if (!response.ok) {
    throw new Error(`Feed API error: ${response.status}`);
  }

  return await response.json();
}
```

### Python (requests)

```python
import requests

def get_personalized_feed(token, limit=50, cursor=None):
    params = {'algo': 'ch', 'limit': limit}
    if cursor:
        params['cursor'] = cursor

    response = requests.get(
        'https://api.nova.com/api/v1/feed',
        headers={'Authorization': f'Bearer {token}'},
        params=params
    )
    response.raise_for_status()
    return response.json()
```

### Swift (iOS)

```swift
func getPersonalizedFeed(token: String, limit: Int = 50, cursor: String? = nil) async throws -> FeedResponse {
    var components = URLComponents(string: "https://api.nova.com/api/v1/feed")!
    components.queryItems = [
        URLQueryItem(name: "algo", value: "ch"),
        URLQueryItem(name: "limit", value: "\(limit)")
    ]
    if let cursor = cursor {
        components.queryItems?.append(URLQueryItem(name: "cursor", value: cursor))
    }

    var request = URLRequest(url: components.url!)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    let (data, _) = try await URLSession.shared.data(for: request)
    return try JSONDecoder().decode(FeedResponse.self, from: data)
}
```

---

## Changelog

### v1.0 (2025-10-18)
- Initial API release
- Three-dimensional ranking algorithm (freshness + engagement + affinity)
- Circuit breaker fallback to PostgreSQL
- Event batch ingestion
- Cache invalidation endpoint

---

## Support

For API support or issues:
- Documentation: https://docs.nova.com/api
- GitHub Issues: https://github.com/nova/backend/issues
- Slack: #feed-ranking-support
