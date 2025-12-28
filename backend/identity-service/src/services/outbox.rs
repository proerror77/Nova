/// Transactional Outbox Pattern implementation for identity-service
///
/// Ensures reliable event publishing by:
/// 1. Writing events to database in same transaction as business logic
/// 2. Background consumer polls outbox table and publishes to Kafka
/// 3. Retries with exponential backoff
/// 4. Dead letter queue for permanently failed events
use crate::services::KafkaEventProducer;
use chrono::{DateTime, Utc};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::{FromRow, PgPool};
use std::{env, time::Duration};
use tokio::task::JoinHandle;
use tokio::time::sleep;
use tracing::{debug, error, info, warn};
use uuid::Uuid;

#[derive(Clone)]
pub struct OutboxConsumerConfig {
    pub poll_interval: Duration,
    pub batch_size: i64,
    pub max_retries: i32,
    pub retry_backoff: Duration,
    pub max_backoff: Duration,
    pub dlq_topic: Option<String>,
}

impl Default for OutboxConsumerConfig {
    fn default() -> Self {
        let dlq_topic = env::var("IDENTITY_OUTBOX_DLQ_TOPIC")
            .or_else(|_| env::var("KAFKA_DLQ_TOPIC"))
            .map(|value| value.trim().to_owned())
            .ok()
            .filter(|value| !value.is_empty())
            .or_else(|| Some("identity-events.dlq".to_string()));

        let max_retries = env::var("IDENTITY_OUTBOX_MAX_RETRIES")
            .or_else(|_| env::var("OUTBOX_MAX_RETRIES"))
            .ok()
            .and_then(|value| value.trim().parse::<i32>().ok())
            .filter(|value| *value > 0)
            .unwrap_or(5);

        Self {
            poll_interval: Duration::from_millis(1500),
            batch_size: 50,
            max_retries,
            retry_backoff: Duration::from_millis(500),
            max_backoff: Duration::from_secs(30),
            dlq_topic,
        }
    }
}

#[derive(Debug, FromRow)]
struct OutboxRecord {
    /// Primary key of the outbox event
    id: Uuid,
    /// Aggregate type, e.g. "User"
    aggregate_type: String,
    /// Aggregate identifier (stored as text, typically a UUID)
    aggregate_id: String,
    /// Event type, e.g. "UserDeleted"
    event_type: String,
    /// Raw event payload stored in the database (library-standard column name)
    payload: Value,
    /// Number of times this event has been retried
    retry_count: i32,
    /// Creation timestamp of the event
    created_at: DateTime<Utc>,
}

/// Spawn background outbox consumer task
///
/// Continuously polls outbox_events table and publishes to Kafka.
///
/// ## Arguments
///
/// * `db_pool` - PostgreSQL connection pool
/// * `producer` - Kafka producer (optional for no-op mode)
/// * `config` - Consumer configuration
///
/// ## Returns
///
/// JoinHandle for background task
pub fn spawn_outbox_consumer(
    db_pool: PgPool,
    producer: Option<KafkaEventProducer>,
    config: OutboxConsumerConfig,
) -> JoinHandle<()> {
    let dlq_label = config
        .dlq_topic
        .as_deref()
        .unwrap_or("disabled")
        .to_string();

    if producer.is_none() {
        warn!("Outbox consumer starting without Kafka producer; events will be marked as handled locally");
    }

    info!(
        poll_interval_ms = %config.poll_interval.as_millis(),
        batch_size = config.batch_size,
        max_retries = config.max_retries,
        retry_backoff_ms = %config.retry_backoff.as_millis(),
        max_backoff_ms = %config.max_backoff.as_millis(),
        dlq_topic = %dlq_label,
        "Starting identity-service outbox consumer"
    );

    tokio::spawn(async move {
        loop {
            if let Err(err) = process_batch(&db_pool, producer.as_ref(), &config).await {
                error!("Outbox consumer batch failed: {:#}", err);
            }
            sleep(config.poll_interval).await;
        }
    })
}

