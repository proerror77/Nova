// WebSocket Hub: Real-time notification broadcasting
// Phase 7A Week 2: T203 - WebSocket Handler
//
// This module provides WebSocket connection management for real-time
// notification delivery to connected clients.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::mpsc::UnboundedSender;
use tokio::sync::{broadcast, RwLock};
use uuid::Uuid;

/// Connection ID type for uniquely identifying WebSocket connections
pub type ConnectionId = Uuid;

/// User ID type for identifying users
pub type UserId = Uuid;

/// WebSocket Hub - Central manager for all WebSocket connections
pub struct WebSocketHub {
    /// All active connections indexed by connection ID
    connections: Arc<RwLock<HashMap<ConnectionId, ClientConnection>>>,
    /// Broadcast channel for sending messages to all connected clients
    broadcast_channel: broadcast::Sender<Message>,
}

/// Individual client connection tracking
pub struct ClientConnection {
    /// User ID this connection belongs to
    pub user_id: UserId,
    /// Unique connection ID
    pub connection_id: ConnectionId,
    /// Channel for sending messages to this specific client
    pub sender: UnboundedSender<Message>,
    /// Current state of this connection
    pub state: ConnectionState,
}

/// Connection state tracking
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ConnectionState {
    /// Newly connected, active
    Connected,
    /// Client disconnected
    Disconnected,
    /// Client attempting to reconnect
    Reconnecting,
}

/// Message structure for WebSocket communication
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    /// Message type identifier
    #[serde(rename = "type")]
    pub message_type: String,
    /// Message payload as JSON
    pub payload: serde_json::Value,
    /// Timestamp when message was created
    pub timestamp: chrono::DateTime<chrono::Utc>,
}

impl WebSocketHub {
    /// Create a new WebSocket Hub with specified broadcast capacity
    pub fn new(broadcast_capacity: usize) -> Self {
        let (broadcast_tx, _) = broadcast::channel(broadcast_capacity);

        Self {
            connections: Arc::new(RwLock::new(HashMap::new())),
            broadcast_channel: broadcast_tx,
        }
    }

    /// Get total number of active connections
    pub async fn connection_count(&self) -> usize {
        let connections = self.connections.read().await;
        connections.len()
    }

    /// Accept a new WebSocket connection
    ///
    /// # Arguments
    /// * `user_id` - User ID for this connection
    /// * `sender` - Message sender channel for this client
    ///
    /// # Returns
    /// Unique connection ID for the new connection
    pub async fn accept_connection(
        &self,
        user_id: UserId,
        sender: UnboundedSender<Message>,
    ) -> ConnectionId {
        let connection_id = Uuid::new_v4();
        let connection = ClientConnection {
            user_id,
            connection_id,
            sender,
            state: ConnectionState::Connected,
        };

        let mut connections = self.connections.write().await;
        connections.insert(connection_id, connection);

        connection_id
    }

    /// Remove a connection when client disconnects
    ///
    /// # Arguments
    /// * `connection_id` - ID of connection to remove
    ///
    /// # Returns
    /// true if connection was found and removed, false otherwise
    pub async fn remove_connection(&self, connection_id: ConnectionId) -> bool {
        let mut connections = self.connections.write().await;
        connections.remove(&connection_id).is_some()
    }

    /// Broadcast a message to all connected clients
    ///
    /// # Arguments
    /// * `message` - Message to broadcast
    ///
    /// # Returns
    /// Number of clients that received the message
    pub async fn broadcast(&self, message: Message) -> usize {
        // Send via broadcast channel
        let _receiver_count = self.broadcast_channel.receiver_count();

        // Also send directly to all client senders for guaranteed delivery
        let connections = self.connections.read().await;
        let mut success_count = 0;

        for connection in connections.values() {
            if connection.state == ConnectionState::Connected
                && connection.sender.send(message.clone()).is_ok()
            {
                success_count += 1;
            }
        }

        success_count
    }

    /// Send a message to a specific user
    ///
    /// # Arguments
    /// * `user_id` - Target user ID
    /// * `message` - Message to send
    ///
    /// # Returns
    /// Number of connections for this user that received the message
    pub async fn send_to_user(&self, user_id: UserId, message: Message) -> usize {
        let connections = self.connections.read().await;
        let mut success_count = 0;

        for connection in connections.values() {
            if connection.user_id == user_id
                && connection.state == ConnectionState::Connected
                && connection.sender.send(message.clone()).is_ok()
            {
                success_count += 1;
            }
        }

        success_count
    }

