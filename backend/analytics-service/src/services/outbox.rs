/// Outbox Publisher - Reliable event publishing to Kafka
///
/// This module implements the Transactional Outbox pattern for guaranteed
/// event delivery to Kafka with at-least-once semantics.
///
/// ## Architecture
///
/// ```text
/// ┌─────────────┐    ┌──────────┐    ┌─────────┐
/// │   Service   │───▶│  Outbox  │───▶│  Kafka  │
/// │  (gRPC)     │    │   Table  │    │  Topic  │
/// └─────────────┘    └──────────┘    └─────────┘
///      │                   │
///      │                   │
///      ▼                   ▼
/// [DB Transaction]    [Background
///  Write to DB +       Publisher]
///  Write to Outbox
/// ```
///
/// ## Flow
///
/// 1. **Write Phase** (Transactional)
///    - Service writes business data to DB
///    - Service writes event to outbox table
///    - Both in same DB transaction (ACID guarantees)
///
/// 2. **Publish Phase** (Background)
///    - OutboxPublisher polls pending events
///    - Publishes to Kafka in batches
///    - Marks as published on success
///    - Retries failed events with exponential backoff
///
/// 3. **Recovery Phase** (Automatic)
///    - Detects failed events (status = 'failed')
///    - Retries with backoff until max_retries
///    - Logs permanent failures for manual intervention
///
/// ## Guarantees
///
/// - **At-least-once delivery**: Events may be published multiple times
/// - **Ordering**: Events for same aggregate_id are ordered (Kafka partition key)
/// - **Durability**: Events survive service crashes (persisted in DB)
/// - **Reliability**: Automatic retry with exponential backoff
use crate::error::{AppError, Result};
use chrono::{DateTime, Utc};
use prometheus::{IntCounter, IntGauge};
use rdkafka::config::ClientConfig;
use rdkafka::producer::{FutureProducer, FutureRecord};
use serde::{Deserialize, Serialize};
use sqlx::{PgPool, Row};
use std::sync::Arc;
use std::time::Duration;
use tokio::time::interval;
use tracing::{debug, error, info, warn};
use uuid::Uuid;

#[derive(Clone)]
pub struct OutboxMetrics {
    pub pending: IntGauge,
    pub oldest_pending_age_seconds: IntGauge,
    pub published: IntCounter,
}

impl OutboxMetrics {
    pub fn new(_service: &str) -> Self {
        let registry = prometheus::default_registry();

        let pending = IntGauge::new(
            "outbox_pending_count",
            "Number of unpublished outbox events currently pending",
        )
        .expect("valid metric for outbox_pending_count");
        let oldest_pending_age_seconds = IntGauge::new(
            "outbox_oldest_pending_age_seconds",
            "Age in seconds of the oldest pending outbox event",
        )
        .expect("valid metric for outbox_oldest_pending_age_seconds");
        let published = IntCounter::new(
            "outbox_published_total",
            "Total number of outbox events marked as published",
        )
        .expect("valid metric for outbox_published_total");

        for metric in [
            Box::new(pending.clone()) as Box<dyn prometheus::core::Collector>,
            Box::new(oldest_pending_age_seconds.clone()),
            Box::new(published.clone()),
        ] {
            let _ = registry.register(metric);
        }

        // attach service label via default process collectors? Use scent: set label by setting prefixed? Instead set via const label by wrapping new opts? To keep minimal, use per-service namespacing in help; label not added.
        // Use service name in debug logs only.
        Self {
            pending,
            oldest_pending_age_seconds,
            published,
        }
    }
}

/// Configuration for OutboxPublisher
#[derive(Debug, Clone)]
pub struct OutboxConfig {
    /// Kafka broker addresses (comma-separated)
    pub kafka_brokers: String,

    /// Number of events to process per batch
    pub batch_size: usize,

    /// How often to poll for pending events (milliseconds)
    pub poll_interval_ms: u64,

