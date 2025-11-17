# Event Sourcing & Audit Trail Implementation Guide

**Status**: ✅ Ready for Implementation
**Technology**: Event Store + PostgreSQL
**Date**: 2025-11-09

---

## Overview

Event Sourcing is a pattern where state changes are stored as a sequence of immutable events. This provides complete audit trails, enables time travel debugging, and supports advanced patterns like CQRS (Command Query Responsibility Segregation).

### Benefits

- **Complete Audit Trail**: Every state change is recorded as an event
- **Time Travel**: Reconstruct state at any point in time
- **Event Replay**: Rebuild projections from event history
- **Debugging**: Understand exactly how system reached current state
- **Compliance**: Meet regulatory requirements for data tracking
- **Analytics**: Historical data analysis without impacting operational database

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Command Handler                                            │
│  - Validates command                                        │
│  - Loads aggregate from event stream                        │
│  - Applies business logic                                   │
│  - Generates events                                         │
└────────────────┬────────────────────────────────────────────┘
                 │ Events
                 ▼
┌─────────────────────────────────────────────────────────────┐
│  Event Store (Append-Only)                                  │
│  - Stores events in order                                   │
│  - Guarantees ordering                                      │
│  - Optimistic concurrency control                          │
│  - Event versioning                                         │
└────────────────┬────────────────────────────────────────────┘
                 │ Event Stream
     ┌───────────┼───────────┬────────────┬──────────────┐
     │           │           │            │              │
     ▼           ▼           ▼            ▼              ▼
┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────────┐
│  Read   │ │Analytics│ │Audit    │ │External │ │Notification │
│  Model  │ │  Model  │ │  Log    │ │ Systems │ │   Handler   │
│(Project)│ │(Project)│ │         │ │         │ │             │
└─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────────┘
```

---

## Core Concepts

### 1. Event

An immutable fact that happened in the past.

**Properties**:
- **Immutable**: Never modified after creation
- **Past Tense**: Named as things that happened (e.g., `UserCreated`, not `CreateUser`)
- **Complete**: Contains all data needed to reconstruct state
- **Versioned**: Schema evolution support

**Example Event**:
```rust
use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Event {
    /// Unique event ID
    pub event_id: Uuid,

    /// Aggregate ID this event belongs to
    pub aggregate_id: String,

    /// Aggregate type (e.g., "User", "Order")
    pub aggregate_type: String,

    /// Event type (e.g., "UserCreated", "OrderPlaced")
    pub event_type: String,

    /// Event version (for schema evolution)
    pub version: i32,

    /// Event sequence number within aggregate stream
    pub sequence_number: i64,

    /// Event data (JSON)
    pub data: serde_json::Value,

    /// Event metadata (user_id, correlation_id, etc.)
    pub metadata: Option<serde_json::Value>,

    /// Timestamp when event occurred
    pub timestamp: DateTime<Utc>,
}
```

### 2. Aggregate

Domain object that produces events.

**Characteristics**:
- **Consistency Boundary**: All changes within aggregate are atomic
- **Event Producer**: Generates events when commands are executed
- **State Reconstruction**: Rebuilds state by replaying events
- **Invariant Enforcement**: Validates business rules

**Example Aggregate**:
```rust
use anyhow::Result;

/// User aggregate
#[derive(Debug, Clone)]
pub struct UserAggregate {
    pub user_id: Uuid,
    pub username: String,
    pub email: String,
    pub is_active: bool,
    pub version: i64,  // Optimistic concurrency control
}

impl UserAggregate {
    /// Create new user (generates UserCreated event)
    pub fn create(
        user_id: Uuid,
        username: String,
        email: String,
    ) -> Result<(Self, Vec<Event>)> {
        // Validate
        if username.is_empty() {
            return Err(anyhow::anyhow!("Username cannot be empty"));
        }

        // Create aggregate
        let aggregate = Self {
            user_id,
            username: username.clone(),
            email: email.clone(),
            is_active: true,
            version: 0,
        };

        // Generate event
        let event = Event {
            event_id: Uuid::new_v4(),
            aggregate_id: user_id.to_string(),
            aggregate_type: "User".to_string(),
            event_type: "UserCreated".to_string(),
            version: 1,
            sequence_number: 1,
            data: serde_json::json!({
                "user_id": user_id,
                "username": username,
                "email": email,
            }),
            metadata: None,
            timestamp: Utc::now(),
        };

        Ok((aggregate, vec![event]))
    }

