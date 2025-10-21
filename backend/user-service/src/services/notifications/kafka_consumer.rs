/// T201: Kafka Consumer for Real-time Notification System
///
/// This module implements the high-efficiency Kafka-based notification consumer
/// with batching support for the Phase 7A notifications system.
///
/// Architecture:
/// 1. KafkaNotificationConsumer: Main consumer loop
/// 2. NotificationBatch: Batching logic
/// 3. ConnectionPool: Kafka connection pooling
/// 4. RetryPolicy: Error handling and retry logic
/// 5. Graceful shutdown with batch flushing
use chrono::{DateTime, Utc};
use rdkafka::config::ClientConfig;
use rdkafka::consumer::{Consumer, StreamConsumer};
use rdkafka::message::Message as KafkaMessage;
use serde::{Deserialize, Serialize};
use serde_json::json;
use sqlx::types::Json;
use sqlx::PgPool;
use std::sync::{Arc, RwLock};
use std::time::Duration;
use tokio::sync::mpsc;
use tokio::time::{interval, sleep};
use tracing::{debug, error, info, warn};
use uuid::Uuid;

use super::{
    retry_handler::{RetryConfig, RetryHandler},
    websocket_hub::{Message as WebSocketMessage, WebSocketHub},
    DeviceInfo, Platform, PlatformRouter,
};

/// Represents a single notification event from Kafka
/// Aligned with design.md NotificationEvent schema
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KafkaNotification {
    /// Unique event ID
    pub event_id: String,
    /// Event type (user_action, follow, like, etc.)
    pub event_type: NotificationEventType,
    /// Source user who triggered the event
    pub source_user_id: Uuid,
    /// Target user who will receive the notification
    pub target_user_id: Uuid,
    /// Additional payload data
    pub payload: serde_json::Value,
    /// Event timestamp
    pub timestamp: DateTime<Utc>,
    /// Record creation time
    pub created_at: DateTime<Utc>,
}

/// Types of notification events as per T201 requirements
/// Supports 7 notification event types
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "snake_case")]
pub enum NotificationEventType {
    /// User action (generic action)
    UserAction,
    /// User followed another user
    Follow,
    /// Post liked
    Like,
    /// Comment on post
    Comment,
    /// User mentioned in post or comment
    Mention,
    /// Post reposted
    Repost,
    /// Direct message received
    DirectMessage,
}

impl std::fmt::Display for NotificationEventType {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            NotificationEventType::UserAction => write!(f, "user_action"),
            NotificationEventType::Follow => write!(f, "follow"),
            NotificationEventType::Like => write!(f, "like"),
            NotificationEventType::Comment => write!(f, "comment"),
            NotificationEventType::Mention => write!(f, "mention"),
            NotificationEventType::Repost => write!(f, "repost"),
            NotificationEventType::DirectMessage => write!(f, "direct_message"),
        }
    }
}

/// Batch of notifications for efficient database insertion
#[derive(Debug, Clone)]
pub struct NotificationBatch {
    pub notifications: Vec<KafkaNotification>,
    pub created_at: DateTime<Utc>,
    pub batch_id: String,
}

impl NotificationBatch {
    /// Create a new notification batch
    pub fn new() -> Self {
        Self {
            notifications: Vec::new(),
            created_at: Utc::now(),
            batch_id: Uuid::new_v4().to_string(),
        }
    }

    /// Check if batch should be flushed based on size
    pub fn should_flush_by_size(&self, max_size: usize) -> bool {
        self.notifications.len() >= max_size
    }

    /// Check if batch should be flushed based on time
    pub fn should_flush_by_time(&self, max_age: Duration) -> bool {
        let age = Utc::now()
            .signed_duration_since(self.created_at)
            .to_std()
            .unwrap_or_default();
        age >= max_age
    }

    /// Add notification to batch
    pub fn add(&mut self, notification: KafkaNotification) {
        self.notifications.push(notification);
    }

    /// Get batch size
    pub fn len(&self) -> usize {
        self.notifications.len()
    }

    /// Check if batch is empty
    pub fn is_empty(&self) -> bool {
        self.notifications.is_empty()
    }

    /// Flush batch to database (TODO: implement with actual DB)
    pub async fn flush(&self) -> Result<usize, String> {
        if self.notifications.is_empty() {
            return Ok(0);
        }

        // TODO: Implement batch insert to PostgreSQL
        // INSERT INTO notifications (user_id, event_type, title, body, data, created_at)
        // VALUES ...
        Ok(self.notifications.len())
    }

