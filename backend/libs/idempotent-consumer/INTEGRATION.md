# Integration Guide: Idempotent Kafka Consumer

This guide shows how to integrate the `idempotent-consumer` library into an existing Kafka consumer service.

---

## Step 1: Add Dependencies

Add to your service's `Cargo.toml`:

```toml
[dependencies]
# Idempotency
idempotent-consumer = { path = "../../libs/idempotent-consumer" }

# Kafka
rdkafka = { version = "0.36", features = ["cmake-build", "ssl", "gssapi"] }

# Database (if not already present)
sqlx = { version = "0.7", features = ["runtime-tokio", "postgres", "uuid", "chrono"] }

# Async runtime
tokio = { version = "1.35", features = ["full"] }

# Error handling
anyhow = "1.0"

# Logging
tracing = "0.1"
```

---

## Step 2: Run Database Migration

```bash
# Navigate to your service directory
cd backend/communication-service

# Copy migration file
cp ../libs/idempotent-consumer/migrations/001_create_processed_events_table.sql \
   migrations/

# Or run migration directly from library
sqlx migrate run \
  --source ../libs/idempotent-consumer/migrations \
  --database-url $DATABASE_URL
```

---

## Step 3: Update Kafka Consumer Code

### Before: Without Idempotency

```rust
// communication-service/src/kafka/consumer.rs

use rdkafka::consumer::{Consumer, StreamConsumer};
use rdkafka::message::Message;

pub async fn consume_notification_events(
    consumer: StreamConsumer,
) -> Result<(), Box<dyn std::error::Error>> {
    loop {
        let message = consumer.recv().await?;

        // Parse payload
        let payload: NotificationEvent = serde_json::from_slice(
            message.payload().unwrap()
        )?;

        // Process event (PROBLEM: May be processed multiple times!)
        create_notification(&payload).await?;

        // Commit offset
        consumer.commit_message(&message, rdkafka::consumer::CommitMode::Async)?;
    }
}
```

### After: With Idempotency

```rust
// communication-service/src/kafka/consumer.rs

use rdkafka::consumer::{Consumer, StreamConsumer};
use rdkafka::message::Message;
use idempotent_consumer::{IdempotencyGuard, ProcessingResult};
use sqlx::PgPool;
use std::sync::Arc;
use std::time::Duration;
use tracing::{info, warn, error};

pub async fn consume_notification_events(
    consumer: StreamConsumer,
    db_pool: PgPool,
) -> Result<(), Box<dyn std::error::Error>> {
    // Create idempotency guard with 7-day retention
    let guard = Arc::new(IdempotencyGuard::new(
        db_pool.clone(),
        Duration::from_secs(7 * 86400), // 7 days
    ));

    // Start cleanup job (runs hourly)
    start_cleanup_job(guard.clone());

    loop {
        let message = consumer.recv().await?;

        // Extract event_id from Kafka header
        let event_id = extract_event_id(&message)?;

        // Process with idempotency check
        match guard.process_if_new(&event_id, async {
            // Parse payload
            let payload: NotificationEvent = serde_json::from_slice(
                message.payload().unwrap()
            )?;

            // Process event (now guaranteed exactly-once)
            create_notification(&payload).await?;

            Ok(())
        }).await {
            Ok(ProcessingResult::Success) => {
                info!(event_id = %event_id, "Event processed successfully");
                consumer.commit_message(&message, rdkafka::consumer::CommitMode::Async)?;
            }
            Ok(ProcessingResult::AlreadyProcessed) => {
                info!(event_id = %event_id, "Event already processed, skipping");
                consumer.commit_message(&message, rdkafka::consumer::CommitMode::Async)?;
            }
            Ok(ProcessingResult::Failed(err)) => {
                error!(event_id = %event_id, error = %err, "Event processing failed");
                // Don't commit offset - will retry on next poll
            }
            Err(e) => {
                error!(event_id = %event_id, error = ?e, "Idempotency check failed");
                // Don't commit offset - will retry on next poll
            }
        }
    }
}

/// Extract event_id from Kafka message header
fn extract_event_id(message: &rdkafka::message::BorrowedMessage) -> Result<String, anyhow::Error> {
    message
        .headers()
        .and_then(|h| h.iter().find(|h| h.key == "idempotency_key"))
        .and_then(|h| h.value)
        .and_then(|v| String::from_utf8(v.to_vec()).ok())
        .ok_or_else(|| anyhow::anyhow!("Missing idempotency_key header"))
}

/// Start background cleanup job
fn start_cleanup_job(guard: Arc<IdempotencyGuard>) {
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(Duration::from_secs(3600)).await; // 1 hour

            match guard.cleanup_old_events().await {
                Ok(deleted_count) if deleted_count > 0 => {
                    info!(deleted_count = deleted_count, "Cleaned up old processed events");
                }
                Ok(_) => {
                    // No events to cleanup
                }
                Err(e) => {
                    error!(error = ?e, "Failed to cleanup old processed events");
                }
            }
        }
    });
}
```

