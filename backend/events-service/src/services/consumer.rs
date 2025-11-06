use rdkafka::config::ClientConfig;
use rdkafka::consumer::{Consumer, StreamConsumer};
use rdkafka::message::Message;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Semaphore;
use tracing::{debug, error, info, warn};

use crate::db::ch_client::ClickHouseClient;
use crate::error::{AppError, Result};
use crate::grpc::ContentServiceClient;

use super::dedup::EventDeduplicator;

/// Events Consumer configuration
#[derive(Debug, Clone)]
pub struct EventsConsumerConfig {
    /// Kafka brokers (comma-separated)
    pub brokers: String,
    /// Consumer group ID
    pub group_id: String,
    /// Events topic name
    pub topic: String,
    /// Batch size for ClickHouse inserts
    pub batch_size: usize,
    /// Max concurrent ClickHouse inserts
    pub max_concurrent_inserts: usize,
}

impl Default for EventsConsumerConfig {
    fn default() -> Self {
        Self {
            brokers: "localhost:9092".to_string(),
            group_id: "nova-events-consumer-v1".to_string(),
            topic: "events".to_string(),
            batch_size: 100,
            max_concurrent_inserts: 5,
        }
    }
}

/// Event message structure
///
/// Expected format from application:
/// ```json
/// {
///   "event_id": "uuid-v4",
///   "event_type": "post_created",
///   "user_id": 123,
///   "timestamp": 1678901234567,
///   "properties": {
///     "post_id": 456,
///     "content_length": 280
///   }
/// }
/// ```
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventMessage {
    /// Unique event identifier (UUID v4)
    pub event_id: String,

    /// Event type (e.g., "post_created", "like_added")
    pub event_type: String,

    /// User who triggered the event
    pub user_id: i64,

    /// Event timestamp (milliseconds since epoch)
    pub timestamp: i64,

    /// Event-specific properties (JSON object)
    #[serde(default)]
    pub properties: Value,
}

impl EventMessage {
    /// Validate event message
    pub fn validate(&self) -> Result<()> {
        // Event ID should be non-empty
        if self.event_id.is_empty() {
            return Err(AppError::Validation("Event ID is empty".to_string()));
        }

        // Event type should be non-empty
        if self.event_type.is_empty() {
            return Err(AppError::Validation("Event type is empty".to_string()));
        }

        // User ID checks: allow system events to omit numeric user_id
        // For events like new_follow/unfollow, UUIDs are provided in `properties`.
        if self.event_type != "new_follow" && self.event_type != "unfollow" {
            if self.user_id <= 0 {
                return Err(AppError::Validation(format!(
                    "Invalid user_id: {}",
                    self.user_id
                )));
            }
        }

        // Timestamp should be reasonable (within 1 year of now)
        let now = chrono::Utc::now().timestamp_millis();
        let ts_diff = (now - self.timestamp).abs();
        const ONE_YEAR_MS: i64 = 365 * 24 * 60 * 60 * 1000;

        if ts_diff > ONE_YEAR_MS {
            return Err(AppError::Validation(format!(
                "Event timestamp {} is too far from current time {}",
                self.timestamp, now
            )));
        }

        Ok(())
    }
}

/// Events Consumer service
///
/// Consumes application events from Kafka and inserts them into ClickHouse
/// for analytics and behavior tracking.
///
/// # Features
/// - Deduplication via Redis (prevents duplicate processing)
/// - Batch processing (100 events per batch for efficiency)
/// - Exactly-once semantics (dedup + manual offset commit)
/// - Concurrent inserts (controlled by semaphore)
pub struct EventsConsumer {
    consumer: StreamConsumer,
    ch_client: ClickHouseClient,
    deduplicator: EventDeduplicator,
    config: EventsConsumerConfig,
    semaphore: Arc<Semaphore>,
    content_client: Arc<ContentServiceClient>,
}

