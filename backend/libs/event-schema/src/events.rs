use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::outbox::priority;

/// Domain events enumeration covering all critical business events
///
/// This enum provides a type-safe way to work with domain events across
/// the entire system, ensuring consistent event handling and priority assignment.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", content = "data")]
pub enum DomainEvent {
    // ============================================================================
    // MESSAGING SERVICE EVENTS
    // ============================================================================
    MessageCreated {
        message_id: Uuid,
        conversation_id: Uuid,
        sender_id: Uuid,
        content: String,
        message_type: String,
        created_at: DateTime<Utc>,
    },

    MessageEdited {
        message_id: Uuid,
        conversation_id: Uuid,
        new_content: String,
        edited_at: DateTime<Utc>,
    },

    MessageDeleted {
        message_id: Uuid,
        conversation_id: Uuid,
        deleted_at: DateTime<Utc>,
    },

    // ============================================================================
    // CONTENT SERVICE EVENTS - Reactions
    // ============================================================================
    ReactionAdded {
        reaction_id: Uuid,
        target_id: Uuid,     // post_id or comment_id
        target_type: String, // "post" or "comment"
        user_id: Uuid,
        reaction_type: String, // "like", "love", "laugh", etc.
        created_at: DateTime<Utc>,
    },

    ReactionRemoved {
        reaction_id: Uuid,
        target_id: Uuid,
        target_type: String,
        user_id: Uuid,
        removed_at: DateTime<Utc>,
    },

    // ============================================================================
    // CONTENT SERVICE EVENTS - Following
    // ============================================================================
    FollowAdded {
        following_id: Uuid,
        follower_id: Uuid,
        following_user_id: Uuid,
        created_at: DateTime<Utc>,
    },

    FollowRemoved {
        following_id: Uuid,
        follower_id: Uuid,
        following_user_id: Uuid,
        removed_at: DateTime<Utc>,
    },

    // ============================================================================
    // CONTENT SERVICE EVENTS - Posts
    // ============================================================================
    PostCreated {
        post_id: Uuid,
        user_id: Uuid,
        content: String,
        content_type: String,
        media_ids: Vec<Uuid>,
        created_at: DateTime<Utc>,
    },

    PostUpdated {
        post_id: Uuid,
        user_id: Uuid,
        new_content: String,
        updated_at: DateTime<Utc>,
    },

    PostDeleted {
        post_id: Uuid,
        user_id: Uuid,
        deleted_at: DateTime<Utc>,
    },

    // ============================================================================
    // NOTIFICATION SERVICE EVENTS
    // ============================================================================
    NotificationCreated {
        notification_id: Uuid,
        user_id: Uuid,
        title: String,
        body: String,
        notification_type: String,
        related_user_id: Option<Uuid>,
        related_post_id: Option<Uuid>,
        created_at: DateTime<Utc>,
    },

    // ============================================================================
    // SEARCH SERVICE EVENTS
    // ============================================================================
    SearchIndexUpdated {
        index_id: Uuid,
        entity_id: Uuid,
        entity_type: String, // "user", "post", "message"
        operation: String,   // "create", "update", "delete"
        updated_at: DateTime<Utc>,
    },

    // ============================================================================
    // STREAMING SERVICE EVENTS
    // ============================================================================
    StreamStarted {
        stream_id: Uuid,
        user_id: Uuid,
        title: String,
        preview_image_url: Option<String>,
        started_at: DateTime<Utc>,
    },

    StreamEnded {
        stream_id: Uuid,
        user_id: Uuid,
        viewer_count: u32,
        duration_seconds: u32,
        ended_at: DateTime<Utc>,
    },

    StreamMessagePosted {
        message_id: Uuid,
        stream_id: Uuid,
        user_id: Uuid,
        content: String,
        posted_at: DateTime<Utc>,
    },
}

