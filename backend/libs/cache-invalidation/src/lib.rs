//! Cache Invalidation Library using Redis Pub/Sub
//!
//! Provides cross-service cache coherence through broadcast invalidation messages.
//!
//! # Architecture
//!
//! ```text
//! Service A (user-service):
//!   1. Update user profile in DB
//!   2. Publish invalidation to Redis:
//!      PUBLISH cache:invalidate {"entity_type": "User", "entity_id": "123"}
//!      ↓
//! Redis Pub/Sub (broadcast to all subscribers)
//!      ↓
//! Service B, C, D (graphql-gateway, feed-service, etc):
//!   3. Receive invalidation message
//!   4. Delete from Redis cache: DEL user:123
//!   5. Delete from in-memory cache: dashmap.remove("user:123")
//! ```
//!
//! # Example: Publisher
//!
//! ```no_run
//! use cache_invalidation::InvalidationPublisher;
//!
//! #[tokio::main]
//! async fn main() -> anyhow::Result<()> {
//!     let publisher = InvalidationPublisher::new(
//!         "redis://localhost:6379",
//!         "user-service".to_string()
//!     ).await?;
//!
//!     // Single entity invalidation
//!     publisher.invalidate_user("123").await?;
//!
//!     // Pattern-based invalidation
//!     publisher.invalidate_pattern("feed:*").await?;
//!
//!     // Batch invalidation
//!     publisher.invalidate_batch(vec!["user:1", "user:2"]).await?;
//!
//!     Ok(())
//! }
//! ```
//!
//! # Example: Subscriber
//!
//! ```no_run
//! use cache_invalidation::{InvalidationSubscriber, InvalidationMessage};
//!
//! #[tokio::main]
//! async fn main() -> anyhow::Result<()> {
//!     let subscriber = InvalidationSubscriber::new("redis://localhost:6379").await?;
//!
//!     let handle = subscriber.subscribe(|msg| async move {
//!         println!("Invalidating: {:?}", msg);
//!         // Delete from Redis cache
//!         // Delete from memory cache
//!         Ok(())
//!     }).await?;
//!
//!     handle.await?;
//!     Ok(())
//! }
//! ```

use futures_util::StreamExt;
use redis::aio::ConnectionManager;
use redis::{AsyncCommands, Client};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::task::JoinHandle;
use tracing::{debug, error, info, warn};

mod error;
mod helpers;
mod stats;

pub use error::InvalidationError;
pub use helpers::{build_cache_key, parse_cache_key};
pub use stats::InvalidationStats;

type Result<T> = std::result::Result<T, InvalidationError>;

/// Supported entity types for cache invalidation
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum EntityType {
    User,
    Post,
    Comment,
    Notification,
    Feed,
    Custom(String),
}

impl std::fmt::Display for EntityType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            EntityType::User => write!(f, "user"),
            EntityType::Post => write!(f, "post"),
            EntityType::Comment => write!(f, "comment"),
            EntityType::Notification => write!(f, "notification"),
            EntityType::Feed => write!(f, "feed"),
            EntityType::Custom(s) => write!(f, "{}", s),
        }
    }
}

impl From<&str> for EntityType {
    fn from(s: &str) -> Self {
        match s {
            "user" => EntityType::User,
            "post" => EntityType::Post,
            "comment" => EntityType::Comment,
            "notification" => EntityType::Notification,
            "feed" => EntityType::Feed,
            custom => EntityType::Custom(custom.to_string()),
        }
    }
}

/// Invalidation action
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum InvalidationAction {
    Delete,  // Delete single entity
    Update,  // Entity updated (may need refresh)
    Batch,   // Batch of entities
    Pattern, // Pattern-based (e.g., "user:*")
}

/// Cache invalidation message
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InvalidationMessage {
    pub message_id: String,
    pub entity_type: EntityType,
    pub entity_id: Option<String>,
    pub pattern: Option<String>,
    pub entity_ids: Option<Vec<String>>,
    pub action: InvalidationAction,
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub source_service: String,
    pub metadata: Option<serde_json::Value>,
}

impl InvalidationMessage {
    /// Create new delete message
    pub fn delete(entity_type: EntityType, entity_id: String, source_service: String) -> Self {
        Self {
            message_id: uuid::Uuid::new_v4().to_string(),
            entity_type,
            entity_id: Some(entity_id),
            pattern: None,
            entity_ids: None,
            action: InvalidationAction::Delete,
            timestamp: chrono::Utc::now(),
            source_service,
            metadata: None,
        }
    }