    /// Update connection state
    ///
    /// # Arguments
    /// * `connection_id` - Connection to update
    /// * `new_state` - New state for the connection
    ///
    /// # Returns
    /// true if connection was found and updated, false otherwise
    pub async fn update_connection_state(
        &self,
        connection_id: ConnectionId,
        new_state: ConnectionState,
    ) -> bool {
        let mut connections = self.connections.write().await;

        if let Some(connection) = connections.get_mut(&connection_id) {
            connection.state = new_state;
            true
        } else {
            false
        }
    }

    /// Get a snapshot of all connection IDs
    pub async fn get_connection_ids(&self) -> Vec<ConnectionId> {
        let connections = self.connections.read().await;
        connections.keys().copied().collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::sync::mpsc;

    #[tokio::test]
    async fn test_websocket_hub_creation() {
        let hub = WebSocketHub::new(1000);
        assert_eq!(hub.connection_count().await, 0);
    }

    #[tokio::test]
    async fn test_websocket_connection_accept() {
        let hub = WebSocketHub::new(1000);
        let user_id = Uuid::new_v4();
        let (tx, _rx) = mpsc::unbounded_channel();

        let connection_id = hub.accept_connection(user_id, tx).await;

        assert_eq!(hub.connection_count().await, 1);
        assert!(connection_id != Uuid::nil());
    }

    #[tokio::test]
    async fn test_websocket_connection_cleanup() {
        let hub = WebSocketHub::new(1000);
        let user_id = Uuid::new_v4();
        let (tx, _rx) = mpsc::unbounded_channel();

        let connection_id = hub.accept_connection(user_id, tx).await;
        assert_eq!(hub.connection_count().await, 1);

        let removed = hub.remove_connection(connection_id).await;
        assert!(removed);
        assert_eq!(hub.connection_count().await, 0);
    }

    #[tokio::test]
    async fn test_websocket_remove_nonexistent_connection() {
        let hub = WebSocketHub::new(1000);
        let fake_id = Uuid::new_v4();

        let removed = hub.remove_connection(fake_id).await;
        assert!(!removed);
    }

    #[tokio::test]
    async fn test_websocket_connection_id_unique() {
        let hub = WebSocketHub::new(1000);
        let user_id = Uuid::new_v4();
        let (tx1, _rx1) = mpsc::unbounded_channel();
        let (tx2, _rx2) = mpsc::unbounded_channel();

        let conn1 = hub.accept_connection(user_id, tx1).await;
        let conn2 = hub.accept_connection(user_id, tx2).await;

        assert_ne!(conn1, conn2);
        assert_eq!(hub.connection_count().await, 2);
    }

    #[tokio::test]
    async fn test_websocket_connection_state_transitions() {
        let hub = WebSocketHub::new(1000);
        let user_id = Uuid::new_v4();
        let (tx, _rx) = mpsc::unbounded_channel();

        let connection_id = hub.accept_connection(user_id, tx).await;

        // Test transition to reconnecting
        let updated = hub
            .update_connection_state(connection_id, ConnectionState::Reconnecting)
            .await;
        assert!(updated);

        // Test transition to disconnected
        let updated = hub
            .update_connection_state(connection_id, ConnectionState::Disconnected)
            .await;
        assert!(updated);

        // Test updating non-existent connection
        let fake_id = Uuid::new_v4();
        let updated = hub
            .update_connection_state(fake_id, ConnectionState::Connected)
            .await;
        assert!(!updated);
    }

    #[tokio::test]
    async fn test_websocket_broadcast_all_clients() {
        let hub = WebSocketHub::new(1000);
        let (tx1, mut rx1) = mpsc::unbounded_channel();
        let (tx2, mut rx2) = mpsc::unbounded_channel();

        let user1 = Uuid::new_v4();
        let user2 = Uuid::new_v4();

        hub.accept_connection(user1, tx1).await;
        hub.accept_connection(user2, tx2).await;

        let message = Message {
            message_type: "notification".to_string(),
            payload: serde_json::json!({"content": "test"}),
            timestamp: chrono::Utc::now(),
        };

        let sent_count = hub.broadcast(message.clone()).await;
        assert_eq!(sent_count, 2);

        // Verify both clients received the message
        let msg1 = rx1.recv().await.unwrap();
        assert_eq!(msg1.message_type, "notification");

        let msg2 = rx2.recv().await.unwrap();
        assert_eq!(msg2.message_type, "notification");
    }

    #[tokio::test]
    async fn test_websocket_send_to_user() {
        let hub = WebSocketHub::new(1000);
        let (tx1, mut rx1) = mpsc::unbounded_channel();
        let (tx2, mut rx2) = mpsc::unbounded_channel();

        let user1 = Uuid::new_v4();
        let user2 = Uuid::new_v4();

        hub.accept_connection(user1, tx1).await;
        hub.accept_connection(user2, tx2).await;

        let message = Message {
            message_type: "direct".to_string(),
            payload: serde_json::json!({"content": "for user1 only"}),
            timestamp: chrono::Utc::now(),
        };

        let sent_count = hub.send_to_user(user1, message.clone()).await;
        assert_eq!(sent_count, 1);

        // Only user1 should receive
        let msg = rx1.recv().await.unwrap();
        assert_eq!(msg.message_type, "direct");

        // User2 should not receive
        match tokio::time::timeout(std::time::Duration::from_millis(10), rx2.recv()).await {
            Ok(_) => panic!("User2 should not have received message"),
            Err(_) => {} // Expected timeout
        }
    }

    #[tokio::test]
    async fn test_websocket_send_to_user_multiple_connections() {
        let hub = WebSocketHub::new(1000);
        let user_id = Uuid::new_v4();

        // Same user with 2 connections (e.g., phone + desktop)
        let (tx1, mut rx1) = mpsc::unbounded_channel();
        let (tx2, mut rx2) = mpsc::unbounded_channel();

        hub.accept_connection(user_id, tx1).await;
        hub.accept_connection(user_id, tx2).await;

        let message = Message {
            message_type: "sync".to_string(),
            payload: serde_json::json!({"content": "multi-device"}),
            timestamp: chrono::Utc::now(),
        };

        let sent_count = hub.send_to_user(user_id, message.clone()).await;
        assert_eq!(sent_count, 2);

        // Both connections should receive
        let msg1 = rx1.recv().await.unwrap();
        assert_eq!(msg1.message_type, "sync");

        let msg2 = rx2.recv().await.unwrap();
        assert_eq!(msg2.message_type, "sync");
    }

    #[tokio::test]
    async fn test_websocket_message_serialization() {
        let message = Message {
            message_type: "test".to_string(),
            payload: serde_json::json!({"key": "value", "count": 42}),
            timestamp: chrono::Utc::now(),
        };

        // Test JSON serialization
        let json = serde_json::to_string(&message).unwrap();
        assert!(json.contains("\"type\":\"test\""));
        assert!(json.contains("\"payload\""));

        // Test deserialization
        let deserialized: Message = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.message_type, "test");
    }