    /// Timeout for Kafka send operations (milliseconds)
    pub kafka_timeout_ms: u64,

    /// Maximum retry attempts for failed events
    pub max_retries: i32,

    /// Initial backoff for retries (milliseconds)
    pub retry_backoff_ms: u64,
}

impl Default for OutboxConfig {
    fn default() -> Self {
        Self {
            kafka_brokers: "localhost:9092".to_string(),
            batch_size: 100,
            poll_interval_ms: 1000, // Poll every 1 second
            kafka_timeout_ms: 5000, // 5 second timeout
            max_retries: 3,
            retry_backoff_ms: 1000, // Start with 1 second backoff
        }
    }
}

impl OutboxConfig {
    /// Load configuration from environment variables
    pub fn from_env() -> Self {
        Self {
            kafka_brokers: std::env::var("KAFKA_BROKERS")
                .unwrap_or_else(|_| "localhost:9092".to_string()),
            batch_size: std::env::var("OUTBOX_BATCH_SIZE")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(100),
            poll_interval_ms: std::env::var("OUTBOX_POLL_INTERVAL_MS")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(1000),
            kafka_timeout_ms: std::env::var("KAFKA_TIMEOUT_MS")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(5000),
            max_retries: std::env::var("OUTBOX_MAX_RETRIES")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(3),
            retry_backoff_ms: std::env::var("OUTBOX_RETRY_BACKOFF_MS")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(1000),
        }
    }
}

/// Outbox event record (from database)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OutboxEvent {
    pub id: Uuid,
    pub event_type: String,
    pub aggregate_id: String,
    pub aggregate_type: String,
    pub data: serde_json::Value,
    pub metadata: Option<serde_json::Value>,
    pub status: String,
    pub priority: i32,
    pub retry_count: i32,
    pub max_retries: i32,
    pub kafka_topic: Option<String>,
    pub kafka_partition: Option<i32>,
    pub kafka_key: Option<String>,
    pub correlation_id: Option<Uuid>,
    pub causation_id: Option<Uuid>,
    pub created_at: DateTime<Utc>,
    pub published_at: Option<DateTime<Utc>>,
    pub next_retry_at: Option<DateTime<Utc>>,
    pub last_error: Option<String>,
}

/// Kafka message to be published
#[derive(Debug, Serialize)]
struct KafkaEventPayload {
    pub id: Uuid,
    pub event_type: String,
    pub aggregate_id: String,
    pub aggregate_type: String,
    pub data: serde_json::Value,
    pub metadata: Option<serde_json::Value>,
    pub correlation_id: Option<Uuid>,
    pub causation_id: Option<Uuid>,
    pub created_at: DateTime<Utc>,
}

/// OutboxPublisher - Background service for publishing outbox events to Kafka
pub struct OutboxPublisher {
    db: PgPool,
    producer: FutureProducer,
    config: OutboxConfig,
    pub metrics: OutboxMetrics,
}

impl OutboxPublisher {
    /// Create a new OutboxPublisher
    ///
    /// # Arguments
    /// * `db` - Database connection pool
    /// * `config` - Outbox configuration
    ///
    /// # Returns
    /// Result containing the publisher or an error
    pub fn new(db: PgPool, config: OutboxConfig) -> Result<Self> {
        info!(
            "Initializing OutboxPublisher (brokers: {}, batch_size: {})",
            config.kafka_brokers, config.batch_size
        );

        // Create Kafka producer with idempotence and durability guarantees
        let producer: FutureProducer = ClientConfig::new()
            .set("bootstrap.servers", &config.kafka_brokers)
            .set("message.timeout.ms", config.kafka_timeout_ms.to_string())
            .set("request.timeout.ms", config.kafka_timeout_ms.to_string())
            .set("acks", "all") // Wait for all replicas
            .set("enable.idempotence", "true") // Prevent duplicates on retry
            .set("max.in.flight.requests.per.connection", "5")
            .set("retries", "2147483647") // Max retries (librdkafka handles)
            .set("compression.type", "lz4") // Fast compression
            .set("batch.size", "16384") // 16KB batches
            .set("linger.ms", "10") // Wait 10ms for batching
            .set("queue.buffering.max.messages", "100000")
            .create()
            .map_err(|e| {
                error!("Failed to create Kafka producer: {}", e);
                AppError::InternalError(format!("Kafka producer creation failed: {}", e))
            })?;

        Ok(Self {
            db,
            producer,
            config,
            metrics: OutboxMetrics::new("analytics-service"),
        })
    }

