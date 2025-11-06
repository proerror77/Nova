use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Priority levels for outbox events
/// Lower number = higher priority (like Unix nice values)
pub mod priority {
    /// Critical events that must be delivered immediately (e.g., payment confirmations)
    pub const CRITICAL: u8 = 0;
    /// High priority events (e.g., user notifications)
    pub const HIGH: u8 = 1;
    /// Normal priority events (e.g., content updates)
    pub const NORMAL: u8 = 2;
    /// Low priority events (e.g., analytics, metrics)
    pub const LOW: u8 = 3;
}

/// Outbox event stored in database for reliable event publishing
///
/// This implements the Transactional Outbox Pattern to ensure atomicity
/// between database writes and event publishing to Kafka.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OutboxEvent {
    /// Unique event ID
    pub id: Uuid,
    /// Aggregate ID (e.g., user_id, post_id, message_id)
    pub aggregate_id: Uuid,
    /// Event type (e.g., "MessageCreated", "PostDeleted")
    pub event_type: String,
    /// Serialized event payload (JSON)
    pub payload: String,
    /// Priority level (0=CRITICAL, 1=HIGH, 2=NORMAL, 3=LOW)
    pub priority: u8,
    /// Event creation timestamp
    pub created_at: DateTime<Utc>,
    /// Event publication timestamp (NULL if not yet published)
    pub published_at: Option<DateTime<Utc>>,
    /// Number of publish retry attempts
    pub retry_count: u32,
    /// Last error message if publish failed
    pub last_error: Option<String>,
}

impl OutboxEvent {
    /// Create a new outbox event
    pub fn new(
        aggregate_id: Uuid,
        event_type: impl Into<String>,
        payload: impl Serialize,
        priority: u8,
    ) -> Result<Self, serde_json::Error> {
        Ok(Self {
            id: Uuid::new_v4(),
            aggregate_id,
            event_type: event_type.into(),
            payload: serde_json::to_string(&payload)?,
            priority,
            created_at: Utc::now(),
            published_at: None,
            retry_count: 0,
            last_error: None,
        })
    }

    /// Get the Kafka topic name for this event
    /// Topic naming: nova.<service>.<aggregate>.<action>
    pub fn kafka_topic(&self) -> String {
        // Parse event_type to extract components
        // Example: "MessageCreated" -> "nova.messaging.message.created"
        let event_type = &self.event_type;

        // Simple heuristic: split camel case and convert to lowercase
        let parts = split_camel_case(event_type);

        if parts.len() >= 2 {
            let aggregate = parts[0].to_lowercase();
            let action = parts[1].to_lowercase();

            // Determine service from aggregate type
            let service = infer_service(&aggregate);

            format!("nova.{}.{}.{}", service, aggregate, action)
        } else {
            // Fallback for unparseable event types
            format!("nova.events.{}", event_type.to_lowercase())
        }
    }

    /// Get the partition key for Kafka
    /// We use aggregate_id to ensure ordered processing for the same entity
    pub fn partition_key(&self) -> String {
        self.aggregate_id.to_string()
    }

    /// Convert to Kafka message (key, value, headers)
    pub fn to_kafka_message(&self) -> KafkaMessage {
        let headers = vec![
            ("event_id".to_string(), self.id.to_string()),
            ("event_type".to_string(), self.event_type.clone()),
            ("priority".to_string(), self.priority.to_string()),
            ("created_at".to_string(), self.created_at.to_rfc3339()),
        ];

        KafkaMessage {
            key: self.partition_key(),
            value: self.payload.clone(),
            headers,
        }
    }

    /// Mark event as published
    pub fn mark_published(&mut self) {
        self.published_at = Some(Utc::now());
    }

    /// Mark event as failed and increment retry count
    pub fn mark_failed(&mut self, error: impl Into<String>) {
        self.retry_count += 1;
        self.last_error = Some(error.into());
    }

