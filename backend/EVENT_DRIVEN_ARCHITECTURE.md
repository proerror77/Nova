# 事件驱动架构实施方案

**Date**: 2025-11-11
**Author**: System Architect (Following Linus Principles)
**Status**: Ready for Implementation

---

## 核心原则

"Talk is cheap. Show me the code."

事件驱动不是目的，解耦才是。如果同步调用更简单，就用同步。

---

## 事件分类

### 1. Domain Events (业务事件)
```rust
// 改变系统状态的事件
pub enum DomainEvent {
    // User Domain
    UserCreated { user_id: Uuid, email: String, created_at: DateTime<Utc> },
    UserUpdated { user_id: Uuid, changes: Vec<FieldChange> },
    UserDeleted { user_id: Uuid, deleted_at: DateTime<Utc> },
    UserRoleAssigned { user_id: Uuid, role_id: Uuid },

    // Content Domain
    PostCreated { post_id: Uuid, author_id: Uuid, created_at: DateTime<Utc> },
    PostUpdated { post_id: Uuid, editor_id: Uuid, version: i32 },
    PostDeleted { post_id: Uuid, deleted_by: Uuid },
    CommentAdded { comment_id: Uuid, post_id: Uuid, author_id: Uuid },

    // Social Domain
    UserFollowed { follower_id: Uuid, followed_id: Uuid },
    PostLiked { post_id: Uuid, user_id: Uuid },
    PostShared { post_id: Uuid, sharer_id: Uuid },
}
```

### 2. Integration Events (集成事件)
```rust
// 跨服务通信事件
pub enum IntegrationEvent {
    // 需要其他服务响应的事件
    UserProfileCompleted { user_id: Uuid }, // -> Trigger welcome email
    PaymentProcessed { order_id: Uuid },    // -> Trigger order fulfillment
    ContentFlagged { content_id: Uuid },    // -> Trigger moderation
}
```

### 3. System Events (系统事件)
```rust
// 技术层面的事件
pub enum SystemEvent {
    ServiceStarted { service: String, version: String },
    ServiceStopped { service: String, reason: String },
    HealthCheckFailed { service: String, error: String },
    RateLimitExceeded { client_id: String, endpoint: String },
}
```

---

## 事件总线实现

### 基础架构

```rust
// backend/common/src/events/mod.rs
use async_trait::async_trait;
use serde::{Serialize, Deserialize};
use uuid::Uuid;
use chrono::{DateTime, Utc};

/// Event metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventMetadata {
    pub event_id: Uuid,
    pub event_type: String,
    pub source_service: String,
    pub timestamp: DateTime<Utc>,
    pub correlation_id: Option<Uuid>,
    pub causation_id: Option<Uuid>,
    pub user_id: Option<Uuid>,
}

/// Event envelope
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventEnvelope<T> {
    pub metadata: EventMetadata,
    pub payload: T,
}

/// Event publisher trait
#[async_trait]
pub trait EventPublisher: Send + Sync {
    async fn publish<T>(&self, event: EventEnvelope<T>) -> Result<(), EventError>
    where
        T: Serialize + Send;

    async fn publish_batch<T>(&self, events: Vec<EventEnvelope<T>>) -> Result<(), EventError>
    where
        T: Serialize + Send;
}

/// Event subscriber trait
#[async_trait]
pub trait EventSubscriber: Send + Sync {
    async fn subscribe(&self, topics: Vec<String>) -> Result<(), EventError>;
    async fn unsubscribe(&self, topics: Vec<String>) -> Result<(), EventError>;
}

/// Event handler trait
#[async_trait]
pub trait EventHandler<T>: Send + Sync
where
    T: for<'de> Deserialize<'de>,
{
    async fn handle(&self, event: EventEnvelope<T>) -> Result<(), EventError>;
    fn event_type(&self) -> &str;
}
```

### Kafka 实现