impl DomainEvent {
    /// Get the aggregate ID for this event
    /// This determines the partition key in Kafka
    pub fn aggregate_id(&self) -> Uuid {
        match self {
            // Messaging events - partition by message_id
            DomainEvent::MessageCreated { message_id, .. }
            | DomainEvent::MessageEdited { message_id, .. }
            | DomainEvent::MessageDeleted { message_id, .. } => *message_id,

            // Reaction events - partition by target_id for ordering
            DomainEvent::ReactionAdded { target_id, .. }
            | DomainEvent::ReactionRemoved { target_id, .. } => *target_id,

            // Follow events - partition by follower_id
            DomainEvent::FollowAdded { follower_id, .. }
            | DomainEvent::FollowRemoved { follower_id, .. } => *follower_id,

            // Post events - partition by post_id
            DomainEvent::PostCreated { post_id, .. }
            | DomainEvent::PostUpdated { post_id, .. }
            | DomainEvent::PostDeleted { post_id, .. } => *post_id,

            // Notification events - partition by user_id
            DomainEvent::NotificationCreated { user_id, .. } => *user_id,

            // Search events - partition by entity_id
            DomainEvent::SearchIndexUpdated { entity_id, .. } => *entity_id,

            // Stream events - partition by stream_id
            DomainEvent::StreamStarted { stream_id, .. }
            | DomainEvent::StreamEnded { stream_id, .. } => *stream_id,

            // Stream message - partition by stream_id for ordering
            DomainEvent::StreamMessagePosted { stream_id, .. } => *stream_id,
        }
    }