    /// Deactivate user (generates UserDeactivated event)
    pub fn deactivate(&mut self) -> Result<Vec<Event>> {
        if !self.is_active {
            return Err(anyhow::anyhow!("User already deactivated"));
        }

        self.is_active = false;
        self.version += 1;

        let event = Event {
            event_id: Uuid::new_v4(),
            aggregate_id: self.user_id.to_string(),
            aggregate_type: "User".to_string(),
            event_type: "UserDeactivated".to_string(),
            version: 1,
            sequence_number: self.version,
            data: serde_json::json!({
                "user_id": self.user_id,
            }),
            metadata: None,
            timestamp: Utc::now(),
        };

        Ok(vec![event])
    }

    /// Rebuild aggregate from event stream
    pub fn from_events(events: Vec<Event>) -> Result<Self> {
        let mut aggregate = None;

        for event in events {
            match event.event_type.as_str() {
                "UserCreated" => {
                    aggregate = Some(Self {
                        user_id: Uuid::parse_str(
                            event.data["user_id"].as_str().unwrap()
                        )?,
                        username: event.data["username"].as_str().unwrap().to_string(),
                        email: event.data["email"].as_str().unwrap().to_string(),
                        is_active: true,
                        version: event.sequence_number,
                    });
                }
                "UserDeactivated" => {
                    if let Some(ref mut agg) = aggregate {
                        agg.is_active = false;
                        agg.version = event.sequence_number;
                    }
                }
                _ => {}  // Unknown event, skip
            }
        }

        aggregate.ok_or_else(|| anyhow::anyhow!("No events found"))
    }
}
```

### 3. Event Store

Persistent storage for events.

**Implementation**:
```rust
// backend/libs/event-store/src/lib.rs
use async_trait::async_trait;
use sqlx::PgPool;
use anyhow::Result;

#[async_trait]
pub trait EventStore: Send + Sync {
    /// Append events to aggregate stream
    async fn append_events(
        &self,
        aggregate_id: &str,
        expected_version: i64,
        events: Vec<Event>,
    ) -> Result<()>;

    /// Load events for aggregate
    async fn load_events(
        &self,
        aggregate_id: &str,
    ) -> Result<Vec<Event>>;

    /// Load events from specific version
    async fn load_events_from_version(
        &self,
        aggregate_id: &str,
        from_version: i64,
    ) -> Result<Vec<Event>>;

    /// Get all events (for projections)
    async fn get_all_events(
        &self,
        from_sequence: i64,
        limit: i64,
    ) -> Result<Vec<Event>>;
}

pub struct PostgresEventStore {
    pool: PgPool,
}