---

## Step 4: Update Kafka Producer (Add idempotency_key Header)

For the idempotency to work, producers must include a unique `idempotency_key` header in every message.

### Example: User Service Publishing user.created Event

```rust
// user-service/src/kafka/producer.rs

use rdkafka::producer::{FutureProducer, FutureRecord};
use rdkafka::message::{Header, OwnedHeaders};
use uuid::Uuid;

pub async fn publish_user_created_event(
    producer: &FutureProducer,
    user_id: Uuid,
    username: String,
) -> Result<(), Box<dyn std::error::Error>> {
    // Generate unique idempotency key
    let idempotency_key = Uuid::new_v4().to_string();

    // Create event payload
    let payload = serde_json::json!({
        "user_id": user_id,
        "username": username,
        "created_at": chrono::Utc::now().to_rfc3339(),
    });

    let payload_str = serde_json::to_string(&payload)?;

    // Create Kafka headers with idempotency_key
    let headers = OwnedHeaders::new()
        .insert(Header {
            key: "idempotency_key",
            value: Some(idempotency_key.as_bytes()),
        })
        .insert(Header {
            key: "event_type",
            value: Some(b"user.created"),
        })
        .insert(Header {
            key: "correlation_id",
            value: Some(Uuid::new_v4().to_string().as_bytes()),
        });

    // Publish to Kafka
    let record = FutureRecord::to("nova.user.events")
        .key(&user_id.to_string())
        .payload(&payload_str)
        .headers(headers);

    producer
        .send(record, Duration::from_secs(10))
        .await
        .map_err(|(err, _)| anyhow::anyhow!("Failed to publish event: {}", err))?;

    tracing::info!(
        user_id = %user_id,
        idempotency_key = %idempotency_key,
        "Published user.created event"
    );

    Ok(())
}
```

**Key point**: Every Kafka message MUST have a unique `idempotency_key` header.

---

## Step 5: Update Service Initialization

### communication-service/src/main.rs

```rust
use idempotent_consumer::IdempotencyGuard;
use sqlx::PgPool;
use std::sync::Arc;
use std::time::Duration;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    // Load configuration
    let config = load_config()?;

    // Connect to database
    let db_pool = PgPool::connect(&config.database_url).await?;

    // Run database migrations
    sqlx::migrate!("./migrations").run(&db_pool).await?;

    // Initialize Kafka consumer
    let consumer: StreamConsumer = create_kafka_consumer(&config)?;

    // Start Kafka consumer with idempotency
    consume_notification_events(consumer, db_pool.clone()).await?;

    Ok(())
}
```

---

## Step 6: Testing

### Unit Test: Consumer Logic

```rust
// communication-service/tests/consumer_test.rs

use idempotent_consumer::{IdempotencyGuard, ProcessingResult};
use sqlx::PgPool;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::Arc;
use std::time::Duration;

#[sqlx::test]
async fn test_duplicate_event_not_reprocessed(pool: PgPool) {
    let guard = IdempotencyGuard::new(pool, Duration::from_secs(86400));
    let event_id = "test-event-123";

    // Track how many times processing logic is called
    let call_count = Arc::new(AtomicU32::new(0));

    // First processing
    let call_count_clone = call_count.clone();
    let result1 = guard.process_if_new(event_id, async move {
        call_count_clone.fetch_add(1, Ordering::SeqCst);
        Ok(())
    }).await.unwrap();

    assert_eq!(result1, ProcessingResult::Success);
    assert_eq!(call_count.load(Ordering::SeqCst), 1);

    // Second processing (duplicate)
    let call_count_clone = call_count.clone();
    let result2 = guard.process_if_new(event_id, async move {
        call_count_clone.fetch_add(1, Ordering::SeqCst);
        Ok(())
    }).await.unwrap();

    assert_eq!(result2, ProcessingResult::AlreadyProcessed);
    assert_eq!(call_count.load(Ordering::SeqCst), 1); // Still 1 (not called again)
}
```