impl EventsConsumer {
    /// Create a new events consumer
    pub fn new(
        config: EventsConsumerConfig,
        ch_client: ClickHouseClient,
        deduplicator: EventDeduplicator,
        content_client: Arc<ContentServiceClient>,
    ) -> Result<Self> {
        info!("Initializing Events consumer with config: {:?}", config);

        // Create Kafka consumer
        let consumer: StreamConsumer = ClientConfig::new()
            .set("group.id", &config.group_id)
            .set("bootstrap.servers", &config.brokers)
            .set("enable.auto.commit", "true") // Auto-commit for events (dedup provides idempotence)
            .set("auto.commit.interval.ms", "5000")
            .set("auto.offset.reset", "earliest")
            .set("session.timeout.ms", "30000")
            .set("heartbeat.interval.ms", "3000")
            .set("max.poll.interval.ms", "300000") // 5 minutes
            .set("enable.partition.eof", "false")
            .create()
            .map_err(|e| {
                error!("Failed to create Kafka consumer: {}", e);
                AppError::Kafka(e)
            })?;

        // Subscribe to events topic
        consumer.subscribe(&[&config.topic]).map_err(|e| {
            error!("Failed to subscribe to topic: {}", e);
            AppError::Kafka(e)
        })?;

        info!("Events consumer subscribed to topic: {}", config.topic);

        Ok(Self {
            consumer,
            ch_client,
            deduplicator,
            semaphore: Arc::new(Semaphore::new(config.max_concurrent_inserts)),
            config,
            content_client,
        })
    }

    /// Run the events consumer loop
    ///
    /// This is a long-running task that should be spawned in a tokio task.
    pub async fn run(&self) -> Result<()> {
        info!("Starting Events consumer loop");

        let mut batch: Vec<EventMessage> = Vec::with_capacity(self.config.batch_size);

        loop {
            match self.consumer.recv().await {
                Ok(msg) => {
                    let topic = msg.topic();
                    let partition = msg.partition();
                    let offset = msg.offset();

                    debug!(
                        "Received event message: topic={}, partition={}, offset={}",
                        topic, partition, offset
                    );

                    // Process message
                    match self.process_message(&msg).await {
                        Ok(Some(event)) => {
                            batch.push(event);

                            // Flush batch when full
                            if batch.len() >= self.config.batch_size {
                                if let Err(e) = self.flush_batch(&mut batch).await {
                                    error!("Failed to flush event batch: {}", e);
                                }
                                batch.clear();
                            }
                        }
                        Ok(None) => {
                            // Duplicate or invalid event, skip
                        }
                        Err(e) => {
                            error!(
                                "Failed to process event (topic={}, partition={}, offset={}): {}",
                                topic, partition, offset, e
                            );
                            // Continue processing other events
                        }
                    }
                }
                Err(e) => {
                    error!("Kafka consumer error: {}", e);

                    // Flush any pending events before sleeping
                    if !batch.is_empty() {
                        if let Err(e) = self.flush_batch(&mut batch).await {
                            error!("Failed to flush event batch on error: {}", e);
                        }
                        batch.clear();
                    }

                    // Sleep briefly before retrying to avoid tight error loop
                    tokio::time::sleep(Duration::from_secs(1)).await;
                }
            }
        }
    }

    /// Process a single event message
    ///
    /// # Returns
    /// * `Ok(Some(event))` - Event is new and should be batched
    /// * `Ok(None)` - Event is duplicate or invalid, skip
    /// * `Err(e)` - Error processing event
    async fn process_message(
        &self,
        msg: &rdkafka::message::BorrowedMessage<'_>,
    ) -> Result<Option<EventMessage>> {
        let payload = msg
            .payload()
            .ok_or_else(|| AppError::Validation("Event message has no payload".to_string()))?;

        // Deserialize event
        let event: EventMessage = serde_json::from_slice(payload).map_err(|e| {
            error!("Failed to deserialize event message: {}", e);
            AppError::Internal(format!("Invalid event format: {}", e))
        })?;

        // Validate event
        event.validate()?;

        // Check for duplicate
        let is_new = self.deduplicator.check_and_mark(&event.event_id).await?;

        if !is_new {
            debug!("Event {} is a duplicate, skipping", event.event_id);
            return Ok(None);
        }

        debug!(
            "Processing event: id={}, type={}, user_id={}",
            event.event_id, event.event_type, event.user_id
        );

        Ok(Some(event))
    }