    #[tokio::test]
    async fn test_websocket_disconnect_cleanup_no_messages() {
        let hub = WebSocketHub::new(1000);
        let user_id = Uuid::new_v4();
        let (tx, mut rx) = mpsc::unbounded_channel();

        let connection_id = hub.accept_connection(user_id, tx).await;

        // Mark as disconnected
        hub.update_connection_state(connection_id, ConnectionState::Disconnected)
            .await;

        let message = Message {
            message_type: "test".to_string(),
            payload: serde_json::json!({}),
            timestamp: chrono::Utc::now(),
        };

        // Broadcast shouldn't send to disconnected clients
        let sent_count = hub.broadcast(message).await;
        assert_eq!(sent_count, 0);

        // Verify no message received
        match tokio::time::timeout(std::time::Duration::from_millis(10), rx.recv()).await {
            Ok(_) => panic!("Disconnected client should not receive messages"),
            Err(_) => {} // Expected timeout
        }
    }

    #[tokio::test]
    async fn test_connection_state_enum_equality() {
        assert_eq!(ConnectionState::Connected, ConnectionState::Connected);
        assert_eq!(ConnectionState::Disconnected, ConnectionState::Disconnected);
        assert_eq!(ConnectionState::Reconnecting, ConnectionState::Reconnecting);

        assert_ne!(ConnectionState::Connected, ConnectionState::Disconnected);
        assert_ne!(ConnectionState::Connected, ConnectionState::Reconnecting);
        assert_ne!(ConnectionState::Disconnected, ConnectionState::Reconnecting);
    }

    #[tokio::test]
    async fn test_get_connection_ids() {
        let hub = WebSocketHub::new(1000);
        let (tx1, _rx1) = mpsc::unbounded_channel();
        let (tx2, _rx2) = mpsc::unbounded_channel();

        let id1 = hub.accept_connection(Uuid::new_v4(), tx1).await;
        let id2 = hub.accept_connection(Uuid::new_v4(), tx2).await;

        let ids = hub.get_connection_ids().await;
        assert_eq!(ids.len(), 2);
        assert!(ids.contains(&id1));
        assert!(ids.contains(&id2));
    }
}