impl PostgresEventStore {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl EventStore for PostgresEventStore {
    async fn append_events(
        &self,
        aggregate_id: &str,
        expected_version: i64,
        events: Vec<Event>,
    ) -> Result<()> {
        let mut tx = self.pool.begin().await?;

        // Check version (optimistic concurrency control)
        let current_version: Option<i64> = sqlx::query_scalar(
            "SELECT MAX(sequence_number) FROM events WHERE aggregate_id = $1"
        )
        .bind(aggregate_id)
        .fetch_optional(&mut *tx)
        .await?;

        let current_version = current_version.unwrap_or(0);
        if current_version != expected_version {
            return Err(anyhow::anyhow!(
                "Concurrency conflict: expected version {}, found {}",
                expected_version,
                current_version
            ));
        }

        // Insert events
        for event in events {
            sqlx::query(
                r#"
                INSERT INTO events (
                    event_id, aggregate_id, aggregate_type, event_type,
                    version, sequence_number, data, metadata, timestamp
                ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
                "#
            )
            .bind(event.event_id)
            .bind(&event.aggregate_id)
            .bind(&event.aggregate_type)
            .bind(&event.event_type)
            .bind(event.version)
            .bind(event.sequence_number)
            .bind(&event.data)
            .bind(&event.metadata)
            .bind(event.timestamp)
            .execute(&mut *tx)
            .await?;
        }

        tx.commit().await?;
        Ok(())
    }

    async fn load_events(
        &self,
        aggregate_id: &str,
    ) -> Result<Vec<Event>> {
        let events = sqlx::query_as::<_, Event>(
            r#"
            SELECT event_id, aggregate_id, aggregate_type, event_type,
                   version, sequence_number, data, metadata, timestamp
            FROM events
            WHERE aggregate_id = $1
            ORDER BY sequence_number ASC
            "#
        )
        .bind(aggregate_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(events)
    }

    async fn load_events_from_version(
        &self,
        aggregate_id: &str,
        from_version: i64,
    ) -> Result<Vec<Event>> {
        let events = sqlx::query_as::<_, Event>(
            r#"
            SELECT event_id, aggregate_id, aggregate_type, event_type,
                   version, sequence_number, data, metadata, timestamp
            FROM events
            WHERE aggregate_id = $1 AND sequence_number > $2
            ORDER BY sequence_number ASC
            "#
        )
        .bind(aggregate_id)
        .bind(from_version)
        .fetch_all(&self.pool)
        .await?;

        Ok(events)
    }

    async fn get_all_events(
        &self,
        from_sequence: i64,
        limit: i64,
    ) -> Result<Vec<Event>> {
        let events = sqlx::query_as::<_, Event>(
            r#"
            SELECT event_id, aggregate_id, aggregate_type, event_type,
                   version, sequence_number, data, metadata, timestamp
            FROM events
            WHERE global_sequence > $1
            ORDER BY global_sequence ASC
            LIMIT $2
            "#
        )
        .bind(from_sequence)
        .bind(limit)
        .fetch_all(&self.pool)
        .await?;

        Ok(events)
    }
}
```

### 4. Command Handler

Executes commands and generates events.

```rust
pub struct UserCommandHandler {
    event_store: Arc<dyn EventStore>,
}

impl UserCommandHandler {
    pub async fn handle_create_user(
        &self,
        user_id: Uuid,
        username: String,
        email: String,
    ) -> Result<()> {
        // Create aggregate and generate events
        let (_aggregate, events) = UserAggregate::create(user_id, username, email)?;

        // Append events to event store
        self.event_store
            .append_events(&user_id.to_string(), 0, events)
            .await?;

        Ok(())
    }

    pub async fn handle_deactivate_user(
        &self,
        user_id: Uuid,
    ) -> Result<()> {
        // Load aggregate from events
        let events = self.event_store.load_events(&user_id.to_string()).await?;
        let mut aggregate = UserAggregate::from_events(events)?;
        let expected_version = aggregate.version;

        // Execute command
        let new_events = aggregate.deactivate()?;

        // Append events
        self.event_store
            .append_events(&user_id.to_string(), expected_version, new_events)
            .await?;

        Ok(())
    }
}
```

### 5. Projections

Read models built from events.

```rust
/// Projection: User read model
#[derive(Debug, Clone)]
pub struct UserReadModel {
    pub user_id: Uuid,
    pub username: String,
    pub email: String,
    pub is_active: bool,
    pub created_at: DateTime<Utc>,
    pub last_updated: DateTime<Utc>,
}

/// Projection builder
pub struct UserProjection {
    pool: PgPool,
}

impl UserProjection {
    pub async fn handle_event(&self, event: &Event) -> Result<()> {
        match event.event_type.as_str() {
            "UserCreated" => {
                sqlx::query(
                    r#"
                    INSERT INTO user_read_model (
                        user_id, username, email, is_active, created_at, last_updated
                    ) VALUES ($1, $2, $3, $4, $5, $6)
                    "#
                )
                .bind(Uuid::parse_str(event.data["user_id"].as_str().unwrap())?)
                .bind(event.data["username"].as_str().unwrap())
                .bind(event.data["email"].as_str().unwrap())
                .bind(true)
                .bind(event.timestamp)
                .bind(event.timestamp)
                .execute(&self.pool)
                .await?;
            }
            "UserDeactivated" => {
                sqlx::query(
                    r#"
                    UPDATE user_read_model
                    SET is_active = false, last_updated = $2
                    WHERE user_id = $1
                    "#
                )
                .bind(Uuid::parse_str(event.data["user_id"].as_str().unwrap())?)
                .bind(event.timestamp)
                .execute(&self.pool)
                .await?;
            }
            _ => {}
        }
        Ok(())
    }

    /// Rebuild projection from scratch
    pub async fn rebuild(&self, event_store: &dyn EventStore) -> Result<()> {
        // Clear existing read model
        sqlx::query("DELETE FROM user_read_model")
            .execute(&self.pool)
            .await?;

        // Replay all events
        let mut from_sequence = 0;
        loop {
            let events = event_store.get_all_events(from_sequence, 1000).await?;
            if events.is_empty() {
                break;
            }

            for event in &events {
                self.handle_event(event).await?;
            }

            from_sequence = events.last().unwrap().sequence_number;
        }

        Ok(())
    }
}
```

---

## Database Schema

```sql
-- Event store table (append-only)
CREATE TABLE events (
    event_id UUID PRIMARY KEY,
    aggregate_id VARCHAR(255) NOT NULL,
    aggregate_type VARCHAR(100) NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    version INTEGER NOT NULL,
    sequence_number BIGINT NOT NULL,
    global_sequence BIGSERIAL,  -- Global ordering
    data JSONB NOT NULL,
    metadata JSONB,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_aggregate_sequence UNIQUE (aggregate_id, sequence_number)
);

-- Indexes for performance
CREATE INDEX idx_events_aggregate ON events(aggregate_id, sequence_number);
CREATE INDEX idx_events_type ON events(event_type);
CREATE INDEX idx_events_timestamp ON events(timestamp);
CREATE INDEX idx_events_global_sequence ON events(global_sequence);

-- Read model: User projection
CREATE TABLE user_read_model (
    user_id UUID PRIMARY KEY,
    username VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL,
    last_updated TIMESTAMPTZ NOT NULL
);

-- Projection checkpoint (track progress)
CREATE TABLE projection_checkpoints (
    projection_name VARCHAR(100) PRIMARY KEY,
    last_global_sequence BIGINT NOT NULL DEFAULT 0,
    last_updated TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

---

## Event Processor (Background Worker)

Processes events and updates projections in real-time.

```rust
use tokio::time::{interval, Duration};

pub struct EventProcessor {
    event_store: Arc<dyn EventStore>,
    projections: Vec<Arc<dyn Projection>>,
    checkpoint_interval: Duration,
}

#[async_trait]
pub trait Projection: Send + Sync {
    fn name(&self) -> &str;
    async fn handle_event(&self, event: &Event) -> Result<()>;
}

impl EventProcessor {
    pub async fn run(&self) -> Result<()> {
        let mut interval = interval(self.checkpoint_interval);

        loop {
            interval.tick().await;

            for projection in &self.projections {
                self.process_projection(projection.as_ref()).await?;
            }
        }
    }

    async fn process_projection(&self, projection: &dyn Projection) -> Result<()> {
        // Get last checkpoint
        let last_sequence = self.get_checkpoint(projection.name()).await?;

        // Get new events
        let events = self.event_store
            .get_all_events(last_sequence, 100)
            .await?;

        // Process events
        for event in &events {
            projection.handle_event(event).await?;
        }

        // Update checkpoint
        if let Some(last_event) = events.last() {
            self.save_checkpoint(projection.name(), last_event.global_sequence).await?;
        }

        Ok(())
    }
}
```

---

## Deployment

### Event Store Migration

```bash
# Create migration
sqlx migrate add create_event_store

# Run migration
sqlx migrate run
```

### Event Processor Service

```yaml
# k8s/microservices/event-processor/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: event-processor
spec:
  replicas: 1  # Single instance (avoid duplicate processing)
  selector:
    matchLabels:
      app: event-processor
  template:
    metadata:
      labels:
        app: event-processor
    spec:
      containers:
        - name: event-processor
          image: nova/event-processor:latest
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: postgres-secrets
                  key: url
            - name: CHECKPOINT_INTERVAL_MS
              value: "1000"  # Process every 1 second
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
```

---

## Best Practices

### 1. Event Naming

✅ **Good** (Past tense, descriptive):
```rust
UserCreated
UserEmailChanged
OrderPlaced
OrderShipped
PaymentProcessed
```

❌ **Bad** (Present tense, command-like):
```rust
CreateUser
ChangeUserEmail
PlaceOrder
```

### 2. Event Granularity

✅ **Good** (Fine-grained):
```rust
// Separate events for different changes
UserEmailChanged { new_email }
UserPasswordChanged { password_hash }
```

❌ **Bad** (Coarse-grained):
```rust
// Single event for multiple changes
UserUpdated { email, password, name, ... }
```

### 3. Event Versioning

```rust
// V1
#[derive(Serialize, Deserialize)]
pub struct UserCreatedV1 {
    pub user_id: Uuid,
    pub email: String,
}

// V2 (added username)
#[derive(Serialize, Deserialize)]
pub struct UserCreatedV2 {
    pub user_id: Uuid,
    pub username: String,
    pub email: String,
}

// Upcasting (convert old events to new format)
impl From<UserCreatedV1> for UserCreatedV2 {
    fn from(v1: UserCreatedV1) -> Self {
        Self {
            user_id: v1.user_id,
            username: v1.email.split('@').next().unwrap().to_string(),
            email: v1.email,
        }
    }
}
```

### 4. Idempotency

Ensure projections handle duplicate events:

```rust
pub async fn handle_user_created(&self, event: &Event) -> Result<()> {
    // Use INSERT ... ON CONFLICT DO NOTHING
    sqlx::query(
        r#"
        INSERT INTO user_read_model (user_id, username, email, created_at)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (user_id) DO NOTHING
        "#
    )
    .bind(user_id)
    .bind(username)
    .bind(email)
    .bind(created_at)
    .execute(&self.pool)
    .await?;

    Ok(())
}
```

---

## Use Cases

### 1. Audit Trail

Query all changes to a user:

```sql
SELECT event_type, data, timestamp
FROM events
WHERE aggregate_id = 'user-123'
ORDER BY sequence_number;
```

Result:
```
UserCreated    | {"email": "user@example.com"} | 2025-01-01 10:00:00
UserEmailChanged | {"new_email": "new@example.com"} | 2025-01-02 11:00:00
UserDeactivated | {} | 2025-01-03 12:00:00
```

### 2. Time Travel

Reconstruct user state at specific time:

```rust
pub async fn get_user_at_time(
    event_store: &dyn EventStore,
    user_id: Uuid,
    at_time: DateTime<Utc>,
) -> Result<UserAggregate> {
    let events = event_store.load_events(&user_id.to_string()).await?;

    // Filter events before target time
    let events_until = events
        .into_iter()
        .filter(|e| e.timestamp <= at_time)
        .collect();

    UserAggregate::from_events(events_until)
}
```

### 3. Compliance Reporting

Generate compliance report:

```sql
-- Users created in last month
SELECT COUNT(*)
FROM events
WHERE event_type = 'UserCreated'
  AND timestamp >= NOW() - INTERVAL '1 month';

-- Users deactivated with reasons
SELECT data->>'reason' as reason, COUNT(*)
FROM events
WHERE event_type = 'UserDeactivated'
GROUP BY data->>'reason';
```

---

## Performance Optimization

### 1. Snapshotting

Avoid replaying thousands of events:

```rust
pub struct Snapshot {
    pub aggregate_id: String,
    pub aggregate_type: String,
    pub version: i64,
    pub state: serde_json::Value,
    pub timestamp: DateTime<Utc>,
}

// Save snapshot every 100 events
pub async fn save_snapshot(
    pool: &PgPool,
    aggregate_id: &str,
    aggregate: &UserAggregate,
) -> Result<()> {
    if aggregate.version % 100 == 0 {
        sqlx::query(
            r#"
            INSERT INTO snapshots (aggregate_id, aggregate_type, version, state, timestamp)
            VALUES ($1, $2, $3, $4, NOW())
            "#
        )
        .bind(aggregate_id)
        .bind("User")
        .bind(aggregate.version)
        .bind(serde_json::to_value(aggregate)?)
        .execute(pool)
        .await?;
    }
    Ok(())
}

// Load from snapshot + replay remaining events
pub async fn load_aggregate_with_snapshot(
    event_store: &dyn EventStore,
    pool: &PgPool,
    aggregate_id: &str,
) -> Result<UserAggregate> {
    // Try to load snapshot
    let snapshot: Option<Snapshot> = sqlx::query_as(
        "SELECT * FROM snapshots WHERE aggregate_id = $1 ORDER BY version DESC LIMIT 1"
    )
    .bind(aggregate_id)
    .fetch_optional(pool)
    .await?;

    if let Some(snapshot) = snapshot {
        // Load aggregate from snapshot
        let mut aggregate: UserAggregate = serde_json::from_value(snapshot.state)?;

        // Replay events after snapshot
        let events = event_store
            .load_events_from_version(aggregate_id, snapshot.version)
            .await?;

        for event in events {
            aggregate.apply_event(&event)?;
        }

        Ok(aggregate)
    } else {
        // No snapshot, load from all events
        let events = event_store.load_events(aggregate_id).await?;
        UserAggregate::from_events(events)
    }
}
```

### 2. Caching

Cache frequently accessed aggregates:

```rust
use std::sync::Arc;
use tokio::sync::RwLock;
use std::collections::HashMap;

pub struct AggregateCache {
    cache: Arc<RwLock<HashMap<String, (UserAggregate, DateTime<Utc>)>>>,
    ttl: Duration,
}

impl AggregateCache {
    pub async fn get_or_load(
        &self,
        aggregate_id: &str,
        event_store: &dyn EventStore,
    ) -> Result<UserAggregate> {
        // Check cache
        {
            let cache = self.cache.read().await;
            if let Some((aggregate, cached_at)) = cache.get(aggregate_id) {
                if Utc::now() - *cached_at < self.ttl {
                    return Ok(aggregate.clone());
                }
            }
        }

        // Load from event store
        let events = event_store.load_events(aggregate_id).await?;
        let aggregate = UserAggregate::from_events(events)?;

        // Update cache
        {
            let mut cache = self.cache.write().await;
            cache.insert(aggregate_id.to_string(), (aggregate.clone(), Utc::now()));
        }

        Ok(aggregate)
    }
}
```

---

## Monitoring

### Key Metrics

```rust
// Event processing lag
gauge!("event_processor.lag", last_global_sequence - last_processed_sequence);

// Events per second
counter!("events.appended", 1, "aggregate_type" => aggregate_type);

// Projection rebuild time
histogram!("projection.rebuild_duration_seconds", rebuild_duration.as_secs_f64());

// Concurrency conflicts
counter!("event_store.concurrency_conflicts", 1);
```

### Alerts

```yaml
# Alert if event processing lag > 10000 events
- alert: EventProcessorLagging
  expr: event_processor_lag > 10000
  for: 5m
  labels:
    severity: warning

# Alert if concurrency conflicts spike
- alert: HighConcurrencyConflicts
  expr: rate(event_store_concurrency_conflicts_total[5m]) > 10
  for: 10m
  labels:
    severity: warning
```

---

## Integration with Distributed Tracing

```rust
use opentelemetry::trace::{Tracer, SpanKind};
use tracing::instrument;

#[instrument(skip(self, events), fields(otel.kind = ?SpanKind::Internal))]
pub async fn append_events(
    &self,
    aggregate_id: &str,
    expected_version: i64,
    events: Vec<Event>,
) -> Result<()> {
    tracing::info!(
        aggregate_id = %aggregate_id,
        expected_version = expected_version,
        event_count = events.len(),
        "Appending events"
    );

    // Existing implementation...
}
```

---

## Next Steps

1. **✅ Implement Event Store Library** - Core event persistence
2. **Create Example Service** - User service with event sourcing
3. **Build Projections** - Read models for queries
4. **Deploy Event Processor** - Background worker for projections
5. **Add Monitoring** - Metrics and dashboards

---

## References

- Event Sourcing Pattern: https://martinfowler.com/eaaDev/EventSourcing.html
- CQRS: https://martinfowler.com/bliki/CQRS.html
- Event Store: https://www.eventstore.com/

---

**Document Version**: 1.0
**Last Updated**: 2025-11-09
**Status**: Ready for Implementation