    /// Create new update message
    pub fn update(entity_type: EntityType, entity_id: String, source_service: String) -> Self {
        Self {
            message_id: uuid::Uuid::new_v4().to_string(),
            entity_type,
            entity_id: Some(entity_id),
            pattern: None,
            entity_ids: None,
            action: InvalidationAction::Update,
            timestamp: chrono::Utc::now(),
            source_service,
            metadata: None,
        }
    }

    /// Create new pattern message
    pub fn pattern(pattern: String, source_service: String) -> Self {
        Self {
            message_id: uuid::Uuid::new_v4().to_string(),
            entity_type: EntityType::Custom("pattern".to_string()),
            entity_id: None,
            pattern: Some(pattern),
            entity_ids: None,
            action: InvalidationAction::Pattern,
            timestamp: chrono::Utc::now(),
            source_service,
            metadata: None,
        }
    }

    /// Create new batch message
    pub fn batch(entity_ids: Vec<String>, source_service: String) -> Self {
        Self {
            message_id: uuid::Uuid::new_v4().to_string(),
            entity_type: EntityType::Custom("batch".to_string()),
            entity_id: None,
            pattern: None,
            entity_ids: Some(entity_ids),
            action: InvalidationAction::Batch,
            timestamp: chrono::Utc::now(),
            source_service,
            metadata: None,
        }
    }
}

/// Publisher for cache invalidation events
#[derive(Clone)]
pub struct InvalidationPublisher {
    client: ConnectionManager,
    channel: String,
    service_name: String,
}

impl InvalidationPublisher {
    /// Default Redis channel for cache invalidation
    pub const DEFAULT_CHANNEL: &'static str = "cache:invalidate";

    /// Create new publisher
    ///
    /// # Arguments
    ///
    /// * `redis_url` - Redis connection URL (e.g., "redis://localhost:6379")
    /// * `service_name` - Name of the publishing service (e.g., "user-service")
    ///
    /// # Example
    ///
    /// ```no_run
    /// # use cache_invalidation::InvalidationPublisher;
    /// # #[tokio::main]
    /// # async fn main() -> anyhow::Result<()> {
    /// let publisher = InvalidationPublisher::new(
    ///     "redis://localhost:6379",
    ///     "user-service".to_string()
    /// ).await?;
    /// # Ok(())
    /// # }
    /// ```
    pub async fn new(redis_url: &str, service_name: String) -> Result<Self> {
        let client = Client::open(redis_url)?;
        let connection = ConnectionManager::new(client).await?;

        Ok(Self {
            client: connection,
            channel: Self::DEFAULT_CHANNEL.to_string(),
            service_name,
        })
    }

    /// Create publisher with custom channel
    pub async fn with_channel(
        redis_url: &str,
        service_name: String,
        channel: String,
    ) -> Result<Self> {
        let client = Client::open(redis_url)?;
        let connection = ConnectionManager::new(client).await?;

        Ok(Self {
            client: connection,
            channel,
            service_name,
        })
    }

    /// Publish invalidation message
    ///
    /// Returns number of subscribers that received the message
    pub async fn publish(&self, msg: InvalidationMessage) -> Result<usize> {
        let payload = serde_json::to_string(&msg)?;

        debug!(
            message_id = %msg.message_id,
            entity_type = %msg.entity_type,
            action = ?msg.action,
            channel = %self.channel,
            "Publishing invalidation message"
        );

        let mut conn = self.client.clone();
        let subscriber_count: usize = conn.publish(&self.channel, payload).await?;

        info!(
            message_id = %msg.message_id,
            subscribers = subscriber_count,
            "Invalidation message published"
        );

        Ok(subscriber_count)
    }

    /// Invalidate single user
    ///
    /// # Example
    ///
    /// ```no_run
    /// # use cache_invalidation::InvalidationPublisher;
    /// # #[tokio::main]
    /// # async fn main() -> anyhow::Result<()> {
    /// # let publisher = InvalidationPublisher::new("redis://localhost", "test".into()).await?;
    /// publisher.invalidate_user("123").await?;
    /// # Ok(())
    /// # }
    /// ```
    pub async fn invalidate_user(&self, user_id: &str) -> Result<usize> {
        let msg = InvalidationMessage::delete(
            EntityType::User,
            user_id.to_string(),
            self.service_name.clone(),
        );
        self.publish(msg).await
    }

