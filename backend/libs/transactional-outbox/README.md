# Transactional Outbox Pattern Library

Production-ready implementation of the Transactional Outbox pattern for reliable event publishing in the Nova backend system.

## Overview

The Transactional Outbox pattern ensures that database writes and event publishing happen atomically, preventing data inconsistencies and event loss in distributed systems.

### Problem Statement

Without this pattern:
- **Lost events**: Database commits but event publishing fails → data divergence
- **Duplicate events**: Publishing succeeds but database commit fails → inconsistency
- **Split brain**: Different services see different versions of truth

### Solution

The Transactional Outbox pattern guarantees **at-least-once delivery** by:
1. Storing events in an outbox table within the same database transaction as business logic
2. A background processor polls for unpublished events
3. Events are published to Kafka with idempotent producer settings
4. Events are marked as published only after successful Kafka delivery

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Service Layer                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────────┐      ┌──────────────────────┐       │
│  │  Business Logic      │      │   Outbox Event       │       │
│  │  (INSERT user)       │──┬──▶│   (user.created)     │       │
│  └──────────────────────┘  │   └──────────────────────┘       │
│                             │                                   │
│                       Database Transaction                      │
│                          (ACID Guaranteed)                      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
              ┌─────────────────────────────────┐
              │     Outbox Processor            │
              │  (Background Worker)            │
              │                                 │
              │  1. Poll unpublished events     │
              │  2. Publish to Kafka            │
              │  3. Mark as published           │
              │  4. Retry with backoff          │
              └─────────────────────────────────┘
                              │
                              ▼
              ┌─────────────────────────────────┐
              │          Kafka                  │
              │  (Idempotent Producer)          │
              │                                 │
              │  Topics: nova.{aggregate}.events│
              └─────────────────────────────────┘
```

## Database Schema

The library requires an `outbox_events` table with the following schema:

```sql
CREATE TABLE outbox_events (
    id UUID PRIMARY KEY,
    aggregate_type VARCHAR(255) NOT NULL,
    aggregate_id UUID NOT NULL,
    event_type VARCHAR(255) NOT NULL,
    payload JSONB NOT NULL,
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL,
    published_at TIMESTAMPTZ,
    retry_count INT NOT NULL DEFAULT 0,
    last_error TEXT
);
```

Run the migration:
```bash
psql -U your_user -d your_database -f migrations/001_create_outbox_table.sql
```

## Usage

### 1. Insert Event in Transaction

```rust
use transactional_outbox::{OutboxEvent, OutboxRepository, SqlxOutboxRepository};
use sqlx::PgPool;
use uuid::Uuid;
use chrono::Utc;

async fn create_user(
    pool: &PgPool,
    outbox_repo: &SqlxOutboxRepository,
    username: String,
) -> Result<(), Box<dyn std::error::Error>> {
    // Start transaction
    let mut tx = pool.begin().await?;

    // 1. Business logic (insert user)
    let user_id = Uuid::new_v4();
    sqlx::query!(
        "INSERT INTO users (id, username) VALUES ($1, $2)",
        user_id,
        username
    )
    .execute(&mut *tx)
    .await?;

    // 2. Insert event (same transaction!)
    let event = OutboxEvent {
        id: Uuid::new_v4(),
        aggregate_type: "user".to_string(),
        aggregate_id: user_id,
        event_type: "user.created".to_string(),
        payload: serde_json::json!({
            "user_id": user_id,
            "username": username,
        }),
        metadata: Some(serde_json::json!({
            "correlation_id": Uuid::new_v4(),
        })),
        created_at: Utc::now(),
        published_at: None,
        retry_count: 0,
        last_error: None,
    };

    outbox_repo.insert(&mut tx, &event).await?;

    // 3. Commit (both user and event saved atomically)
    tx.commit().await?;

    Ok(())
}
```

### 2. Using Helper Macros

```rust
use transactional_outbox::{publish_event, publish_event_with_metadata};

// Simple event
publish_event!(
    &mut tx,
    &outbox_repo,
    "user",
    user_id,
    "user.created",
    json!({ "user_id": user_id, "username": "alice" })
);

