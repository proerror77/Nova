# Cache Invalidation - Quick Reference Card

**One-page summary for rapid integration**

---

## Installation

```toml
# Add to service Cargo.toml
[dependencies]
cache-invalidation = { path = "../libs/cache-invalidation" }
```

---

## Publisher (Data-Modifying Services)

### Initialize

```rust
use cache_invalidation::InvalidationPublisher;

let publisher = InvalidationPublisher::new(
    &redis_url,
    "my-service".to_string()
).await?;
```

### Usage Patterns

```rust
// ✅ Single entity (most common)
publisher.invalidate_user("123").await?;
publisher.invalidate_post("456").await?;

// ✅ Pattern-based (cascade)
publisher.invalidate_pattern("feed:user_123:*").await?;

// ✅ Batch (efficient)
publisher.invalidate_batch(vec![
    "user:1".into(), "user:2".into()
]).await?;

// ✅ Custom entity
publisher.invalidate_custom("session", "abc123").await?;
```

### Best Practice: Invalidate AFTER DB Commit

```rust
// ❌ WRONG
publisher.invalidate_user("123").await?;
db.update_user("123", data).await?;

// ✅ CORRECT
db.update_user("123", data).await?;
publisher.invalidate_user("123").await?;
```

---

## Subscriber (Cache-Consuming Services)

### Initialize

```rust
use cache_invalidation::{InvalidationSubscriber, InvalidationAction};

let subscriber = InvalidationSubscriber::new(&redis_url).await?;
```

### Subscribe with Callback

```rust
let handle = subscriber.subscribe(|msg| async move {
    match msg.action {
        InvalidationAction::Delete | InvalidationAction::Update => {
            if let Some(entity_id) = &msg.entity_id {
                let key = format!("{}:{}", msg.entity_type, entity_id);

                // Delete from Redis
                redis.del(&key).await?;

                // Delete from memory cache
                memory_cache.remove(&key);
            }
        }
        InvalidationAction::Pattern => {
            if let Some(pattern) = &msg.pattern {
                // Get matching keys
                let keys: Vec<String> = redis.keys(pattern).await?;

                // Batch delete
                redis.del(&keys).await?;
                for key in keys {
                    memory_cache.remove(&key);
                }
            }
        }
        InvalidationAction::Batch => {
            if let Some(entity_ids) = &msg.entity_ids {
                // Batch delete
                redis.del(entity_ids).await?;
                for id in entity_ids {
                    memory_cache.remove(id);
                }
            }
        }
    }
    Ok(())
}).await?;
```

---

## Entity Types

```rust
EntityType::User          // user:123
EntityType::Post          // post:456
EntityType::Comment       // comment:789
EntityType::Notification  // notification:123
EntityType::Feed          // feed:user_123:timeline
EntityType::Custom(s)     // custom:value
```

---

## Helper Functions

```rust
use cache_invalidation::{build_cache_key, parse_cache_key};

// Build key
let key = build_cache_key(&EntityType::User, "123");
// => "user:123"

// Parse key
let (entity_type, entity_id) = parse_cache_key("user:123")?;
// => (EntityType::User, "123")
```

---

## Common Patterns

### User Profile Update

```rust
// Publisher (user-service)
pub async fn update_user(&self, id: &str, data: Input) -> Result<User> {
    let user = db.update_user(id, data).await?;
    publisher.invalidate_user(id).await?;
    Ok(user)
}
```

### Post Delete (Cascade)

```rust
// Publisher (content-service)
pub async fn delete_post(&self, post_id: &str, user_id: &str) -> Result<()> {
    db.delete_post(post_id).await?;

    // Invalidate post
    publisher.invalidate_post(post_id).await?;

    // Invalidate user's feed
    publisher.invalidate_pattern(&format!("feed:{}:*", user_id)).await?;

    Ok(())
}
```

### Batch Update

```rust
// Publisher (user-service)
pub async fn batch_update(&self, updates: Vec<Update>) -> Result<()> {
    db.batch_update(&updates).await?;

    let keys: Vec<String> = updates
        .iter()
        .map(|u| format!("user:{}", u.id))
        .collect();

    publisher.invalidate_batch(keys).await?;
    Ok(())
}
```

---

## Error Handling

```rust
// ✅ CORRECT: Don't fail request on invalidation error
match publisher.invalidate_user(user_id).await {
    Ok(_) => tracing::debug!("Cache invalidated"),
    Err(e) => tracing::error!(error = ?e, "Invalidation failed - cache will expire via TTL"),
}

// Cache will expire naturally via TTL if invalidation fails
```

---

## Environment Configuration

```bash
# .env
REDIS_URL=redis://localhost:6379

# Production
REDIS_URL=redis://:password@redis.prod.com:6379
```

---

## Testing

### Unit Tests

```bash
cargo test -p cache-invalidation --lib
```

### Integration Tests (requires Redis)

```bash
# Start Redis
docker run -d -p 6379:6379 redis:7-alpine

# Run tests
cargo test -p cache-invalidation --test integration_test -- --ignored
```

### Manual Testing

```bash
# Terminal 1: Redis monitor
redis-cli SUBSCRIBE cache:invalidate

# Terminal 2: Run publisher example
cargo run --example publisher

# Terminal 3: Run subscriber example
cargo run --example subscriber
```

---

## Performance Targets

- **Latency**: <2ms (p99)
- **Throughput**: >10k msg/sec
- **Memory**: <100MB

---

## Troubleshooting

### Subscriber not receiving messages

```bash
# Check Redis connection
redis-cli PING

# Check active channels
redis-cli PUBSUB CHANNELS

# Monitor in real-time
redis-cli SUBSCRIBE cache:invalidate
```

### High latency

```bash
# Check Redis latency
redis-cli --latency

# Check Redis load
redis-cli INFO stats
```

---

## Monitoring

### Metrics to Track

```rust
// Publisher
cache_invalidation_published_total
cache_invalidation_publish_latency_seconds

// Subscriber
cache_invalidation_received_total
cache_invalidation_processing_latency_seconds
cache_invalidation_errors_total
```

### Alerts to Set

- Latency >10ms for 5 minutes
- Error rate >1%
- Subscriber disconnected

---

## Documentation

- **Comprehensive Guide**: `README.md`
- **Integration Steps**: `INTEGRATION_GUIDE.md`
- **Implementation Details**: `IMPLEMENTATION_SUMMARY.md`
- **Verification Report**: `VERIFICATION.md`
- **This Card**: `QUICK_REFERENCE.md`

---

## Support

- Issues: Create GitHub issue
- Questions: Check README troubleshooting section
- Examples: See `examples/` directory

---

**Quick Start Time**: 15 minutes per service
**Production Ready**: Yes
**Status**: ✅ Stable

