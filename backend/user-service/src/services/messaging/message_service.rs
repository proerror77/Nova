// Message Service: Handles message sending, receiving, and history
// Phase 7B Feature 2: T211 - Message Storage Service

use crate::db::messaging::{Message, MessageType, MessagingRepository};
use crate::error::AppError;
use crate::services::messaging::websocket_handler::MessagingWebSocketHandler;
use redis::aio::ConnectionManager;
use sqlx::PgPool;
use std::sync::Arc;
use uuid::Uuid;

pub struct MessageService {
    pool: PgPool,
    ws_handler: Option<Arc<MessagingWebSocketHandler>>,
}

impl MessageService {
    pub fn new(pool: PgPool) -> Self {
        Self {
            pool,
            ws_handler: None,
        }
    }

    /// Create MessageService with Redis pub/sub support for real-time delivery
    pub fn with_websocket(pool: PgPool, redis: Arc<ConnectionManager>) -> Self {
        Self {
            pool,
            ws_handler: Some(Arc::new(MessagingWebSocketHandler::new(redis))),
        }
    }

    /// Send a new message to a conversation
    /// Validates user is a member, stores encrypted content, publishes to Redis Pub/Sub
    pub async fn send_message(
        &self,
        sender_id: Uuid,
        conversation_id: Uuid,
        encrypted_content: String,
        nonce: String,
        message_type: MessageType,
        search_text: Option<String>,
    ) -> Result<Message, AppError> {
        let repo = MessagingRepository::new(&self.pool);

        // Verify sender is a member of the conversation
        let is_member = repo
            .is_conversation_member(conversation_id, sender_id)
            .await?;
        if !is_member {
            return Err(AppError::Authorization(
                "You are not a member of this conversation".to_string(),
            ));
        }

        // Validate encrypted content and nonce
        if encrypted_content.is_empty() {
            return Err(AppError::BadRequest(
                "Message content cannot be empty".to_string(),
            ));
        }

        if nonce.len() != 32 {
            // Base64-encoded 24 bytes = 32 chars
            return Err(AppError::BadRequest("Invalid nonce length".to_string()));
        }

        // Create message
        let message = repo
            .create_message(
                conversation_id,
                sender_id,
                encrypted_content,
                nonce,
                message_type,
            )
            .await?;

        // Optional: index plaintext for searchable conversations (client-provided)
        if let Some(text) = search_text {
            // Only index when conversation privacy allows
            if let Ok(mode) = repo.get_conversation_privacy(conversation_id).await {
                if mode == "search_enabled" {
                    let _ = repo
                        .upsert_message_search(message.id, conversation_id, sender_id, &text)
                        .await;
                }
            }
        }

        // Publish to Redis Pub/Sub for WebSocket delivery (best-effort)
        if let Some(ws_handler) = &self.ws_handler {
            if let Err(e) = ws_handler.publish_message_event(&message).await {
                // Log error but don't fail the entire operation
                // Message is already persisted to database
                tracing::warn!(
                    "Failed to publish message {} to Redis pub/sub: {}. Message saved to DB successfully.",
                    message.id, e
                );
            } else {
                tracing::debug!(
                    "Published message {} to Redis channel conversation:{}:messages",
                    message.id, conversation_id
                );
            }
        } else {
            tracing::warn!(
                "MessageService created without WebSocket support. Message {} will not be delivered in real-time.",
                message.id
            );
        }

        Ok(message)
    }

    /// Get message history for a conversation
    /// Implements cursor-based pagination using message_id
    pub async fn get_message_history(
        &self,
        conversation_id: Uuid,
        user_id: Uuid,
        limit: i64,
        before: Option<Uuid>, // Cursor (message_id)
    ) -> Result<MessageHistoryResponse, AppError> {
        let repo = MessagingRepository::new(&self.pool);

        // Verify user is a member
        let is_member = repo
            .is_conversation_member(conversation_id, user_id)
            .await?;
        if !is_member {
            return Err(AppError::Authorization(
                "You are not a member of this conversation".to_string(),
            ));
        }

        // Fetch messages
        let messages = repo.get_messages(conversation_id, limit, before).await?;

        let has_more = messages.len() == limit as usize;
        let next_cursor = messages.last().map(|m| m.id);

        Ok(MessageHistoryResponse {
            messages,
            has_more,
            next_cursor,
        })
    }

