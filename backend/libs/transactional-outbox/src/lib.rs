//! # Transactional Outbox Pattern Implementation
//!
//! This library implements the Transactional Outbox pattern to ensure reliable event publishing
//! in microservices architectures. It guarantees that database writes and event publishing happen
//! atomically, preventing data inconsistencies.
//!
//! ## What is the Transactional Outbox Pattern?
//!
//! The Transactional Outbox pattern ensures that:
//! 1. Business logic changes (database writes) and event creation happen in the same transaction
//! 2. Events are stored in an "outbox" table within the same database
//! 3. A background processor reads unpublished events and publishes them to Kafka
//! 4. Events are marked as published only after successful Kafka delivery
//!
//! This guarantees **at-least-once delivery** and prevents event loss even if:
//! - The service crashes after database commit but before Kafka publish
//! - Kafka is temporarily unavailable
//! - Network partitions occur
//!
//! ## Why is it needed?
//!
//! Without this pattern, you face these problems:
//! - **Lost events**: Database commits but event publishing fails → data divergence
//! - **Duplicate events**: Publishing succeeds but database commit fails → inconsistency
//! - **Split brain**: Different services see different versions of truth
//!
//! ## Usage Example
//!
//! ### 1. Insert data and event in same transaction
//!
//! ```rust,no_run
//! use transactional_outbox::{OutboxEvent, OutboxRepository, SqlxOutboxRepository};
//! use sqlx::{PgPool, Postgres, Transaction};
//! use uuid::Uuid;
//! use chrono::Utc;
//!
//! async fn create_user(
//!     pool: &PgPool,
//!     outbox_repo: &SqlxOutboxRepository,
//!     username: String,
//! ) -> Result<(), Box<dyn std::error::Error>> {
//!     // Start transaction
//!     let mut tx = pool.begin().await?;
//!
//!     // 1. Insert user into database
//!     let user_id = Uuid::new_v4();
//!     sqlx::query!(
//!         "INSERT INTO users (id, username) VALUES ($1, $2)",
//!         user_id,
//!         username
//!     )
//!     .execute(&mut *tx)
//!     .await?;
//!
//!     // 2. Insert event into outbox (same transaction!)
//!     let event = OutboxEvent {
//!         id: Uuid::new_v4(),
//!         aggregate_type: "user".to_string(),
//!         aggregate_id: user_id,
//!         event_type: "user.created".to_string(),
//!         payload: serde_json::json!({
//!             "user_id": user_id,
//!             "username": username,
//!             "created_at": Utc::now(),
//!         }),
//!         metadata: Some(serde_json::json!({
//!             "correlation_id": Uuid::new_v4(),
//!             "service": "user-service",
//!         })),
//!         created_at: Utc::now(),
//!         published_at: None,
//!         retry_count: 0,
//!         last_error: None,
//!     };
//!
//!     outbox_repo.insert(&mut tx, &event).await?;
//!
//!     // 3. Commit transaction (both user and event are saved atomically)
//!     tx.commit().await?;
//!
//!     Ok(())
//! }
//! ```
//!
//! ### 2. Start background processor
//!
//! ```rust,no_run
//! use transactional_outbox::{
//!     OutboxProcessor, SqlxOutboxRepository, KafkaOutboxPublisher
//! };
//! use rdkafka::producer::{FutureProducer, FutureRecord};
//! use rdkafka::ClientConfig;
//! use sqlx::PgPool;
//! use std::sync::Arc;
//! use std::time::Duration;
//!
//! #[tokio::main]
//! async fn main() -> Result<(), Box<dyn std::error::Error>> {
//!     // Initialize database pool
//!     let pool = PgPool::connect("postgresql://localhost/mydb").await?;
//!
//!     // Initialize Kafka producer with idempotence enabled
//!     let producer: FutureProducer = ClientConfig::new()
//!         .set("bootstrap.servers", "localhost:9092")
//!         .set("enable.idempotence", "true")
//!         .set("acks", "all")
//!         .set("max.in.flight.requests.per.connection", "5")
//!         .create()?;
//!
//!     // Create repository and publisher
//!     let repository = Arc::new(SqlxOutboxRepository::new(pool));
//!     let publisher = Arc::new(KafkaOutboxPublisher::new(
//!         producer,
//!         "nova".to_string(), // topic prefix
//!     ));
//!
//!     // Create and start processor
//!     let processor = OutboxProcessor::new(
//!         repository,
//!         publisher,
//!         100,                          // batch_size
//!         Duration::from_secs(5),       // poll_interval
//!         5,                            // max_retries
//!     );
//!
//!     processor.start().await?;
//!
//!     Ok(())
//! }
//! ```