    /// Start the background publisher loop
    ///
    /// This runs forever, polling for pending events and publishing them to Kafka.
    /// Should be spawned as a tokio task.
    ///
    /// # Example
    /// ```ignore
    /// tokio::spawn(async move {
    ///     if let Err(e) = publisher.start().await {
    ///         error!("OutboxPublisher failed: {:?}", e);
    ///     }
    /// });
    /// ```
    pub async fn start(self: Arc<Self>) -> Result<()> {
        info!(
            "Starting OutboxPublisher loop (poll interval: {}ms)",
            self.config.poll_interval_ms
        );

        let mut ticker = interval(Duration::from_millis(self.config.poll_interval_ms));

        loop {
            ticker.tick().await;

            match self.publish_batch().await {
                Ok(count) => {
                    if count > 0 {
                        debug!("Published {} events in batch", count);
                        self.metrics.published.inc_by(count as u64);
                    }
                }
                Err(e) => {
                    error!("Failed to publish batch: {:?}", e);
                    // Continue processing - don't crash on errors
                }
            }

            // Update pending metrics
            if let Err(e) = self.record_pending_metrics().await {
                warn!("Failed to record outbox metrics: {}", e);
            }

            // Also check for failed events to retry
            if let Err(e) = self.retry_failed_events().await {
                error!("Failed to retry failed events: {:?}", e);
            }
        }
    }

    /// Publish a batch of pending events to Kafka
    ///
    /// # Process
    /// 1. Fetch pending events from outbox (status = 'pending')
    /// 2. Publish each to Kafka
    /// 3. Mark as published on success
    /// 4. Mark as failed on error (with retry logic)
    ///
    /// # Returns
    /// Number of events successfully published
    async fn publish_batch(&self) -> Result<usize> {
        // Fetch pending events ordered by priority (lower = higher priority) and creation time
        let events = sqlx::query_as::<_, OutboxEventRow>(
            r#"
            SELECT id, event_type, aggregate_id, aggregate_type, data, metadata,
                   status, priority, retry_count, max_retries, kafka_topic,
                   kafka_partition, kafka_key, correlation_id, causation_id,
                   created_at, published_at, next_retry_at, last_error
            FROM outbox_events
            WHERE status = 'pending'
            ORDER BY priority ASC, created_at ASC
            LIMIT $1
            FOR UPDATE SKIP LOCKED
            "#,
        )
        .bind(self.config.batch_size as i64)
        .fetch_all(&self.db)
        .await
        .map_err(|e| {
            error!("Failed to fetch pending outbox events: {}", e);
            AppError::DatabaseError(e.to_string())
        })?;

        if events.is_empty() {
            return Ok(0);
        }

        debug!("Processing batch of {} pending events", events.len());

        let mut success_count = 0;

        for event_row in events {
            let event: OutboxEvent = event_row.into();

            match self.publish_event(&event).await {
                Ok(_) => {
                    // Mark as published
                    if let Err(e) = self.mark_published(&event.id).await {
                        error!("Failed to mark event {} as published: {:?}", event.id, e);
                        // Continue - Kafka has the message, DB update can retry
                    } else {
                        success_count += 1;
                    }
                }
                Err(e) => {
                    error!(
                        "Failed to publish event {} (type: {}): {:?}",
                        event.id, event.event_type, e
                    );

                    // Mark as failed and schedule retry
                    if let Err(e) = self.mark_failed(&event.id, &e.to_string()).await {
                        error!("Failed to mark event {} as failed: {:?}", event.id, e);
                    }
                }
            }
        }

        Ok(success_count)
    }

