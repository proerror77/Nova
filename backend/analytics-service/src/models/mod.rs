use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Domain Event - Represents a business event that occurred in the system
///
/// Domain events are immutable records of things that have happened.
/// They follow the pattern: `<aggregate>.<action>` (e.g., "user.created", "post.published")
///
/// # Example
/// ```ignore
/// let event = DomainEvent {
///     id: Uuid::new_v4(),
///     event_type: "user.created".to_string(),
///     aggregate_id: user_id.to_string(),
///     aggregate_type: "user".to_string(),
///     version: 1,
///     data: serde_json::json!({"username": "alice", "email": "alice@example.com"}),
///     metadata: Some(serde_json::json!({"source": "api"})),
///     correlation_id: Some(request_id),
///     causation_id: None,
///     created_at: Utc::now(),
///     created_by: Some("system".to_string()),
/// };
/// ```
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DomainEvent {
    /// Unique event identifier
    pub id: Uuid,

    /// Event type (e.g., "user.created", "post.published")
    pub event_type: String,

    /// ID of the aggregate (entity) that triggered the event
    pub aggregate_id: String,

    /// Type of aggregate (user, post, message, etc.)
    pub aggregate_type: String,

    /// Event schema version (for evolution)
    pub version: i32,

    /// Event data as JSON
    pub data: serde_json::Value,

    /// Optional metadata (correlation_id, source, etc.)
    pub metadata: Option<serde_json::Value>,

    /// For tracing related events across services
    pub correlation_id: Option<Uuid>,

    /// ID of the event that caused this one
    pub causation_id: Option<Uuid>,

    /// Timestamp when event occurred
    pub created_at: DateTime<Utc>,

    /// User/service that triggered the event
    pub created_by: Option<String>,
}

impl DomainEvent {
    /// Create a new domain event
    pub fn new(
        event_type: String,
        aggregate_id: String,
        aggregate_type: String,
        data: serde_json::Value,
    ) -> Self {
        Self {
            id: Uuid::new_v4(),
            event_type,
            aggregate_id,
            aggregate_type,
            version: 1,
            data,
            metadata: None,
            correlation_id: None,
            causation_id: None,
            created_at: Utc::now(),
            created_by: None,
        }
    }

    /// Create event with correlation tracking
    pub fn with_correlation(
        event_type: String,
        aggregate_id: String,
        aggregate_type: String,
        data: serde_json::Value,
        correlation_id: Uuid,
    ) -> Self {
        Self {
            id: Uuid::new_v4(),
            event_type,
            aggregate_id,
            aggregate_type,
            version: 1,
            data,
            metadata: None,
            correlation_id: Some(correlation_id),
            causation_id: None,
            created_at: Utc::now(),
            created_by: None,
        }
    }
}

/// Event Schema - JSON schema definition for event validation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventSchema {
    pub id: Uuid,
    pub event_type: String,
    pub version: i32,
    pub schema_json: serde_json::Value,
    pub description: Option<String>,
    pub example_payload: Option<serde_json::Value>,
    pub is_active: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Event Subscription - Tracks which services subscribe to which events
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventSubscription {
    pub id: Uuid,
    pub subscriber_service: String,
    pub event_types: Vec<String>,
    pub endpoint: Option<String>,
    pub subscription_type: SubscriptionType,
    pub is_active: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Subscription type enum
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum SubscriptionType {
    PushGrpc,
    PullGrpc,
    KafkaConsumer,
}

impl std::fmt::Display for SubscriptionType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::PushGrpc => write!(f, "push_grpc"),
            Self::PullGrpc => write!(f, "pull_grpc"),
            Self::KafkaConsumer => write!(f, "kafka_consumer"),
        }
    }
}

impl std::str::FromStr for SubscriptionType {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "push_grpc" => Ok(Self::PushGrpc),
            "pull_grpc" => Ok(Self::PullGrpc),
            "kafka_consumer" => Ok(Self::KafkaConsumer),
            _ => Err(format!("Invalid subscription type: {}", s)),
        }
    }
}

/// Kafka Topic Configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KafkaTopic {
    pub id: Uuid,
    pub topic_name: String,
    pub event_types: Vec<String>,
    pub partitions: i32,
    pub replication_factor: i32,
    pub retention_ms: Option<i64>,
    pub is_active: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Event Statistics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventStats {
    pub total_events_published: i32,
    pub total_events_processed: i32,
    pub failed_events: i32,
    pub events_by_type: std::collections::HashMap<String, i32>,
}

impl Default for EventStats {
    fn default() -> Self {
        Self {
            total_events_published: 0,
            total_events_processed: 0,
            failed_events: 0,
            events_by_type: std::collections::HashMap::new(),
        }
    }
}