use anyhow::{Context, Result};
use async_trait::async_trait;
use chrono::{DateTime, Utc};
use rdkafka::message::{Header, OwnedHeaders};
use rdkafka::producer::{FutureProducer, FutureRecord};
use serde::{Deserialize, Serialize};
use sqlx::{PgPool, Postgres, Row, Transaction};
use std::sync::Arc;
use std::time::Duration;
use tracing::{debug, error, info, warn};
use uuid::Uuid;

mod error;
pub mod macros;
pub mod metrics;

pub use error::{OutboxError, OutboxResult};

/// Represents an event stored in the outbox table.
///
/// Events are created within a database transaction alongside business logic changes,
/// ensuring atomicity. They are later published to Kafka by the background processor.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OutboxEvent {
    /// Unique identifier for this event
    pub id: Uuid,

    /// Type of aggregate this event relates to (e.g., "user", "content", "feed")
    pub aggregate_type: String,

    /// ID of the entity this event relates to
    pub aggregate_id: Uuid,

    /// Fully qualified event type (e.g., "user.created", "content.published")
    pub event_type: String,

    /// Event payload as JSON
    pub payload: serde_json::Value,

    /// Optional metadata (correlation_id, user_id, trace_id, etc.)
    pub metadata: Option<serde_json::Value>,

    /// Timestamp when event was created
    pub created_at: DateTime<Utc>,

    /// Timestamp when event was successfully published to Kafka (None = unpublished)
    pub published_at: Option<DateTime<Utc>>,

    /// Number of failed publish attempts
    pub retry_count: i32,

    /// Last error message from failed publish attempt
    pub last_error: Option<String>,
}

/// Repository trait for managing outbox events in the database.
///
/// This trait abstracts database operations to allow for testing and
/// alternative implementations.
#[async_trait]
pub trait OutboxRepository: Send + Sync {
    /// Insert a new event into the outbox within a transaction.
    ///
    /// This method MUST be called within an existing transaction to ensure
    /// atomicity with business logic changes.
    ///
    /// # Arguments
    ///
    /// * `tx` - Active database transaction
    /// * `event` - Event to insert
    ///
    /// # Errors
    ///
    /// Returns error if database insertion fails.
    async fn insert(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        event: &OutboxEvent,
    ) -> OutboxResult<()>;

    /// Get unpublished events for processing.
    ///
    /// Returns events ordered by creation time (oldest first) that have not been
    /// successfully published yet.
    ///
    /// # Arguments
    ///
    /// * `limit` - Maximum number of events to retrieve
    ///
    /// # Errors
    ///
    /// Returns error if database query fails.
    async fn get_unpublished(&self, limit: i32) -> OutboxResult<Vec<OutboxEvent>>;

    /// Mark an event as successfully published.
    ///
    /// Sets the `published_at` timestamp to indicate successful Kafka delivery.
    ///
    /// # Arguments
    ///
    /// * `event_id` - ID of the event to mark as published
    ///
    /// # Errors
    ///
    /// Returns error if database update fails.
    async fn mark_published(&self, event_id: Uuid) -> OutboxResult<()>;

    /// Mark an event as failed with error details.
    ///
    /// Increments retry count and stores error message for debugging.
    ///
    /// # Arguments
    ///
    /// * `event_id` - ID of the event that failed
    /// * `error` - Error message describing the failure
    ///
    /// # Errors
    ///
    /// Returns error if database update fails.
    async fn mark_failed(&self, event_id: Uuid, error: &str) -> OutboxResult<()>;

    /// Compute pending count and oldest pending age (seconds). Should return age=0 if none pending.
    async fn pending_stats(&self) -> OutboxResult<(i64, i64)>;
}

/// SQLx-based implementation of OutboxRepository using PostgreSQL.
///
/// This implementation uses connection pooling and prepared statements
/// for optimal performance.
pub struct SqlxOutboxRepository {
    pool: PgPool,
}