```rust
// backend/common/src/events/kafka.rs
use rdkafka::producer::{FutureProducer, FutureRecord};
use rdkafka::consumer::{StreamConsumer, Consumer};
use rdkafka::Message;
use futures::stream::StreamExt;

pub struct KafkaEventBus {
    producer: FutureProducer,
    consumer: StreamConsumer,
    handlers: Arc<RwLock<HashMap<String, Box<dyn EventHandler<serde_json::Value>>>>>,
}

impl KafkaEventBus {
    pub fn new(brokers: &str) -> Result<Self, EventError> {
        let producer: FutureProducer = ClientConfig::new()
            .set("bootstrap.servers", brokers)
            .set("message.timeout.ms", "5000")
            .set("compression.type", "snappy")
            .set("batch.size", "16384")
            .set("linger.ms", "10")
            .create()
            .map_err(|e| EventError::ConnectionFailed(e.to_string()))?;

        let consumer: StreamConsumer = ClientConfig::new()
            .set("bootstrap.servers", brokers)
            .set("group.id", "service-group")
            .set("enable.auto.commit", "false")
            .set("auto.offset.reset", "earliest")
            .create()
            .map_err(|e| EventError::ConnectionFailed(e.to_string()))?;

        Ok(Self {
            producer,
            consumer,
            handlers: Arc::new(RwLock::new(HashMap::new())),
        })
    }

    pub fn register_handler<T, H>(&self, handler: H)
    where
        T: DeserializeOwned + 'static,
        H: EventHandler<T> + 'static,
    {
        let event_type = handler.event_type().to_string();
        self.handlers.write().await.insert(event_type, Box::new(handler));
    }

    pub async fn start_consuming(&self) {
        let mut stream = self.consumer.stream();

        while let Some(message) = stream.next().await {
            match message {
                Ok(msg) => {
                    if let Some(payload) = msg.payload() {
                        self.process_message(payload).await;
                    }

                    // Commit offset after successful processing
                    self.consumer.commit_message(&msg, CommitMode::Async).ok();
                }
                Err(e) => {
                    error!("Error consuming message: {:?}", e);
                }
            }
        }
    }

    async fn process_message(&self, payload: &[u8]) {
        match serde_json::from_slice::<EventEnvelope<serde_json::Value>>(payload) {
            Ok(envelope) => {
                let handlers = self.handlers.read().await;

                if let Some(handler) = handlers.get(&envelope.metadata.event_type) {
                    if let Err(e) = handler.handle(envelope).await {
                        error!("Handler error for {}: {:?}", envelope.metadata.event_type, e);
                    }
                }
            }
            Err(e) => {
                error!("Failed to deserialize event: {:?}", e);
            }
        }
    }
}

#[async_trait]
impl EventPublisher for KafkaEventBus {
    async fn publish<T>(&self, event: EventEnvelope<T>) -> Result<(), EventError>
    where
        T: Serialize + Send,
    {
        let topic = format!("events.{}", event.metadata.event_type);
        let key = event.metadata.event_id.to_string();
        let payload = serde_json::to_vec(&event)
            .map_err(|e| EventError::SerializationFailed(e.to_string()))?;

        let record = FutureRecord::to(&topic)
            .key(&key)
            .payload(&payload);

        self.producer
            .send(record, Duration::from_secs(5))
            .await
            .map_err(|(e, _)| EventError::PublishFailed(e.to_string()))?;

        Ok(())
    }

    async fn publish_batch<T>(&self, events: Vec<EventEnvelope<T>>) -> Result<(), EventError>
    where
        T: Serialize + Send,
    {
        for event in events {
            self.publish(event).await?;
        }
        Ok(())
    }
}
```

---

## 事件溯源 (Event Sourcing)

### Event Store 实现

