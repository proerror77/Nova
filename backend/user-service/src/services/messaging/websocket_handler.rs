//! WebSocket Handler: Real-time message delivery and typing indicators
//!
//! Phase 5 Feature 2: T216 - WebSocket Real-Time Sync for E2E Encrypted Messaging
//!
//! This module provides Redis Pub/Sub integration for real-time message delivery,
//! typing indicators, and read receipts via WebSocket connections.

use crate::error::AppError;
use redis::aio::ConnectionManager;
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use uuid::Uuid;
use chrono::{DateTime, Utc};

/// WebSocket handler for real-time messaging
pub struct MessagingWebSocketHandler {
    redis: Arc<ConnectionManager>,
}

impl MessagingWebSocketHandler {
    pub fn new(redis: Arc<ConnectionManager>) -> Self {
        Self { redis }
    }

    /// Publish a new encrypted message event to Redis Pub/Sub
    ///
    /// WebSocket server subscribed to the conversation channel will receive
    /// this message and broadcast it to all connected clients.
    pub async fn publish_message_event(
        &self,
        message_id: Uuid,
        sender_id: Uuid,
        recipient_id: Uuid,
        encrypted_content: &str,
        nonce: &str,
        sender_public_key: &str,
    ) -> Result<(), AppError> {
        // Use conversation pair for consistent channel naming
        let conversation_pair = Self::make_conversation_pair(sender_id, recipient_id);
        let channel = format!("messaging:conversation:{}:messages", conversation_pair);

        let event = MessageEvent {
            event_type: "message.new".to_string(),
            data: MessageEventData {
                id: message_id,
                sender_id,
                recipient_id,
                encrypted_content: encrypted_content.to_string(),
                nonce: nonce.to_string(),
                sender_public_key: sender_public_key.to_string(),
                timestamp: Utc::now(),
            },
        };

        let payload = serde_json::to_string(&event)
            .map_err(|e| AppError::Internal(format!("Failed to serialize message event: {}", e)))?;

        let mut conn = (*self.redis).clone();
        conn.publish::<_, _, i32>(&channel, &payload)
            .await
            .map_err(|e| AppError::Internal(format!("Redis publish failed: {}", e)))?;

        Ok(())
    }

    /// Publish a typing indicator event to Redis Pub/Sub
    ///
    /// When user is typing, stores state in Redis with 3-second TTL and publishes event.
    /// When user stops typing, removes state and publishes stop event.
    pub async fn publish_typing_event(
        &self,
        sender_id: Uuid,
        recipient_id: Uuid,
        sender_username: &str,
        is_typing: bool,
    ) -> Result<(), AppError> {
        let conversation_pair = Self::make_conversation_pair(sender_id, recipient_id);
        let channel = format!("messaging:conversation:{}:typing", conversation_pair);
        let typing_key = format!("messaging:typing:{}:{}", conversation_pair, sender_id);

        if is_typing {
            // Store typing indicator with 3-second TTL
            let mut conn = (*self.redis).clone();
            conn.set_ex::<_, _, ()>(&typing_key, "1", 3)
                .await
                .map_err(|e| AppError::Internal(format!("Redis SET EX failed: {}", e)))?;
        } else {
            // Remove typing indicator
            let mut conn = (*self.redis).clone();
            let _: () = conn.del(&typing_key)
                .await
                .map_err(|e| AppError::Internal(format!("Redis DEL failed: {}", e)))?;
        }

        // Publish typing event
        let event = TypingEvent {
            event_type: "typing.indicator".to_string(),
            data: TypingEventData {
                sender_id,
                recipient_id,
                sender_username: sender_username.to_string(),
                is_typing,
                timestamp: Utc::now(),
            },
        };

        let payload = serde_json::to_string(&event)
            .map_err(|e| AppError::Internal(format!("Failed to serialize typing event: {}", e)))?;

        let mut conn = (*self.redis).clone();
        conn.publish::<_, _, i32>(&channel, &payload)
            .await
            .map_err(|e| AppError::Internal(format!("Redis publish failed: {}", e)))?;

        Ok(())
    }

    /// Publish a read receipt event to Redis Pub/Sub
    ///
    /// Notifies other user that a message was read.
    pub async fn publish_read_receipt_event(
        &self,
        message_id: Uuid,
        sender_id: Uuid,
        recipient_id: Uuid,
    ) -> Result<(), AppError> {
        let conversation_pair = Self::make_conversation_pair(sender_id, recipient_id);
        let channel = format!("messaging:conversation:{}:read_receipts", conversation_pair);

        let event = ReadReceiptEvent {
            event_type: "message.read".to_string(),
            data: ReadReceiptEventData {
                message_id,
                recipient_id, // The user who read the message
                read_at: Utc::now(),
            },
        };

        let payload = serde_json::to_string(&event)
            .map_err(|e| AppError::Internal(format!("Failed to serialize read receipt event: {}", e)))?;

        let mut conn = (*self.redis).clone();
        conn.publish::<_, _, i32>(&channel, &payload)
            .await
            .map_err(|e| AppError::Internal(format!("Redis publish failed: {}", e)))?;

        Ok(())
    }

