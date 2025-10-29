/// Notifications module - Phase 7A Feature 1
///
/// Real-time notification system with:
/// - Kafka-based event consumption
/// - FCM/APNs integration for push notifications
/// - WebSocket support for real-time delivery
pub mod apns_client;
pub mod fcm_client;
pub mod kafka_consumer;
pub mod notification_service;

pub use apns_client::{APNsClient, APNsPriority, APNsSendResult};
pub use fcm_client::{FCMClient, FCMSendResult, ServiceAccountKey};
pub use kafka_consumer::{
    KafkaNotification, KafkaNotificationConsumer, NotificationBatch, NotificationEventType,
    RetryPolicy,
};
pub use notification_service::{
    DevicePushConfig, DeviceType, NotificationPreferences, NotificationService,
    PushNotificationResult,
};