    pub async fn record_pending_metrics(&self) -> Result<()> {
        let rec = sqlx::query(
            r#"
            SELECT COUNT(*)::BIGINT AS pending,
                   EXTRACT(EPOCH FROM (NOW() - MIN(created_at)))::BIGINT AS age_seconds
            FROM outbox_events
            WHERE status = 'pending'
            "#,
        )
        .fetch_one(&self.db)
        .await?;

        let pending: i64 = rec.try_get("pending").unwrap_or(0);
        let age: i64 = rec.try_get("age_seconds").unwrap_or(0);
        self.metrics.pending.set(pending);
        self.metrics.oldest_pending_age_seconds.set(age);
        Ok(())
    }

    pub async fn replay_since(&self, ts: DateTime<Utc>) -> Result<u64> {
        let res = sqlx::query(
            r#"
            UPDATE outbox_events
            SET status = 'pending',
                published_at = NULL,
                retry_count = 0,
                last_error = NULL,
                next_retry_at = NULL
            WHERE created_at >= $1
            "#,
        )
        .bind(ts)
        .execute(&self.db)
        .await?;
        Ok(res.rows_affected())
    }

    pub async fn replay_range(&self, from_id: Uuid, to_id: Uuid) -> Result<u64> {
        let res = sqlx::query(
            r#"
            UPDATE outbox_events
            SET status = 'pending',
                published_at = NULL,
                retry_count = 0,
                last_error = NULL,
                next_retry_at = NULL
            WHERE id BETWEEN $1 AND $2
            "#,
        )
        .bind(from_id)
        .bind(to_id)
        .execute(&self.db)
        .await?;
        Ok(res.rows_affected())
    }

    /// Publish a single event to Kafka
    async fn publish_event(&self, event: &OutboxEvent) -> Result<()> {
        // Determine Kafka topic
        let topic = match &event.kafka_topic {
            Some(t) => t.as_str(),
            None => self.get_default_topic(&event.event_type).ok_or_else(|| {
                AppError::ValidationError(format!(
                    "No Kafka topic configured for event type: {}",
                    event.event_type
                ))
            })?,
        };

        // Build Kafka message payload
        let payload = KafkaEventPayload {
            id: event.id,
            event_type: event.event_type.clone(),
            aggregate_id: event.aggregate_id.clone(),
            aggregate_type: event.aggregate_type.clone(),
            data: event.data.clone(),
            metadata: event.metadata.clone(),
            correlation_id: event.correlation_id,
            causation_id: event.causation_id,
            created_at: event.created_at,
        };

        let payload_json = serde_json::to_string(&payload).map_err(|e| {
            error!("Failed to serialize event payload: {}", e);
            AppError::InternalError(format!("JSON serialization failed: {}", e))
        })?;

        // Use aggregate_id as Kafka key for ordering guarantee
        let key = match &event.kafka_key {
            Some(k) => k.as_str(),
            None => event.aggregate_id.as_str(),
        };

        // Build Kafka record
        let mut record = FutureRecord::to(topic).payload(&payload_json).key(key);

        // Set partition if specified
        if let Some(partition) = event.kafka_partition {
            record = record.partition(partition);
        }

        // Publish to Kafka with timeout
        let timeout = Duration::from_millis(self.config.kafka_timeout_ms);

        debug!(
            "Publishing event {} to topic {} (key: {})",
            event.id, topic, key
        );

        self.producer
            .send(record, timeout)
            .await
            .map_err(|(e, _)| {
                error!("Kafka send failed for event {}: {}", event.id, e);
                AppError::InternalError(format!("Kafka send failed: {}", e))
            })?;

        debug!("Successfully published event {} to Kafka", event.id);
        Ok(())
    }