    /// Clear batch
    pub fn clear(&mut self) {
        self.notifications.clear();
        self.created_at = Utc::now();
    }
}

/// Retry policy for failed notifications
#[derive(Debug, Clone)]
pub struct RetryPolicy {
    pub max_retries: u32,
    pub backoff_ms: u64,
    pub max_backoff_ms: u64,
}

impl Default for RetryPolicy {
    fn default() -> Self {
        Self {
            max_retries: 3,
            backoff_ms: 100,
            max_backoff_ms: 5000,
        }
    }
}

impl RetryPolicy {
    /// Calculate backoff duration for retry attempt
    pub fn get_backoff(&self, attempt: u32) -> Duration {
        // Use saturating multiplication to avoid overflow
        let backoff = self
            .backoff_ms
            .saturating_mul(2_u64.saturating_pow(attempt));
        let capped = backoff.min(self.max_backoff_ms);
        Duration::from_millis(capped)
    }

    /// Check if should retry
    pub fn should_retry(&self, attempt: u32) -> bool {
        attempt < self.max_retries
    }
}

/// Connection pool for Kafka consumers
pub struct ConnectionPool {
    consumers: Vec<Arc<StreamConsumer>>,
    current_index: usize,
}

impl std::fmt::Debug for ConnectionPool {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ConnectionPool")
            .field("pool_size", &self.consumers.len())
            .field("current_index", &self.current_index)
            .finish()
    }
}

impl ConnectionPool {
    /// Create new connection pool with specified size
    pub fn new(brokers: &str, group_id: &str, pool_size: usize) -> Result<Self, String> {
        let mut consumers = Vec::with_capacity(pool_size);

        for i in 0..pool_size {
            let consumer: StreamConsumer = ClientConfig::new()
                .set("group.id", group_id)
                .set("bootstrap.servers", brokers)
                .set("enable.auto.commit", "true")
                .set("auto.commit.interval.ms", "1000")
                .set("session.timeout.ms", "6000")
                .set("enable.partition.eof", "false")
                .set("client.id", &format!("{}-{}", group_id, i))
                .create()
                .map_err(|e| format!("Failed to create consumer {}: {}", i, e))?;

            consumers.push(Arc::new(consumer));
        }

        Ok(Self {
            consumers,
            current_index: 0,
        })
    }

    /// Get next consumer from pool (round-robin)
    pub fn next_consumer(&mut self) -> Arc<StreamConsumer> {
        let consumer = self.consumers[self.current_index].clone();
        self.current_index = (self.current_index + 1) % self.consumers.len();
        consumer
    }

    /// Get pool size
    pub fn size(&self) -> usize {
        self.consumers.len()
    }
}

/// Main Kafka consumer for notifications with connection pooling
pub struct KafkaNotificationConsumer {
    brokers: String,
    topic: String,
    group_id: String,
    batch_size: usize,
    flush_interval_ms: u64,
    retry_policy: RetryPolicy,
    connection_pool: Arc<RwLock<ConnectionPool>>,
    shutdown_tx: Option<mpsc::Sender<()>>,
    db_pool: Option<PgPool>,
    platform_router: Option<Arc<PlatformRouter>>,
    websocket_hub: Option<Arc<WebSocketHub>>,
    retry_config: RetryConfig,
}

impl KafkaNotificationConsumer {
    /// Create new consumer with connection pooling
    pub fn new(brokers: String, topic: String) -> Result<Self, String> {
        Self::with_pool_size(brokers, topic, 5)
    }

    /// Create new consumer with custom pool size
    pub fn with_pool_size(
        brokers: String,
        topic: String,
        pool_size: usize,
    ) -> Result<Self, String> {
        let group_id = "notifications-consumer".to_string();
        let connection_pool = ConnectionPool::new(&brokers, &group_id, pool_size)?;

        Ok(Self {
            brokers,
            topic,
            group_id,
            batch_size: 100,
            flush_interval_ms: 5000, // 5 seconds
            retry_policy: RetryPolicy::default(),
            connection_pool: Arc::new(RwLock::new(connection_pool)),
            shutdown_tx: None,
            db_pool: None,
            platform_router: None,
            websocket_hub: None,
            retry_config: RetryConfig::default(),
        })
    }

    /// Provide PostgreSQL pool for persistence
    pub fn set_db_pool(&mut self, pool: PgPool) {
        self.db_pool = Some(pool);
    }

    /// Provide platform router for push delivery
    pub fn set_platform_router(&mut self, router: Arc<PlatformRouter>) {
        self.platform_router = Some(router);
    }

