/// WebSocket message types for real-time notifications
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Message types for WebSocket communication
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type")]
pub enum WebSocketMessage {
    /// Client subscribes to user's notifications
    Subscribe { user_id: Uuid },

    /// Client unsubscribes from notifications
    Unsubscribe { user_id: Uuid },

    /// Server pushes a notification to client
    Notification {
        id: Uuid,
        recipient_id: Uuid,
        notification_type: String,
        title: String,
        body: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        image_url: Option<String>,
        priority: String,
        timestamp: i64,
    },

    /// Server acknowledges message receipt
    Ack { message_id: Option<String> },

    /// Heartbeat/ping from server
    Ping { timestamp: i64 },

    /// Client responds to ping
    Pong { timestamp: i64 },

    /// Error message from server
    Error { code: String, message: String },

    /// Connection established confirmation
    Connected { server_id: String, timestamp: i64 },
}

impl WebSocketMessage {
    /// Create a subscription message
    pub fn subscribe(user_id: Uuid) -> Self {
        WebSocketMessage::Subscribe { user_id }
    }

    /// Create an unsubscribe message
    pub fn unsubscribe(user_id: Uuid) -> Self {
        WebSocketMessage::Unsubscribe { user_id }
    }

    /// Create a notification message
    pub fn notification(
        id: Uuid,
        recipient_id: Uuid,
        notification_type: String,
        title: String,
        body: String,
        image_url: Option<String>,
        priority: String,
    ) -> Self {
        WebSocketMessage::Notification {
            id,
            recipient_id,
            notification_type,
            title,
            body,
            image_url,
            priority,
            timestamp: chrono::Utc::now().timestamp(),
        }
    }

    /// Create a ping message
    pub fn ping() -> Self {
        WebSocketMessage::Ping {
            timestamp: chrono::Utc::now().timestamp(),
        }
    }

    /// Create a pong message
    pub fn pong(timestamp: i64) -> Self {
        WebSocketMessage::Pong { timestamp }
    }

    /// Create an error message
    pub fn error(code: String, message: String) -> Self {
        WebSocketMessage::Error { code, message }
    }

    /// Create a connected message
    pub fn connected() -> Self {
        WebSocketMessage::Connected {
            server_id: Uuid::new_v4().to_string(),
            timestamp: chrono::Utc::now().timestamp(),
        }
    }

    /// Serialize to JSON string
    pub fn to_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string(self)
    }

    /// Deserialize from JSON string
    pub fn from_json(json: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(json)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_subscribe_message() {
        let user_id = Uuid::new_v4();
        let msg = WebSocketMessage::subscribe(user_id);
        assert_eq!(msg, WebSocketMessage::Subscribe { user_id });
    }

    #[test]
    fn test_notification_message_serialization() {
        let notification = WebSocketMessage::notification(
            Uuid::new_v4(),
            Uuid::new_v4(),
            "like".to_string(),
            "New Like".to_string(),
            "Someone liked your post".to_string(),
            None,
            "normal".to_string(),
        );

        let json = notification.to_json().unwrap();
        let deserialized = WebSocketMessage::from_json(&json).unwrap();

        // Verify type is preserved
        assert!(matches!(
            deserialized,
            WebSocketMessage::Notification { .. }
        ));
    }

    #[test]
    fn test_ping_pong_messages() {
        let ping = WebSocketMessage::ping();
        assert!(matches!(ping, WebSocketMessage::Ping { .. }));

        let json = ping.to_json().unwrap();
        let deserialized = WebSocketMessage::from_json(&json).unwrap();
        assert!(matches!(deserialized, WebSocketMessage::Ping { .. }));
    }

    #[test]
    fn test_error_message() {
        let error =
            WebSocketMessage::error("INVALID_USER".to_string(), "User ID is invalid".to_string());
        let json = error.to_json().unwrap();
        let deserialized = WebSocketMessage::from_json(&json).unwrap();
        assert!(matches!(deserialized, WebSocketMessage::Error { .. }));
    }

    #[test]
    fn test_connected_message() {
        let msg = WebSocketMessage::connected();
        let json = msg.to_json().unwrap();
        assert!(json.contains("Connected"));
    }
}