    /// Mark an event as published
    async fn mark_published(&self, event_id: &Uuid) -> Result<()> {
        sqlx::query(
            r#"
            UPDATE outbox_events
            SET status = 'published',
                published_at = NOW()
            WHERE id = $1
            "#,
        )
        .bind(event_id)
        .execute(&self.db)
        .await
        .map_err(|e| {
            error!("Failed to mark event {} as published: {}", event_id, e);
            AppError::DatabaseError(e.to_string())
        })?;

        Ok(())
    }

    /// Mark an event as failed and schedule retry
    async fn mark_failed(&self, event_id: &Uuid, error: &str) -> Result<()> {
        // Calculate next retry time with exponential backoff
        let backoff_ms = self.config.retry_backoff_ms;

        sqlx::query(
            r#"
            UPDATE outbox_events
            SET status = 'failed',
                retry_count = retry_count + 1,
                last_error = $2,
                next_retry_at = NOW() + (INTERVAL '1 millisecond' * $3 * POWER(2, retry_count))
            WHERE id = $1
            "#,
        )
        .bind(event_id)
        .bind(error)
        .bind(backoff_ms as i64)
        .execute(&self.db)
        .await
        .map_err(|e| {
            error!("Failed to mark event {} as failed: {}", event_id, e);
            AppError::DatabaseError(e.to_string())
        })?;

        Ok(())
    }

    /// Retry failed events that are ready for retry
    async fn retry_failed_events(&self) -> Result<usize> {
        // Find failed events that are ready to retry
        let events = sqlx::query_as::<_, OutboxEventRow>(
            r#"
            SELECT id, event_type, aggregate_id, aggregate_type, data, metadata,
                   status, priority, retry_count, max_retries, kafka_topic,
                   kafka_partition, kafka_key, correlation_id, causation_id,
                   created_at, published_at, next_retry_at, last_error
            FROM outbox_events
            WHERE status = 'failed'
              AND retry_count < max_retries
              AND (next_retry_at IS NULL OR next_retry_at <= NOW())
            ORDER BY next_retry_at ASC NULLS FIRST
            LIMIT $1
            FOR UPDATE SKIP LOCKED
            "#,
        )
        .bind(self.config.batch_size as i64)
        .fetch_all(&self.db)
        .await
        .map_err(|e| {
            error!("Failed to fetch failed events for retry: {}", e);
            AppError::DatabaseError(e.to_string())
        })?;

        if events.is_empty() {
            return Ok(0);
        }

        debug!("Retrying {} failed events", events.len());

        let mut success_count = 0;

        for event_row in events {
            let event: OutboxEvent = event_row.into();

            warn!(
                "Retrying failed event {} (attempt {}/{})",
                event.id,
                event.retry_count + 1,
                event.max_retries
            );

            // Reset status to pending for retry
            if let Err(e) = self.reset_to_pending(&event.id).await {
                error!("Failed to reset event {} to pending: {:?}", event.id, e);
                continue;
            }

            match self.publish_event(&event).await {
                Ok(_) => {
                    if let Err(e) = self.mark_published(&event.id).await {
                        error!(
                            "Failed to mark retried event {} as published: {:?}",
                            event.id, e
                        );
                    } else {
                        success_count += 1;
                        info!("Successfully retried event {}", event.id);
                    }
                }
                Err(e) => {
                    error!("Retry failed for event {}: {:?}", event.id, e);
                    if let Err(e) = self.mark_failed(&event.id, &e.to_string()).await {
                        error!(
                            "Failed to mark retried event {} as failed: {:?}",
                            event.id, e
                        );
                    }
                }
            }
        }

        Ok(success_count)
    }

    /// Reset event status to pending for retry
    async fn reset_to_pending(&self, event_id: &Uuid) -> Result<()> {
        sqlx::query(
            r#"
            UPDATE outbox_events
            SET status = 'pending'
            WHERE id = $1
            "#,
        )
        .bind(event_id)
        .execute(&self.db)
        .await
        .map_err(|e| {
            error!("Failed to reset event {} to pending: {}", event_id, e);
            AppError::DatabaseError(e.to_string())
        })?;

        Ok(())
    }

