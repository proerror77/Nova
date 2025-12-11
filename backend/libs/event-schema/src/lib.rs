use chrono::{DateTime, Utc};
/// Event Schema Registry for all Kafka topics across Nova microservices
///
/// This library defines versioned event schemas to prevent payload incompatibilities
/// as services evolve. Each event has a required `schema_version` field.
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// Outbox pattern for transactional event publishing
pub mod outbox;
// Domain events enumeration
pub mod events;

// Re-export commonly used types
pub use events::DomainEvent;
pub use outbox::{priority, KafkaMessage, OutboxEvent};

/// Current schema version for all events
pub const SCHEMA_VERSION: u32 = 1;

/// Base event envelope for all Kafka messages
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventEnvelope<T> {
    /// Unique event ID for idempotency and tracing
    pub event_id: Uuid,
    /// Event timestamp
    pub timestamp: DateTime<Utc>,
    /// Schema version for compatibility checking
    pub schema_version: u32,
    /// Source service that generated the event
    pub source: String,
    /// Correlation ID for distributed tracing
    pub correlation_id: Option<Uuid>,
    /// Actual event payload
    pub data: T,
}

impl<T> EventEnvelope<T> {
    pub fn new(source: impl Into<String>, data: T) -> Self {
        Self {
            event_id: Uuid::new_v4(),
            timestamp: Utc::now(),
            schema_version: SCHEMA_VERSION,
            source: source.into(),
            correlation_id: None,
            data,
        }
    }

    pub fn with_correlation_id(mut self, correlation_id: Uuid) -> Self {
        self.correlation_id = Some(correlation_id);
        self
    }
}