### Integration Test: End-to-End

```bash
# Start local Kafka and PostgreSQL
docker-compose up -d

# Run integration tests
cargo test --package communication-service --test integration_test
```

---

## Step 7: Monitoring and Alerting

### Prometheus Metrics (Future Enhancement)

```rust
// Expose metrics via Prometheus
use prometheus::{IntCounter, IntGauge, Registry};

lazy_static! {
    static ref EVENTS_PROCESSED_TOTAL: IntCounter = IntCounter::new(
        "kafka_events_processed_total",
        "Total number of Kafka events processed"
    ).unwrap();

    static ref EVENTS_DUPLICATES_TOTAL: IntCounter = IntCounter::new(
        "kafka_events_duplicates_total",
        "Total number of duplicate events skipped"
    ).unwrap();

    static ref PROCESSED_EVENTS_TABLE_SIZE: IntGauge = IntGauge::new(
        "processed_events_table_size",
        "Current number of rows in processed_events table"
    ).unwrap();
}

// In consumer loop:
match guard.process_if_new(&event_id, async { /* ... */ }).await {
    Ok(ProcessingResult::Success) => {
        EVENTS_PROCESSED_TOTAL.inc();
    }
    Ok(ProcessingResult::AlreadyProcessed) => {
        EVENTS_DUPLICATES_TOTAL.inc();
    }
    // ...
}
```

### Grafana Dashboard Queries

```promql
# Event processing rate
rate(kafka_events_processed_total[5m])

# Duplicate rate (should be low in healthy system)
rate(kafka_events_duplicates_total[5m])

# Processed events table size
processed_events_table_size
```

### Alert Rules

```yaml
# alerts.yml

groups:
  - name: kafka_consumer
    interval: 30s
    rules:
      - alert: HighDuplicateRate
        expr: rate(kafka_events_duplicates_total[5m]) > 100
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High duplicate event rate in {{ $labels.service }}"
          description: "Duplicate rate is {{ $value }}/sec (threshold: 100/sec)"

      - alert: ProcessedEventsTableGrowth
        expr: processed_events_table_size > 10000000
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "processed_events table is growing ({{ $value }} rows)"
          description: "Check cleanup job is running"
```

---

## Step 8: Operational Playbook

### 1. Service Restart / Rolling Update

**Expected behavior**:
- ✅ No duplicate processing (idempotency persists across restarts)
- ✅ Kafka offset committed after processing
- ✅ New instances pick up from last committed offset

**Monitoring**:
```bash
# Check processed_events table before/after restart
psql -c "SELECT COUNT(*) FROM processed_events;" $DATABASE_URL

# Should not grow significantly during restart (only new events)
```

### 2. Kafka Consumer Rebalance

**Expected behavior**:
- ✅ Events may be redelivered to different consumers
- ✅ Idempotency prevents duplicate processing
- ✅ `AlreadyProcessed` logged for redelivered events

**Monitoring**:
```bash
# Check duplicate rate during rebalance
# Should see spike in EVENTS_DUPLICATES_TOTAL
```

### 3. Database Failover

**Expected behavior**:
- ❌ Consumer temporarily fails (cannot check idempotency)
- ✅ Kafka offset NOT committed (events will be retried)
- ✅ After database recovery, events reprocessed successfully

**Monitoring**:
```bash
# Check consumer lag during database outage
kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --describe --group notification-consumer
```

### 4. Cleanup Job Failure

**Symptom**: `processed_events` table grows unbounded

**Resolution**:
```sql
-- Manual cleanup (7 days retention)
DELETE FROM processed_events
WHERE processed_at < NOW() - INTERVAL '7 days';

-- Check table size
SELECT pg_size_pretty(pg_total_relation_size('processed_events'));

-- Vacuum to reclaim space
VACUUM ANALYZE processed_events;
```