async fn process_batch(
    db_pool: &PgPool,
    producer: Option<&KafkaEventProducer>,
    config: &OutboxConsumerConfig,
) -> Result<(), sqlx::Error> {
    let events: Vec<OutboxRecord> = sqlx::query_as::<_, OutboxRecord>(
        r#"
        SELECT
            id,
            aggregate_type,
            aggregate_id,
            event_type,
            payload,
            retry_count,
            created_at
        FROM outbox_events
        WHERE published_at IS NULL
          AND retry_count < $2
        ORDER BY created_at ASC
        LIMIT $1
        FOR UPDATE SKIP LOCKED
        "#,
    )
    .bind(config.batch_size)
    .bind(config.max_retries)
    .fetch_all(db_pool)
    .await?;

    if events.is_empty() {
        return Ok(());
    }

    for event in events {
        let attempt_number = event.retry_count.saturating_add(1);

        let span = tracing::info_span!(
            "outbox_event",
            event_id = %event.id,
            aggregate_type = %event.aggregate_type,
            aggregate_id = %event.aggregate_id,
            event_type = %event.event_type,
            retry_count = event.retry_count
        );
        let _guard = span.enter();

        let processing_result = process_event(&event, producer, config).await;
        let latency_seconds =
            (Utc::now() - event.created_at).num_milliseconds().max(0) as f64 / 1_000.0;

        tracing::debug!(latency_seconds, "Outbox event processing latency");

        match processing_result {
            Ok(ProcessOutcome::Published) => {
                mark_published(db_pool, event.id).await?;
            }
            Ok(ProcessOutcome::Skipped) => {
                mark_published(db_pool, event.id).await?;
            }
            Err(failure) => {
                warn!(
                    error = %failure.message(),
                    reason = failure.reason(),
                    attempt = attempt_number,
                    "Outbox event processing failed"
                );

                let should_move_to_dlq = failure.is_fatal() || attempt_number >= config.max_retries;

                if should_move_to_dlq {
                    if let (Some(producer), Some(topic)) = (producer, config.dlq_topic.as_deref()) {
                        match send_to_dlq(producer, topic, &event, &failure).await {
                            Ok(_) => {
                                info!(
                                    "Event routed to DLQ after {} attempts ({})",
                                    attempt_number,
                                    failure.reason()
                                );
                                mark_published(db_pool, event.id).await?;
                                continue;
                            }
                            Err(dlq_err) => {
                                error!(
                                    error = %dlq_err,
                                    "Failed to publish outbox event to DLQ"
                                );
                            }
                        }
                    } else {
                        warn!(
                            "DLQ topic or producer unavailable; marking event as published to prevent backlog"
                        );
                        mark_published(db_pool, event.id).await?;
                        continue;
                    }
                }

                let backoff =
                    calculate_backoff(config.retry_backoff, config.max_backoff, event.retry_count);

                if backoff > Duration::from_millis(0) {
                    debug!(
                        backoff_ms = %backoff.as_millis(),
                        attempt = attempt_number,
                        "Sleeping before retrying outbox event"
                    );
                    sleep(backoff).await;
                }

                increment_retry(db_pool, event.id).await?;
            }
        }
    }

    Ok(())
}

fn calculate_backoff(base: Duration, max: Duration, retry_count: i32) -> Duration {
    if retry_count < 0 {
        return base.min(max);
    }

    let shift = retry_count.clamp(0, 16) as u32;
    let multiplier = 1_u32 << shift;
    let backoff = base.saturating_mul(multiplier);
    if backoff > max {
        max
    } else {
        backoff
    }
}

#[derive(Debug, Deserialize)]
struct UserDeletedPayload {
    #[serde(default)]
    user_id: Option<Uuid>,
    #[serde(default)]
    deleted_at: Option<DateTime<Utc>>,
    #[serde(default = "default_true")]
    soft_delete: bool,
}

