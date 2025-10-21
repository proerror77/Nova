//! Real-time Notification System
//!
//! This module handles multi-channel notifications (push, email, in-app) with:
//! - Event-driven architecture via Kafka
//! - Batch aggregation for efficiency
//! - Channel-specific delivery strategies
//! - Delivery tracking and retry logic
//!
//! ## Architecture
//!
//! 1. **Event Source**: Kafka topics (nova-notifications)
//! 2. **Processing**: Kafka consumer with batch aggregation
//! 3. **Delivery**:
//!    - Push: Firebase Cloud Messaging (FCM) or Apple Push Notification (APNs)
//!    - Email: SMTP via configured provider
//!    - In-App: WebSocket or database polling
//! 4. **Tracking**: PostgreSQL notification_delivery_logs
//!
//! ## Typical Flow
//!
//! ```text
//! User Action → Service → Kafka (nova-notifications)
//!                          ↓
//!                    Kafka Consumer
//!                          ↓
//!                    Batch Aggregation
//!                          ↓
//!          Rate Limiting + User Preferences
//!                          ↓
//!          Deliver via Push/Email/In-App
//!                          ↓
//!          Log to notification_delivery_logs
//! ```

pub mod models;
pub mod kafka_consumer;
pub mod delivery;
pub mod preferences;

pub use models::{
    Notification, NotificationEvent, NotificationType, DeliveryChannel, DeliveryStatus,
    NotificationPreferences, DevicePushToken,
};
pub use kafka_consumer::NotificationConsumer;
pub use delivery::{DeliveryService, DeliveryResult};
pub use preferences::PreferencesService;

#[cfg(test)]
mod tests;