    /// Check if event should be retried
    /// Uses exponential backoff strategy
    pub fn should_retry(&self, max_retries: u32) -> bool {
        if self.retry_count >= max_retries {
            return false;
        }

        if self.published_at.is_some() {
            // Already published successfully
            return false;
        }

        // Calculate exponential backoff
        let backoff_seconds = 2_i64.pow(self.retry_count.min(10)); // Cap at 1024 seconds
        let next_retry_time = self.created_at + chrono::Duration::seconds(backoff_seconds);

        Utc::now() >= next_retry_time
    }

    /// Check if event is expired and should be discarded
    pub fn is_expired(&self, max_age_hours: i64) -> bool {
        let age = Utc::now().signed_duration_since(self.created_at);
        age.num_hours() > max_age_hours
    }
}

/// Kafka message structure
#[derive(Debug, Clone)]
pub struct KafkaMessage {
    /// Partition key (usually aggregate_id)
    pub key: String,
    /// Message value (JSON payload)
    pub value: String,
    /// Message headers
    pub headers: Vec<(String, String)>,
}

/// Split camel case string into parts
/// Example: "MessageCreated" -> ["Message", "Created"]
fn split_camel_case(s: &str) -> Vec<String> {
    let mut result = Vec::new();
    let mut current = String::new();

    for ch in s.chars() {
        if ch.is_uppercase() && !current.is_empty() {
            result.push(current.clone());
            current.clear();
        }
        current.push(ch);
    }

    if !current.is_empty() {
        result.push(current);
    }

    result
}