    /// Get the event type string for this event
    pub fn event_type(&self) -> &'static str {
        match self {
            DomainEvent::MessageCreated { .. } => "MessageCreated",
            DomainEvent::MessageEdited { .. } => "MessageEdited",
            DomainEvent::MessageDeleted { .. } => "MessageDeleted",
            DomainEvent::ReactionAdded { .. } => "ReactionAdded",
            DomainEvent::ReactionRemoved { .. } => "ReactionRemoved",
            DomainEvent::FollowAdded { .. } => "FollowAdded",
            DomainEvent::FollowRemoved { .. } => "FollowRemoved",
            DomainEvent::PostCreated { .. } => "PostCreated",
            DomainEvent::PostUpdated { .. } => "PostUpdated",
            DomainEvent::PostDeleted { .. } => "PostDeleted",
            DomainEvent::NotificationCreated { .. } => "NotificationCreated",
            DomainEvent::SearchIndexUpdated { .. } => "SearchIndexUpdated",
            DomainEvent::StreamStarted { .. } => "StreamStarted",
            DomainEvent::StreamEnded { .. } => "StreamEnded",
            DomainEvent::StreamMessagePosted { .. } => "StreamMessagePosted",
        }
    }

    /// Get the priority for this event
    /// Critical events need immediate delivery, low-priority can be batched
    pub fn priority(&self) -> u8 {
        match self {
            // CRITICAL: User-facing real-time messaging
            DomainEvent::MessageCreated { .. }
            | DomainEvent::NotificationCreated { .. }
            | DomainEvent::StreamStarted { .. }
            | DomainEvent::StreamMessagePosted { .. } => priority::CRITICAL,

            // HIGH: Important user actions
            DomainEvent::MessageDeleted { .. }
            | DomainEvent::ReactionAdded { .. }
            | DomainEvent::FollowAdded { .. }
            | DomainEvent::PostCreated { .. }
            | DomainEvent::StreamEnded { .. } => priority::HIGH,

            // NORMAL: Updates and modifications
            DomainEvent::MessageEdited { .. }
            | DomainEvent::PostUpdated { .. }
            | DomainEvent::ReactionRemoved { .. }
            | DomainEvent::FollowRemoved { .. } => priority::NORMAL,

            // LOW: Deletions and index updates (can be eventual)
            DomainEvent::PostDeleted { .. } | DomainEvent::SearchIndexUpdated { .. } => {
                priority::LOW
            }
        }
    }

    /// Check if this event affects feed generation
    pub fn affects_feed(&self) -> bool {
        matches!(
            self,
            DomainEvent::PostCreated { .. }
                | DomainEvent::PostDeleted { .. }
                | DomainEvent::FollowAdded { .. }
                | DomainEvent::FollowRemoved { .. }
        )
    }

    /// Check if this event should trigger a notification
    pub fn triggers_notification(&self) -> bool {
        matches!(
            self,
            DomainEvent::MessageCreated { .. }
                | DomainEvent::ReactionAdded { .. }
                | DomainEvent::FollowAdded { .. }
                | DomainEvent::StreamStarted { .. }
        )
    }

    /// Check if this event should update search index
    pub fn requires_search_indexing(&self) -> bool {
        matches!(
            self,
            DomainEvent::PostCreated { .. }
                | DomainEvent::PostUpdated { .. }
                | DomainEvent::PostDeleted { .. }
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_message_created_event() {
        let message_id = Uuid::new_v4();
        let event = DomainEvent::MessageCreated {
            message_id,
            conversation_id: Uuid::new_v4(),
            sender_id: Uuid::new_v4(),
            content: "Hello".to_string(),
            message_type: "text".to_string(),
            created_at: Utc::now(),
        };

        assert_eq!(event.aggregate_id(), message_id);
        assert_eq!(event.event_type(), "MessageCreated");
        assert_eq!(event.priority(), priority::CRITICAL);
        assert!(event.triggers_notification());
    }

    #[test]
    fn test_post_created_event() {
        let post_id = Uuid::new_v4();
        let event = DomainEvent::PostCreated {
            post_id,
            user_id: Uuid::new_v4(),
            content: "My new post".to_string(),
            content_type: "text".to_string(),
            media_ids: vec![],
            created_at: Utc::now(),
        };

        assert_eq!(event.aggregate_id(), post_id);
        assert_eq!(event.event_type(), "PostCreated");
        assert_eq!(event.priority(), priority::HIGH);
        assert!(event.affects_feed());
        assert!(event.requires_search_indexing());
    }

    #[test]
    fn test_reaction_added_event() {
        let target_id = Uuid::new_v4();
        let event = DomainEvent::ReactionAdded {
            reaction_id: Uuid::new_v4(),
            target_id,
            target_type: "post".to_string(),
            user_id: Uuid::new_v4(),
            reaction_type: "like".to_string(),
            created_at: Utc::now(),
        };

        assert_eq!(event.aggregate_id(), target_id);
        assert_eq!(event.event_type(), "ReactionAdded");
        assert_eq!(event.priority(), priority::HIGH);
        assert!(event.triggers_notification());
    }

    #[test]
    fn test_follow_added_event() {
        let follower_id = Uuid::new_v4();
        let event = DomainEvent::FollowAdded {
            following_id: Uuid::new_v4(),
            follower_id,
            following_user_id: Uuid::new_v4(),
            created_at: Utc::now(),
        };

        assert_eq!(event.aggregate_id(), follower_id);
        assert_eq!(event.event_type(), "FollowAdded");
        assert_eq!(event.priority(), priority::HIGH);
        assert!(event.affects_feed());
        assert!(event.triggers_notification());
    }

    #[test]
    fn test_notification_created_event() {
        let user_id = Uuid::new_v4();
        let event = DomainEvent::NotificationCreated {
            notification_id: Uuid::new_v4(),
            user_id,
            title: "New message".to_string(),
            body: "You have a new message".to_string(),
            notification_type: "message".to_string(),
            related_user_id: Some(Uuid::new_v4()),
            related_post_id: None,
            created_at: Utc::now(),
        };

        assert_eq!(event.aggregate_id(), user_id);
        assert_eq!(event.event_type(), "NotificationCreated");
        assert_eq!(event.priority(), priority::CRITICAL);
    }

    #[test]
    fn test_stream_started_event() {
        let stream_id = Uuid::new_v4();
        let event = DomainEvent::StreamStarted {
            stream_id,
            user_id: Uuid::new_v4(),
            title: "Live Gaming".to_string(),
            preview_image_url: Some("https://example.com/preview.jpg".to_string()),
            started_at: Utc::now(),
        };

        assert_eq!(event.aggregate_id(), stream_id);
        assert_eq!(event.event_type(), "StreamStarted");
        assert_eq!(event.priority(), priority::CRITICAL);
        assert!(event.triggers_notification());
    }

    #[test]
    fn test_search_index_updated_event() {
        let entity_id = Uuid::new_v4();
        let event = DomainEvent::SearchIndexUpdated {
            index_id: Uuid::new_v4(),
            entity_id,
            entity_type: "post".to_string(),
            operation: "update".to_string(),
            updated_at: Utc::now(),
        };

        assert_eq!(event.aggregate_id(), entity_id);
        assert_eq!(event.event_type(), "SearchIndexUpdated");
        assert_eq!(event.priority(), priority::LOW);
    }

    #[test]
    fn test_event_serialization() {
        let event = DomainEvent::MessageCreated {
            message_id: Uuid::new_v4(),
            conversation_id: Uuid::new_v4(),
            sender_id: Uuid::new_v4(),
            content: "Test".to_string(),
            message_type: "text".to_string(),
            created_at: Utc::now(),
        };

        let json = serde_json::to_string(&event).unwrap();
        let deserialized: DomainEvent = serde_json::from_str(&json).unwrap();

        assert_eq!(event.event_type(), deserialized.event_type());
    }

    #[test]
    fn test_priority_levels() {
        let critical_event = DomainEvent::MessageCreated {
            message_id: Uuid::new_v4(),
            conversation_id: Uuid::new_v4(),
            sender_id: Uuid::new_v4(),
            content: "Test".to_string(),
            message_type: "text".to_string(),
            created_at: Utc::now(),
        };

        let high_event = DomainEvent::PostCreated {
            post_id: Uuid::new_v4(),
            user_id: Uuid::new_v4(),
            content: "Post".to_string(),
            content_type: "text".to_string(),
            media_ids: vec![],
            created_at: Utc::now(),
        };

        let normal_event = DomainEvent::MessageEdited {
            message_id: Uuid::new_v4(),
            conversation_id: Uuid::new_v4(),
            new_content: "Edited".to_string(),
            edited_at: Utc::now(),
        };

        let low_event = DomainEvent::PostDeleted {
            post_id: Uuid::new_v4(),
            user_id: Uuid::new_v4(),
            deleted_at: Utc::now(),
        };

        assert_eq!(critical_event.priority(), priority::CRITICAL);
        assert_eq!(high_event.priority(), priority::HIGH);
        assert_eq!(normal_event.priority(), priority::NORMAL);
        assert_eq!(low_event.priority(), priority::LOW);
    }

    #[test]
    fn test_affects_feed() {
        let post_created = DomainEvent::PostCreated {
            post_id: Uuid::new_v4(),
            user_id: Uuid::new_v4(),
            content: "Post".to_string(),
            content_type: "text".to_string(),
            media_ids: vec![],
            created_at: Utc::now(),
        };

        let message_created = DomainEvent::MessageCreated {
            message_id: Uuid::new_v4(),
            conversation_id: Uuid::new_v4(),
            sender_id: Uuid::new_v4(),
            content: "Message".to_string(),
            message_type: "text".to_string(),
            created_at: Utc::now(),
        };

        assert!(post_created.affects_feed());
        assert!(!message_created.affects_feed());
    }

    #[test]
    fn test_requires_search_indexing() {
        let post_created = DomainEvent::PostCreated {
            post_id: Uuid::new_v4(),
            user_id: Uuid::new_v4(),
            content: "Post".to_string(),
            content_type: "text".to_string(),
            media_ids: vec![],
            created_at: Utc::now(),
        };

        let reaction_added = DomainEvent::ReactionAdded {
            reaction_id: Uuid::new_v4(),
            target_id: Uuid::new_v4(),
            target_type: "post".to_string(),
            user_id: Uuid::new_v4(),
            reaction_type: "like".to_string(),
            created_at: Utc::now(),
        };

        assert!(post_created.requires_search_indexing());
        assert!(!reaction_added.requires_search_indexing());
    }
}