```rust
// backend/common/src/events/store.rs
use sqlx::PgPool;

pub struct EventStore {
    pool: PgPool,
}

impl EventStore {
    pub async fn append<T>(&self, event: EventEnvelope<T>) -> Result<(), EventError>
    where
        T: Serialize,
    {
        let payload = serde_json::to_value(&event.payload)?;

        sqlx::query!(
            r#"
            INSERT INTO domain_events (
                event_id, event_type, source_service,
                timestamp, correlation_id, causation_id,
                user_id, payload
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            "#,
            event.metadata.event_id,
            event.metadata.event_type,
            event.metadata.source_service,
            event.metadata.timestamp,
            event.metadata.correlation_id,
            event.metadata.causation_id,
            event.metadata.user_id,
            payload
        )
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    pub async fn get_events_for_aggregate(
        &self,
        aggregate_id: Uuid,
        after_version: Option<i64>,
    ) -> Result<Vec<EventEnvelope<serde_json::Value>>, EventError> {
        let events = sqlx::query_as!(
            StoredEvent,
            r#"
            SELECT event_id, event_type, source_service,
                   timestamp, correlation_id, causation_id,
                   user_id, payload, version
            FROM domain_events
            WHERE aggregate_id = $1
            AND ($2::BIGINT IS NULL OR version > $2)
            ORDER BY version ASC
            "#,
            aggregate_id,
            after_version
        )
        .fetch_all(&self.pool)
        .await?;

        Ok(events.into_iter().map(Into::into).collect())
    }

    pub async fn get_snapshot(
        &self,
        aggregate_id: Uuid,
    ) -> Result<Option<AggregateSnapshot>, EventError> {
        let snapshot = sqlx::query_as!(
            AggregateSnapshot,
            r#"
            SELECT aggregate_id, version, data, created_at
            FROM aggregate_snapshots
            WHERE aggregate_id = $1
            ORDER BY version DESC
            LIMIT 1
            "#,
            aggregate_id
        )
        .fetch_optional(&self.pool)
        .await?;

        Ok(snapshot)
    }

    pub async fn save_snapshot(
        &self,
        aggregate_id: Uuid,
        version: i64,
        data: serde_json::Value,
    ) -> Result<(), EventError> {
        sqlx::query!(
            r#"
            INSERT INTO aggregate_snapshots (aggregate_id, version, data)
            VALUES ($1, $2, $3)
            ON CONFLICT (aggregate_id, version) DO NOTHING
            "#,
            aggregate_id,
            version,
            data
        )
        .execute(&self.pool)
        .await?;

        Ok(())
    }
}
```

---

## 服务集成示例

### 1. User Service 发布事件

```rust
// user-service/src/handlers.rs
impl UserService {
    pub async fn create_user(&self, req: CreateUserRequest) -> Result<User> {
        // Begin transaction
        let mut tx = self.pool.begin().await?;

        // Create user
        let user = sqlx::query_as!(User,
            "INSERT INTO users (id, email, username) VALUES ($1, $2, $3) RETURNING *",
            Uuid::new_v4(),
            req.email,
            req.username
        )
        .fetch_one(&mut *tx)
        .await?;

        // Create event
        let event = EventEnvelope {
            metadata: EventMetadata {
                event_id: Uuid::new_v4(),
                event_type: "user.created".to_string(),
                source_service: "user-service".to_string(),
                timestamp: Utc::now(),
                correlation_id: self.correlation_id,
                causation_id: None,
                user_id: Some(user.id),
            },
            payload: UserCreatedEvent {
                user_id: user.id,
                email: user.email.clone(),
                username: user.username.clone(),
                created_at: user.created_at,
            },
        };

        // Store event in outbox (transactional outbox pattern)
        sqlx::query!(
            "INSERT INTO outbox_events (event_id, payload) VALUES ($1, $2)",
            event.metadata.event_id,
            serde_json::to_value(&event)?
        )
        .execute(&mut *tx)
        .await?;

        // Commit transaction
        tx.commit().await?;

        // Publish event (async, non-blocking)
        tokio::spawn(async move {
            if let Err(e) = self.event_bus.publish(event).await {
                error!("Failed to publish event: {:?}", e);
                // Event will be retried by outbox processor
            }
        });

        Ok(user)
    }
}
```

### 2. Content Service 订阅事件