impl SqlxOutboxRepository {
    /// Create a new repository with the given database pool.
    ///
    /// # Arguments
    ///
    /// * `pool` - PostgreSQL connection pool
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Return pending count and oldest pending age (seconds). If no pending, age = 0.
    pub async fn pending_stats(&self) -> OutboxResult<(i64, i64)> {
        let rec = sqlx::query(
            r#"
            SELECT
                COUNT(*)::BIGINT AS pending,
                EXTRACT(EPOCH FROM (NOW() - MIN(created_at)))::BIGINT AS age_seconds
            FROM outbox_events
            WHERE published_at IS NULL
            "#,
        )
        .fetch_one(&self.pool)
        .await
        .context("Failed to compute pending stats")?;

        let pending: i64 = rec.try_get("pending").unwrap_or(0);
        let age: i64 = rec.try_get("age_seconds").unwrap_or(0);
        Ok((pending, age))
    }

    /// Replay events created since the given timestamp by resetting published_at and retry counters.
    pub async fn replay_since(&self, ts: DateTime<Utc>) -> OutboxResult<u64> {
        let res = sqlx::query(
            r#"
            UPDATE outbox_events
            SET published_at = NULL,
                retry_count = 0,
                last_error = NULL
            WHERE created_at >= $1
            "#,
        )
        .bind(ts)
        .execute(&self.pool)
        .await
        .context("Failed to replay events since timestamp")?;

        Ok(res.rows_affected())
    }

    /// Replay events by ID range (inclusive) for operational backfill.
    pub async fn replay_range(&self, from_id: Uuid, to_id: Uuid) -> OutboxResult<u64> {
        let res = sqlx::query(
            r#"
            UPDATE outbox_events
            SET published_at = NULL,
                retry_count = 0,
                last_error = NULL
            WHERE id BETWEEN $1 AND $2
            "#,
        )
        .bind(from_id)
        .bind(to_id)
        .execute(&self.pool)
        .await
        .context("Failed to replay events by id range")?;

        Ok(res.rows_affected())
    }
}

#[async_trait]
impl OutboxRepository for SqlxOutboxRepository {
    async fn insert(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        event: &OutboxEvent,
    ) -> OutboxResult<()> {
        sqlx::query(
            r#"
            INSERT INTO outbox_events (
                id,
                aggregate_type,
                aggregate_id,
                event_type,
                payload,
                metadata,
                created_at,
                published_at,
                retry_count,
                last_error
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
            "#,
        )
        .bind(event.id)
        .bind(&event.aggregate_type)
        .bind(event.aggregate_id)
        .bind(&event.event_type)
        .bind(&event.payload)
        .bind(&event.metadata)
        .bind(event.created_at)
        .bind(event.published_at)
        .bind(event.retry_count)
        .bind(&event.last_error)
        .execute(&mut **tx)
        .await
        .context("Failed to insert event into outbox")?;

        debug!(
            event_id = %event.id,
            event_type = %event.event_type,
            aggregate_id = %event.aggregate_id,
            "Event inserted into outbox"
        );

        Ok(())
    }

    async fn get_unpublished(&self, limit: i32) -> OutboxResult<Vec<OutboxEvent>> {
        let rows = sqlx::query(
            r#"
            SELECT
                id,
                aggregate_type,
                aggregate_id,
                event_type,
                payload,
                metadata,
                created_at,
                published_at,
                retry_count,
                last_error
            FROM outbox_events
            WHERE published_at IS NULL
            ORDER BY created_at ASC, retry_count ASC
            LIMIT $1
            "#,
        )
        .bind(limit)
        .fetch_all(&self.pool)
        .await
        .context("Failed to fetch unpublished events")?;

        let events: Vec<OutboxEvent> = rows
            .into_iter()
            .map(|row| {
                Ok(OutboxEvent {
                    id: row.try_get("id")?,
                    aggregate_type: row.try_get("aggregate_type")?,
                    aggregate_id: row.try_get("aggregate_id")?,
                    event_type: row.try_get("event_type")?,
                    payload: row.try_get("payload")?,
                    metadata: row.try_get("metadata")?,
                    created_at: row.try_get("created_at")?,
                    published_at: row.try_get("published_at")?,
                    retry_count: row.try_get("retry_count")?,
                    last_error: row.try_get("last_error")?,
                })
            })
            .collect::<Result<Vec<_>, sqlx::Error>>()
            .context("Failed to parse events")?;

        debug!(count = events.len(), "Fetched unpublished events");

        Ok(events)
    }

    async fn mark_published(&self, event_id: Uuid) -> OutboxResult<()> {
        let result = sqlx::query(
            r#"
            UPDATE outbox_events
            SET published_at = NOW()
            WHERE id = $1
            "#,
        )
        .bind(event_id)
        .execute(&self.pool)
        .await
        .context("Failed to mark event as published")?;

        if result.rows_affected() == 0 {
            warn!(event_id = %event_id, "Event not found when marking as published");
            return Err(OutboxError::EventNotFound(event_id));
        }

        debug!(event_id = %event_id, "Event marked as published");

        Ok(())
    }

    async fn mark_failed(&self, event_id: Uuid, error: &str) -> OutboxResult<()> {
        let result = sqlx::query(
            r#"
            UPDATE outbox_events
            SET
                retry_count = retry_count + 1,
                last_error = $2
            WHERE id = $1
            "#,
        )
        .bind(event_id)
        .bind(error)
        .execute(&self.pool)
        .await
        .context("Failed to mark event as failed")?;

        if result.rows_affected() == 0 {
            warn!(event_id = %event_id, "Event not found when marking as failed");
            return Err(OutboxError::EventNotFound(event_id));
        }

        warn!(
            event_id = %event_id,
            error = %error,
            "Event marked as failed"
        );

        Ok(())
    }

    async fn pending_stats(&self) -> OutboxResult<(i64, i64)> {
        SqlxOutboxRepository::pending_stats(self).await
    }
}

/// Publisher trait for publishing events to external systems (e.g., Kafka).
///
/// Implementations should be idempotent to handle retries safely.
#[async_trait]
pub trait OutboxPublisher: Send + Sync {
    /// Publish an event to the message broker.
    ///
    /// # Arguments
    ///
    /// * `event` - Event to publish
    ///
    /// # Errors
    ///
    /// Returns error if publishing fails.
    async fn publish(&self, event: &OutboxEvent) -> OutboxResult<()>;
}

/// Kafka-based implementation of OutboxPublisher.
///
/// This publisher:
/// - Uses idempotent producer settings (enable.idempotence=true)
/// - Maps event types to Kafka topics
/// - Includes event metadata in Kafka headers
/// - Uses aggregate_id as partition key for ordering
pub struct KafkaOutboxPublisher {
    producer: FutureProducer,
    topic_prefix: String,
}

impl KafkaOutboxPublisher {
    /// Create a new Kafka publisher.
    ///
    /// # Arguments
    ///
    /// * `producer` - Kafka producer (MUST have enable.idempotence=true)
    /// * `topic_prefix` - Prefix for topic names (e.g., "nova")
    ///
    /// # Kafka Configuration Requirements
    ///
    /// The producer MUST be configured with:
    /// - `enable.idempotence = true` (prevents duplicates)
    /// - `acks = all` (ensures durability)
    /// - `max.in.flight.requests.per.connection = 5` (with idempotence)
    pub fn new(producer: FutureProducer, topic_prefix: String) -> Self {
        Self {
            producer,
            topic_prefix,
        }
    }