/// Infer service name from aggregate type
fn infer_service(aggregate: &str) -> &'static str {
    match aggregate {
        "message" | "conversation" => "messaging",
        "post" | "comment" | "like" | "following" => "content",
        "user" | "password" | "twofa" => "auth",
        "media" | "transcoding" => "media",
        "notification" => "notification",
        "stream" | "viewer" => "streaming",
        "feed" | "candidate" | "engagement" => "feed",
        "search" | "index" => "search",
        _ => "events",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_outbox_event_creation() {
        let aggregate_id = Uuid::new_v4();
        let payload = json!({
            "message_id": aggregate_id,
            "content": "Hello World"
        });

        let event = OutboxEvent::new(
            aggregate_id,
            "MessageCreated",
            &payload,
            priority::NORMAL,
        ).unwrap();

        assert_eq!(event.aggregate_id, aggregate_id);
        assert_eq!(event.event_type, "MessageCreated");
        assert_eq!(event.priority, priority::NORMAL);
        assert_eq!(event.retry_count, 0);
        assert!(event.published_at.is_none());
        assert!(event.last_error.is_none());
    }

    #[test]
    fn test_kafka_topic_generation() {
        let event = OutboxEvent {
            id: Uuid::new_v4(),
            aggregate_id: Uuid::new_v4(),
            event_type: "MessageCreated".to_string(),
            payload: "{}".to_string(),
            priority: priority::NORMAL,
            created_at: Utc::now(),
            published_at: None,
            retry_count: 0,
            last_error: None,
        };

        assert_eq!(event.kafka_topic(), "nova.messaging.message.created");
    }

    #[test]
    fn test_kafka_topic_various_events() {
        let test_cases = vec![
            ("PostCreated", "nova.content.post.created"),
            ("UserDeleted", "nova.auth.user.deleted"),
            ("StreamStarted", "nova.streaming.stream.started"),
            ("NotificationSent", "nova.notification.notification.sent"),
        ];

        for (event_type, expected_topic) in test_cases {
            let event = OutboxEvent {
                id: Uuid::new_v4(),
                aggregate_id: Uuid::new_v4(),
                event_type: event_type.to_string(),
                payload: "{}".to_string(),
                priority: priority::NORMAL,
                created_at: Utc::now(),
                published_at: None,
                retry_count: 0,
                last_error: None,
            };

            assert_eq!(event.kafka_topic(), expected_topic);
        }
    }

    #[test]
    fn test_partition_key() {
        let aggregate_id = Uuid::new_v4();
        let event = OutboxEvent {
            id: Uuid::new_v4(),
            aggregate_id,
            event_type: "MessageCreated".to_string(),
            payload: "{}".to_string(),
            priority: priority::NORMAL,
            created_at: Utc::now(),
            published_at: None,
            retry_count: 0,
            last_error: None,
        };

        assert_eq!(event.partition_key(), aggregate_id.to_string());
    }

    #[test]
    fn test_kafka_message_generation() {
        let event = OutboxEvent {
            id: Uuid::new_v4(),
            aggregate_id: Uuid::new_v4(),
            event_type: "MessageCreated".to_string(),
            payload: r#"{"content":"test"}"#.to_string(),
            priority: priority::HIGH,
            created_at: Utc::now(),
            published_at: None,
            retry_count: 0,
            last_error: None,
        };

        let kafka_msg = event.to_kafka_message();

        assert_eq!(kafka_msg.key, event.partition_key());
        assert_eq!(kafka_msg.value, r#"{"content":"test"}"#);
        assert!(kafka_msg.headers.iter().any(|(k, _)| k == "event_id"));
        assert!(kafka_msg.headers.iter().any(|(k, _)| k == "event_type"));
        assert!(kafka_msg.headers.iter().any(|(k, _)| k == "priority"));
    }

    #[test]
    fn test_mark_published() {
        let mut event = OutboxEvent {
            id: Uuid::new_v4(),
            aggregate_id: Uuid::new_v4(),
            event_type: "MessageCreated".to_string(),
            payload: "{}".to_string(),
            priority: priority::NORMAL,
            created_at: Utc::now(),
            published_at: None,
            retry_count: 0,
            last_error: None,
        };

        assert!(event.published_at.is_none());
        event.mark_published();
        assert!(event.published_at.is_some());
    }

    #[test]
    fn test_mark_failed() {
        let mut event = OutboxEvent {
            id: Uuid::new_v4(),
            aggregate_id: Uuid::new_v4(),
            event_type: "MessageCreated".to_string(),
            payload: "{}".to_string(),
            priority: priority::NORMAL,
            created_at: Utc::now(),
            published_at: None,
            retry_count: 0,
            last_error: None,
        };

        event.mark_failed("Connection timeout");
        assert_eq!(event.retry_count, 1);
        assert_eq!(event.last_error, Some("Connection timeout".to_string()));

        event.mark_failed("Broker unavailable");
        assert_eq!(event.retry_count, 2);
        assert_eq!(event.last_error, Some("Broker unavailable".to_string()));
    }

    #[test]
    fn test_should_retry() {
        let mut event = OutboxEvent {
            id: Uuid::new_v4(),
            aggregate_id: Uuid::new_v4(),
            event_type: "MessageCreated".to_string(),
            payload: "{}".to_string(),
            priority: priority::NORMAL,
            created_at: Utc::now() - chrono::Duration::hours(1),
            published_at: None,
            retry_count: 0,
            last_error: None,
        };

        // Should retry when below max_retries and enough time has passed
        assert!(event.should_retry(5));

        // Should not retry when max_retries reached
        event.retry_count = 5;
        assert!(!event.should_retry(5));

        // Should not retry when already published
        event.retry_count = 0;
        event.mark_published();
        assert!(!event.should_retry(5));
    }

    #[test]
    fn test_is_expired() {
        let event = OutboxEvent {
            id: Uuid::new_v4(),
            aggregate_id: Uuid::new_v4(),
            event_type: "MessageCreated".to_string(),
            payload: "{}".to_string(),
            priority: priority::NORMAL,
            created_at: Utc::now() - chrono::Duration::hours(25),
            published_at: None,
            retry_count: 0,
            last_error: None,
        };

        assert!(event.is_expired(24));
        assert!(!event.is_expired(48));
    }

    #[test]
    fn test_split_camel_case() {
        assert_eq!(
            split_camel_case("MessageCreated"),
            vec!["Message", "Created"]
        );
        assert_eq!(
            split_camel_case("UserProfileUpdated"),
            vec!["User", "Profile", "Updated"]
        );
        assert_eq!(split_camel_case("Simple"), vec!["Simple"]);
    }

    #[test]
    fn test_priority_constants() {
        assert_eq!(priority::CRITICAL, 0);
        assert_eq!(priority::HIGH, 1);
        assert_eq!(priority::NORMAL, 2);
        assert_eq!(priority::LOW, 3);
    }
}