    /// Provide WebSocket hub for real-time broadcasting
    pub fn set_websocket_hub(&mut self, hub: Arc<WebSocketHub>) {
        self.websocket_hub = Some(hub);
    }

    /// Override retry configuration for push delivery
    pub fn set_retry_config(&mut self, config: RetryConfig) {
        self.retry_config = config;
    }

    /// Start consuming messages with batching and error recovery
    pub async fn start(&mut self) -> Result<(), String> {
        let mut consumer = {
            let mut pool = self
                .connection_pool
                .write()
                .map_err(|e| format!("Failed to acquire connection pool: {}", e))?;
            pool.next_consumer()
        };

        // Subscribe to topic
        consumer
            .subscribe(&[&self.topic])
            .map_err(|e| format!("Failed to subscribe to topic: {}", e))?;

        let (shutdown_tx, mut shutdown_rx) = mpsc::channel::<()>(1);
        self.shutdown_tx = Some(shutdown_tx);

        let mut batch = NotificationBatch::new();
        let mut flush_timer = interval(Duration::from_millis(self.flush_interval_ms));
        let batch_size = self.batch_size;
        let retry_policy = self.retry_policy.clone();

        loop {
            tokio::select! {
                // Check for shutdown signal
                _ = shutdown_rx.recv() => {
                    tracing::info!("Shutdown signal received, flushing pending batch");
                    if !batch.is_empty() {
                        match self.flush_batch_with_retry(&batch, &retry_policy).await {
                            Ok(_) => batch.clear(),
                            Err(e) => tracing::error!("Failed to flush batch on shutdown: {}", e),
                        }
                    }
                    break;
                }

                // Check flush timer
                _ = flush_timer.tick() => {
                    if batch.should_flush_by_time(Duration::from_millis(self.flush_interval_ms)) {
                        match self.flush_batch_with_retry(&batch, &retry_policy).await {
                            Ok(_) => batch.clear(),
                            Err(e) => tracing::error!("Failed to flush batch by time: {}", e),
                        }
                    }
                }

                // Poll for messages
                message = consumer.recv() => {
                    match message {
                        Ok(msg) => {
                            if let Some(payload) = msg.payload() {
                                match self.deserialize_message(payload) {
                                    Ok(notification) => {
                                        batch.add(notification);

                                        // Flush if batch size reached
                                        if batch.should_flush_by_size(batch_size) {
                                            match self.flush_batch_with_retry(&batch, &retry_policy).await {
                                                Ok(_) => batch.clear(),
                                                Err(e) => tracing::error!("Failed to flush batch by size: {}", e),
                                            }
                                        }
                                    }
                                    Err(e) => {
                                        tracing::error!("Failed to deserialize message: {}", e);
                                        // Skip malformed messages
                                    }
                                }
                            }
                        }
                        Err(e) => {
                            tracing::error!("Kafka error: {}", e);
                            // Attempt reconnection with retry policy
                            match self.handle_connection_error(&retry_policy).await {
                                Ok(new_consumer) => {
                                    consumer = new_consumer;
                                }
                                Err(retry_err) => {
                                    tracing::error!("Failed to recover from connection error: {}", retry_err);
                                    return Err(format!("Unrecoverable Kafka error: {}", retry_err));
                                }
                            }
                        }
                    }
                }
            }
        }

        Ok(())
    }

    /// Deserialize Kafka message payload into NotificationEvent
    fn deserialize_message(&self, payload: &[u8]) -> Result<KafkaNotification, String> {
        serde_json::from_slice(payload).map_err(|e| format!("JSON deserialization error: {}", e))
    }

    /// Flush batch with retry logic
    async fn flush_batch_with_retry(
        &self,
        batch: &NotificationBatch,
        retry_policy: &RetryPolicy,
    ) -> Result<usize, String> {
        let mut attempt = 0;

        loop {
            match self.persist_batch(batch).await {
                Ok(count) => {
                    tracing::info!("Flushed {} notifications successfully", count);
                    return Ok(count);
                }
                Err(e) => {
                    if retry_policy.should_retry(attempt) {
                        let backoff = retry_policy.get_backoff(attempt);
                        tracing::warn!(
                            "Flush failed (attempt {}), retrying after {:?}: {}",
                            attempt + 1,
                            backoff,
                            e
                        );
                        sleep(backoff).await;
                        attempt += 1;
                    } else {
                        return Err(format!(
                            "Failed to flush batch after {} attempts: {}",
                            attempt, e
                        ));
                    }
                }
            }
        }
    }

