/// gRPC service implementation for Nova Messaging Service
///
/// Implements all 10 RPC methods from Phase 0 proto definition:
/// - GetMessages, GetMessage, GetConversation, GetConversationMembers
/// - SendMessage, UpdateMessage, DeleteMessage
/// - MarkAsRead, GetUnreadCount, ListConversations

use crate::nova::messaging_service::*;
use crate::state::AppState;
use tonic::{Request, Response, Status};
use sqlx::Row;

/// MessagingServiceImpl - gRPC service implementation
#[derive(Clone)]
pub struct MessagingServiceImpl {
    state: AppState,
}

impl MessagingServiceImpl {
    pub fn new(state: AppState) -> Self {
        Self { state }
    }
}

#[tonic::async_trait]
impl messaging_service_server::MessagingService for MessagingServiceImpl {
    /// GetMessages - Retrieve messages in a conversation with pagination
    async fn get_messages(
        &self,
        request: Request<GetMessagesRequest>,
    ) -> Result<Response<GetMessagesResponse>, Status> {
        let req = request.into_inner();

        // Validation
        if req.conversation_id.is_empty() {
            return Err(Status::invalid_argument("conversation_id is required"));
        }

        let limit = if req.limit <= 0 || req.limit > 100 {
            50 // default
        } else {
            req.limit as i64
        };
        let offset = if req.offset < 0 { 0 } else { req.offset as i64 };

        // Build query with soft delete support
        let deleted_clause = if req.include_deleted {
            "".to_string()
        } else {
            "AND deleted_at IS NULL".to_string()
        };

        // Get total count
        let total_count: i64 = sqlx::query_scalar(
            &format!(
                "SELECT COUNT(*) FROM messages WHERE conversation_id = $1 {}",
                deleted_clause
            ),
        )
        .bind(&req.conversation_id)
        .fetch_one(&self.state.db)
        .await
        .unwrap_or(0);

        // Get messages
        let rows = sqlx::query(
            &format!(
                "SELECT id, conversation_id, sender_id, content, encrypted_content, nonce,
                        encryption_version, created_at, updated_at, deleted_at, version_number
                 FROM messages
                 WHERE conversation_id = $1 {}
                 ORDER BY created_at DESC
                 LIMIT $2 OFFSET $3",
                deleted_clause
            ),
        )
        .bind(&req.conversation_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.state.db)
        .await
        .unwrap_or_default();

        let messages = rows
            .iter()
            .map(|row| Message {
                id: row.get("id"),
                conversation_id: row.get("conversation_id"),
                sender_id: row.get("sender_id"),
                content: row.get("content"),
                encrypted_content: row.get("encrypted_content"),
                nonce: row.get("nonce"),
                encryption_version: row.get("encryption_version"),
                created_at: row.get("created_at"),
                updated_at: row.get("updated_at"),
                deleted_at: row.get("deleted_at"),
                version_number: row.get("version_number"),
            })
            .collect();

        Ok(Response::new(GetMessagesResponse {
            messages,
            total_count: total_count as i32,
        }))
    }

    /// GetMessage - Retrieve a single message by ID
    async fn get_message(
        &self,
        request: Request<GetMessageRequest>,
    ) -> Result<Response<GetMessageResponse>, Status> {
        let req = request.into_inner();

        if req.message_id.is_empty() {
            return Err(Status::invalid_argument("message_id is required"));
        }

        let row = sqlx::query(
            "SELECT id, conversation_id, sender_id, content, encrypted_content, nonce,
                    encryption_version, created_at, updated_at, deleted_at, version_number
             FROM messages WHERE id = $1 AND deleted_at IS NULL",
        )
        .bind(&req.message_id)
        .fetch_optional(&self.state.db)
        .await
        .map_err(|e| Status::internal(format!("Database error: {}", e)))?;

        match row {
            Some(row) => Ok(Response::new(GetMessageResponse {
                message: Some(Message {
                    id: row.get("id"),
                    conversation_id: row.get("conversation_id"),
                    sender_id: row.get("sender_id"),
                    content: row.get("content"),
                    encrypted_content: row.get("encrypted_content"),
                    nonce: row.get("nonce"),
                    encryption_version: row.get("encryption_version"),
                    created_at: row.get("created_at"),
                    updated_at: row.get("updated_at"),
                    deleted_at: row.get("deleted_at"),
                    version_number: row.get("version_number"),
                }),
            })),
            None => Err(Status::not_found("Message not found")),
        }
    }