```rust
// content-service/src/event_handlers.rs
pub struct UserCreatedHandler {
    cache: Arc<Cache>,
}

#[async_trait]
impl EventHandler<UserCreatedEvent> for UserCreatedHandler {
    async fn handle(&self, event: EventEnvelope<UserCreatedEvent>) -> Result<(), EventError> {
        // Update local user projection
        self.cache.set(
            format!("user:{}", event.payload.user_id),
            UserProjection {
                id: event.payload.user_id,
                username: event.payload.username,
                email: event.payload.email,
            },
            Duration::hours(24),
        ).await?;

        info!("Updated user projection for user {}", event.payload.user_id);
        Ok(())
    }

    fn event_type(&self) -> &str {
        "user.created"
    }
}
```

### 3. Saga 编排

```rust
// backend/common/src/saga.rs
pub struct OrderSaga {
    event_bus: Arc<dyn EventPublisher>,
    state_store: Arc<SagaStateStore>,
}

impl OrderSaga {
    pub async fn handle_order_created(&self, event: OrderCreatedEvent) -> Result<()> {
        // Start saga
        let saga_id = Uuid::new_v4();
        self.state_store.create_saga(saga_id, "order_fulfillment").await?;

        // Step 1: Reserve inventory
        self.event_bus.publish(EventEnvelope {
            metadata: EventMetadata::new("inventory.reserve_requested"),
            payload: ReserveInventoryCommand {
                saga_id,
                order_id: event.order_id,
                items: event.items,
            },
        }).await?;

        Ok(())
    }

    pub async fn handle_inventory_reserved(&self, event: InventoryReservedEvent) -> Result<()> {
        // Step 2: Process payment
        self.event_bus.publish(EventEnvelope {
            metadata: EventMetadata::new("payment.charge_requested"),
            payload: ChargePaymentCommand {
                saga_id: event.saga_id,
                order_id: event.order_id,
                amount: event.total_amount,
            },
        }).await?;

        Ok(())
    }

    pub async fn handle_payment_failed(&self, event: PaymentFailedEvent) -> Result<()> {
        // Compensate: Release inventory
        self.event_bus.publish(EventEnvelope {
            metadata: EventMetadata::new("inventory.release_requested"),
            payload: ReleaseInventoryCommand {
                saga_id: event.saga_id,
                order_id: event.order_id,
            },
        }).await?;

        // Mark saga as failed
        self.state_store.fail_saga(event.saga_id).await?;

        Ok(())
    }
}
```

---

## Outbox Pattern 实现

```rust
// backend/common/src/outbox.rs
pub struct OutboxProcessor {
    pool: PgPool,
    event_bus: Arc<dyn EventPublisher>,
}

impl OutboxProcessor {
    pub async fn start(&self) {
        let mut interval = tokio::time::interval(Duration::from_secs(5));

        loop {
            interval.tick().await;
            if let Err(e) = self.process_outbox().await {
                error!("Outbox processing error: {:?}", e);
            }
        }
    }

    async fn process_outbox(&self) -> Result<()> {
        // Get unpublished events
        let events = sqlx::query!(
            r#"
            SELECT event_id, payload, retry_count
            FROM outbox_events
            WHERE published = false
            AND retry_count < 3
            ORDER BY created_at
            LIMIT 100
            FOR UPDATE SKIP LOCKED
            "#
        )
        .fetch_all(&self.pool)
        .await?;

        for record in events {
            let event: EventEnvelope<serde_json::Value> =
                serde_json::from_value(record.payload)?;

            match self.event_bus.publish(event).await {
                Ok(_) => {
                    // Mark as published
                    sqlx::query!(
                        "UPDATE outbox_events SET published = true WHERE event_id = $1",
                        record.event_id
                    )
                    .execute(&self.pool)
                    .await?;
                }
                Err(e) => {
                    // Increment retry count
                    sqlx::query!(
                        "UPDATE outbox_events SET retry_count = retry_count + 1 WHERE event_id = $1",
                        record.event_id
                    )
                    .execute(&self.pool)
                    .await?;

                    error!("Failed to publish event {}: {:?}", record.event_id, e);
                }
            }
        }

        Ok(())
    }
}
```

---

## 数据库 Schema