// ============================================================================
// AUTH SERVICE EVENTS
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserCreatedEvent {
    pub user_id: Uuid,
    pub email: String,
    pub username: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PasswordChangedEvent {
    pub user_id: Uuid,
    pub changed_at: DateTime<Utc>,
    pub invalidate_all_sessions: bool, // true = logout everywhere
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TwoFAEnabledEvent {
    pub user_id: Uuid,
    pub enabled_at: DateTime<Utc>,
    pub method: String, // "totp", "sms", etc.
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserDeletedEvent {
    pub user_id: Uuid,
    pub deleted_at: DateTime<Utc>,
    pub soft_delete: bool, // false = hard delete user data
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserProfileUpdatedEvent {
    pub user_id: Uuid,
    pub username: String,
    pub display_name: Option<String>,
    pub bio: Option<String>,
    pub avatar_url: Option<String>,
    pub is_verified: bool,
    pub follower_count: i32,
    pub updated_at: DateTime<Utc>,
}

// ============================================================================
// CONTENT SERVICE EVENTS
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PostCreatedEvent {
    pub post_id: Uuid,
    pub user_id: Uuid,
    pub content: String,
    pub content_type: String, // "text", "image", "video", "story"
    pub media_ids: Vec<Uuid>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PostDeletedEvent {
    pub post_id: Uuid,
    pub user_id: Uuid,
    pub deleted_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommentCreatedEvent {
    pub comment_id: Uuid,
    pub post_id: Uuid,
    pub user_id: Uuid,
    pub content: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommentDeletedEvent {
    pub comment_id: Uuid,
    pub post_id: Uuid,
    pub deleted_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LikeCreatedEvent {
    pub like_id: Uuid,
    pub target_id: Uuid,     // post_id or comment_id
    pub target_type: String, // "post", "comment"
    pub user_id: Uuid,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LikeDeletedEvent {
    pub like_id: Uuid,
    pub target_id: Uuid,
    pub target_type: String,
    pub deleted_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FollowingCreatedEvent {
    pub following_id: Uuid,
    pub follower_id: Uuid,
    pub following_user_id: Uuid,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FollowingDeletedEvent {
    pub following_id: Uuid,
    pub follower_id: Uuid,
    pub following_user_id: Uuid,
    pub deleted_at: DateTime<Utc>,
}

// ============================================================================
// MEDIA SERVICE EVENTS
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MediaUploadedEvent {
    pub media_id: Uuid,
    pub user_id: Uuid,
    pub media_type: String, // "image", "video", "audio"
    pub file_size: u64,
    pub s3_key: String,
    pub mime_type: String,
    pub uploaded_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscodingStartedEvent {
    pub transcoding_id: Uuid,
    pub media_id: Uuid,
    pub quality: String, // "360p", "720p", "1080p"
    pub started_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscodingCompletedEvent {
    pub transcoding_id: Uuid,
    pub media_id: Uuid,
    pub quality: String,
    pub output_s3_key: String,
    pub duration_seconds: Option<u32>,
    pub completed_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscodingFailedEvent {
    pub transcoding_id: Uuid,
    pub media_id: Uuid,
    pub quality: String,
    pub error_message: String,
    pub failed_at: DateTime<Utc>,
}

// ============================================================================
// FEED/RECOMMENDATION SERVICE EVENTS
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeedCandidateAddedEvent {
    pub candidate_id: Uuid,
    pub post_id: Uuid,
    pub user_id: Uuid,
    pub source: String, // "following", "trending", "recommended"
    pub score: f64,
    pub added_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeedInvalidatedEvent {
    pub user_id: Uuid,
    pub reason: String, // "new_post", "follow_change", "profile_update"
    pub invalidated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PostEngagementEvent {
    pub post_id: Uuid,
    pub user_id: Uuid,
    pub action: String, // "viewed", "liked", "commented", "shared"
    pub action_at: DateTime<Utc>,
}

// ============================================================================
// NOTIFICATION SERVICE EVENTS
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NotificationCreatedEvent {
    pub notification_id: Uuid,
    pub user_id: Uuid,
    pub title: String,
    pub body: String,
    pub notification_type: String, // "like", "comment", "follow", "message"
    pub related_user_id: Option<Uuid>,
    pub related_post_id: Option<Uuid>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NotificationSentEvent {
    pub notification_id: Uuid,
    pub user_id: Uuid,
    pub channels: Vec<String>, // "push", "email", "sms"
    pub sent_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NotificationReadEvent {
    pub notification_id: Uuid,
    pub user_id: Uuid,
    pub read_at: DateTime<Utc>,
}

// ============================================================================
// MESSAGING SERVICE EVENTS
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageSentEvent {
    pub message_id: Uuid,
    pub conversation_id: Uuid,
    pub sender_id: Uuid,
    pub content: String,
    pub message_type: String, // "text", "media", "system"
    pub sent_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageReadEvent {
    pub message_id: Uuid,
    pub reader_id: Uuid,
    pub read_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConversationCreatedEvent {
    pub conversation_id: Uuid,
    pub participants: Vec<Uuid>,
    pub is_group: bool,
    pub created_at: DateTime<Utc>,
}

// ============================================================================
// STREAMING SERVICE EVENTS
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LiveStreamStartedEvent {
    pub stream_id: Uuid,
    pub user_id: Uuid,
    pub title: String,
    pub preview_image_url: Option<String>,
    pub started_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LiveStreamEndedEvent {
    pub stream_id: Uuid,
    pub user_id: Uuid,
    pub viewer_count: u32,
    pub duration_seconds: u32,
    pub ended_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LiveViewerUpdateEvent {
    pub stream_id: Uuid,
    pub current_viewers: u32,
    pub updated_at: DateTime<Utc>,
}

// ============================================================================
// Version compatibility helpers
// ============================================================================

pub fn is_compatible(current_version: u32, message_version: u32) -> bool {
    // For now, enforce exact version match
    // In future, implement backward compatibility logic
    current_version == message_version
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_event_envelope_creation() {
        let event = UserCreatedEvent {
            user_id: Uuid::new_v4(),
            email: "test@example.com".to_string(),
            username: "testuser".to_string(),
            created_at: Utc::now(),
        };

        let envelope = EventEnvelope::new("auth-service", event);
        assert_eq!(envelope.schema_version, SCHEMA_VERSION);
        assert_eq!(envelope.source, "auth-service");
        assert!(envelope.correlation_id.is_none());
    }

    #[test]
    fn test_version_compatibility() {
        assert!(is_compatible(SCHEMA_VERSION, SCHEMA_VERSION));
        assert!(!is_compatible(1, 2));
    }
}
