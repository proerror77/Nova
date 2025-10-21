//! Data models for notification system

use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;
use chrono::{DateTime, Utc};
use std::collections::HashMap;

/// Notification types supported by the system
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "varchar", rename_all = "lowercase")]
pub enum NotificationType {
    /// User received a like on their post
    #[serde(rename = "like")]
    Like,
    /// User received a comment on their post
    #[serde(rename = "comment")]
    Comment,
    /// User was followed by another user
    #[serde(rename = "follow")]
    Follow,
    /// User received a direct message
    #[serde(rename = "message")]
    Message,
    /// User's stream went live
    #[serde(rename = "live_start")]
    LiveStart,
    /// Stream update notification
    #[serde(rename = "stream_update")]
    StreamUpdate,
}

/// Delivery channels for notifications
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "varchar", rename_all = "lowercase")]
pub enum DeliveryChannel {
    /// Firebase Cloud Messaging (FCM) for Android
    #[serde(rename = "fcm")]
    FCM,
    /// Apple Push Notification (APNs) for iOS
    #[serde(rename = "apns")]
    APNs,
    /// Email notification
    #[serde(rename = "email")]
    Email,
    /// In-app notification (WebSocket)
    #[serde(rename = "in_app")]
    InApp,
}

/// Delivery status tracking
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "varchar", rename_all = "lowercase")]
pub enum DeliveryStatus {
    /// Notification pending delivery
    #[serde(rename = "pending")]
    Pending,
    /// Notification sent successfully
    #[serde(rename = "sent")]
    Sent,
    /// Delivery failed (retrying)
    #[serde(rename = "failed")]
    Failed,
    /// Delivery abandoned after max retries
    #[serde(rename = "abandoned")]
    Abandoned,
}

/// Kafka event that triggers notification
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NotificationEvent {
    /// Event ID for deduplication
    pub id: String,
    /// Type of event
    pub event_type: NotificationType,
    /// User who should receive notification
    pub recipient_id: Uuid,
    /// User who triggered the event
    pub actor_id: Option<Uuid>,
    /// Related post/content ID
    pub related_entity_id: Option<String>,
    /// Event timestamp
    pub timestamp: i64,
    /// Additional metadata
    pub metadata: HashMap<String, String>,
}

/// Notification record in database
#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Notification {
    pub id: i64,
    pub user_id: Uuid,
    pub notification_type: String,
    pub title: String,
    pub message: String,
    pub related_user_id: Option<Uuid>,
    pub related_post_id: Option<Uuid>,
    pub related_entity_id: Option<String>,
    pub read: bool,
    pub read_at: Option<DateTime<Utc>>,
    pub dismissed: bool,
    pub dismissed_at: Option<DateTime<Utc>>,
    pub push_sent: bool,
    pub email_sent: bool,
    pub in_app_created: bool,
    pub device_platform: Option<String>,
    pub created_at: DateTime<Utc>,
    pub delivered_at: Option<DateTime<Utc>>,
    pub expires_at: DateTime<Utc>,
}

/// User notification preferences
#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct NotificationPreferences {
    pub id: i64,
    pub user_id: Uuid,
    pub push_enabled: bool,
    pub email_enabled: bool,
    pub in_app_enabled: bool,
    pub likes_enabled: bool,
    pub comments_enabled: bool,
    pub follows_enabled: bool,
    pub messages_enabled: bool,
    pub live_notifications_enabled: bool,
    pub quiet_hours_start: Option<String>,
    pub quiet_hours_end: Option<String>,
    pub quiet_hours_enabled: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Device push token for mobile apps
#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct DevicePushToken {
    pub id: Uuid,
    pub user_id: Uuid,
    pub token: String,
    pub platform: String, // "ios" or "android"
    pub device_id: Option<String>,
    pub app_version: Option<String>,
    pub os_version: Option<String>,
    pub active: bool,
    pub last_used_at: Option<DateTime<Utc>>,
    pub registered_at: DateTime<Utc>,
}