    /// Publish a delivered receipt event to Redis Pub/Sub
    ///
    /// Notifies other user that a message was delivered to recipient's device.
    pub async fn publish_delivered_event(
        &self,
        message_id: Uuid,
        sender_id: Uuid,
        recipient_id: Uuid,
    ) -> Result<(), AppError> {
        let conversation_pair = Self::make_conversation_pair(sender_id, recipient_id);
        let channel = format!("messaging:conversation:{}:deliveries", conversation_pair);

        let event = DeliveredEvent {
            event_type: "message.delivered".to_string(),
            data: DeliveredEventData {
                message_id,
                recipient_id, // The user who received the message
                delivered_at: Utc::now(),
            },
        };

        let payload = serde_json::to_string(&event)
            .map_err(|e| AppError::Internal(format!("Failed to serialize delivered event: {}", e)))?;

        let mut conn = (*self.redis).clone();
        conn.publish::<_, _, i32>(&channel, &payload)
            .await
            .map_err(|e| AppError::Internal(format!("Redis publish failed: {}", e)))?;

        Ok(())
    }

    /// Get list of channels a user should subscribe to
    ///
    /// Returns channels for all active conversations the user is part of.
    pub async fn get_user_subscription_channels(&self, _user_id: Uuid) -> Result<Vec<String>, AppError> {
        // TODO (T217): Query user's active conversations from database
        // For now, return empty list - actual implementation will fetch from DB
        Ok(vec![])
    }

    /// Helper: Create deterministic conversation pair identifier
    ///
    /// Ensures the same conversation is identified regardless of participant order.
    fn make_conversation_pair(user_a: Uuid, user_b: Uuid) -> String {
        let (min, max) = if user_a < user_b {
            (user_a, user_b)
        } else {
            (user_b, user_a)
        };
        format!("{}:{}", min, max)
    }
}

// ============================================
// WebSocket Event Structures
// ============================================

/// New message event pushed via WebSocket
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageEvent {
    #[serde(rename = "type")]
    pub event_type: String, // "message.new"
    pub data: MessageEventData,
}

/// Payload for new message event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageEventData {
    pub id: Uuid,
    pub sender_id: Uuid,
    pub recipient_id: Uuid,
    pub encrypted_content: String,
    pub nonce: String,
    pub sender_public_key: String,
    pub timestamp: DateTime<Utc>,
}

/// Typing indicator event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TypingEvent {
    #[serde(rename = "type")]
    pub event_type: String, // "typing.indicator"
    pub data: TypingEventData,
}

/// Payload for typing indicator event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TypingEventData {
    pub sender_id: Uuid,
    pub recipient_id: Uuid,
    pub sender_username: String,
    pub is_typing: bool,
    pub timestamp: DateTime<Utc>,
}

/// Read receipt event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReadReceiptEvent {
    #[serde(rename = "type")]
    pub event_type: String, // "message.read"
    pub data: ReadReceiptEventData,
}

/// Payload for read receipt event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReadReceiptEventData {
    pub message_id: Uuid,
    pub recipient_id: Uuid, // User who read the message
    pub read_at: DateTime<Utc>,
}

/// Delivered event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeliveredEvent {
    #[serde(rename = "type")]
    pub event_type: String, // "message.delivered"
    pub data: DeliveredEventData,
}

/// Payload for delivered event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeliveredEventData {
    pub message_id: Uuid,
    pub recipient_id: Uuid, // User who received the message
    pub delivered_at: DateTime<Utc>,
}

// ============================================
// Client-Side WebSocket Integration Guide
// ============================================