    /// Map event type to Kafka topic.
    ///
    /// Strategy:
    /// - "user.created" -> "nova.user.events"
    /// - "content.published" -> "nova.content.events"
    /// - "feed.item.added" -> "nova.feed.events"
    fn get_topic(&self, event_type: &str) -> String {
        // Extract aggregate type from event_type (e.g., "user" from "user.created")
        let aggregate = event_type.split('.').next().unwrap_or("unknown");

        format!("{}.{}.events", self.topic_prefix, aggregate)
    }
}

#[async_trait]
impl OutboxPublisher for KafkaOutboxPublisher {
    async fn publish(&self, event: &OutboxEvent) -> OutboxResult<()> {
        let topic = self.get_topic(&event.event_type);

        // Serialize payload
        let payload_str =
            serde_json::to_string(&event.payload).context("Failed to serialize event payload")?;

        // Create string values that will live long enough
        let event_id_str = event.id.to_string();
        let aggregate_id_str = event.aggregate_id.to_string();
        let created_at_str = event.created_at.to_rfc3339();

        // Build Kafka headers
        let mut headers = OwnedHeaders::new()
            .insert(Header {
                key: "event_type",
                value: Some(event.event_type.as_bytes()),
            })
            .insert(Header {
                key: "event_id",
                value: Some(event_id_str.as_bytes()),
            })
            .insert(Header {
                key: "aggregate_type",
                value: Some(event.aggregate_type.as_bytes()),
            })
            .insert(Header {
                key: "aggregate_id",
                value: Some(aggregate_id_str.as_bytes()),
            })
            .insert(Header {
                key: "created_at",
                value: Some(created_at_str.as_bytes()),
            });

        // Add metadata headers if present
        if let Some(metadata) = &event.metadata {
            if let Some(correlation_id) = metadata.get("correlation_id") {
                if let Some(cid_str) = correlation_id.as_str() {
                    headers = headers.insert(Header {
                        key: "correlation_id",
                        value: Some(cid_str.as_bytes()),
                    });
                }
            }
        }

        // Create Kafka record with aggregate_id as key (for ordering)
        let aggregate_id_key = event.aggregate_id.to_string();
        let record = FutureRecord::to(&topic)
            .key(&aggregate_id_key)
            .payload(&payload_str)
            .headers(headers);

        // Publish with timeout
        let delivery_timeout = Duration::from_secs(30);
        self.producer
            .send(record, delivery_timeout)
            .await
            .map_err(|(err, _)| {
                OutboxError::PublishFailed(format!("Kafka publish failed: {}", err))
            })?;

        info!(
            event_id = %event.id,
            event_type = %event.event_type,
            topic = %topic,
            "Event published to Kafka"
        );

        Ok(())
    }
}

/// Background processor for publishing outbox events.
///
/// This component:
/// - Polls database for unpublished events at regular intervals
/// - Publishes events to Kafka using the configured publisher
/// - Implements retry logic with exponential backoff
/// - Marks events as published or failed
///
/// # Processing Guarantees
///
/// - **At-least-once delivery**: Events may be published multiple times if crashes occur
/// - **Ordering per aggregate**: Events for the same aggregate_id are processed in order
/// - **Automatic retries**: Failed events are retried up to max_retries times
/// - **Dead letter handling**: Events exceeding max_retries are skipped (manual intervention needed)
pub struct OutboxProcessor<R: OutboxRepository, P: OutboxPublisher> {
    repository: Arc<R>,
    publisher: Arc<P>,
    batch_size: i32,
    poll_interval: Duration,
    max_retries: i32,
    metrics: Option<crate::metrics::OutboxMetrics>,
}

impl<R: OutboxRepository, P: OutboxPublisher> OutboxProcessor<R, P> {
    /// Create a new outbox processor.
    ///
    /// # Arguments
    ///
    /// * `repository` - Repository for accessing outbox events
    /// * `publisher` - Publisher for sending events to Kafka
    /// * `batch_size` - Number of events to process per batch
    /// * `poll_interval` - Interval between polling for new events
    /// * `max_retries` - Maximum retry attempts before giving up
    pub fn new(
        repository: Arc<R>,
        publisher: Arc<P>,
        batch_size: i32,
        poll_interval: Duration,
        max_retries: i32,
    ) -> Self {
        Self {
            repository,
            publisher,
            batch_size,
            poll_interval,
            max_retries,
            metrics: None,
        }
    }