    /// Invalidate single post
    pub async fn invalidate_post(&self, post_id: &str) -> Result<usize> {
        let msg = InvalidationMessage::delete(
            EntityType::Post,
            post_id.to_string(),
            self.service_name.clone(),
        );
        self.publish(msg).await
    }

    /// Invalidate single comment
    pub async fn invalidate_comment(&self, comment_id: &str) -> Result<usize> {
        let msg = InvalidationMessage::delete(
            EntityType::Comment,
            comment_id.to_string(),
            self.service_name.clone(),
        );
        self.publish(msg).await
    }

    /// Invalidate single notification
    pub async fn invalidate_notification(&self, notification_id: &str) -> Result<usize> {
        let msg = InvalidationMessage::delete(
            EntityType::Notification,
            notification_id.to_string(),
            self.service_name.clone(),
        );
        self.publish(msg).await
    }

    /// Invalidate with pattern
    ///
    /// # Example
    ///
    /// ```no_run
    /// # use cache_invalidation::InvalidationPublisher;
    /// # #[tokio::main]
    /// # async fn main() -> anyhow::Result<()> {
    /// # let publisher = InvalidationPublisher::new("redis://localhost", "test".into()).await?;
    /// // Invalidate all user caches
    /// publisher.invalidate_pattern("user:*").await?;
    ///
    /// // Invalidate all feed caches
    /// publisher.invalidate_pattern("feed:*").await?;
    /// # Ok(())
    /// # }
    /// ```
    pub async fn invalidate_pattern(&self, pattern: &str) -> Result<usize> {
        let msg = InvalidationMessage::pattern(pattern.to_string(), self.service_name.clone());
        self.publish(msg).await
    }

    /// Batch invalidate
    ///
    /// # Example
    ///
    /// ```no_run
    /// # use cache_invalidation::InvalidationPublisher;
    /// # #[tokio::main]
    /// # async fn main() -> anyhow::Result<()> {
    /// # let publisher = InvalidationPublisher::new("redis://localhost", "test".into()).await?;
    /// publisher.invalidate_batch(vec![
    ///     "user:1".to_string(),
    ///     "user:2".to_string(),
    ///     "user:3".to_string()
    /// ]).await?;
    /// # Ok(())
    /// # }
    /// ```
    pub async fn invalidate_batch(&self, cache_keys: Vec<String>) -> Result<usize> {
        let msg = InvalidationMessage::batch(cache_keys, self.service_name.clone());
        self.publish(msg).await
    }

    /// Invalidate entity with custom type
    pub async fn invalidate_custom(&self, entity_type: &str, entity_id: &str) -> Result<usize> {
        let msg = InvalidationMessage::delete(
            EntityType::Custom(entity_type.to_string()),
            entity_id.to_string(),
            self.service_name.clone(),
        );
        self.publish(msg).await
    }
}

/// Subscriber for cache invalidation events
pub struct InvalidationSubscriber {
    client: Client,
    channel: String,
}

impl InvalidationSubscriber {
    /// Create new subscriber
    ///
    /// # Example
    ///
    /// ```no_run
    /// # use cache_invalidation::InvalidationSubscriber;
    /// # #[tokio::main]
    /// # async fn main() -> anyhow::Result<()> {
    /// let subscriber = InvalidationSubscriber::new("redis://localhost:6379").await?;
    /// # Ok(())
    /// # }
    /// ```
    pub async fn new(redis_url: &str) -> Result<Self> {
        let client = Client::open(redis_url)?;

        Ok(Self {
            client,
            channel: InvalidationPublisher::DEFAULT_CHANNEL.to_string(),
        })
    }

    /// Create subscriber with custom channel
    pub async fn with_channel(redis_url: &str, channel: String) -> Result<Self> {
        let client = Client::open(redis_url)?;

        Ok(Self { client, channel })
    }

