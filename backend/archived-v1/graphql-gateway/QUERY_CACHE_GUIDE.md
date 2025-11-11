# GraphQL Query Cache Integration Guide

**Quick Win #5**: In-memory L1 cache for GraphQL responses

## Overview

The `GraphqlQueryCache` provides **process-local in-memory caching** for GraphQL query responses to reduce downstream load on ClickHouse and other data sources.

### Architecture

```
┌─────────────────┐
│ GraphQL Request │
└────────┬────────┘
         ▼
┌─────────────────────────────────┐
│ L1: GraphqlQueryCache           │
│ - In-memory (nanosecond)        │
│ - TTL-based expiration          │
│ - Pattern-based invalidation    │
└────────┬────────────────────────┘
         │ (on miss)
         ▼
┌─────────────────────────────────┐
│ L2: Redis (existing)            │
│ - Distributed (millisecond)     │
│ - Cross-instance sharing        │
└────────┬────────────────────────┘
         │ (on miss)
         ▼
┌─────────────────────────────────┐
│ Data Source (ClickHouse, etc)   │
└─────────────────────────────────┘
```

## Usage

### 1. Initialize Cache

```rust
use std::sync::Arc;
use crate::cache::{GraphqlQueryCache, CachePolicy};

// In main() or startup
let query_cache = Arc::new(GraphqlQueryCache::new());  // Default: 100MB, 10k entries

// OR with custom limits
let query_cache = Arc::new(GraphqlQueryCache::with_limits(
    50 * 1024 * 1024,  // 50MB
    5000,              // 5000 entries
));

// Share with GraphQL context
let schema = Schema::build(QueryRoot, MutationRoot, SubscriptionRoot)
    .data(query_cache.clone())
    .finish();
```

### 2. Cache GraphQL Queries

#### Basic Pattern

```rust
use bytes::Bytes;
use crate::cache::{CachePolicy, QueryHash};

async fn resolve_user_profile(
    ctx: &Context<'_>,
    user_id: String,
) -> Result<UserProfile> {
    let cache = ctx.data::<Arc<GraphqlQueryCache>>()?;

    // Generate unique cache key (query + variables)
    let query_hash = format!("user:profile:{}", user_id);

    // Get from cache or execute
    let result = cache.get_or_execute(
        query_hash,
        CachePolicy::PUBLIC,  // 30s TTL
        || async {
            // Execute actual query (only on cache miss)
            let profile = fetch_from_clickhouse(&user_id).await?;
            let json = serde_json::to_vec(&profile)?;
            Ok(Bytes::from(json))
        }
    ).await?;

    // Deserialize cached result
    let profile = serde_json::from_slice(&result)?;
    Ok(profile)
}
```

#### With Different Policies

```rust
// Public content: 30s TTL
CachePolicy::PUBLIC

// User-specific data: 5s TTL (more dynamic)
CachePolicy::USER_DATA

// Search results: 60s TTL (less volatile)
CachePolicy::SEARCH

// Real-time data: No cache
CachePolicy::NO_CACHE
```

### 3. Invalidate on Mutations

```rust
async fn update_user_profile(
    ctx: &Context<'_>,
    user_id: String,
    updates: UserProfileInput,
) -> Result<UserProfile> {
    let cache = ctx.data::<Arc<GraphqlQueryCache>>()?;

    // Perform update
    let updated_profile = update_in_database(&user_id, updates).await?;

    // Invalidate all related cache entries
    cache.invalidate_by_pattern(&format!("user:{}:*", user_id)).await;

    Ok(updated_profile)
}
```

#### Invalidation Patterns

| Pattern | Invalidates | Use Case |
|---------|-------------|----------|
| `user:123:*` | All queries for user 123 | User profile update |
| `post:456:*` | All queries for post 456 | Post update/delete |
| `feed:*` | All feed queries | New post created |
| `search:*` | All search results | Content changed |

### 4. Monitor Performance

```rust
// Expose metrics endpoint
async fn cache_metrics(ctx: &Context<'_>) -> Result<CacheMetrics> {
    let cache = ctx.data::<Arc<GraphqlQueryCache>>()?;
    let stats = cache.stats();

    Ok(CacheMetrics {
        entries: stats.entries,
        size_mb: stats.size_bytes / (1024 * 1024),
        hit_rate: stats.hit_rate(),
        memory_utilization: stats.memory_utilization(),
    })
}
```

#### Prometheus Metrics (Auto-Exposed)

- `graphql_query_cache_hit_total` - Cache hits
- `graphql_query_cache_miss_total` - Cache misses
- `graphql_query_cache_eviction_total` - Entries evicted (TTL or memory limit)
- `graphql_query_cache_invalidation_total` - Manual invalidations

## Best Practices

### Cache Key Design

```rust
// ✅ GOOD: Structured, predictable keys
format!("user:{}:profile", user_id)
format!("post:{}:comments:page:{}", post_id, page)
format!("search:{}:page:{}", md5_hash(query), page)

// ❌ BAD: Unstructured, hard to invalidate
format!("{}", uuid::Uuid::new_v4())
format!("cache_{}", random_string())
```