// Event with metadata
publish_event_with_metadata!(
    &mut tx,
    &outbox_repo,
    "content",
    content_id,
    "content.published",
    json!({ "content_id": content_id }),
    json!({ "correlation_id": correlation_id, "user_id": user_id })
);
```

### 3. Start Background Processor

```rust
use transactional_outbox::{
    OutboxProcessor, SqlxOutboxRepository, KafkaOutboxPublisher
};
use rdkafka::producer::FutureProducer;
use rdkafka::ClientConfig;
use std::sync::Arc;
use std::time::Duration;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize database pool
    let pool = PgPool::connect("postgresql://localhost/mydb").await?;

    // Initialize Kafka producer with IDEMPOTENCE ENABLED
    let producer: FutureProducer = ClientConfig::new()
        .set("bootstrap.servers", "localhost:9092")
        .set("enable.idempotence", "true")    // ⚠️ CRITICAL
        .set("acks", "all")                   // ⚠️ CRITICAL
        .set("max.in.flight.requests.per.connection", "5")
        .create()?;

    // Create repository and publisher
    let repository = Arc::new(SqlxOutboxRepository::new(pool));
    let publisher = Arc::new(KafkaOutboxPublisher::new(
        producer,
        "nova".to_string(), // topic prefix
    ));

    // Create and start processor
    let processor = OutboxProcessor::new(
        repository,
        publisher,
        100,                          // batch_size: process 100 events per poll
        Duration::from_secs(5),       // poll_interval: check every 5 seconds
        5,                            // max_retries: retry up to 5 times
    );

    // Run processor (blocks forever)
    processor.start().await?;

    Ok(())
}
```

## Kafka Configuration

**CRITICAL**: The Kafka producer MUST be configured with idempotence enabled:

```rust
ClientConfig::new()
    .set("enable.idempotence", "true")
    .set("acks", "all")
    .set("max.in.flight.requests.per.connection", "5")
    .create()?
```

This prevents duplicate messages even if the processor crashes after publishing but before marking the event as published.

## Event Flow

1. **Business Transaction**: Service inserts data + event in same transaction
2. **Commit**: Database commits atomically (both succeed or both fail)
3. **Polling**: Background processor polls for unpublished events every N seconds
4. **Publishing**: Processor publishes event to Kafka topic
5. **Marking**: If publish succeeds, event is marked as published
6. **Retry**: If publish fails, event is retried with exponential backoff

## Retry Strategy

The processor implements exponential backoff:

- Retry 0: 1 second
- Retry 1: 2 seconds
- Retry 2: 4 seconds
- Retry 3: 8 seconds
- Retry 4: 16 seconds
- Retry 5+: 300 seconds (5 minutes, capped)

After `max_retries` attempts, events are skipped and require manual intervention.

## Topic Mapping

Events are mapped to Kafka topics based on aggregate type:

| Event Type | Kafka Topic |
|-----------|-------------|
| `user.created` | `nova.user.events` |
| `content.published` | `nova.content.events` |
| `feed.item.added` | `nova.feed.events` |

## Monitoring

The processor emits structured logs with tracing:

```rust
// Success
info!(event_id=%id, event_type=%type, topic=%topic, "Event published to Kafka");

// Failure
error!(event_id=%id, retry_count=%count, error=?err, "Failed to publish event");

// Max retries exceeded
warn!(event_id=%id, retry_count=%count, "Event exceeded max retries, requires manual intervention");
```

Monitor these metrics:
- Events published per minute
- Events pending in outbox
- Events exceeding max retries (requires alerts)
- Average publish latency

## Testing

Run unit tests:
```bash
cargo test -p transactional-outbox
```

## Integration with Services

### User Service Example

```rust
// user-service/src/service.rs
use transactional_outbox::{publish_event, SqlxOutboxRepository};

pub struct UserService {
    pool: PgPool,
    outbox_repo: Arc<SqlxOutboxRepository>,
}

impl UserService {
    pub async fn create_user(&self, username: String) -> Result<Uuid> {
        let mut tx = self.pool.begin().await?;

        let user_id = Uuid::new_v4();

        // Insert user
        sqlx::query!("INSERT INTO users (id, username) VALUES ($1, $2)", user_id, username)
            .execute(&mut *tx)
            .await?;

        // Publish event
        publish_event!(
            &mut tx,
            &self.outbox_repo,
            "user",
            user_id,
            "user.created",
            json!({ "user_id": user_id, "username": username })
        );

        tx.commit().await?;
        Ok(user_id)
    }
}
```

## Security Considerations

- **No PII in logs**: Events may contain sensitive data, structured logging redacts PII
- **Payload validation**: Validate event payloads before insertion
- **Access control**: Only authorized services should access outbox table
- **Audit trail**: All events are preserved for compliance

## Performance

- **Batch processing**: Processor fetches multiple events per poll (configurable)
- **Indexed queries**: Partial index on `published_at IS NULL` for fast lookups
- **Connection pooling**: Uses sqlx connection pool for optimal throughput
- **Backpressure**: Processor respects Kafka backpressure signals

## Limitations

- **At-least-once delivery**: Events may be delivered multiple times (design for idempotent consumers)
- **Ordering**: Only guaranteed per `aggregate_id` (partition key)
- **Manual intervention**: Events exceeding `max_retries` require manual resolution
- **Storage growth**: Consider archiving old published events

## References

- [Transactional Outbox Pattern (Microservices.io)](https://microservices.io/patterns/data/transactional-outbox.html)
- [Kafka Idempotent Producer](https://kafka.apache.org/documentation/#producerconfigs_enable.idempotence)
- [Event Sourcing vs Transactional Outbox](https://martinfowler.com/eaaDev/EventSourcing.html)

## License

MIT