```sql
-- Event store tables
CREATE TABLE domain_events (
    event_id UUID PRIMARY KEY,
    event_type VARCHAR(100) NOT NULL,
    source_service VARCHAR(50) NOT NULL,
    aggregate_id UUID,
    version BIGSERIAL,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    correlation_id UUID,
    causation_id UUID,
    user_id UUID,
    payload JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    INDEX idx_events_aggregate (aggregate_id, version),
    INDEX idx_events_type (event_type),
    INDEX idx_events_timestamp (timestamp DESC),
    INDEX idx_events_correlation (correlation_id)
);

-- Outbox pattern
CREATE TABLE outbox_events (
    event_id UUID PRIMARY KEY,
    payload JSONB NOT NULL,
    published BOOLEAN DEFAULT false,
    retry_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    published_at TIMESTAMP WITH TIME ZONE,

    INDEX idx_outbox_unpublished (published, created_at)
);

-- Aggregate snapshots for event sourcing
CREATE TABLE aggregate_snapshots (
    aggregate_id UUID NOT NULL,
    version BIGINT NOT NULL,
    data JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (aggregate_id, version),
    INDEX idx_snapshots_aggregate (aggregate_id, version DESC)
);

-- Saga state management
CREATE TABLE saga_state (
    saga_id UUID PRIMARY KEY,
    saga_type VARCHAR(100) NOT NULL,
    current_step VARCHAR(100) NOT NULL,
    state JSONB NOT NULL,
    started_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP WITH TIME ZONE,
    failed_at TIMESTAMP WITH TIME ZONE,
    error_message TEXT,

    INDEX idx_saga_type (saga_type),
    INDEX idx_saga_status (completed_at, failed_at)
);
```

---

## 监控和告警

```yaml
# prometheus metrics
event_metrics:
  - name: events_published_total
    type: counter
    labels: [event_type, service]

  - name: events_consumed_total
    type: counter
    labels: [event_type, service]

  - name: event_processing_duration
    type: histogram
    labels: [event_type, handler]

  - name: outbox_queue_size
    type: gauge

  - name: saga_duration
    type: histogram
    labels: [saga_type]

alerts:
  - name: EventPublishingFailed
    expr: rate(event_publish_failures[5m]) > 0.1
    severity: critical

  - name: EventProcessingLag
    expr: event_queue_lag_seconds > 60
    severity: warning

  - name: OutboxBacklog
    expr: outbox_queue_size > 1000
    severity: critical
```

---

## 测试策略

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_event_publishing() {
        let event_bus = MockEventBus::new();
        let service = UserService::new(event_bus.clone());

        let user = service.create_user(CreateUserRequest {
            email: "test@example.com".to_string(),
            username: "test".to_string(),
        }).await.unwrap();

        // Verify event was published
        let published_events = event_bus.get_published_events().await;
        assert_eq!(published_events.len(), 1);

        let event = &published_events[0];
        assert_eq!(event.metadata.event_type, "user.created");
    }

    #[tokio::test]
    async fn test_event_handler() {
        let handler = UserCreatedHandler::new();
        let event = EventEnvelope {
            metadata: EventMetadata::new("user.created"),
            payload: UserCreatedEvent {
                user_id: Uuid::new_v4(),
                email: "test@example.com".to_string(),
                username: "test".to_string(),
                created_at: Utc::now(),
            },
        };

        let result = handler.handle(event).await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_saga_compensation() {
        let saga = OrderSaga::new();

        // Simulate payment failure
        let event = PaymentFailedEvent {
            saga_id: Uuid::new_v4(),
            order_id: Uuid::new_v4(),
            reason: "Insufficient funds".to_string(),
        };

        saga.handle_payment_failed(event).await.unwrap();

        // Verify compensation event was published
        // ...
    }
}
```

---

## 成功指标

- Event publishing latency < 10ms (P99)
- Event processing latency < 100ms (P99)
- Zero event loss (exactly-once delivery)
- Outbox processing interval < 5s
- Saga completion rate > 99%

---

"Linus says: Don't over-engineer. Start simple, evolve as needed."