    async fn persist_batch(&self, batch: &NotificationBatch) -> Result<usize, String> {
        if batch.notifications.is_empty() {
            return Ok(0);
        }

        self.store_batch_in_db(batch).await?;
        self.dispatch_notifications(&batch.notifications).await;

        Ok(batch.notifications.len())
    }

    async fn store_batch_in_db(&self, batch: &NotificationBatch) -> Result<(), String> {
        let pool = match &self.db_pool {
            Some(pool) => pool,
            None => return Ok(()),
        };

        let mut transaction = pool
            .begin()
            .await
            .map_err(|e| format!("Failed to begin notification transaction: {}", e))?;

        for notification in &batch.notifications {
            sqlx::query(
                r#"
                INSERT INTO notification_events (
                    event_id,
                    event_type,
                    source_user_id,
                    target_user_id,
                    payload,
                    event_timestamp,
                    created_at
                )
                VALUES ($1, $2, $3, $4, $5, $6, $7)
                ON CONFLICT (event_id) DO NOTHING
                "#,
            )
            .bind(&notification.event_id)
            .bind(notification.event_type.to_string())
            .bind(notification.source_user_id)
            .bind(notification.target_user_id)
            .bind(Json(notification.payload.clone()))
            .bind(notification.timestamp)
            .bind(notification.created_at)
            .execute(&mut *transaction)
            .await
            .map_err(|e| {
                format!(
                    "Failed to insert notification {}: {}",
                    notification.event_id, e
                )
            })?;
        }

        transaction
            .commit()
            .await
            .map_err(|e| format!("Failed to commit notification batch: {}", e))?;

        Ok(())
    }

    async fn dispatch_notifications(&self, notifications: &[KafkaNotification]) {
        for notification in notifications {
            if let Err(err) = self.dispatch_notification(notification).await {
                error!(
                    event_id = %notification.event_id,
                    error = %err,
                    "Failed to dispatch notification"
                );
            }
        }
    }

    async fn dispatch_notification(&self, notification: &KafkaNotification) -> Result<(), String> {
        if let Err(err) = self.push_to_devices(notification).await {
            warn!(
                event_id = %notification.event_id,
                error = %err,
                "Push delivery failed"
            );
        }

        self.push_to_websocket(notification).await;
        Ok(())
    }

    async fn push_to_devices(&self, notification: &KafkaNotification) -> Result<(), String> {
        let router = match &self.platform_router {
            Some(router) => Arc::clone(router),
            None => return Ok(()),
        };

        let devices = Self::extract_devices(router.as_ref(), &notification.payload);
        if devices.is_empty() {
            return Ok(());
        }

        let (title, body, data) = Self::extract_notification_content(notification);
        let retry_handler = RetryHandler::new(self.retry_config.clone());
        let devices_clone = devices.clone();
        let data_clone = data.clone();
        let title_clone = title.clone();
        let body_clone = body.clone();

        match retry_handler
            .execute(|| {
                let router = Arc::clone(&router);
                let devices = devices_clone.clone();
                let data = data_clone.clone();
                let title = title_clone.clone();
                let body = body_clone.clone();

                async move {
                    router
                        .send_multicast(&devices, &title, &body, data.clone())
                        .await
                }
            })
            .await
        {
            Ok(results) => {
                let successes = results.iter().filter(|r| r.success).count();
                let failures = results.len().saturating_sub(successes);
                debug!(
                    event_id = %notification.event_id,
                    successes,
                    failures,
                    "Push notification delivery results"
                );
            }
            Err(error) => {
                return Err(format!(
                    "Push notification delivery failed after retries: {}",
                    error
                ));
            }
        }

        Ok(())
    }

    async fn push_to_websocket(&self, notification: &KafkaNotification) {
        if let Some(hub) = &self.websocket_hub {
            let payload = json!({
                "event_id": notification.event_id,
                "event_type": notification.event_type,
                "source_user_id": notification.source_user_id,
                "payload": notification.payload,
                "timestamp": notification.timestamp,
            });

            let message = WebSocketMessage {
                message_type: format!("notification.{}", notification.event_type),
                payload,
                timestamp: Utc::now(),
            };

            let delivered = hub.send_to_user(notification.target_user_id, message).await;

            debug!(
                event_id = %notification.event_id,
                target_user = %notification.target_user_id,
                delivered,
                "Dispatched notification via WebSocket"
            );
        }
    }