    /// GetConversation - Retrieve conversation details with unread count
    async fn get_conversation(
        &self,
        request: Request<GetConversationRequest>,
    ) -> Result<Response<GetConversationResponse>, Status> {
        let req = request.into_inner();

        if req.conversation_id.is_empty() {
            return Err(Status::invalid_argument("conversation_id is required"));
        }

        // Get conversation
        let conv_row = sqlx::query(
            "SELECT id, type, name, member_ids, created_at, updated_at
             FROM conversations WHERE id = $1",
        )
        .bind(&req.conversation_id)
        .fetch_optional(&self.state.db)
        .await
        .map_err(|e| Status::internal(format!("Database error: {}", e)))?;

        let conversation = match conv_row {
            Some(row) => Conversation {
                id: row.get("id"),
                type_: row.get("type"),
                name: row.get("name"),
                member_ids: row.get::<Vec<String>, _>("member_ids"),
                created_at: row.get("created_at"),
                updated_at: row.get("updated_at"),
            },
            None => return Err(Status::not_found("Conversation not found")),
        };

        // Get unread count (placeholder - would need user context)
        let unread_count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM message_reads
             WHERE conversation_id = $1 AND is_read = false",
        )
        .bind(&req.conversation_id)
        .fetch_one(&self.state.db)
        .await
        .unwrap_or(0);

        // Get last message
        let last_msg_row = sqlx::query(
            "SELECT id, conversation_id, sender_id, content, encrypted_content, nonce,
                    encryption_version, created_at, updated_at, deleted_at, version_number
             FROM messages WHERE conversation_id = $1 AND deleted_at IS NULL
             ORDER BY created_at DESC LIMIT 1",
        )
        .bind(&req.conversation_id)
        .fetch_optional(&self.state.db)
        .await
        .map_err(|e| Status::internal(format!("Database error: {}", e)))?;

        let last_message = last_msg_row.map(|row| Message {
            id: row.get("id"),
            conversation_id: row.get("conversation_id"),
            sender_id: row.get("sender_id"),
            content: row.get("content"),
            encrypted_content: row.get("encrypted_content"),
            nonce: row.get("nonce"),
            encryption_version: row.get("encryption_version"),
            created_at: row.get("created_at"),
            updated_at: row.get("updated_at"),
            deleted_at: row.get("deleted_at"),
            version_number: row.get("version_number"),
        });