### 5. Invalid idempotency_key Header

**Symptom**: Consumer crashes with "Missing idempotency_key header"

**Resolution**:
```rust
// Add fallback to Kafka offset if header missing
fn extract_event_id(message: &BorrowedMessage) -> Result<String> {
    // Try header first
    if let Some(id) = extract_from_header(message) {
        return Ok(id);
    }

    // Fallback to Kafka offset (partition-specific)
    Ok(format!(
        "{}-{}-{}",
        message.topic(),
        message.partition(),
        message.offset()
    ))
}
```

---

## Step 9: Performance Tuning

### Database Connection Pool

```rust
// Tune pool size based on consumer parallelism
let pool = PgPoolOptions::new()
    .max_connections(50)  // Match or exceed Kafka consumer threads
    .min_connections(10)
    .acquire_timeout(Duration::from_secs(10))
    .idle_timeout(Duration::from_secs(300))
    .connect(&database_url)
    .await?;
```

### Kafka Consumer Configuration

```rust
use rdkafka::ClientConfig;

let consumer: StreamConsumer = ClientConfig::new()
    .set("bootstrap.servers", "localhost:9092")
    .set("group.id", "notification-consumer")
    .set("enable.auto.commit", "false")  // Manual commit after processing
    .set("auto.offset.reset", "earliest")
    .set("max.poll.interval.ms", "300000")  // 5 minutes (allow slow processing)
    .create()?;
```

### Parallel Processing (Advanced)

```rust
// Process events in parallel (be careful with ordering!)
use futures::stream::StreamExt;

let guard = Arc::new(IdempotencyGuard::new(pool, Duration::from_secs(7 * 86400)));

loop {
    let messages: Vec<_> = (0..10)
        .map(|_| consumer.recv().await)
        .collect();

    let tasks: Vec<_> = messages.into_iter()
        .map(|message| {
            let guard = guard.clone();
            tokio::spawn(async move {
                let event_id = extract_event_id(&message)?;
                guard.process_if_new(&event_id, async {
                    process_event(&message).await
                }).await
            })
        })
        .collect();

    let results = futures::future::join_all(tasks).await;

    // Handle results...
}
```

**⚠️ Warning**: Parallel processing may reorder events within a partition. Only use if event order doesn't matter.

---

## Checklist: Integration Complete

- [ ] Added `idempotent-consumer` dependency to `Cargo.toml`
- [ ] Ran database migration (created `processed_events` table)
- [ ] Updated Kafka consumer to use `IdempotencyGuard`
- [ ] Updated Kafka producer to add `idempotency_key` header
- [ ] Added cleanup job (runs hourly)
- [ ] Added unit tests for idempotency logic
- [ ] Added integration tests with real PostgreSQL
- [ ] Configured connection pool sizing
- [ ] Added monitoring/alerting for duplicate rate
- [ ] Documented operational procedures
- [ ] Tested service restart (verify no duplicates)
- [ ] Tested consumer rebalance (verify idempotency)
- [ ] Load tested with expected event volume

---

## Common Pitfalls

### 1. Missing idempotency_key Header

**Problem**: Producer doesn't set `idempotency_key` header → consumer crashes

**Solution**: Add header to all Kafka messages (see Step 4)

### 2. Using Non-Unique Event ID

**Problem**: Using timestamp or partition as event_id → false duplicates

**Solution**: Use UUID or ensure global uniqueness

### 3. Committing Offset Before Processing

**Problem**: Offset committed before `process_if_new()` → events lost

**Solution**: Commit AFTER successful processing

### 4. Not Running Cleanup Job

**Problem**: `processed_events` table grows unbounded → disk full

**Solution**: Start cleanup job in service initialization (see Step 3)

### 5. Database Connection Pool Too Small

**Problem**: Consumers block waiting for DB connections → high latency

**Solution**: Set `max_connections` >= number of consumer threads

---

## Support

For issues or questions:
- **Library Issues**: https://github.com/your-org/nova/issues
- **Integration Help**: See inline documentation in `idempotent-consumer/src/lib.rs`
- **Performance Tuning**: See `DESIGN.md` for performance analysis
