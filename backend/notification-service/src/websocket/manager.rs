/// WebSocket Connection Manager
///
/// Manages active WebSocket connections and routes notifications to connected clients.
/// Supports:
/// - User subscription/unsubscription
/// - Notification routing to specific users
/// - Heartbeat (ping/pong) mechanism
/// - Graceful disconnection handling
/// - Multiple concurrent connections per user

use super::WebSocketMessage;
use crate::error::Result;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{mpsc, RwLock};
use uuid::Uuid;

/// Type alias for WebSocket message sender
pub type WebSocketSender = mpsc::UnboundedSender<WebSocketMessage>;

/// Manages active WebSocket connections
///
/// Thread-safe connection manager using Arc<RwLock<>> for shared state.
/// Routes notifications to specific users and maintains connection lifecycle.
#[derive(Clone)]
pub struct ConnectionManager {
    /// Map of user_id -> Vec of message senders
    /// Each user can have multiple concurrent connections
    connections: Arc<RwLock<HashMap<Uuid, Vec<WebSocketSender>>>>,
}

impl ConnectionManager {
    /// Create a new ConnectionManager
    pub fn new() -> Self {
        Self {
            connections: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Subscribe a user to notifications
    ///
    /// Adds a new WebSocket sender for the given user.
    /// Multiple senders (connections) can be added per user.
    ///
    /// # Arguments
    ///
    /// * `user_id` - The user to subscribe
    /// * `sender` - The WebSocket message sender
    ///
    /// # Returns
    ///
    /// A connection ID that can be used for cleanup
    pub async fn subscribe(&self, user_id: Uuid, sender: WebSocketSender) -> Result<String> {
        let mut connections = self.connections.write().await;

        // Add sender to user's connection list
        connections
            .entry(user_id)
            .or_insert_with(Vec::new)
            .push(sender);

        // Generate connection ID
        let connection_id = format!("{}-{}", user_id, chrono::Utc::now().timestamp_millis());

        Ok(connection_id)
    }

    /// Unsubscribe a user by removing all their connections
    ///
    /// # Arguments
    ///
    /// * `user_id` - The user to unsubscribe
    pub async fn unsubscribe(&self, user_id: Uuid) -> Result<()> {
        let mut connections = self.connections.write().await;
        connections.remove(&user_id);
        Ok(())
    }

    /// Send a notification to a specific user
    ///
    /// Routes the notification to all active connections for the user.
    /// Silently skips if user has no active connections.
    ///
    /// # Arguments
    ///
    /// * `user_id` - The recipient user
    /// * `notification` - The notification message
    pub async fn send_notification(
        &self,
        user_id: Uuid,
        notification: WebSocketMessage,
    ) -> Result<()> {
        let connections = self.connections.read().await;

        if let Some(senders) = connections.get(&user_id) {
            // Send to all active connections for this user
            for sender in senders {
                // Ignore send errors (connection might be closed)
                let _ = sender.send(notification.clone());
            }
        }

        Ok(())
    }

    /// Broadcast a message to all connected users
    ///
    /// # Arguments
    ///
    /// * `message` - The message to broadcast
    pub async fn broadcast(&self, message: WebSocketMessage) -> Result<()> {
        let connections = self.connections.read().await;

        for senders in connections.values() {
            for sender in senders {
                // Ignore send errors (connection might be closed)
                let _ = sender.send(message.clone());
            }
        }

        Ok(())
    }

    /// Send a heartbeat (ping) to a specific user
    ///
    /// # Arguments
    ///
    /// * `user_id` - The user to ping
    pub async fn ping_user(&self, user_id: Uuid) -> Result<()> {
        let ping = WebSocketMessage::ping();
        self.send_notification(user_id, ping).await
    }

    /// Send a heartbeat (ping) to all connected users
    pub async fn ping_all(&self) -> Result<()> {
        let ping = WebSocketMessage::ping();
        self.broadcast(ping).await
    }

    /// Get the number of active connections for a user
    ///
    /// # Arguments
    ///
    /// * `user_id` - The user to check
    ///
    /// # Returns
    ///
    /// The number of active connections
    pub async fn connection_count(&self, user_id: Uuid) -> usize {
        let connections = self.connections.read().await;
        connections.get(&user_id).map(|v| v.len()).unwrap_or(0)
    }

    /// Get the total number of active connections
    pub async fn total_connections(&self) -> usize {
        let connections = self.connections.read().await;
        connections.values().map(|v| v.len()).sum()
    }

    /// Get the number of connected users
    pub async fn connected_users_count(&self) -> usize {
        let connections = self.connections.read().await;
        connections.len()
    }

    /// Send error message to a user
    ///
    /// # Arguments
    ///
    /// * `user_id` - The recipient user
    /// * `code` - The error code
    /// * `message` - The error message
    pub async fn send_error(
        &self,
        user_id: Uuid,
        code: String,
        message: String,
    ) -> Result<()> {
        let error_msg = WebSocketMessage::error(code, message);
        self.send_notification(user_id, error_msg).await
    }

    /// Broadcast error to all users
    ///
    /// # Arguments
    ///
    /// * `code` - The error code
    /// * `message` - The error message
    pub async fn broadcast_error(&self, code: String, message: String) -> Result<()> {
        let error_msg = WebSocketMessage::error(code, message);
        self.broadcast(error_msg).await
    }

    /// Send acknowledgment to a user
    ///
    /// # Arguments
    ///
    /// * `user_id` - The recipient user
    /// * `message_id` - The message ID being acknowledged
    pub async fn send_ack(&self, user_id: Uuid, message_id: Option<String>) -> Result<()> {
        let ack = WebSocketMessage::Ack { message_id };
        self.send_notification(user_id, ack).await
    }

    /// Send connection confirmation to a user
    ///
    /// # Arguments
    ///
    /// * `user_id` - The user to send confirmation to
    pub async fn send_connected(&self, user_id: Uuid) -> Result<()> {
        let connected = WebSocketMessage::connected();
        self.send_notification(user_id, connected).await
    }

    /// Clear all connections (useful for testing or graceful shutdown)
    pub async fn clear_all(&self) -> Result<()> {
        let mut connections = self.connections.write().await;
        connections.clear();
        Ok(())
    }

    /// Get list of all connected user IDs
    pub async fn connected_user_ids(&self) -> Vec<Uuid> {
        let connections = self.connections.read().await;
        connections.keys().copied().collect()
    }
}

impl Default for ConnectionManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::sync::mpsc;

    #[tokio::test]
    async fn test_connection_manager_creation() {
        let manager = ConnectionManager::new();
        assert_eq!(manager.total_connections().await, 0);
        assert_eq!(manager.connected_users_count().await, 0);
    }

    #[tokio::test]
    async fn test_subscribe_user() {
        let manager = ConnectionManager::new();
        let user_id = Uuid::new_v4();
        let (tx, _rx) = mpsc::unbounded_channel();

        let result = manager.subscribe(user_id, tx).await;
        assert!(result.is_ok());
        assert_eq!(manager.connection_count(user_id).await, 1);
        assert_eq!(manager.connected_users_count().await, 1);
    }

    #[tokio::test]
    async fn test_multiple_connections_same_user() {
        let manager = ConnectionManager::new();
        let user_id = Uuid::new_v4();

        for _ in 0..3 {
            let (tx, _rx) = mpsc::unbounded_channel();
            manager.subscribe(user_id, tx).await.unwrap();
        }

        assert_eq!(manager.connection_count(user_id).await, 3);
        assert_eq!(manager.total_connections().await, 3);
        assert_eq!(manager.connected_users_count().await, 1);
    }

    #[tokio::test]
    async fn test_multiple_users() {
        let manager = ConnectionManager::new();

        for _ in 0..5 {
            let user_id = Uuid::new_v4();
            let (tx, _rx) = mpsc::unbounded_channel();
            manager.subscribe(user_id, tx).await.unwrap();
        }

        assert_eq!(manager.total_connections().await, 5);
        assert_eq!(manager.connected_users_count().await, 5);
    }

    #[tokio::test]
    async fn test_send_notification() {
        let manager = ConnectionManager::new();
        let user_id = Uuid::new_v4();
        let (tx, mut rx) = mpsc::unbounded_channel();

        manager.subscribe(user_id, tx).await.unwrap();

        let notification = WebSocketMessage::notification(
            Uuid::new_v4(),
            user_id,
            "like".to_string(),
            "New Like".to_string(),
            "Someone liked your post".to_string(),
            None,
            "normal".to_string(),
        );

        manager
            .send_notification(user_id, notification.clone())
            .await
            .unwrap();

        // Check that message was received
        let received = rx.recv().await;
        assert!(received.is_some());
        assert_eq!(received.unwrap(), notification);
    }

    #[tokio::test]
    async fn test_send_notification_no_connection() {
        let manager = ConnectionManager::new();
        let user_id = Uuid::new_v4();

        let notification = WebSocketMessage::notification(
            Uuid::new_v4(),
            user_id,
            "like".to_string(),
            "New Like".to_string(),
            "Someone liked your post".to_string(),
            None,
            "normal".to_string(),
        );

        // Should not error if user has no connections
        let result = manager.send_notification(user_id, notification).await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_unsubscribe_user() {
        let manager = ConnectionManager::new();
        let user_id = Uuid::new_v4();
        let (tx, _rx) = mpsc::unbounded_channel();

        manager.subscribe(user_id, tx).await.unwrap();
        assert_eq!(manager.connection_count(user_id).await, 1);

        manager.unsubscribe(user_id).await.unwrap();
        assert_eq!(manager.connection_count(user_id).await, 0);
        assert_eq!(manager.connected_users_count().await, 0);
    }

    #[tokio::test]
    async fn test_broadcast_message() {
        let manager = ConnectionManager::new();
        let mut receivers = vec![];

        // Subscribe 3 users
        for _ in 0..3 {
            let user_id = Uuid::new_v4();
            let (tx, rx) = mpsc::unbounded_channel();
            manager.subscribe(user_id, tx).await.unwrap();
            receivers.push(rx);
        }

        let message = WebSocketMessage::ping();
        manager.broadcast(message.clone()).await.unwrap();

        // Check all users received the message
        for mut rx in receivers {
            let received = rx.recv().await;
            assert!(received.is_some());
            assert_eq!(received.unwrap(), message);
        }
    }

    #[tokio::test]
    async fn test_ping_user() {
        let manager = ConnectionManager::new();
        let user_id = Uuid::new_v4();
        let (tx, mut rx) = mpsc::unbounded_channel();

        manager.subscribe(user_id, tx).await.unwrap();
        manager.ping_user(user_id).await.unwrap();

        let received = rx.recv().await;
        assert!(received.is_some());
        assert!(matches!(received.unwrap(), WebSocketMessage::Ping { .. }));
    }

    #[tokio::test]
    async fn test_ping_all() {
        let manager = ConnectionManager::new();
        let mut receivers = vec![];

        // Subscribe 2 users
        for _ in 0..2 {
            let user_id = Uuid::new_v4();
            let (tx, rx) = mpsc::unbounded_channel();
            manager.subscribe(user_id, tx).await.unwrap();
            receivers.push(rx);
        }

        manager.ping_all().await.unwrap();

        // Check all users received ping
        for mut rx in receivers {
            let received = rx.recv().await;
            assert!(received.is_some());
            assert!(matches!(received.unwrap(), WebSocketMessage::Ping { .. }));
        }
    }

    #[tokio::test]
    async fn test_send_error() {
        let manager = ConnectionManager::new();
        let user_id = Uuid::new_v4();
        let (tx, mut rx) = mpsc::unbounded_channel();

        manager.subscribe(user_id, tx).await.unwrap();
        manager
            .send_error(user_id, "INVALID_USER".to_string(), "User not found".to_string())
            .await
            .unwrap();

        let received = rx.recv().await;
        assert!(received.is_some());
        assert!(matches!(received.unwrap(), WebSocketMessage::Error { .. }));
    }

    #[tokio::test]
    async fn test_send_ack() {
        let manager = ConnectionManager::new();
        let user_id = Uuid::new_v4();
        let (tx, mut rx) = mpsc::unbounded_channel();

        manager.subscribe(user_id, tx).await.unwrap();
        manager
            .send_ack(user_id, Some("msg-123".to_string()))
            .await
            .unwrap();

        let received = rx.recv().await;
        assert!(received.is_some());
        assert!(matches!(received.unwrap(), WebSocketMessage::Ack { .. }));
    }

    #[tokio::test]
    async fn test_send_connected() {
        let manager = ConnectionManager::new();
        let user_id = Uuid::new_v4();
        let (tx, mut rx) = mpsc::unbounded_channel();

        manager.subscribe(user_id, tx).await.unwrap();
        manager.send_connected(user_id).await.unwrap();

        let received = rx.recv().await;
        assert!(received.is_some());
        assert!(matches!(received.unwrap(), WebSocketMessage::Connected { .. }));
    }

    #[tokio::test]
    async fn test_clear_all() {
        let manager = ConnectionManager::new();

        // Subscribe multiple users
        for _ in 0..3 {
            let user_id = Uuid::new_v4();
            let (tx, _rx) = mpsc::unbounded_channel();
            manager.subscribe(user_id, tx).await.unwrap();
        }

        assert_eq!(manager.connected_users_count().await, 3);

        manager.clear_all().await.unwrap();

        assert_eq!(manager.connected_users_count().await, 0);
        assert_eq!(manager.total_connections().await, 0);
    }

    #[tokio::test]
    async fn test_connected_user_ids() {
        let manager = ConnectionManager::new();
        let user_ids: Vec<Uuid> = (0..3).map(|_| Uuid::new_v4()).collect();

        for user_id in &user_ids {
            let (tx, _rx) = mpsc::unbounded_channel();
            manager.subscribe(*user_id, tx).await.unwrap();
        }

        let connected = manager.connected_user_ids().await;
        assert_eq!(connected.len(), 3);

        for user_id in user_ids {
            assert!(connected.contains(&user_id));
        }
    }

    #[tokio::test]
    async fn test_default_constructor() {
        let manager = ConnectionManager::default();
        assert_eq!(manager.total_connections().await, 0);
    }
}