    /// Subscribe to invalidation events with callback
    ///
    /// Returns JoinHandle for background task
    ///
    /// # Example
    ///
    /// ```no_run
    /// # use cache_invalidation::{InvalidationSubscriber, InvalidationMessage};
    /// # #[tokio::main]
    /// # async fn main() -> anyhow::Result<()> {
    /// let subscriber = InvalidationSubscriber::new("redis://localhost:6379").await?;
    ///
    /// let handle = subscriber.subscribe(|msg| async move {
    ///     println!("Received: {:?}", msg);
    ///     Ok(())
    /// }).await?;
    ///
    /// // Wait for subscription to complete
    /// handle.await?;
    /// # Ok(())
    /// # }
    /// ```
    pub async fn subscribe<F, Fut>(&self, callback: F) -> Result<JoinHandle<()>>
    where
        F: Fn(InvalidationMessage) -> Fut + Send + Sync + 'static,
        Fut: std::future::Future<Output = Result<()>> + Send + 'static,
    {
        let mut pubsub = self.client.get_async_pubsub().await?;
        pubsub.subscribe(&self.channel).await?;

        info!(channel = %self.channel, "Subscribed to invalidation events");

        let callback = Arc::new(callback);

        let handle = tokio::spawn(async move {
            let mut stream = pubsub.on_message();

            while let Some(msg) = stream.next().await {
                let payload = match msg.get_payload::<String>() {
                    Ok(p) => p,
                    Err(e) => {
                        error!(error = ?e, "Failed to get message payload");
                        continue;
                    }
                };

                let invalidation_msg: InvalidationMessage = match serde_json::from_str(&payload) {
                    Ok(m) => m,
                    Err(e) => {
                        error!(error = ?e, payload = %payload, "Failed to deserialize message");
                        continue;
                    }
                };

                debug!(
                    message_id = %invalidation_msg.message_id,
                    entity_type = %invalidation_msg.entity_type,
                    action = ?invalidation_msg.action,
                    "Received invalidation message"
                );

                let callback_clone = Arc::clone(&callback);
                if let Err(e) = callback_clone(invalidation_msg.clone()).await {
                    error!(
                        error = ?e,
                        message_id = %invalidation_msg.message_id,
                        "Callback execution failed"
                    );
                }
            }

            warn!("Invalidation subscription ended");
        });

        Ok(handle)
    }

    /// Stop subscription
    pub async fn unsubscribe(&self, handle: JoinHandle<()>) -> Result<()> {
        handle.abort();
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_entity_type_display() {
        assert_eq!(EntityType::User.to_string(), "user");
        assert_eq!(EntityType::Post.to_string(), "post");
        assert_eq!(EntityType::Custom("custom".into()).to_string(), "custom");
    }

    #[test]
    fn test_entity_type_from_str() {
        assert_eq!(EntityType::from("user"), EntityType::User);
        assert_eq!(EntityType::from("post"), EntityType::Post);
        assert_eq!(
            EntityType::from("custom"),
            EntityType::Custom("custom".into())
        );
    }

    #[test]
    fn test_invalidation_message_delete() {
        let msg = InvalidationMessage::delete(
            EntityType::User,
            "123".to_string(),
            "test-service".to_string(),
        );

        assert_eq!(msg.entity_type, EntityType::User);
        assert_eq!(msg.entity_id, Some("123".to_string()));
        assert_eq!(msg.action, InvalidationAction::Delete);
        assert_eq!(msg.source_service, "test-service");
    }

    #[test]
    fn test_invalidation_message_pattern() {
        let msg = InvalidationMessage::pattern("user:*".to_string(), "test-service".to_string());

        assert_eq!(msg.pattern, Some("user:*".to_string()));
        assert_eq!(msg.action, InvalidationAction::Pattern);
    }

    #[test]
    fn test_invalidation_message_batch() {
        let msg = InvalidationMessage::batch(
            vec!["user:1".into(), "user:2".into()],
            "test-service".to_string(),
        );

        assert_eq!(msg.entity_ids, Some(vec!["user:1".into(), "user:2".into()]));
        assert_eq!(msg.action, InvalidationAction::Batch);
    }

    #[test]
    fn test_invalidation_message_serialization() {
        let msg = InvalidationMessage::delete(
            EntityType::User,
            "123".to_string(),
            "test-service".to_string(),
        );

        let json = serde_json::to_string(&msg).unwrap();
        let deserialized: InvalidationMessage = serde_json::from_str(&json).unwrap();

        assert_eq!(msg.message_id, deserialized.message_id);
        assert_eq!(msg.entity_type, deserialized.entity_type);
        assert_eq!(msg.entity_id, deserialized.entity_id);
    }
}