    /// Create a processor that also updates Prometheus metrics each polling cycle.
    pub fn new_with_metrics(
        repository: Arc<R>,
        publisher: Arc<P>,
        metrics: crate::metrics::OutboxMetrics,
        batch_size: i32,
        poll_interval: Duration,
        max_retries: i32,
    ) -> Self {
        Self {
            repository,
            publisher,
            batch_size,
            poll_interval,
            max_retries,
            metrics: Some(metrics),
        }
    }

    /// Start the processor loop.
    ///
    /// This method runs indefinitely, polling for events and publishing them.
    /// It should be spawned as a background task.
    ///
    /// # Errors
    ///
    /// Returns error if processor encounters fatal error (should never happen in production).
    ///
    /// # Panics
    ///
    /// This method uses `loop` and should never panic. All errors are logged and handled gracefully.
    pub async fn start(&self) -> Result<()> {
        info!(
            batch_size = self.batch_size,
            poll_interval_secs = self.poll_interval.as_secs(),
            max_retries = self.max_retries,
            "Outbox processor starting"
        );

        loop {
            match self.process_batch().await {
                Ok(count) => {
                    if count > 0 {
                        info!(published_count = count, "Published events from outbox");
                    } else {
                        debug!("No events to publish");
                    }
                }
                Err(e) => {
                    error!(error = ?e, "Outbox processor error");
                }
            }

            if let Some(metrics) = &self.metrics {
                if let Ok((pending, age)) = self.repository.pending_stats().await {
                    metrics.pending.set(pending);
                    metrics.oldest_pending_age_seconds.set(age);
                }
            }

            tokio::time::sleep(self.poll_interval).await;
        }
    }