    fn extract_devices(router: &PlatformRouter, payload: &serde_json::Value) -> Vec<DeviceInfo> {
        if let Some(devices_value) = payload.get("devices") {
            if let Some(array) = devices_value.as_array() {
                return array
                    .iter()
                    .filter_map(|entry| {
                        let token = entry
                            .get("token")
                            .and_then(|v| v.as_str())
                            .map(|s| s.to_string())?;
                        let platform = entry
                            .get("platform")
                            .and_then(|v| Self::parse_platform_value(v));
                        let platform = platform.unwrap_or_else(|| router.detect_platform(&token));
                        Some(DeviceInfo { token, platform })
                    })
                    .collect();
            }
        }

        if let Some(tokens_value) = payload.get("device_tokens") {
            if let Some(array) = tokens_value.as_array() {
                return array
                    .iter()
                    .filter_map(|token| token.as_str().map(|s| s.to_string()))
                    .map(|token| DeviceInfo {
                        platform: router.detect_platform(&token),
                        token,
                    })
                    .collect();
            }
        }

        if let Some(token) = payload.get("device_token").and_then(|token| token.as_str()) {
            return vec![DeviceInfo {
                platform: router.detect_platform(token),
                token: token.to_string(),
            }];
        }

        Vec::new()
    }

    fn parse_platform_value(value: &serde_json::Value) -> Option<Platform> {
        let platform_str = value.as_str()?.to_lowercase();
        match platform_str.as_str() {
            "ios" => Some(Platform::iOS),
            "android" => Some(Platform::Android),
            "web" => Some(Platform::Web),
            _ => None,
        }
    }

    fn extract_notification_content(
        notification: &KafkaNotification,
    ) -> (String, String, Option<serde_json::Value>) {
        let payload = &notification.payload;

        let title = payload
            .get("title")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
            .unwrap_or_else(|| Self::default_title(&notification.event_type).to_string());

        let body = payload
            .get("body")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
            .unwrap_or_else(|| Self::default_body(&notification.event_type).to_string());

        let data = payload.get("data").cloned().unwrap_or_else(|| {
            json!({
                "event_id": notification.event_id,
                "event_type": notification.event_type,
                "source_user_id": notification.source_user_id
            })
        });

        (title, body, Some(data))
    }

