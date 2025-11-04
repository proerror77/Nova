# P0 Fix #3: Transactional Kafka Publishing (Outbox Pattern)

## Problem

**Issue**: Kafka publishing can fail after database write
```rust
// Current unsafe code:
let post = db.insert_post(post_data)?;  // ✓ Success
let _ = kafka.publish("post-created", post)?;  // ❌ Can fail
// Result: post in DB, not in Kafka → feed/search out of sync
```

**Risk**: At scale (1M+ posts/day), failures happen
- Post saved to DB ✓
- Network hiccup to Kafka broker ✗
- Post invisible in feed/search for users
- No retry mechanism

---

## Solution: Outbox Pattern (Already Partially Implemented)

Migration 067 created `outbox_events` table. Need to:
1. **Write all events to outbox atomically with DB changes**
2. **Implement Outbox consumer** to publish to Kafka reliably
3. **Add idempotency keys** to prevent duplicate processing

### Database Layer

```rust
// ATOMIC: Everything in one transaction
pub async fn create_post(user_id: Uuid, caption: &str) -> Result<Post> {
    let mut tx = pool.begin().await?;

    // 1. Insert post
    let post = sqlx::query_as::<_, Post>(
        "INSERT INTO posts (user_id, caption, status)
         VALUES ($1, $2, 'published') RETURNING *"
    )
    .bind(user_id)
    .bind(caption)
    .fetch_one(&mut *tx)
    .await?;

    // 2. Insert Outbox event (SAME TRANSACTION)
    sqlx::query(
        "INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
         VALUES ($1, $2, $3, $4)"
    )
    .bind("Post")
    .bind(post.id)
    .bind("PostCreated")
    .bind(serde_json::json!({
        "post_id": post.id,
        "user_id": user_id,
        "caption": caption,
        "created_at": post.created_at
    }))
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;  // COMMIT: both succeed or both fail
    Ok(post)
}
```

### Outbox Consumer

```rust
// Separate service/thread that polls outbox_events
pub async fn consume_outbox_events(pool: PgPool, kafka: KafkaProducer) -> Result<()> {
    loop {
        // 1. Fetch unpublished events (with ordering)
        let events = sqlx::query_as::<_, OutboxEvent>(
            "SELECT * FROM outbox_events
             WHERE published_at IS NULL AND retry_count < 3
             ORDER BY created_at ASC
             LIMIT 100
             FOR UPDATE SKIP LOCKED"
        )
        .fetch_all(&pool)
        .await?;

        // 2. Publish each event to Kafka
        for event in events {
            let topic = match event.aggregate_type.as_str() {
                "Post" => "post-events",
                "Comment" => "comment-events",
                "User" => "user-events",
                _ => continue,
            };

            match kafka.send(&event.payload, topic).await {
                Ok(_) => {
                    // 3. Mark as published
                    sqlx::query(
                        "UPDATE outbox_events SET published_at = NOW() WHERE id = $1"
                    )
                    .bind(event.id)
                    .execute(&pool)
                    .await?;
                }
                Err(e) => {
                    // Increment retry count
                    sqlx::query(
                        "UPDATE outbox_events SET retry_count = retry_count + 1
                         WHERE id = $1"
                    )
                    .bind(event.id)
                    .execute(&pool)
                    .await?;

                    tracing::warn!("Failed to publish event {}: {}", event.id, e);
                }
            }
        }

        tokio::time::sleep(Duration::from_secs(5)).await;
    }
}
```

---

## Implementation Checklist

### Phase 1: Database (Already Done)
- [x] Create outbox_events table (Migration 067)
- [x] Create indexes for consumer polling
- [x] Create triggers for automatic event creation

### Phase 2: Application Code Changes
Services to update:
- [ ] **content-service**: Wrap post/comment creation in Outbox
- [ ] **messaging-service**: Wrap message send in Outbox
- [ ] **user-service**: Wrap follow/unfollow in Outbox

Example (content-service):
```rust
// File: content-service/src/services/posts.rs
// Before:
pub async fn create_post(...) -> Result<Post> {
    let post = db.insert_post(...)?;
    kafka.publish("post-created", &post)?;
    Ok(post)
}

// After:
pub async fn create_post(...) -> Result<Post> {
    let mut tx = db.begin()?;
    let post = db.insert_post_tx(&mut tx, ...)?;
    db.insert_outbox_event_tx(&mut tx, &post)?;  // Atomic!
    tx.commit()?;
    Ok(post)
}
```

### Phase 3: Outbox Consumer Service

