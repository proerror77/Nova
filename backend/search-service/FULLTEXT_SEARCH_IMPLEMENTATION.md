# Full-Text Search and Redis Cache Implementation

## Overview

This document describes the implementation of PostgreSQL full-text search and Redis caching for the search service.

## Architecture Changes

### 1. Dependencies Added

- `redis = { version = "0.26", features = ["tokio-comp", "connection-manager"] }`

### 2. Core Components

#### PostgreSQL Full-Text Search

The `search_posts()` function now uses PostgreSQL's `tsvector` and `tsquery` for full-text search:

```sql
SELECT id, user_id, caption, created_at
FROM posts
WHERE to_tsvector('english', COALESCE(caption, '')) @@
      plainto_tsquery('english', $1)
  AND soft_delete IS NULL
  AND status = 'published'
ORDER BY ts_rank(to_tsvector('english', COALESCE(caption, '')),
                 plainto_tsquery('english', $1)) DESC,
         created_at DESC
LIMIT $2
```

**Benefits:**
- Relevance ranking via `ts_rank()`
- Better linguistic matching (stemming, stop words)
- More accurate search results than ILIKE

#### Redis Cache Layer

- **Cache Key Format**: `search:posts:{query}`
- **TTL**: 24 hours (86400 seconds)
- **Storage Format**: JSON-serialized `Vec<PostResult>`

**Cache Flow:**
1. Check Redis cache for query
2. If cache hit: return cached results
3. If cache miss: query database → store in cache → return results

**Graceful Degradation:**
- If Redis GET fails, service falls back to database query
- If Redis SET fails, query still succeeds (cache update fails silently)

### 3. New Endpoint

**POST /api/v1/search/clear-cache**

Clears all cached search results using Redis SCAN pattern matching.

```bash
curl -X POST http://localhost:8081/api/v1/search/clear-cache
```

Response:
```json
{
  "message": "Search cache cleared",
  "deleted_count": 42
}
```

## Configuration

### Environment Variables

Add to `.env`:

```bash
REDIS_URL=redis://127.0.0.1:6379
```

Defaults to `redis://127.0.0.1:6379` if not set.

## Testing

### Prerequisites

1. PostgreSQL with posts table
2. Redis server running on port 6379

### Test Scenarios

#### 1. Full-Text Search Accuracy

```bash
# Search for posts with "awesome photo"
curl "http://localhost:8081/api/v1/search/posts?q=awesome+photo&limit=10"
```

Expected: Posts containing "awesome", "photo", or variations ranked by relevance.

#### 2. Cache Hit/Miss

```bash
# First request (cache miss)
time curl "http://localhost:8081/api/v1/search/posts?q=test"

# Second request (cache hit)
time curl "http://localhost:8081/api/v1/search/posts?q=test"
```

Expected: Second request significantly faster.

Check logs for:
```
Cache miss for query: test
Cache hit for query: test
```

#### 3. Cache Clearing

```bash
# Create cache entries
curl "http://localhost:8081/api/v1/search/posts?q=test1"
curl "http://localhost:8081/api/v1/search/posts?q=test2"

# Clear cache
curl -X POST http://localhost:8081/api/v1/search/clear-cache

# Verify cache cleared
curl "http://localhost:8081/api/v1/search/posts?q=test1"  # Should log "Cache miss"
```

#### 4. Redis Connection Failure

```bash
# Stop Redis
redis-cli shutdown

# Query should still work (fallback to database)
curl "http://localhost:8081/api/v1/search/posts?q=test"
```

Expected: Query succeeds, no cache operations.

## Performance Expectations

### Before (ILIKE)
- Sequential scan of posts table
- No relevance ranking
- ~100-500ms for medium datasets

### After (Full-Text + Cache)
- First request: ~50-200ms (full-text search)
- Cached requests: ~5-20ms (Redis)
- Better relevance ranking

## Database Indexes (Recommended)

For optimal performance, create GIN index on posts.caption:

```sql
CREATE INDEX idx_posts_caption_fts ON posts USING GIN(to_tsvector('english', COALESCE(caption, '')));
```

This eliminates the need to compute `to_tsvector()` on every query.

## Monitoring

### Key Metrics

- **Cache Hit Rate**: `cache_hits / (cache_hits + cache_misses)`
- **Search Latency**: p50, p95, p99 response times
- **Redis Connection Health**: Connection errors, timeouts

### Logs

```bash
# Monitor cache behavior
grep -E "Cache (hit|miss)" search-service.log

# Monitor Redis connection
grep "Redis connection" search-service.log
```

## Limitations

1. **Cache Invalidation**: Currently no automatic cache invalidation when posts are updated/deleted
2. **Cache Key Size**: Very long queries may exceed Redis key size limits
3. **Language Support**: Currently hardcoded to English full-text search
4. **Memory Usage**: Cache can grow unbounded (consider MAXMEMORY policy)

## Future Improvements

1. **Automatic Cache Invalidation**: Invalidate cache when posts are updated
2. **Multi-language Support**: Detect language and use appropriate text search configuration
3. **Cache Compression**: Compress cached JSON for large result sets
4. **Cache Analytics**: Track hit rates, popular queries
5. **Query Normalization**: Normalize queries (lowercase, trim) before caching
6. **Pagination Cache**: Cache individual pages rather than full result sets