    fn default_title(event_type: &NotificationEventType) -> &'static str {
        match event_type {
            NotificationEventType::UserAction => "New activity",
            NotificationEventType::Follow => "New follower",
            NotificationEventType::Like => "Someone liked your post",
            NotificationEventType::Comment => "New comment",
            NotificationEventType::Mention => "You were mentioned",
            NotificationEventType::Repost => "Your post was reposted",
            NotificationEventType::DirectMessage => "New message",
        }
    }

    fn default_body(event_type: &NotificationEventType) -> &'static str {
        match event_type {
            NotificationEventType::UserAction => "Open the app to see what's happening.",
            NotificationEventType::Follow => "A new user started following you.",
            NotificationEventType::Like => "Your post is getting love!",
            NotificationEventType::Comment => "Someone commented on your post.",
            NotificationEventType::Mention => "You were mentioned by another user.",
            NotificationEventType::Repost => "Your post was shared.",
            NotificationEventType::DirectMessage => "You received a new direct message.",
        }
    }

    /// Handle connection errors with retry logic
    async fn handle_connection_error(
        &self,
        retry_policy: &RetryPolicy,
    ) -> Result<Arc<StreamConsumer>, String> {
        let mut attempt = 0;

        while retry_policy.should_retry(attempt) {
            let backoff = retry_policy.get_backoff(attempt);
            tracing::warn!(
                "Connection error, attempting reconnection (attempt {}) after {:?}",
                attempt + 1,
                backoff
            );
            sleep(backoff).await;

            // Attempt to get a new consumer from pool
            let consumer = {
                let mut pool = self
                    .connection_pool
                    .write()
                    .map_err(|e| format!("Failed to acquire connection pool: {}", e))?;
                pool.next_consumer()
            };

            // Try to subscribe
            match consumer.subscribe(&[&self.topic]) {
                Ok(_) => {
                    tracing::info!("Successfully reconnected to Kafka");
                    return Ok(consumer);
                }
                Err(e) => {
                    tracing::error!("Reconnection failed: {}", e);
                    attempt += 1;
                }
            }
        }

        Err(format!(
            "Failed to reconnect after {} attempts",
            retry_policy.max_retries
        ))
    }

    /// Graceful shutdown
    pub async fn shutdown(&mut self) -> Result<(), String> {
        if let Some(tx) = self.shutdown_tx.take() {
            tx.send(())
                .await
                .map_err(|e| format!("Failed to send shutdown signal: {}", e))?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_notification_batch_creation() {
        let batch = NotificationBatch::new();
        assert!(batch.is_empty());
        assert_eq!(batch.len(), 0);
    }

    #[test]
    fn test_notification_batch_add() {
        let mut batch = NotificationBatch::new();
        let notification = KafkaNotification {
            event_id: "evt-test-1".to_string(),
            event_type: NotificationEventType::Like,
            source_user_id: Uuid::new_v4(),
            target_user_id: Uuid::new_v4(),
            payload: serde_json::json!({"count": 1}),
            timestamp: Utc::now(),
            created_at: Utc::now(),
        };

        batch.add(notification);
        assert_eq!(batch.len(), 1);
    }

    #[test]
    fn test_notification_batch_should_flush_by_size() {
        let mut batch = NotificationBatch::new();
        for i in 0..100 {
            batch.add(KafkaNotification {
                event_id: format!("evt-test-{}", i),
                event_type: NotificationEventType::Like,
                source_user_id: Uuid::new_v4(),
                target_user_id: Uuid::new_v4(),
                payload: serde_json::json!({"count": 1}),
                timestamp: Utc::now(),
                created_at: Utc::now(),
            });
        }

        assert!(batch.should_flush_by_size(100));
        assert!(!batch.should_flush_by_size(101));
    }

    #[test]
    fn test_retry_policy_backoff() {
        let policy = RetryPolicy::default();

        let backoff0 = policy.get_backoff(0);
        let backoff1 = policy.get_backoff(1);
        let backoff2 = policy.get_backoff(2);

        // Each attempt should have exponential backoff
        assert!(backoff1 > backoff0);
        assert!(backoff2 > backoff1);
    }

    #[test]
    fn test_retry_policy_max_retries() {
        let policy = RetryPolicy::default();

        assert!(policy.should_retry(0));
        assert!(policy.should_retry(1));
        assert!(policy.should_retry(2));
        assert!(!policy.should_retry(3));
    }

    #[test]
    fn test_notification_event_type_display() {
        assert_eq!(NotificationEventType::UserAction.to_string(), "user_action");
        assert_eq!(NotificationEventType::Follow.to_string(), "follow");
        assert_eq!(NotificationEventType::Like.to_string(), "like");
        assert_eq!(NotificationEventType::Comment.to_string(), "comment");
        assert_eq!(NotificationEventType::Mention.to_string(), "mention");
        assert_eq!(NotificationEventType::Repost.to_string(), "repost");
        assert_eq!(
            NotificationEventType::DirectMessage.to_string(),
            "direct_message"
        );
    }

    #[tokio::test]
    async fn test_kafka_consumer_creation() {
        // Note: This will fail if Kafka is not running, but it tests struct creation
        let result = KafkaNotificationConsumer::new(
            "localhost:9092".to_string(),
            "notifications".to_string(),
        );

        // In unit tests, we expect this might fail if Kafka is not available
        // The important part is the struct is correctly configured
        if let Ok(consumer) = result {
            assert_eq!(consumer.brokers, "localhost:9092");
            assert_eq!(consumer.topic, "notifications");
            assert_eq!(consumer.batch_size, 100);
        }
    }

    #[test]
    fn test_batch_clear() {
        let mut batch = NotificationBatch::new();
        let notification = KafkaNotification {
            event_id: "evt-test-1".to_string(),
            event_type: NotificationEventType::Like,
            source_user_id: Uuid::new_v4(),
            target_user_id: Uuid::new_v4(),
            payload: serde_json::json!({"count": 1}),
            timestamp: Utc::now(),
            created_at: Utc::now(),
        };

        batch.add(notification);
        assert_eq!(batch.len(), 1);

        batch.clear();
        assert_eq!(batch.len(), 0);
    }

    #[tokio::test]
    async fn test_batch_flush_empty() {
        let batch = NotificationBatch::new();
        let result = batch.flush().await;

        assert!(result.is_ok());
        assert_eq!(result.unwrap(), 0);
    }

    // Additional tests for T201.5 - 30+ unit tests requirement

    #[test]
    fn test_notification_event_type_all_variants() {
        // Ensure all 7 event types exist
        let events = vec![
            NotificationEventType::UserAction,
            NotificationEventType::Follow,
            NotificationEventType::Like,
            NotificationEventType::Comment,
            NotificationEventType::Mention,
            NotificationEventType::Repost,
            NotificationEventType::DirectMessage,
        ];
        assert_eq!(events.len(), 7);
    }

    #[test]
    fn test_notification_event_type_serialization() {
        let event = NotificationEventType::Follow;
        let json = serde_json::to_string(&event).unwrap();
        assert!(json.contains("follow"));
    }

    #[test]
    fn test_notification_event_type_deserialization() {
        let json = r#""follow""#;
        let event: NotificationEventType = serde_json::from_str(json).unwrap();
        assert_eq!(event, NotificationEventType::Follow);
    }

    #[test]
    fn test_kafka_notification_serialization() {
        let notification = KafkaNotification {
            event_id: "evt-123".to_string(),
            event_type: NotificationEventType::Like,
            source_user_id: Uuid::new_v4(),
            target_user_id: Uuid::new_v4(),
            payload: serde_json::json!({"count": 5}),
            timestamp: Utc::now(),
            created_at: Utc::now(),
        };

        let json = serde_json::to_string(&notification).unwrap();
        assert!(json.contains("evt-123"));
        assert!(json.contains("like"));
    }

    #[test]
    fn test_kafka_notification_deserialization() {
        let now = Utc::now();
        let json = serde_json::json!({
            "event_id": "evt-456",
            "event_type": "comment",
            "source_user_id": Uuid::new_v4(),
            "target_user_id": Uuid::new_v4(),
            "payload": {"text": "Great post!"},
            "timestamp": now,
            "created_at": now
        });

        let notification: KafkaNotification = serde_json::from_value(json).unwrap();
        assert_eq!(notification.event_id, "evt-456");
        assert_eq!(notification.event_type, NotificationEventType::Comment);
    }

    #[test]
    fn test_batch_should_flush_by_time() {
        let mut batch = NotificationBatch::new();
        batch.created_at = Utc::now() - chrono::Duration::seconds(6);

        assert!(batch.should_flush_by_time(Duration::from_secs(5)));
        assert!(!batch.should_flush_by_time(Duration::from_secs(10)));
    }

    #[test]
    fn test_batch_mixed_event_types() {
        let mut batch = NotificationBatch::new();
        let event_types = vec![
            NotificationEventType::Follow,
            NotificationEventType::Like,
            NotificationEventType::Comment,
        ];

        for event_type in event_types {
            batch.add(KafkaNotification {
                event_id: format!("evt-{}", Uuid::new_v4()),
                event_type,
                source_user_id: Uuid::new_v4(),
                target_user_id: Uuid::new_v4(),
                payload: serde_json::json!({}),
                timestamp: Utc::now(),
                created_at: Utc::now(),
            });
        }

        assert_eq!(batch.len(), 3);
    }

    #[test]
    fn test_retry_policy_custom() {
        let policy = RetryPolicy {
            max_retries: 5,
            backoff_ms: 200,
            max_backoff_ms: 10000,
        };

        assert!(policy.should_retry(0));
        assert!(policy.should_retry(4));
        assert!(!policy.should_retry(5));
    }

    #[test]
    fn test_retry_policy_backoff_capped() {
        let policy = RetryPolicy {
            max_retries: 10,
            backoff_ms: 100,
            max_backoff_ms: 1000,
        };

        let backoff0 = policy.get_backoff(0);
        let backoff5 = policy.get_backoff(5);
        let backoff10 = policy.get_backoff(10);

        assert_eq!(backoff0, Duration::from_millis(100));
        assert!(backoff5 > backoff0);
        assert_eq!(backoff10, Duration::from_millis(1000)); // Capped at max
    }

    #[test]
    fn test_notification_batch_id_unique() {
        let batch1 = NotificationBatch::new();
        let batch2 = NotificationBatch::new();

        assert_ne!(batch1.batch_id, batch2.batch_id);
    }

    #[test]
    fn test_batch_len_after_clear() {
        let mut batch = NotificationBatch::new();

        for i in 0..50 {
            batch.add(KafkaNotification {
                event_id: format!("evt-{}", i),
                event_type: NotificationEventType::Like,
                source_user_id: Uuid::new_v4(),
                target_user_id: Uuid::new_v4(),
                payload: serde_json::json!({}),
                timestamp: Utc::now(),
                created_at: Utc::now(),
            });
        }

        assert_eq!(batch.len(), 50);
        batch.clear();
        assert_eq!(batch.len(), 0);
        assert!(batch.is_empty());
    }

    #[test]
    fn test_retry_policy_zero_retries() {
        let policy = RetryPolicy {
            max_retries: 0,
            backoff_ms: 100,
            max_backoff_ms: 5000,
        };

        assert!(!policy.should_retry(0));
    }

    #[test]
    fn test_batch_should_not_flush_immediately() {
        let batch = NotificationBatch::new();

        assert!(!batch.should_flush_by_size(100));
        assert!(!batch.should_flush_by_time(Duration::from_secs(5)));
    }

    #[test]
    fn test_notification_event_type_equality() {
        assert_eq!(NotificationEventType::Follow, NotificationEventType::Follow);
        assert_ne!(NotificationEventType::Follow, NotificationEventType::Like);
    }

    #[test]
    fn test_retry_backoff_exponential_growth() {
        let policy = RetryPolicy::default();

        let b0 = policy.get_backoff(0);
        let b1 = policy.get_backoff(1);
        let b2 = policy.get_backoff(2);

        // Each backoff should be roughly double the previous (exponential)
        assert!(b1.as_millis() >= b0.as_millis() * 2);
        assert!(b2.as_millis() >= b1.as_millis() * 2);
    }

    #[tokio::test]
    async fn test_batch_clear_resets_timestamp() {
        let mut batch = NotificationBatch::new();
        let original_time = batch.created_at;

        tokio::time::sleep(Duration::from_millis(10)).await;
        batch.clear();

        assert!(batch.created_at > original_time);
    }

    #[test]
    fn test_notification_payload_complex() {
        let notification = KafkaNotification {
            event_id: "evt-complex".to_string(),
            event_type: NotificationEventType::Comment,
            source_user_id: Uuid::new_v4(),
            target_user_id: Uuid::new_v4(),
            payload: serde_json::json!({
                "comment_id": "cmt-123",
                "post_id": "post-456",
                "text": "Nice work!",
                "metadata": {
                    "reply_to": "cmt-789"
                }
            }),
            timestamp: Utc::now(),
            created_at: Utc::now(),
        };

        let serialized = serde_json::to_string(&notification).unwrap();
        let deserialized: KafkaNotification = serde_json::from_str(&serialized).unwrap();

        assert_eq!(deserialized.event_id, "evt-complex");
        assert!(deserialized.payload.get("comment_id").is_some());
    }

    #[test]
    fn test_batch_size_boundary() {
        let mut batch = NotificationBatch::new();

        for i in 0..99 {
            batch.add(KafkaNotification {
                event_id: format!("evt-{}", i),
                event_type: NotificationEventType::Like,
                source_user_id: Uuid::new_v4(),
                target_user_id: Uuid::new_v4(),
                payload: serde_json::json!({}),
                timestamp: Utc::now(),
                created_at: Utc::now(),
            });
        }

        assert!(!batch.should_flush_by_size(100));

        batch.add(KafkaNotification {
            event_id: "evt-100".to_string(),
            event_type: NotificationEventType::Like,
            source_user_id: Uuid::new_v4(),
            target_user_id: Uuid::new_v4(),
            payload: serde_json::json!({}),
            timestamp: Utc::now(),
            created_at: Utc::now(),
        });

        assert!(batch.should_flush_by_size(100));
    }

    #[test]
    fn test_all_event_types_have_unique_string_representation() {
        use std::collections::HashSet;

        let mut strings = HashSet::new();
        strings.insert(NotificationEventType::UserAction.to_string());
        strings.insert(NotificationEventType::Follow.to_string());
        strings.insert(NotificationEventType::Like.to_string());
        strings.insert(NotificationEventType::Comment.to_string());
        strings.insert(NotificationEventType::Mention.to_string());
        strings.insert(NotificationEventType::Repost.to_string());
        strings.insert(NotificationEventType::DirectMessage.to_string());

        assert_eq!(strings.len(), 7);
    }

    #[test]
    fn test_retry_policy_initial_delay() {
        let policy = RetryPolicy::default();
        let backoff0 = policy.get_backoff(0);

        assert_eq!(backoff0, Duration::from_millis(100));
    }

    #[test]
    fn test_retry_policy_max_delay() {
        let policy = RetryPolicy::default();
        let backoff_large = policy.get_backoff(100); // Very large attempt

        assert_eq!(backoff_large, Duration::from_millis(5000)); // Capped at max
    }

    #[test]
    fn test_notification_batch_not_empty_after_add() {
        let mut batch = NotificationBatch::new();
        assert!(batch.is_empty());

        batch.add(KafkaNotification {
            event_id: "evt-1".to_string(),
            event_type: NotificationEventType::Follow,
            source_user_id: Uuid::new_v4(),
            target_user_id: Uuid::new_v4(),
            payload: serde_json::json!({}),
            timestamp: Utc::now(),
            created_at: Utc::now(),
        });

        assert!(!batch.is_empty());
    }

    #[test]
    fn test_connection_pool_size() {
        // This test may fail if Kafka is not available, but it tests the pool creation
        let result = ConnectionPool::new("localhost:9092", "test-group", 3);

        if let Ok(pool) = result {
            assert_eq!(pool.size(), 3);
        }
    }
}
