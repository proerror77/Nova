use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{
    mpsc::{unbounded_channel, UnboundedReceiver, UnboundedSender},
    RwLock,
};
use uuid::Uuid;

pub mod broadcast;
pub mod events;
pub mod handlers;
pub mod message_types;
pub mod streams;
pub mod subscription;

/// Unique identifier for a WebSocket subscriber
///
/// Each WebSocket connection gets a unique subscriber ID when it registers.
/// This allows for precise cleanup when connections close.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct SubscriberId(Uuid);

impl SubscriberId {
    pub fn new() -> Self {
        Self(Uuid::new_v4())
    }
}

impl Default for SubscriberId {
    fn default() -> Self {
        Self::new()
    }
}

/// Subscriber entry with ID and channel
struct Subscriber {
    id: SubscriberId,
    sender: UnboundedSender<String>, // Changed from axum Message to String
}

/// Connection registry for WebSocket subscribers
///
/// Tracks which WebSocket connections are subscribed to which conversations.
/// Supports precise cleanup using subscriber IDs to prevent memory leaks.
#[derive(Default, Clone)]
pub struct ConnectionRegistry {
    // conversation_id -> list of subscribers
    inner: Arc<RwLock<HashMap<Uuid, Vec<Subscriber>>>>,
}

impl ConnectionRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    /// Add a subscriber to a conversation
    ///
    /// Returns a tuple of (subscriber_id, receiver) where:
    /// - subscriber_id: Unique ID for this subscription (used for cleanup)
    /// - receiver: Channel to receive broadcast messages
    pub async fn add_subscriber(
        &self,
        conversation_id: Uuid,
    ) -> (SubscriberId, UnboundedReceiver<String>) {
        let (tx, rx) = unbounded_channel();
        let subscriber_id = SubscriberId::new();

        let subscriber = Subscriber {
            id: subscriber_id,
            sender: tx,
        };

        let mut guard = self.inner.write().await;
        guard.entry(conversation_id).or_default().push(subscriber);

        tracing::debug!(
            "Added subscriber {:?} to conversation {}, total subscribers: {}",
            subscriber_id,
            conversation_id,
            guard.get(&conversation_id).map(|v| v.len()).unwrap_or(0)
        );

        (subscriber_id, rx)
    }

    /// Remove a specific subscriber from a conversation
    ///
    /// This is the CRITICAL cleanup function that prevents memory leaks.
    /// Must be called when a WebSocket connection closes.
    pub async fn remove_subscriber(&self, conversation_id: Uuid, subscriber_id: SubscriberId) {
        let mut guard = self.inner.write().await;

        if let Some(subscribers) = guard.get_mut(&conversation_id) {
            let before = subscribers.len();
            subscribers.retain(|s| s.id != subscriber_id);
            let after = subscribers.len();

            if before != after {
                tracing::debug!(
                    "Removed subscriber {:?} from conversation {}, remaining: {}",
                    subscriber_id,
                    conversation_id,
                    after
                );
            }

            // Clean up empty conversation entries
            if subscribers.is_empty() {
                guard.remove(&conversation_id);
                tracing::debug!(
                    "Removed empty conversation {} from registry",
                    conversation_id
                );
            }
        }
    }

    /// Broadcast message to all subscribers of a conversation
    ///
    /// Automatically cleans up dead senders (where send fails).
    pub async fn broadcast(&self, conversation_id: Uuid, msg: String) {
        let mut guard = self.inner.write().await;
        if let Some(subscribers) = guard.get_mut(&conversation_id) {
            let before = subscribers.len();

            // Send to all subscribers, remove dead ones
            subscribers.retain(|subscriber| subscriber.sender.send(msg.clone()).is_ok());

            let after = subscribers.len();
            if before != after {
                tracing::debug!(
                    "Broadcast to conversation {}: {} dead senders cleaned up, {} active",
                    conversation_id,
                    before - after,
                    after
                );
            }
        }
    }

    /// Get subscriber count for a conversation (for debugging/metrics)
    pub async fn subscriber_count(&self, conversation_id: Uuid) -> usize {
        let guard = self.inner.read().await;
        guard.get(&conversation_id).map(|v| v.len()).unwrap_or(0)
    }
}