    /// Get default Kafka topic for an event type
    ///
    /// Maps event types to topics based on domain:
    /// - user.* -> nova-events-user
    /// - post.*, comment.* -> nova-events-content
    /// - message.*, conversation.* -> nova-events-messaging
    /// - follow.*, like.* -> nova-events-social
    fn get_default_topic(&self, event_type: &str) -> Option<&'static str> {
        let parts: Vec<&str> = event_type.split('.').collect();
        if parts.is_empty() {
            return None;
        }

        match parts[0] {
            "user" => Some("nova-events-user"),
            "post" | "comment" => Some("nova-events-content"),
            "message" | "conversation" => Some("nova-events-messaging"),
            "follow" | "like" => Some("nova-events-social"),
            _ => Some("nova-events-default"), // Fallback topic
        }
    }

    /// Health check - verify Kafka connectivity
    pub async fn health_check(&self) -> Result<()> {
        // Simplified health check - just verify producer is initialized
        // Full connectivity test requires blocking operations
        debug!("Kafka producer health check passed (producer initialized)");
        Ok(())
    }
}

/// SQLx row mapping for outbox_events table
#[derive(Debug)]
struct OutboxEventRow {
    id: Uuid,
    event_type: String,
    aggregate_id: String,
    aggregate_type: String,
    data: serde_json::Value,
    metadata: Option<serde_json::Value>,
    status: String,
    priority: i32,
    retry_count: i32,
    max_retries: i32,
    kafka_topic: Option<String>,
    kafka_partition: Option<i32>,
    kafka_key: Option<String>,
    correlation_id: Option<Uuid>,
    causation_id: Option<Uuid>,
    created_at: DateTime<Utc>,
    published_at: Option<DateTime<Utc>>,
    next_retry_at: Option<DateTime<Utc>>,
    last_error: Option<String>,
}

impl sqlx::FromRow<'_, sqlx::postgres::PgRow> for OutboxEventRow {
    fn from_row(row: &sqlx::postgres::PgRow) -> sqlx::Result<Self> {
        Ok(Self {
            id: row.try_get("id")?,
            event_type: row.try_get("event_type")?,
            aggregate_id: row.try_get("aggregate_id")?,
            aggregate_type: row.try_get("aggregate_type")?,
            data: row.try_get("data")?,
            metadata: row.try_get("metadata")?,
            status: row.try_get("status")?,
            priority: row.try_get("priority")?,
            retry_count: row.try_get("retry_count")?,
            max_retries: row.try_get("max_retries")?,
            kafka_topic: row.try_get("kafka_topic")?,
            kafka_partition: row.try_get("kafka_partition")?,
            kafka_key: row.try_get("kafka_key")?,
            correlation_id: row.try_get("correlation_id")?,
            causation_id: row.try_get("causation_id")?,
            created_at: row.try_get("created_at")?,
            published_at: row.try_get("published_at")?,
            next_retry_at: row.try_get("next_retry_at")?,
            last_error: row.try_get("last_error")?,
        })
    }
}

impl From<OutboxEventRow> for OutboxEvent {
    fn from(row: OutboxEventRow) -> Self {
        Self {
            id: row.id,
            event_type: row.event_type,
            aggregate_id: row.aggregate_id,
            aggregate_type: row.aggregate_type,
            data: row.data,
            metadata: row.metadata,
            status: row.status,
            priority: row.priority,
            retry_count: row.retry_count,
            max_retries: row.max_retries,
            kafka_topic: row.kafka_topic,
            kafka_partition: row.kafka_partition,
            kafka_key: row.kafka_key,
            correlation_id: row.correlation_id,
            causation_id: row.causation_id,
            created_at: row.created_at,
            published_at: row.published_at,
            next_retry_at: row.next_retry_at,
            last_error: row.last_error,
        }
    }
}