fn default_true() -> bool {
    true
}

async fn process_event(
    event: &OutboxRecord,
    producer: Option<&KafkaEventProducer>,
    _config: &OutboxConsumerConfig,
) -> Result<ProcessOutcome, ProcessingFailure> {
    let Some(producer) = producer else {
        info!(
            aggregate_type = %event.aggregate_type,
            aggregate_id = %event.aggregate_id,
            event_type = %event.event_type,
            "Kafka producer unavailable; marking outbox event as handled"
        );
        return Ok(ProcessOutcome::Skipped);
    };

    match (event.aggregate_type.as_str(), event.event_type.as_str()) {
        ("User", "UserDeleted") => {
            process_user_deleted(event, producer).await?;
            Ok(ProcessOutcome::Published)
        }
        (aggregate, event_type) => Err(ProcessingFailure::new(
            "unknown_event",
            format!(
                "Unsupported outbox event_type '{}' for aggregate '{}'",
                event_type, aggregate
            ),
        )),
    }
}

async fn process_user_deleted(
    event: &OutboxRecord,
    producer: &KafkaEventProducer,
) -> Result<(), ProcessingFailure> {
    let payload: UserDeletedPayload = serde_json::from_value(event.payload.clone())
        .map_err(|err| ProcessingFailure::new("payload_error", err.to_string()))?;

    // aggregate_id is stored as text, usually a UUID
    let aggregate_id = event
        .aggregate_id
        .parse::<Uuid>()
        .map_err(|err| ProcessingFailure::new("payload_error", err.to_string()))?;

    let user_id = payload.user_id.unwrap_or(aggregate_id);
    let deleted_at = payload.deleted_at.unwrap_or_else(Utc::now);

    producer
        .publish_user_deleted(user_id, deleted_at, payload.soft_delete)
        .await
        .map_err(|err| ProcessingFailure::new("publish_error", err.to_string()))?;

    info!(
        user_id = %user_id,
        deleted_at = %deleted_at,
        soft_delete = payload.soft_delete,
        "Published UserDeleted event to Kafka"
    );

    Ok(())
}

async fn send_to_dlq(
    producer: &KafkaEventProducer,
    topic: &str,
    event: &OutboxRecord,
    failure: &ProcessingFailure,
) -> Result<(), String> {
    let dlq_payload = json!({
        "event_id": event.id,
        "aggregate_type": event.aggregate_type,
        "aggregate_id": event.aggregate_id,
        "event_type": event.event_type,
        "payload": event.payload,
        "retry_count": event.retry_count,
        "failed_at": Utc::now(),
        "reason": failure.reason(),
        "error": failure.message(),
    });

    let key = format!("outbox-dlq-{}", event.aggregate_id);

    producer
        .publish_raw_to_topic(topic, &key, &dlq_payload.to_string())
        .await
        .map_err(|err| err.to_string())
}

async fn mark_published(db_pool: &PgPool, event_id: Uuid) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE outbox_events
        SET published_at = NOW()
        WHERE id = $1
        "#,
    )
    .bind(event_id)
    .execute(db_pool)
    .await
    .map(|_| ())
}

async fn increment_retry(db_pool: &PgPool, event_id: Uuid) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE outbox_events
        SET retry_count = retry_count + 1
        WHERE id = $1
        "#,
    )
    .bind(event_id)
    .execute(db_pool)
    .await
    .map(|_| ())
}

enum ProcessOutcome {
    Published,
    Skipped,
}

struct ProcessingFailure {
    reason: &'static str,
    message: String,
}

impl ProcessingFailure {
    fn new(reason: &'static str, message: impl Into<String>) -> Self {
        Self {
            reason,
            message: message.into(),
        }
    }

    fn reason(&self) -> &'static str {
        self.reason
    }

    fn message(&self) -> &str {
        &self.message
    }

    fn is_fatal(&self) -> bool {
        matches!(self.reason, "unknown_event" | "payload_error")
    }
}
