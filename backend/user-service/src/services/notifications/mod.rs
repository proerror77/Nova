/// Notifications module - Phase 7A Feature 1
///
/// Real-time notification system with:
/// - Kafka-based event consumption
/// - FCM/APNs integration for push notifications
/// - WebSocket support for real-time delivery
/// - Platform routing for multi-platform support
pub mod apns_client;
pub mod fcm_client;
pub mod kafka_consumer;
pub mod platform_router;
pub mod retry_handler;
pub mod websocket_hub;

pub use apns_client::{APNsClient, APNsPriority, APNsSendResult};
pub use fcm_client::{FCMClient, FCMSendResult, ServiceAccountKey};
pub use kafka_consumer::{
    KafkaNotification, KafkaNotificationConsumer, NotificationBatch, NotificationEventType,
    RetryPolicy,
};
pub use platform_router::{DeviceInfo, Platform, PlatformRouter, UnifiedSendResult};
pub use retry_handler::{RetryConfig, RetryHandler};
pub use websocket_hub::{
    ClientConnection, ConnectionId, ConnectionState, Message, UserId, WebSocketHub,
};