/// CLIENT-SIDE WEBSOCKET GUIDE
///
/// ## 1. Establish WebSocket Connection
///
/// ```swift
/// let url = URL(string: "wss://api.nova.app/ws?token=\(jwtToken)")!
/// let webSocket = URLSessionWebSocketTask(url: url)
/// webSocket.resume()
///
/// // Wait for connection established event
/// receiveMessage { message in
///     if message.type == "connection.established" {
///         print("Connected: \(message.data.connection_id)")
///     }
/// }
/// ```
///
/// ## 2. Receive New Messages
///
/// ```swift
/// receiveMessage { message in
///     if message.type == "message.new" {
///         let encryptedContent = message.data.encrypted_content
///         let nonce = message.data.nonce
///         let senderId = message.data.sender_id
///
///         // Decrypt message
///         let plaintext = decryptMessage(
///             ciphertext: encryptedContent,
///             nonce: nonce,
///             senderId: senderId
///         )
///
///         // Display in UI
///         displayMessage(plaintext, from: senderId)
///     }
/// }
/// ```
///
/// ## 3. Send Typing Indicator
///
/// ```swift
/// // User starts typing
/// let typingEvent = [
///     "type": "typing.start",
///     "data": [
///         "conversation_id": conversationId
///     ]
/// ]
/// webSocket.send(.string(JSONEncoder().encode(typingEvent)))
///
/// // Auto-stop after 3 seconds (or when user stops typing)
/// DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
///     let stopEvent = [
///         "type": "typing.stop",
///         "data": [
///             "conversation_id": conversationId
///         ]
///     ]
///     webSocket.send(.string(JSONEncoder().encode(stopEvent)))
/// }
/// ```
///
/// ## 4. Receive Typing Indicators
///
/// ```swift
/// receiveMessage { message in
///     if message.type == "typing.indicator" {
///         if message.data.is_typing {
///             showTypingIndicator(username: message.data.username)
///         } else {
///             hideTypingIndicator(username: message.data.username)
///         }
///     }
/// }
/// ```
///
/// ## 5. Handle Read Receipts
///
/// ```swift
/// // Mark as read when user opens conversation
/// POST /api/v1/conversations/{id}/read
/// { "message_id": lastMessageId }
///
/// // Receive read receipt event
/// receiveMessage { message in
///     if message.type == "message.read" {
///         updateReadReceipt(
///             conversationId: message.data.conversation_id,
///             userId: message.data.user_id,
///             lastReadMessageId: message.data.last_read_message_id
///         )
///     }
/// }
/// ```
///
/// ## 6. Reconnection Logic
///
/// ```swift
/// webSocket.onClose = { code, reason in
///     print("WebSocket closed: \(code) - \(reason)")
///
///     // Exponential backoff retry
///     var retryDelay = 1.0
///     for attempt in 1...5 {
///         DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
///             reconnectWebSocket()
///         }
///         retryDelay *= 2  // 1s, 2s, 4s, 8s, 16s
///     }
/// }
///
/// func reconnectWebSocket() {
///     webSocket.resume()
///
///     // After reconnection, fetch missed messages
///     fetchMissedMessages(since: lastReceivedMessageId)
/// }
/// ```

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_make_conversation_pair_idempotent() {
        let user_a = Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap();
        let user_b = Uuid::parse_str("550e8400-e29b-41d4-a716-446655440001").unwrap();

        let pair_ab = MessagingWebSocketHandler::make_conversation_pair(user_a, user_b);
        let pair_ba = MessagingWebSocketHandler::make_conversation_pair(user_b, user_a);

        assert_eq!(pair_ab, pair_ba);
        assert!(pair_ab.contains(':'));
    }

    #[test]
    fn test_message_event_serialization() {
        let event = MessageEvent {
            event_type: "message.new".to_string(),
            data: MessageEventData {
                id: Uuid::new_v4(),
                sender_id: Uuid::new_v4(),
                recipient_id: Uuid::new_v4(),
                encrypted_content: "encrypted_payload".to_string(),
                nonce: "nonce_value".to_string(),
                sender_public_key: "public_key".to_string(),
                timestamp: Utc::now(),
            },
        };

        let json = serde_json::to_string(&event).expect("Failed to serialize");
        assert!(json.contains("message.new"));
        assert!(json.contains("encrypted_payload"));

        let deserialized: MessageEvent = serde_json::from_str(&json).expect("Failed to deserialize");
        assert_eq!(deserialized.event_type, "message.new");
    }

    #[test]
    fn test_typing_event_serialization() {
        let event = TypingEvent {
            event_type: "typing.indicator".to_string(),
            data: TypingEventData {
                sender_id: Uuid::new_v4(),
                recipient_id: Uuid::new_v4(),
                sender_username: "alice".to_string(),
                is_typing: true,
                timestamp: Utc::now(),
            },
        };

        let json = serde_json::to_string(&event).expect("Failed to serialize");
        assert!(json.contains("typing.indicator"));
        assert!(json.contains("alice"));
        assert!(json.contains("true"));

        let deserialized: TypingEvent = serde_json::from_str(&json).expect("Failed to deserialize");
        assert_eq!(deserialized.data.sender_username, "alice");
        assert!(deserialized.data.is_typing);
    }

    #[test]
    fn test_read_receipt_event_serialization() {
        let message_id = Uuid::new_v4();
        let event = ReadReceiptEvent {
            event_type: "message.read".to_string(),
            data: ReadReceiptEventData {
                message_id,
                recipient_id: Uuid::new_v4(),
                read_at: Utc::now(),
            },
        };

        let json = serde_json::to_string(&event).expect("Failed to serialize");
        assert!(json.contains("message.read"));
        assert!(json.contains(&message_id.to_string()));

        let deserialized: ReadReceiptEvent = serde_json::from_str(&json).expect("Failed to deserialize");
        assert_eq!(deserialized.data.message_id, message_id);
    }

    #[test]
    fn test_delivered_event_serialization() {
        let message_id = Uuid::new_v4();
        let event = DeliveredEvent {
            event_type: "message.delivered".to_string(),
            data: DeliveredEventData {
                message_id,
                recipient_id: Uuid::new_v4(),
                delivered_at: Utc::now(),
            },
        };

        let json = serde_json::to_string(&event).expect("Failed to serialize");
        assert!(json.contains("message.delivered"));
        assert!(json.contains(&message_id.to_string()));

        let deserialized: DeliveredEvent = serde_json::from_str(&json).expect("Failed to deserialize");
        assert_eq!(deserialized.data.message_id, message_id);
    }

    // Note: Full integration tests for Redis Pub/Sub (publish_message_event, etc.)
    // require a running Redis instance and are covered in integration tests
}