    /// Mark messages as read in a conversation
    /// Updates last_read_message_id and last_read_at for the user
    pub async fn mark_as_read(
        &self,
        conversation_id: Uuid,
        user_id: Uuid,
        message_id: Uuid,
    ) -> Result<(), AppError> {
        let repo = MessagingRepository::new(&self.pool);

        // Verify user is a member
        let is_member = repo
            .is_conversation_member(conversation_id, user_id)
            .await?;
        if !is_member {
            return Err(AppError::Authorization(
                "You are not a member of this conversation".to_string(),
            ));
        }

        // Verify message belongs to the conversation
        let message = repo.get_message(message_id).await?;
        if message.conversation_id != conversation_id {
            return Err(AppError::BadRequest(
                "Message does not belong to this conversation".to_string(),
            ));
        }

        // Update last_read_message_id
        repo.update_last_read(conversation_id, user_id, message_id)
            .await?;

        // Publish read receipt event to Redis Pub/Sub (best-effort)
        if let Some(ws_handler) = &self.ws_handler {
            if let Err(e) = ws_handler
                .publish_read_receipt_event(conversation_id, user_id, message_id)
                .await
            {
                tracing::warn!(
                    "Failed to publish read receipt for conversation {} user {}: {}",
                    conversation_id, user_id, e
                );
            }
        }

        Ok(())
    }

    /// Get unread message count for a user in a conversation
    pub async fn get_unread_count(
        &self,
        conversation_id: Uuid,
        user_id: Uuid,
    ) -> Result<i64, AppError> {
        let repo = MessagingRepository::new(&self.pool);

        let count = repo.get_unread_count(conversation_id, user_id).await?;
        Ok(count)
    }

    // ============================================
    // Future Features (Phase 2)
    // ============================================

    /// Edit a message (future feature)
    pub async fn edit_message(
        &self,
        message_id: Uuid,
        user_id: Uuid,
        new_encrypted_content: String,
        new_nonce: String,
    ) -> Result<Message, AppError> {
        let repo = MessagingRepository::new(&self.pool);

        // Validate input
        if new_encrypted_content.is_empty() {
            return Err(AppError::BadRequest(
                "Message content cannot be empty".to_string(),
            ));
        }
        if new_nonce.len() != 32 {
            return Err(AppError::BadRequest("Invalid nonce length".to_string()));
        }

        // Load and authorize
        let existing = repo.get_message(message_id).await?;
        if existing.sender_id != user_id {
            return Err(AppError::Authorization(
                "You can only edit your own message".to_string(),
            ));
        }
        if existing.deleted_at.is_some() {
            return Err(AppError::BadRequest(
                "Cannot edit a deleted message".to_string(),
            ));
        }

        // Update content
        let updated = repo
            .update_message_content(message_id, new_encrypted_content, new_nonce)
            .await?;

        // Publish message updated event to Redis Pub/Sub (best-effort)
        if let Some(ws_handler) = &self.ws_handler {
            if let Err(e) = ws_handler.publish_message_updated_event(&updated).await {
                tracing::warn!(
                    "Failed to publish message.updated event for message {}: {}",
                    message_id, e
                );
            }
        }

        Ok(updated)
    }

    /// Delete a message (future feature)
    pub async fn delete_message(&self, message_id: Uuid, user_id: Uuid) -> Result<(), AppError> {
        let repo = MessagingRepository::new(&self.pool);

        // Load and authorize
        let existing = repo.get_message(message_id).await?;
        if existing.sender_id != user_id {
            return Err(AppError::Authorization(
                "You can only delete your own message".to_string(),
            ));
        }
        if existing.deleted_at.is_some() {
            // idempotent
            return Ok(());
        }

        let conversation_id = existing.conversation_id;

        // Soft delete
        repo.soft_delete_message(message_id).await?;

        // Publish message deleted event to Redis Pub/Sub (best-effort)
        if let Some(ws_handler) = &self.ws_handler {
            if let Err(e) = ws_handler
                .publish_message_deleted_event(conversation_id, message_id, user_id)
                .await
            {
                tracing::warn!(
                    "Failed to publish message.deleted event for message {}: {}",
                    message_id, e
                );
            }
        }

        Ok(())
    }
}

// ============================================
// DTOs (Data Transfer Objects)
// ============================================

#[derive(Debug, Clone, serde::Serialize)]
pub struct MessageHistoryResponse {
    pub messages: Vec<Message>,
    pub has_more: bool,
    pub next_cursor: Option<Uuid>,
}

#[cfg(test)]
mod tests {
    use super::*;

    // TODO: Unit tests for message service
    // - send_message: validation, permission check
    // - get_message_history: pagination, cursor-based
    // - mark_as_read: update last_read_message_id
    // - get_unread_count: calculation logic

    #[tokio::test]
    async fn test_send_message_requires_membership() {
        // TODO: Implement test
        unimplemented!("T217: Add unit test for send_message");
    }

    #[tokio::test]
    async fn test_message_history_pagination() {
        // TODO: Implement test
        unimplemented!("T217: Add unit test for pagination");
    }
}