### TTL Selection

| Query Type | Recommended TTL | Reasoning |
|------------|-----------------|-----------|
| Public profiles | 30s | Updated infrequently, safe to cache |
| User feed | 5s | Personalized, changes frequently |
| Search results | 60s | Expensive to compute, acceptable staleness |
| Notifications | 0s (no cache) | Real-time requirement |
| Static content | 300s (5min) | Rarely changes |

### Memory Management

```rust
// Default limits are conservative
GraphqlQueryCache::new()  // 100MB, 10k entries

// For high-traffic services, increase limits
GraphqlQueryCache::with_limits(
    500 * 1024 * 1024,  // 500MB
    50_000,             // 50k entries
)

// For low-memory environments, decrease limits
GraphqlQueryCache::with_limits(
    10 * 1024 * 1024,   // 10MB
    1_000,              // 1k entries
)
```

### Invalidation Strategy

```rust
// Mutation handler example
async fn create_post(ctx: &Context<'_>, input: CreatePostInput) -> Result<Post> {
    let cache = ctx.data::<Arc<GraphqlQueryCache>>()?;

    // 1. Create post
    let post = insert_into_db(input).await?;

    // 2. Invalidate affected caches
    cache.invalidate_by_pattern(&format!("user:{}:posts", post.author_id)).await;
    cache.invalidate_by_pattern("feed:*").await;  // All feeds

    // 3. Return result
    Ok(post)
}
```

## Performance Expectations

Based on Quick Win #5 goals:

| Metric | Target | Measurement |
|--------|--------|-------------|
| Cache hit rate | >60% | `stats.hit_rate()` |
| Downstream load reduction | -30-40% | Database query logs |
| P50 latency reduction | -50% | Request tracing |
| Memory overhead | <100MB | `stats.size_bytes` |

### Example Performance Gains

```
Before:
  - User profile query: 50ms (ClickHouse)
  - Feed query: 150ms (ClickHouse + aggregation)

After (with L1 cache):
  - User profile query: 25ms (50% reduction) - Cache hit
  - Feed query: 75ms (50% reduction) - Cache hit
  - Cache miss overhead: <1ms (negligible)
```

## Troubleshooting

### High Memory Usage

```rust
let stats = cache.stats();
if stats.memory_utilization() > 90.0 {
    warn!("L1 cache memory usage high: {:.1}%", stats.memory_utilization());
    // Cache will auto-evict, but consider increasing max_size_bytes
}
```

### Low Hit Rate

```rust
let stats = cache.stats();
if stats.hit_rate() < 30.0 {
    warn!("L1 cache hit rate low: {:.1}%", stats.hit_rate());
    // Possible causes:
    // - TTL too short (queries expire before reuse)
    // - Cache keys not consistent (different hash for same query)
    // - Too many unique queries (increase max_entries)
}
```

### Stale Data Issues

```rust
// If users report stale data:
// 1. Check invalidation logic in mutations
// 2. Reduce TTL for affected query types
// 3. Add explicit invalidation triggers

// Temporary fix: clear entire cache
cache.clear();
```

## Testing

### Unit Tests

```rust
#[tokio::test]
async fn test_resolver_with_cache() {
    let cache = Arc::new(GraphqlQueryCache::new());

    // First call: miss
    let result1 = resolve_user_profile(&cache, "user123").await.unwrap();

    // Second call: hit (verified by metrics)
    let result2 = resolve_user_profile(&cache, "user123").await.unwrap();

    assert_eq!(result1, result2);
    assert!(cache.stats().hit_count > 0);
}
```

### Integration Tests

```rust
#[tokio::test]
async fn test_invalidation_on_update() {
    let cache = Arc::new(GraphqlQueryCache::new());

    // Cache user profile
    let profile1 = resolve_user_profile(&cache, "user123").await.unwrap();

    // Update user
    update_user_profile(&cache, "user123", updates).await.unwrap();

    // Should fetch fresh data (cache invalidated)
    let profile2 = resolve_user_profile(&cache, "user123").await.unwrap();

    assert_ne!(profile1.updated_at, profile2.updated_at);
}
```

## Migration Path

### Phase 1: Add Cache (Non-Breaking)

```rust
// Wrap existing resolvers with cache
let result = cache.get_or_execute(key, policy, || async {
    existing_resolver_logic().await  // No changes to existing code
}).await?;
```

### Phase 2: Monitor & Tune

- Check Prometheus metrics for hit rate
- Adjust TTL values based on staleness tolerance
- Identify high-value queries to cache

### Phase 3: Optimize Invalidation

- Add pattern-based invalidation to mutations
- Test edge cases (concurrent updates, race conditions)
- Document invalidation patterns for team

## See Also

- [Redis Cache (L2)](./src/cache/redis_cache.rs) - Distributed caching
- [DataLoader](./src/schema/) - Batch query optimization
- [Performance Guide](../../docs/API_PERFORMANCE_GUIDE.md) - Overall optimization strategy
