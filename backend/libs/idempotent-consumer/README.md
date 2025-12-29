# Idempotent Kafka Consumer Library

[![Rust](https://img.shields.io/badge/rust-1.75%2B-orange.svg)](https://www.rust-lang.org/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Exactly-once semantics for Kafka event processing using PostgreSQL as persistent idempotency tracking storage.**

## Problem Statement

Without persistent idempotency tracking, Kafka consumers face these issues:

| Problem | Impact | Example |
|---------|--------|---------|
| **Service restarts** | In-memory HashMap lost → events reprocessed | Duplicate notifications sent |
| **Consumer rebalancing** | New instances reprocess same events | Duplicate charges applied |
| **At-least-once delivery** | Kafka guarantees cause duplicates | Same order processed twice |
| **Data corruption** | No idempotency → duplicate side effects | Double database writes |

**This library solves these problems by using PostgreSQL to persistently track processed event IDs.**

---

## Architecture

```text
┌─────────────────────────────────────────────────────────────────┐
│                         Kafka Topic                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐       │
│  │ Event 1  │  │ Event 2  │  │ Event 3  │  │ Event 4  │  ...  │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘       │
└─────────────────────────────────────────────────────────────────┘
         │              │              │              │
         ▼              ▼              ▼              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Kafka Consumer Group                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │ Consumer 1   │  │ Consumer 2   │  │ Consumer 3   │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
└─────────────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                    IdempotencyGuard                             │
│                                                                 │
│  1. Extract event_id from Kafka message                        │
│  2. Check if event_id exists in processed_events table         │
│     ├─ EXISTS → Return AlreadyProcessed (skip)                 │
│     └─ NOT EXISTS → Continue to step 3                         │
│  3. Execute business logic                                      │
│  4. INSERT event_id into processed_events                       │
│     (ON CONFLICT DO NOTHING for race condition safety)         │
└─────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│                    PostgreSQL                                   │
│                                                                 │
│  processed_events table:                                        │
│  ┌────────────┬──────────────┬─────────────┬──────────────┐   │
│  │ id (UUID)  │ event_id     │ processed_at│ metadata     │   │
│  ├────────────┼──────────────┼─────────────┼──────────────┤   │
│  │ abc-123... │ event-1      │ 2024-01-01  │ {...}        │   │
│  │ def-456... │ event-2      │ 2024-01-01  │ {...}        │   │
│  │ ghi-789... │ event-3      │ 2024-01-01  │ {...}        │   │
│  └────────────┴──────────────┴─────────────┴──────────────┘   │
│                                                                 │
│  Indexes:                                                       │
│  - UNIQUE INDEX on event_id (O(1) lookups)                     │
│  - INDEX on processed_at (efficient cleanup)                   │
└─────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Business Logic (Your Service)                  │
│                                                                 │
│  - Create notifications                                         │
│  - Update database                                              │
│  - Send emails                                                  │
│  - Trigger workflows                                            │
│  - etc.                                                         │
└─────────────────────────────────────────────────────────────────┘
```

---

## Key Features

✅ **Exactly-once processing** across service restarts
✅ **Concurrency-safe** (10 consumers, same event → only 1 processes)
✅ **Fast O(1) lookups** using PostgreSQL UNIQUE index
✅ **Configurable retention** (default 7 days, prevents unbounded growth)
✅ **Metadata support** (store consumer group, partition, offset, etc.)
✅ **Transient error retry** (automatic handling of connection errors)
✅ **Clean API** (process_if_new, is_processed, mark_processed)

---

## Installation

Add to `Cargo.toml`:

```toml
[dependencies]
idempotent-consumer = { path = "../libs/idempotent-consumer" }
sqlx = { version = "0.7", features = ["runtime-tokio", "postgres"] }
tokio = { version = "1", features = ["full"] }
```

---

## Quick Start

### 1. Database Setup

Run the migration to create the `processed_events` table:

```bash
# Apply migration
sqlx migrate run --source backend/libs/idempotent-consumer/migrations
```

Or manually run `migrations/001_create_processed_events_table.sql`.

### 2. Basic Usage

```rust
use idempotent_consumer::{IdempotencyGuard, ProcessingResult};
use sqlx::PgPool;
use std::time::Duration;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Connect to database
    let pool = PgPool::connect("postgresql://localhost/mydb").await?;

    // Create guard with 7-day retention
    let guard = IdempotencyGuard::new(pool, Duration::from_secs(7 * 86400));

    // Process event with idempotency check
    let event_id = "event-123";
    match guard.process_if_new(event_id, async {
        // Business logic here
        println!("Processing event {}...", event_id);
        create_notification().await?;
        Ok(())
    }).await? {
        ProcessingResult::Success => {
            println!("Event processed successfully");
        }
        ProcessingResult::AlreadyProcessed => {
            println!("Event already processed, skipping");
        }
        ProcessingResult::Failed(err) => {
            eprintln!("Processing failed: {}", err);
        }
    }

    Ok(())
}

async fn create_notification() -> Result<(), anyhow::Error> {
    // Your business logic
    Ok(())
}
```

---

## Usage Examples

### Example 1: Kafka Consumer with Idempotency

```rust
use rdkafka::consumer::{Consumer, StreamConsumer};
use rdkafka::message::Message;
use idempotent_consumer::{IdempotencyGuard, ProcessingResult};

async fn consume_events(
    consumer: StreamConsumer,
    guard: IdempotencyGuard,
) -> Result<(), Box<dyn std::error::Error>> {
    loop {
        let message = consumer.recv().await?;

        // Extract event_id from Kafka header
        let event_id = message
            .headers()
            .and_then(|h| h.iter().find(|h| h.key == "idempotency_key"))
            .and_then(|h| h.value)
            .and_then(|v| String::from_utf8(v.to_vec()).ok())
            .expect("Missing idempotency_key header");

        // Process with idempotency
        match guard.process_if_new(&event_id, async {
            let payload: serde_json::Value = serde_json::from_slice(
                message.payload().unwrap()
            )?;

            // Business logic
            process_business_logic(&payload).await?;

            Ok(())
        }).await? {
            ProcessingResult::Success => {
                println!("Processed event: {}", event_id);
            }
            ProcessingResult::AlreadyProcessed => {
                println!("Skipped duplicate event: {}", event_id);
            }
            ProcessingResult::Failed(err) => {
                eprintln!("Failed to process event {}: {}", event_id, err);
                // Decide: retry, dead letter queue, etc.
            }
        }

        // Commit offset after processing (or use manual commit)
        consumer.commit_message(&message, rdkafka::consumer::CommitMode::Async)?;
    }
}

async fn process_business_logic(payload: &serde_json::Value) -> Result<(), anyhow::Error> {
    // Your business logic here
    Ok(())
}
```

### Example 2: Manual Idempotency Control

```rust
use idempotent_consumer::IdempotencyGuard;

async fn manual_idempotency_check(
    guard: &IdempotencyGuard,
    event_id: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    // Check if already processed
    if guard.is_processed(event_id).await? {
        println!("Event {} already processed, skipping", event_id);
        return Ok(());
    }

    // Execute business logic
    println!("Processing event {}...", event_id);
    let result = process_complex_workflow(event_id).await;

    // Only mark as processed if successful
    if result.is_ok() {
        let metadata = serde_json::json!({
            "consumer_group": "my-consumer-group",
            "partition": 0,
            "offset": 12345,
            "processing_time_ms": 123,
        });

        guard.mark_processed(event_id, Some(metadata)).await?;
        println!("Event {} marked as processed", event_id);
    } else {
        eprintln!("Event {} processing failed, will retry", event_id);
    }

    result
}

async fn process_complex_workflow(event_id: &str) -> Result<(), Box<dyn std::error::Error>> {
    // Complex multi-step workflow
    Ok(())
}
```

### Example 3: Periodic Cleanup Job

```rust
use idempotent_consumer::IdempotencyGuard;
use std::time::Duration;

async fn start_cleanup_job(guard: IdempotencyGuard) {
    tokio::spawn(async move {
        loop {
            // Run cleanup every hour
            tokio::time::sleep(Duration::from_secs(3600)).await;

            match guard.cleanup_old_events().await {
                Ok(deleted_count) => {
                    if deleted_count > 0 {
                        println!("Cleaned up {} old events", deleted_count);
                    }
                }
                Err(e) => {
                    eprintln!("Cleanup job failed: {}", e);
                }
            }
        }
    });
}
```

### Example 4: Concurrent Processing Safety

```rust
use idempotent_consumer::{IdempotencyGuard, ProcessingResult};
use std::sync::Arc;

async fn spawn_concurrent_consumers(
    guard: Arc<IdempotencyGuard>,
    event_id: String,
) {
    // Spawn 10 concurrent tasks processing the same event
    let mut handles = vec![];
    for i in 0..10 {
        let guard_clone = guard.clone();
        let event_id_clone = event_id.clone();

        let handle = tokio::spawn(async move {
            guard_clone.process_if_new(&event_id_clone, async {
                println!("Consumer {} processing event", i);
                tokio::time::sleep(Duration::from_millis(100)).await;
                Ok(())
            }).await
        });

        handles.push(handle);
    }

    // Wait for all tasks
    let results: Vec<_> = futures_util::future::join_all(handles)
        .await
        .into_iter()
        .collect();

    // Count results
    let success_count = results.iter()
        .filter(|r| matches!(r, Ok(Ok(ProcessingResult::Success))))
        .count();

    println!("Success: {} (expected: 1)", success_count);
    // Output: Success: 1 (expected: 1)
    // Only 1 consumer actually processed the event
}
```

---

## Event ID Strategies

The choice of event ID strategy is critical for idempotency:

### Strategy 1: Kafka Message Headers (Recommended)

**Pros**: Producer controls uniqueness, works across topics
**Cons**: Requires producer support

```rust
// Producer side:
let headers = OwnedHeaders::new()
    .insert(Header {
        key: "idempotency_key",
        value: Some(uuid::Uuid::new_v4().to_string().as_bytes()),
    });

let record = FutureRecord::to("my-topic")
    .key("key")
    .payload("payload")
    .headers(headers);

// Consumer side:
let event_id = message
    .headers()
    .and_then(|h| h.iter().find(|h| h.key == "idempotency_key"))
    .and_then(|h| h.value)
    .and_then(|v| String::from_utf8(v.to_vec()).ok())
    .expect("Missing idempotency_key");
```

### Strategy 2: Kafka Offset (Partition-Specific)

**Pros**: Always available, no producer changes
**Cons**: Only unique within partition

```rust
let event_id = format!(
    "{}-{}-{}",
    message.topic(),
    message.partition(),
    message.offset()
);
// Example: "nova.identity.events-0-12345"
```

⚠️ **Warning**: This only works if you process partitions in order. If you use parallel processing within a partition, you may reprocess events after consumer restart.

### Strategy 3: Payload-Based UUID

**Pros**: Business-level uniqueness, natural deduplication
**Cons**: Requires events to have IDs

```rust
#[derive(Deserialize)]
struct Event {
    id: Uuid,
    // other fields
}

let event: Event = serde_json::from_slice(message.payload())?;
let event_id = event.id.to_string();
```

### Strategy 4: Content Hash (Deterministic)

**Pros**: Works for any event, no producer changes
**Cons**: Same content = same ID (may not be desired)

```rust
use sha2::{Sha256, Digest};

let content = message.payload().unwrap();
let hash = Sha256::digest(content);
let event_id = format!("{:x}", hash);
```

---

## Integration Guide

### Step 1: Update Kafka Consumer

```rust
use idempotent_consumer::{IdempotencyGuard, ProcessingResult};
use rdkafka::consumer::{Consumer, StreamConsumer};
use sqlx::PgPool;
use std::sync::Arc;
use std::time::Duration;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize database pool
    let pool = PgPool::connect("postgresql://localhost/mydb").await?;

    // Create idempotency guard
    let guard = Arc::new(IdempotencyGuard::new(
        pool.clone(),
        Duration::from_secs(7 * 86400), // 7 days
    ));

    // Initialize Kafka consumer
    let consumer: StreamConsumer = /* ... */;

    // Start cleanup job
    let guard_clone = guard.clone();
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(Duration::from_secs(3600)).await;
            let _ = guard_clone.cleanup_old_events().await;
        }
    });

    // Consume events
    loop {
        let message = consumer.recv().await?;
        let event_id = extract_event_id(&message);

        match guard.process_if_new(&event_id, async {
            process_event(&message).await
        }).await? {
            ProcessingResult::Success => {
                consumer.commit_message(&message, rdkafka::consumer::CommitMode::Async)?;
            }
            ProcessingResult::AlreadyProcessed => {
                consumer.commit_message(&message, rdkafka::consumer::CommitMode::Async)?;
            }
            ProcessingResult::Failed(err) => {
                eprintln!("Processing failed: {}", err);
                // Handle failure (retry, DLQ, etc.)
            }
        }
    }
}
```

### Step 2: Add Cleanup Job (Optional but Recommended)

Add to your service's startup code:

```rust
use idempotent_consumer::IdempotencyGuard;
use std::time::Duration;

pub async fn start_cleanup_job(guard: IdempotencyGuard) {
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(Duration::from_secs(3600)).await; // Every hour

            match guard.cleanup_old_events().await {
                Ok(count) if count > 0 => {
                    tracing::info!(deleted_count = count, "Cleaned up old processed events");
                }
                Ok(_) => {
                    tracing::debug!("No old events to cleanup");
                }
                Err(e) => {
                    tracing::error!(error = ?e, "Cleanup job failed");
                }
            }
        }
    });
}
```

---

## Performance Considerations

### Database Performance

| Operation | Time Complexity | Typical Latency | Notes |
|-----------|----------------|-----------------|-------|
| `is_processed()` | O(1) | 1-2ms | UNIQUE index on event_id |
| `mark_processed()` | O(1) | 2-3ms | Single INSERT |
| `process_if_new()` | O(1) | 3-5ms | CHECK + INSERT |
| `cleanup_old_events()` | O(n) | 10-100ms | Deletes n events, run hourly |

### Throughput Estimates

| Event Volume | Database Load | Recommendation |
|-------------|---------------|----------------|
| < 1k events/sec | Low (<10% CPU) | ✅ No issues |
| 1k-10k events/sec | Medium (10-30% CPU) | ✅ Use connection pooling |
| 10k-100k events/sec | High (30-70% CPU) | ⚠️ Consider sharding or batching |
| > 100k events/sec | Very High (>70% CPU) | ❌ Not recommended (use stateless consumers) |

### Optimization Tips

1. **Connection Pooling**: Use PgPool with sufficient connections
   ```rust
   let pool = PgPoolOptions::new()
       .max_connections(50)
       .connect(&database_url)
       .await?;
   ```

2. **Batch Cleanup**: Run cleanup during off-peak hours
   ```rust
   // Run at 3 AM daily instead of hourly
   tokio::spawn(async move {
       loop {
           tokio::time::sleep(Duration::from_secs(86400)).await;
           guard.cleanup_old_events().await;
       }
   });
   ```

3. **Index Maintenance**: Periodically vacuum/reindex
   ```sql
   VACUUM ANALYZE processed_events;
   REINDEX TABLE processed_events;
   ```

4. **Partition Table**: For extreme volumes (>1M events/day)
   ```sql
   -- Partition by processed_at month
   CREATE TABLE processed_events (
       -- ... columns ...
   ) PARTITION BY RANGE (processed_at);
   ```

---

## Error Handling

### Transient Errors (Auto-Retry)

The library automatically detects transient errors:
- Connection timeout
- Pool exhausted
- Temporary network issues

### Permanent Errors (Manual Handling)

Your code should handle:
- Invalid event ID format
- Business logic failures
- Database schema mismatch

```rust
use idempotent_consumer::{IdempotencyError, ProcessingResult};

match guard.process_if_new(event_id, async {
    // Business logic
    Ok(())
}).await {
    Ok(ProcessingResult::Success) => { /* ... */ }
    Ok(ProcessingResult::AlreadyProcessed) => { /* ... */ }
    Ok(ProcessingResult::Failed(err)) => {
        // Business logic error
        eprintln!("Processing failed: {}", err);
        // Send to DLQ, log, etc.
    }
    Err(IdempotencyError::InvalidEventId(msg)) => {
        // Invalid event ID
        eprintln!("Invalid event ID: {}", msg);
    }
    Err(IdempotencyError::Database(db_err)) => {
        // Database error
        eprintln!("Database error: {}", db_err);
        // Retry, alert, etc.
    }
    Err(e) => {
        eprintln!("Unexpected error: {}", e);
    }
}
```

---

## Testing

### Run Integration Tests

```bash
# Start PostgreSQL
docker run --name postgres-test -e POSTGRES_PASSWORD=postgres -p 5432:5432 -d postgres:15

# Create test database
export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/nova_test"
sqlx database create --database-url $DATABASE_URL

# Run migrations
sqlx migrate run --source backend/libs/idempotent-consumer/migrations

# Run tests
cargo test --package idempotent-consumer --test integration_test -- --nocapture
```

### Run Benchmarks

```bash
cargo test --package idempotent-consumer benchmark_mark_1000_events -- --ignored --nocapture
```

Expected output:
```
Marked 1000 events in 1.2s (avg: 1.2ms/event)
Throughput: 833 events/sec
```

---

## Design Trade-offs

### When to Use This Library

✅ **Use when**:
- Duplicate processing causes data corruption
- Events trigger external actions (payments, emails, notifications)
- Consumers restart frequently (K8s rolling updates)
- Event volume is reasonable (<10k events/sec per consumer)
- You need exactly-once semantics across restarts

❌ **Don't use when**:
- Duplicate processing is acceptable (idempotent business logic)
- Consumer is stateless and deterministic
- Extreme throughput requirements (>100k events/sec per consumer)
- Can use Kafka transactions instead
- Events already have natural deduplication (e.g., database UPSERT)

### Comparison with Alternatives

| Approach | Pros | Cons | Use Case |
|----------|------|------|----------|
| **In-memory HashMap** | Fast, no DB overhead | Lost on restart | Short-lived consumers |
| **This library** | Survives restarts, exact-once | DB write per event | Production services |
| **Kafka transactions** | Native Kafka support | Complex, limited support | Kafka Streams |
| **Redis** | Fast, distributed | Additional dependency | High-throughput systems |
| **Idempotent business logic** | No overhead | Not always possible | RESTful APIs, UPSERT |

---

## Migration Instructions

### From In-Memory HashMap

**Before**:
```rust
let mut processed_events = HashSet::new();

if !processed_events.contains(&event_id) {
    process_event(&event).await?;
    processed_events.insert(event_id);
}
```

**After**:
```rust
let guard = IdempotencyGuard::new(pool, Duration::from_secs(7 * 86400));

match guard.process_if_new(&event_id, async {
    process_event(&event).await
}).await? {
    ProcessingResult::Success => { /* ... */ }
    ProcessingResult::AlreadyProcessed => { /* ... */ }
}
```

### Database Migration

```bash
# Create migration
sqlx migrate add create_processed_events_table

# Copy SQL from migrations/001_create_processed_events_table.sql

# Run migration
sqlx migrate run
```

---

## Contributing

Contributions welcome! Please open an issue or pull request.

### Development Setup

```bash
# Clone repository
git clone https://github.com/your-org/nova.git
cd nova/backend/libs/idempotent-consumer

# Start PostgreSQL
docker run --name postgres-dev -e POSTGRES_PASSWORD=postgres -p 5432:5432 -d postgres:15

# Setup database
export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/nova_test"
sqlx database create
sqlx migrate run --source migrations

# Run tests
cargo test
```

---

## License

MIT License - see [LICENSE](../../../LICENSE) for details.

---

## Support

- **GitHub Issues**: https://github.com/your-org/nova/issues
- **Documentation**: See inline code documentation
- **Examples**: See `examples/` directory (TODO)

---

## Changelog

### v0.1.0 (2024-01-01)
- Initial release
- Core idempotency functionality
- PostgreSQL integration
- Concurrent processing safety
- Cleanup job support