/// Delivery attempt record
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeliveryAttempt {
    pub notification_id: i64,
    pub channel: DeliveryChannel,
    pub status: DeliveryStatus,
    pub attempt_number: u32,
    pub max_retries: u32,
    pub error_message: Option<String>,
    pub error_code: Option<String>,
    pub next_retry_at: Option<DateTime<Utc>>,
}

/// Batch aggregation for efficiency
#[derive(Debug, Clone)]
pub struct NotificationBatch {
    pub events: Vec<NotificationEvent>,
    pub count: usize,
    pub received_at: DateTime<Utc>,
}

impl NotificationBatch {
    /// Create a new batch
    pub fn new() -> Self {
        Self {
            events: Vec::new(),
            count: 0,
            received_at: Utc::now(),
        }
    }

    /// Add event to batch
    pub fn push(&mut self, event: NotificationEvent) {
        self.events.push(event);
        self.count += 1;
    }

    /// Check if batch should be flushed (size or time-based)
    pub fn should_flush(&self, max_size: usize, timeout_secs: i64) -> bool {
        if self.count >= max_size {
            return true;
        }

        let age = Utc::now()
            .signed_duration_since(self.received_at)
            .num_seconds();
        age >= timeout_secs
    }

    /// Clear batch
    pub fn clear(&mut self) {
        self.events.clear();
        self.count = 0;
        self.received_at = Utc::now();
    }
}

/// Create notification request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateNotificationRequest {
    pub user_id: Uuid,
    pub notification_type: NotificationType,
    pub title: String,
    pub message: String,
    pub related_user_id: Option<Uuid>,
    pub related_post_id: Option<Uuid>,
    pub related_entity_id: Option<String>,
}

/// Notification response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NotificationResponse {
    pub id: i64,
    pub user_id: Uuid,
    pub notification_type: String,
    pub title: String,
    pub message: String,
    pub read: bool,
    pub created_at: DateTime<Utc>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_notification_batch_creation() {
        let batch = NotificationBatch::new();
        assert_eq!(batch.count, 0);
        assert_eq!(batch.events.len(), 0);
    }

    #[test]
    fn test_notification_batch_push() {
        let mut batch = NotificationBatch::new();
        let event = NotificationEvent {
            id: "test-1".to_string(),
            event_type: NotificationType::Like,
            recipient_id: Uuid::new_v4(),
            actor_id: Some(Uuid::new_v4()),
            related_entity_id: Some("post-1".to_string()),
            timestamp: Utc::now().timestamp(),
            metadata: HashMap::new(),
        };

        batch.push(event);
        assert_eq!(batch.count, 1);
        assert_eq!(batch.events.len(), 1);
    }

    #[test]
    fn test_notification_batch_should_flush_by_size() {
        let mut batch = NotificationBatch::new();
        assert!(!batch.should_flush(10, 60));

        for i in 0..10 {
            batch.push(NotificationEvent {
                id: format!("test-{}", i),
                event_type: NotificationType::Like,
                recipient_id: Uuid::new_v4(),
                actor_id: None,
                related_entity_id: None,
                timestamp: Utc::now().timestamp(),
                metadata: HashMap::new(),
            });
        }

        assert!(batch.should_flush(10, 60));
    }

    #[test]
    fn test_notification_batch_clear() {
        let mut batch = NotificationBatch::new();
        batch.push(NotificationEvent {
            id: "test-1".to_string(),
            event_type: NotificationType::Follow,
            recipient_id: Uuid::new_v4(),
            actor_id: None,
            related_entity_id: None,
            timestamp: Utc::now().timestamp(),
            metadata: HashMap::new(),
        });

        assert_eq!(batch.count, 1);
        batch.clear();
        assert_eq!(batch.count, 0);
        assert_eq!(batch.events.len(), 0);
    }
}