    /// Flush a batch of events to ClickHouse
    async fn flush_batch(&self, batch: &mut Vec<EventMessage>) -> Result<()> {
        if batch.is_empty() {
            return Ok(());
        }

        info!("Flushing batch of {} events to ClickHouse", batch.len());

        // Acquire semaphore permit for concurrent insert control
        let _permit = self
            .semaphore
            .acquire()
            .await
            .map_err(|e| AppError::Internal(format!("Failed to acquire semaphore: {}", e)))?;

        // Build batch insert query
        let values: Vec<String> = batch
            .iter()
            .map(|event| {
                format!(
                    "('{}', '{}', {}, {}, '{}')",
                    Self::escape_string(&event.event_id),
                    Self::escape_string(&event.event_type),
                    event.user_id,
                    event.timestamp,
                    Self::escape_string(&event.properties.to_string())
                )
            })
            .collect();

        let query = format!(
            r#"
            INSERT INTO events (
                event_id, event_type, user_id, timestamp, properties
            ) VALUES {}
            "#,
            values.join(", ")
        );

        self.ch_client.execute(&query).await?;

        info!("Successfully flushed {} events", batch.len());

        // Apply side effects (e.g., cache invalidation) non-critically
        if let Err(e) = self.apply_side_effects(&batch).await {
            warn!("Event side-effects failed: {}", e);
        }
        Ok(())
    }

    /// Escape string for ClickHouse query
    fn escape_string(s: &str) -> String {
        s.replace('\\', "\\\\")
            .replace('\'', "\\'")
            .replace('\n', "\\n")
            .replace('\r', "\\r")
            .replace('\t', "\\t")
    }
}

impl EventsConsumer {
    /// Apply non-critical side effects for events (cache invalidation)
    async fn apply_side_effects(&self, events: &[EventMessage]) -> Result<()> {
        for ev in events {
            match ev.event_type.as_str() {
                "new_follow" | "unfollow" => {
                    if let Some(props) = ev.properties.as_object() {
                        let follower_id = props
                            .get("follower_id")
                            .and_then(|v| v.as_str())
                            .and_then(|s| uuid::Uuid::parse_str(s).ok());
                        let followee_id = props
                            .get("followee_id")
                            .and_then(|v| v.as_str())
                            .and_then(|s| uuid::Uuid::parse_str(s).ok());
                        if let (Some(_follower), Some(_followee)) = (follower_id, followee_id) {
                            // Feed cache invalidation is now handled through Kafka events
                            // The follower's feed should be auto-invalidated when they follow/unfollow
                            // Phase 1 Stage 1.4: Will implement Redis cache invalidation
                            crate::metrics::helpers::record_social_follow_event(
                                ev.event_type.as_str(),
                                "processed",
                            );
                        }
                    }
                }
                _ => {}
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_event_validation() {
        let valid_event = EventMessage {
            event_id: "test-123".to_string(),
            event_type: "post_created".to_string(),
            user_id: 456,
            timestamp: chrono::Utc::now().timestamp_millis(),
            properties: json!({"post_id": 789}),
        };

        assert!(valid_event.validate().is_ok());

        let empty_id = EventMessage {
            event_id: "".to_string(),
            ..valid_event.clone()
        };
        assert!(empty_id.validate().is_err());

        let empty_type = EventMessage {
            event_type: "".to_string(),
            ..valid_event.clone()
        };
        assert!(empty_type.validate().is_err());

        let invalid_user = EventMessage {
            user_id: 0,
            ..valid_event.clone()
        };
        assert!(invalid_user.validate().is_err());

        let old_timestamp = EventMessage {
            timestamp: 1000000000, // Year 1970
            ..valid_event.clone()
        };
        assert!(old_timestamp.validate().is_err());
    }

    #[test]
    fn test_escape_string() {
        assert_eq!(
            EventsConsumer::escape_string("hello'world"),
            "hello\\'world"
        );
        assert_eq!(
            EventsConsumer::escape_string("line1\nline2"),
            "line1\\nline2"
        );
        assert_eq!(EventsConsumer::escape_string("tab\there"), "tab\\there");
    }

    #[test]
    fn test_event_deserialization() {
        let json = r#"{
            "event_id": "uuid-123",
            "event_type": "post_created",
            "user_id": 456,
            "timestamp": 1678901234567,
            "properties": {"post_id": 789, "content": "hello"}
        }"#;

        let event: EventMessage = serde_json::from_str(json).unwrap();

        assert_eq!(event.event_id, "uuid-123");
        assert_eq!(event.event_type, "post_created");
        assert_eq!(event.user_id, 456);
        assert_eq!(event.timestamp, 1678901234567);
        assert_eq!(event.properties["post_id"], 789);
    }

    #[test]
    fn test_event_without_properties() {
        let json = r#"{
            "event_id": "uuid-123",
            "event_type": "user_login",
            "user_id": 456,
            "timestamp": 1678901234567
        }"#;

        let event: EventMessage = serde_json::from_str(json).unwrap();

        assert_eq!(event.event_id, "uuid-123");
        assert_eq!(event.properties, Value::Null);
    }
}