        Ok(Response::new(GetConversationResponse {
            conversation: Some(conversation),
            unread_count: unread_count as i32,
            last_message,
        }))
    }

    /// GetConversationMembers - Retrieve list of member IDs in conversation
    async fn get_conversation_members(
        &self,
        request: Request<GetConversationMembersRequest>,
    ) -> Result<Response<GetConversationMembersResponse>, Status> {
        let req = request.into_inner();

        if req.conversation_id.is_empty() {
            return Err(Status::invalid_argument("conversation_id is required"));
        }

        let row = sqlx::query(
            "SELECT member_ids FROM conversations WHERE id = $1",
        )
        .bind(&req.conversation_id)
        .fetch_optional(&self.state.db)
        .await
        .map_err(|e| Status::internal(format!("Database error: {}", e)))?;

        match row {
            Some(row) => {
                let member_ids: Vec<String> = row.get("member_ids");
                Ok(Response::new(GetConversationMembersResponse {
                    member_ids: member_ids.clone(),
                    total_members: member_ids.len() as i32,
                }))
            }
            None => Err(Status::not_found("Conversation not found")),
        }
    }

    /// SendMessage - Create a new message
    async fn send_message(
        &self,
        request: Request<SendMessageRequest>,
    ) -> Result<Response<SendMessageResponse>, Status> {
        let req = request.into_inner();

        // Validation
        if req.conversation_id.is_empty() {
            return Err(Status::invalid_argument("conversation_id is required"));
        }
        if req.sender_id.is_empty() {
            return Err(Status::invalid_argument("sender_id is required"));
        }
        if req.plaintext.is_empty() && req.encrypted_content.is_empty() {
            return Err(Status::invalid_argument(
                "plaintext or encrypted_content is required",
            ));
        }

        let message_id = uuid::Uuid::new_v4().to_string();
        let now = chrono::Utc::now().to_rfc3339();

        let result = sqlx::query(
            "INSERT INTO messages
             (id, conversation_id, sender_id, content, encrypted_content, nonce,
              encryption_version, created_at, updated_at, deleted_at, version_number)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NULL, 1)
             RETURNING id, conversation_id, sender_id, content, encrypted_content, nonce,
                       encryption_version, created_at, updated_at, deleted_at, version_number",
        )
        .bind(&message_id)
        .bind(&req.conversation_id)
        .bind(&req.sender_id)
        .bind(&req.plaintext)
        .bind(&req.encrypted_content)
        .bind(&req.nonce)
        .bind(req.encryption_version)
        .bind(&now)
        .bind(&now)
        .fetch_one(&self.state.db)
        .await;

        match result {
            Ok(row) => Ok(Response::new(SendMessageResponse {
                message: Some(Message {
                    id: row.get("id"),
                    conversation_id: row.get("conversation_id"),
                    sender_id: row.get("sender_id"),
                    content: row.get("content"),
                    encrypted_content: row.get("encrypted_content"),
                    nonce: row.get("nonce"),
                    encryption_version: row.get("encryption_version"),
                    created_at: row.get("created_at"),
                    updated_at: row.get("updated_at"),
                    deleted_at: row.get("deleted_at"),
                    version_number: row.get("version_number"),
                }),
            })),
            Err(e) => Err(Status::internal(format!("Failed to send message: {}", e))),
        }
    }

    /// UpdateMessage - Update message content with optimistic locking
    async fn update_message(
        &self,
        request: Request<UpdateMessageRequest>,
    ) -> Result<Response<UpdateMessageResponse>, Status> {
        let req = request.into_inner();

        if req.message_id.is_empty() {
            return Err(Status::invalid_argument("message_id is required"));
        }
        if req.new_content.is_empty() && req.new_encrypted_content.is_empty() {
            return Err(Status::invalid_argument(
                "new_content or new_encrypted_content is required",
            ));
        }

        let now = chrono::Utc::now().to_rfc3339();

        let result = sqlx::query(
            "UPDATE messages
             SET content = $1, encrypted_content = $2, nonce = $3,
                 updated_at = $4, version_number = version_number + 1
             WHERE id = $5 AND version_number = $6 AND deleted_at IS NULL
             RETURNING id, conversation_id, sender_id, content, encrypted_content, nonce,
                       encryption_version, created_at, updated_at, deleted_at, version_number",
        )
        .bind(&req.new_content)
        .bind(&req.new_encrypted_content)
        .bind(&req.new_nonce)
        .bind(&now)
        .bind(&req.message_id)
        .bind(req.version_number as i32)
        .fetch_optional(&self.state.db)
        .await
        .map_err(|e| Status::internal(format!("Database error: {}", e)))?;

        match result {
            Some(row) => Ok(Response::new(UpdateMessageResponse {
                message: Some(Message {
                    id: row.get("id"),
                    conversation_id: row.get("conversation_id"),
                    sender_id: row.get("sender_id"),
                    content: row.get("content"),
                    encrypted_content: row.get("encrypted_content"),
                    nonce: row.get("nonce"),
                    encryption_version: row.get("encryption_version"),
                    created_at: row.get("created_at"),
                    updated_at: row.get("updated_at"),
                    deleted_at: row.get("deleted_at"),
                    version_number: row.get("version_number"),
                }),
            })),
            None => Err(Status::not_found(
                "Message not found or version mismatch (optimistic lock conflict)",
            )),
        }
    }

    /// DeleteMessage - Soft delete a message
    async fn delete_message(
        &self,
        request: Request<DeleteMessageRequest>,
    ) -> Result<Response<DeleteMessageResponse>, Status> {
        let req = request.into_inner();

        if req.message_id.is_empty() {
            return Err(Status::invalid_argument("message_id is required"));
        }
        if req.deleted_by_id.is_empty() {
            return Err(Status::invalid_argument("deleted_by_id is required"));
        }

        let now = chrono::Utc::now().to_rfc3339();

        let result = sqlx::query_scalar::<_, String>(
            "UPDATE messages SET deleted_at = $1 WHERE id = $2 AND deleted_at IS NULL
             RETURNING deleted_at",
        )
        .bind(&now)
        .bind(&req.message_id)
        .fetch_optional(&self.state.db)
        .await
        .map_err(|e| Status::internal(format!("Database error: {}", e)))?;

        match result {
            Some(deleted_at) => Ok(Response::new(DeleteMessageResponse {
                message_id: req.message_id,
                deleted_at,
            })),
            None => Err(Status::not_found("Message not found or already deleted")),
        }
    }

    /// MarkAsRead - Mark message(s) as read for a user
    async fn mark_as_read(
        &self,
        request: Request<MarkAsReadRequest>,
    ) -> Result<Response<MarkAsReadResponse>, Status> {
        let req = request.into_inner();

        if req.conversation_id.is_empty() {
            return Err(Status::invalid_argument("conversation_id is required"));
        }
        if req.user_id.is_empty() {
            return Err(Status::invalid_argument("user_id is required"));
        }

        // If message_id provided, mark only that message
        // Otherwise, mark all messages in conversation as read
        if !req.message_id.is_empty() {
            let _ = sqlx::query(
                "INSERT INTO message_reads (user_id, message_id, conversation_id, is_read)
                 VALUES ($1, $2, $3, true)
                 ON CONFLICT (user_id, message_id) DO UPDATE SET is_read = true",
            )
            .bind(&req.user_id)
            .bind(&req.message_id)
            .bind(&req.conversation_id)
            .execute(&self.state.db)
            .await;
        } else {
            let _ = sqlx::query(
                "UPDATE message_reads SET is_read = true
                 WHERE user_id = $1 AND conversation_id = $2",
            )
            .bind(&req.user_id)
            .bind(&req.conversation_id)
            .execute(&self.state.db)
            .await;
        }

        // Get remaining unread count
        let unread_count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM message_reads
             WHERE user_id = $1 AND conversation_id = $2 AND is_read = false",
        )
        .bind(&req.user_id)
        .bind(&req.conversation_id)
        .fetch_one(&self.state.db)
        .await
        .unwrap_or(0);

        Ok(Response::new(MarkAsReadResponse {
            unread_count: unread_count as i32,
        }))
    }

    /// GetUnreadCount - Get unread message count for a conversation
    async fn get_unread_count(
        &self,
        request: Request<GetUnreadCountRequest>,
    ) -> Result<Response<GetUnreadCountResponse>, Status> {
        let req = request.into_inner();

        if req.conversation_id.is_empty() {
            return Err(Status::invalid_argument("conversation_id is required"));
        }
        if req.user_id.is_empty() {
            return Err(Status::invalid_argument("user_id is required"));
        }

        let unread_count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM message_reads
             WHERE user_id = $1 AND conversation_id = $2 AND is_read = false",
        )
        .bind(&req.user_id)
        .bind(&req.conversation_id)
        .fetch_one(&self.state.db)
        .await
        .unwrap_or(0);

        Ok(Response::new(GetUnreadCountResponse {
            unread_count: unread_count as i32,
        }))
    }

    /// ListConversations - List all conversations for a user with pagination
    async fn list_conversations(
        &self,
        request: Request<ListConversationsRequest>,
    ) -> Result<Response<ListConversationsResponse>, Status> {
        let req = request.into_inner();

        if req.user_id.is_empty() {
            return Err(Status::invalid_argument("user_id is required"));
        }

        let limit = if req.limit <= 0 || req.limit > 100 {
            20 // default
        } else {
            req.limit as i64
        };
        let offset = if req.offset < 0 { 0 } else { req.offset as i64 };

        // Get total count of conversations containing this user
        let total_count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM conversations WHERE $1 = ANY(member_ids)",
        )
        .bind(&req.user_id)
        .fetch_one(&self.state.db)
        .await
        .unwrap_or(0);

        // Get conversations
        let rows = sqlx::query(
            "SELECT id, type, name, member_ids, created_at, updated_at
             FROM conversations WHERE $1 = ANY(member_ids)
             ORDER BY updated_at DESC
             LIMIT $2 OFFSET $3",
        )
        .bind(&req.user_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.state.db)
        .await
        .unwrap_or_default();

        let conversations: Vec<Conversation> = rows
            .iter()
            .map(|row| Conversation {
                id: row.get("id"),
                type_: row.get("type"),
                name: row.get("name"),
                member_ids: row.get::<Vec<String>, _>("member_ids"),
                created_at: row.get("created_at"),
                updated_at: row.get("updated_at"),
            })
            .collect();

        // Get unread counts for each conversation
        let unread_counts: Vec<i32> = futures::future::join_all(
            conversations.iter().map(|conv| async {
                let count: i64 = sqlx::query_scalar(
                    "SELECT COUNT(*) FROM message_reads
                     WHERE user_id = $1 AND conversation_id = $2 AND is_read = false",
                )
                .bind(&req.user_id)
                .bind(&conv.id)
                .fetch_one(&self.state.db)
                .await
                .unwrap_or(0);
                count as i32
            }),
        )
        .await;

        Ok(Response::new(ListConversationsResponse {
            conversations,
            unread_counts,
            total_count: total_count as i32,
        }))
    }
}