Create new service or add to existing:
```rust
// outbox-consumer/src/main.rs
#[tokio::main]
async fn main() -> Result<()> {
    let pool = create_pool().await?;
    let kafka = KafkaProducer::new(&config.kafka.brokers).await?;

    // Start consumer loop
    consume_outbox_events(pool, kafka).await?;
    Ok(())
}
```

### Phase 4: Idempotency

Add idempotency keys to prevent double-processing:
```sql
ALTER TABLE outbox_events ADD COLUMN IF NOT EXISTS
    idempotency_key VARCHAR(255) UNIQUE NULL;

-- When publishing, include idempotency key in Kafka message:
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "type": "PostCreated",
  "data": {...},
  "idempotency_key": "550e8400-e29b-41d4-a716-446655440000"
}

-- Kafka consumer checks if already processed:
if (cache.get(idempotency_key)) {
    // Already processed, skip
} else {
    // Process and cache
}
```

---

## Monitoring

```rust
lazy_static::lazy_static! {
    static ref OUTBOX_BACKLOG: prometheus::Gauge =
        prometheus::Gauge::new("outbox_backlog_events", "Unpublished events in outbox").unwrap();
    static ref OUTBOX_PUBLISH_TIME: prometheus::Histogram =
        prometheus::Histogram::new("outbox_publish_duration_secs", "Time to publish event").unwrap();
}

// In consumer loop:
let backlog: i64 = sqlx::query_scalar(
    "SELECT COUNT(*) FROM outbox_events WHERE published_at IS NULL"
)
.fetch_one(&pool)
.await?;

OUTBOX_BACKLOG.set(backlog as f64);

if backlog > 10000 {
    alert!("Outbox backlog growing - consumer may be slow");
}
```

---

## Testing

```rust
#[tokio::test]
async fn test_post_creation_is_atomic() {
    // Simulate Kafka failure after DB insert
    let mut kafka_mock = MockKafka::new();
    kafka_mock.will_fail(true);

    let post = create_post(user_id, "test").await;

    // Post should still be in DB
    let post_in_db = db.get_post(post.id).await;
    assert!(post_in_db.is_ok());

    // Outbox event should be created
    let event = db.get_outbox_event(post.id).await?;
    assert!(event.is_some());
    assert_eq!(event.unwrap().published_at, None);  // Not yet published

    // When Kafka recovers, consumer should retry
    kafka_mock.will_fail(false);
    outbox_consumer.consume().await?;

    // Now event should be published
    let event = db.get_outbox_event(post.id).await?;
    assert!(event.unwrap().published_at.is_some());
}

#[tokio::test]
async fn test_idempotent_event_processing() {
    // Simulate duplicate Kafka consumer processing same event
    let event_data = json!({...});

    // Process once
    let result1 = process_kafka_event(&event_data).await?;

    // Process again (duplicate)
    let result2 = process_kafka_event(&event_data).await?;

    // Should be idempotent - no duplicate post created
    let posts = db.get_posts_by_user(user_id).await?;
    assert_eq!(posts.len(), 1);  // Only one post despite duplicate
}
```

---

## Troubleshooting

### Issue: Outbox backlog growing

**Check**:
```sql
SELECT COUNT(*) FROM outbox_events WHERE published_at IS NULL;
SELECT aggregate_type, COUNT(*) FROM outbox_events
WHERE published_at IS NULL GROUP BY aggregate_type;
```

**Causes**:
1. Consumer not running
2. Kafka broker unreachable
3. Consumer slow (high retry_count)

**Fix**:
```bash
# Check consumer logs
kubectl logs -f outbox-consumer-0

# Check Kafka broker
kafka-broker-api-versions.sh --bootstrap-server kafka:9092

# Scale consumer if slow
kubectl scale deploy outbox-consumer --replicas=3
```

### Issue: Duplicate events in Kafka

**Check**:
```sql
SELECT idempotency_key, COUNT(*) FROM outbox_events
GROUP BY idempotency_key HAVING COUNT(*) > 1;
```

**Cause**: Consumer processing event twice (not updating published_at)

**Fix**: Verify `published_at` update logic in consumer:
```rust
// WRONG: May publish twice if update fails
kafka.publish(&event).await?;
db.update_published_at(event.id).await?;

// CORRECT: Update atomically or use idempotency key
let tx = db.begin()?;
kafka.publish_with_tx(&event, &tx).await?;
db.update_published_at_tx(event.id, &tx).await?;
tx.commit()?;
```

---

## Status

- **Created**: 2025-11-04
- **Priority**: P0
- **Estimated Effort**: 2 weeks
- **Impact**: Prevents data loss, ensures feed/search consistency