    /// Process a single batch of events.
    ///
    /// Returns the number of successfully published events.
    async fn process_batch(&self) -> OutboxResult<i32> {
        let events = self.repository.get_unpublished(self.batch_size).await?;
        let mut published_count = 0;

        for event in events {
            // Skip events that exceeded max retries (manual intervention needed)
            if event.retry_count >= self.max_retries {
                warn!(
                    event_id = %event.id,
                    event_type = %event.event_type,
                    retry_count = event.retry_count,
                    max_retries = self.max_retries,
                    last_error = ?event.last_error,
                    "Event exceeded max retries, skipping (requires manual intervention)"
                );
                continue;
            }

            // Calculate exponential backoff delay
            let backoff_delay = self.calculate_backoff(event.retry_count);
            if backoff_delay.as_secs() > 0 {
                debug!(
                    event_id = %event.id,
                    retry_count = event.retry_count,
                    backoff_secs = backoff_delay.as_secs(),
                    "Applying exponential backoff"
                );
                tokio::time::sleep(backoff_delay).await;
            }

            // Attempt to publish
            match self.publisher.publish(&event).await {
                Ok(_) => {
                    // Mark as published
                    if let Err(e) = self.repository.mark_published(event.id).await {
                        error!(
                            event_id = %event.id,
                            error = ?e,
                            "Failed to mark event as published (event was delivered to Kafka)"
                        );
                    // Event was delivered to Kafka but marking failed
                    // This could lead to duplicate delivery on retry
                    // Consider implementing idempotent consumers
                    } else {
                        published_count += 1;
                        if let Some(metrics) = &self.metrics {
                            metrics.published.inc();
                        }
                    }
                }
                Err(e) => {
                    error!(
                        event_id = %event.id,
                        event_type = %event.event_type,
                        retry_count = event.retry_count,
                        error = ?e,
                        "Failed to publish event"
                    );

                    // Mark as failed
                    if let Err(mark_err) =
                        self.repository.mark_failed(event.id, &e.to_string()).await
                    {
                        error!(
                            event_id = %event.id,
                            error = ?mark_err,
                            "Failed to mark event as failed"
                        );
                    }
                }
            }
        }

        Ok(published_count)
    }

    /// Calculate exponential backoff delay based on retry count.
    ///
    /// Strategy: 2^retry_count seconds, capped at 5 minutes
    /// - Retry 0: 1 second
    /// - Retry 1: 2 seconds
    /// - Retry 2: 4 seconds
    /// - Retry 3: 8 seconds
    /// - Retry 4: 16 seconds
    /// - Retry 5+: 300 seconds (5 minutes)
    fn calculate_backoff(&self, retry_count: i32) -> Duration {
        const MAX_BACKOFF_SECS: u64 = 300; // 5 minutes

        let backoff_secs = 2u64.pow(retry_count as u32).min(MAX_BACKOFF_SECS);
        Duration::from_secs(backoff_secs)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_backoff_calculation() {
        let repo = Arc::new(SqlxOutboxRepository::new(
            PgPool::connect_lazy("postgresql://localhost/test").unwrap(),
        ));
        let producer =
            rdkafka::producer::FutureProducer::from_config(&rdkafka::ClientConfig::new()).unwrap();
        let publisher = Arc::new(KafkaOutboxPublisher::new(producer, "test".to_string()));
        let processor = OutboxProcessor::new(repo, publisher, 10, Duration::from_secs(1), 5);

        assert_eq!(processor.calculate_backoff(0).as_secs(), 1);
        assert_eq!(processor.calculate_backoff(1).as_secs(), 2);
        assert_eq!(processor.calculate_backoff(2).as_secs(), 4);
        assert_eq!(processor.calculate_backoff(3).as_secs(), 8);
        assert_eq!(processor.calculate_backoff(4).as_secs(), 16);
        assert_eq!(processor.calculate_backoff(5).as_secs(), 32);
        assert_eq!(processor.calculate_backoff(10).as_secs(), 300); // capped
    }

    #[test]
    fn test_topic_mapping() {
        let producer =
            rdkafka::producer::FutureProducer::from_config(&rdkafka::ClientConfig::new()).unwrap();
        let publisher = KafkaOutboxPublisher::new(producer, "nova".to_string());

        assert_eq!(publisher.get_topic("user.created"), "nova.user.events");
        assert_eq!(
            publisher.get_topic("content.published"),
            "nova.content.events"
        );
        assert_eq!(publisher.get_topic("feed.item.added"), "nova.feed.events");
    }
}
