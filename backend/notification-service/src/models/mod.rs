use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Notification type enumeration
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "UPPERCASE")]
pub enum NotificationType {
    /// User liked a post/comment
    Like,
    /// User commented on a post
    Comment,
    /// User started following
    Follow,
    /// User mentioned in a post/comment
    Mention,
    /// System notification
    System,
    /// Direct message notification
    Message,
    /// Video-related notification
    Video,
    /// Live stream notification
    Stream,
}

impl NotificationType {
    pub fn as_str(&self) -> &'static str {
        match self {
            NotificationType::Like => "like",
            NotificationType::Comment => "comment",
            NotificationType::Follow => "follow",
            NotificationType::Mention => "mention",
            NotificationType::System => "system",
            NotificationType::Message => "message",
            NotificationType::Video => "video",
            NotificationType::Stream => "stream",
        }
    }
}

/// Notification priority level
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
#[serde(rename_all = "UPPERCASE")]
pub enum NotificationPriority {
    /// Low priority (batched delivery, can wait)
    Low,
    /// Normal priority (standard delivery)
    Normal,
    /// High priority (immediate delivery)
    High,
}

impl NotificationPriority {
    pub fn as_str(&self) -> &'static str {
        match self {
            NotificationPriority::Low => "low",
            NotificationPriority::Normal => "normal",
            NotificationPriority::High => "high",
        }
    }
}

/// Notification channel (where to send)
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "UPPERCASE")]
pub enum NotificationChannel {
    /// Firebase Cloud Messaging (Android/Web)
    FCM,
    /// Apple Push Notification Service (iOS/macOS)
    APNs,
    /// WebSocket (real-time, browser)
    WebSocket,
    /// Email
    Email,
    /// SMS
    SMS,
}

impl NotificationChannel {
    pub fn as_str(&self) -> &'static str {
        match self {
            NotificationChannel::FCM => "fcm",
            NotificationChannel::APNs => "apns",
            NotificationChannel::WebSocket => "websocket",
            NotificationChannel::Email => "email",
            NotificationChannel::SMS => "sms",
        }
    }
}

/// Notification status
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "UPPERCASE")]
pub enum NotificationStatus {
    /// Queued for delivery
    Queued,
    /// Currently being sent
    Sending,
    /// Successfully delivered
    Delivered,
    /// Failed to deliver
    Failed,
    /// Read by recipient
    Read,
    /// Expired/dismissed
    Dismissed,
}

impl NotificationStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            NotificationStatus::Queued => "queued",
            NotificationStatus::Sending => "sending",
            NotificationStatus::Delivered => "delivered",
            NotificationStatus::Failed => "failed",
            NotificationStatus::Read => "read",
            NotificationStatus::Dismissed => "dismissed",
        }
    }
}

/// Core notification model
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Notification {
    pub id: Uuid,

    /// Recipient user ID
    pub recipient_id: Uuid,

    /// Sender user ID (if applicable)
    pub sender_id: Option<Uuid>,

    /// Notification type
    pub notification_type: NotificationType,

    /// Notification title
    pub title: String,

    /// Notification body/message
    pub body: String,

    /// Optional image URL
    pub image_url: Option<String>,

    /// Associated object ID (post, comment, conversation, etc.)
    pub object_id: Option<Uuid>,

    /// Associated object type
    pub object_type: Option<String>,

    /// Custom data as JSON
    pub metadata: Option<serde_json::Value>,

    /// Priority level
    pub priority: NotificationPriority,

    /// Delivery status
    pub status: NotificationStatus,

    /// Read status
    pub is_read: bool,

    /// Timestamp when marked as read
    pub read_at: Option<DateTime<Utc>>,

    /// Creation timestamp
    pub created_at: DateTime<Utc>,

    /// Last update timestamp
    pub updated_at: DateTime<Utc>,

    /// Expiration timestamp
    pub expires_at: Option<DateTime<Utc>>,
}

/// Notification device token for push notifications
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceToken {
    pub id: Uuid,

    /// User ID
    pub user_id: Uuid,

    /// Device token
    pub token: String,

    /// Channel (FCM, APNs, etc.)
    pub channel: NotificationChannel,

    /// Device type (ios, android, web)
    pub device_type: String,

    /// Device name/identifier
    pub device_name: Option<String>,

    /// Is this token active
    pub is_active: bool,

    /// Timestamp when last used
    pub last_used_at: Option<DateTime<Utc>>,

    /// Creation timestamp
    pub created_at: DateTime<Utc>,
}

/// Notification delivery attempt record
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeliveryAttempt {
    pub id: Uuid,

    /// Notification ID
    pub notification_id: Uuid,

    /// Device token ID
    pub device_token_id: Uuid,

    /// Delivery channel
    pub channel: NotificationChannel,

    /// Delivery status
    pub status: NotificationStatus,

    /// Error message if failed
    pub error_message: Option<String>,

    /// Number of retry attempts
    pub retry_count: i32,

    /// Timestamp of attempt
    pub attempted_at: DateTime<Utc>,

    /// Timestamp of next retry
    pub retry_at: Option<DateTime<Utc>>,
}

/// Notification preference per user
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NotificationPreference {
    pub id: Uuid,

    /// User ID
    pub user_id: Uuid,

    /// Enable all notifications
    pub enabled: bool,

    /// Per-type preferences
    pub like_enabled: bool,
    pub comment_enabled: bool,
    pub follow_enabled: bool,
    pub mention_enabled: bool,
    pub message_enabled: bool,
    pub stream_enabled: bool,

    /// Quiet hours (ISO 8601 time format, e.g., "22:00-08:00")
    pub quiet_hours_start: Option<String>,
    pub quiet_hours_end: Option<String>,

    /// Preferred channels
    pub prefer_fcm: bool,
    pub prefer_apns: bool,
    pub prefer_email: bool,

    /// Updated timestamp
    pub updated_at: DateTime<Utc>,
}

/// Request to create a notification
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateNotificationRequest {
    pub recipient_id: Uuid,
    pub sender_id: Option<Uuid>,
    pub notification_type: NotificationType,
    pub title: String,
    pub body: String,
    pub image_url: Option<String>,
    pub object_id: Option<Uuid>,
    pub object_type: Option<String>,
    pub metadata: Option<serde_json::Value>,
    #[serde(default = "default_priority")]
    pub priority: NotificationPriority,
}

fn default_priority() -> NotificationPriority {
    NotificationPriority::Normal
}
