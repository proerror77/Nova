/// gRPC service implementation for Nova Messaging Service
///
/// Implements all 10 RPC methods from Phase 0 proto definition:
/// - GetMessages, GetMessage, GetConversation, GetConversationMembers
/// - SendMessage, UpdateMessage, DeleteMessage
/// - MarkAsRead, GetUnreadCount, ListConversations
use crate::nova::messaging_service::*;
use crate::state::AppState;
use sqlx::Row;
use tonic::{Request, Response, Status};

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

        // Get total count - fix: separate SQL statements instead of string concatenation
        let total_count: i64 = if req.include_deleted {
            sqlx::query_scalar("SELECT COUNT(*) FROM messages WHERE conversation_id = $1")
        } else {
            sqlx::query_scalar(
                "SELECT COUNT(*) FROM messages WHERE conversation_id = $1 AND deleted_at IS NULL",
            )
        }
        .bind(&req.conversation_id)
        .fetch_one(&self.state.db)
        .await
        .map_err(|e| {
            tracing::error!(
                error = %e,
                conversation_id = %req.conversation_id,
                "Failed to count messages"
            );
            Status::internal("Failed to retrieve message count")
        })?;

        // Get messages - fix: separate SQL statements instead of string concatenation
        let rows = if req.include_deleted {
            sqlx::query(
                "SELECT id, conversation_id, sender_id, content, encrypted_content, nonce,
                        encryption_version, created_at, updated_at, deleted_at, version_number
                 FROM messages
                 WHERE conversation_id = $1
                 ORDER BY created_at DESC
                 LIMIT $2 OFFSET $3",
            )
        } else {
            sqlx::query(
                "SELECT id, conversation_id, sender_id, content, encrypted_content, nonce,
                        encryption_version, created_at, updated_at, deleted_at, version_number
                 FROM messages
                 WHERE conversation_id = $1 AND deleted_at IS NULL
                 ORDER BY created_at DESC
                 LIMIT $2 OFFSET $3",
            )
        }
        .bind(&req.conversation_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.state.db)
        .await
        .map_err(|e| {
            tracing::error!(
                error = %e,
                conversation_id = %req.conversation_id,
                "Failed to fetch messages"
            );
            Status::internal("Failed to retrieve messages")
        })?;

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
                r#type: row.get("type"),
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
        .map_err(|e| {
            tracing::error!(
                error = %e,
                conversation_id = %req.conversation_id,
                "Failed to get unread count"
            );
            Status::internal("Failed to retrieve unread count")
        })?;

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

        let row = sqlx::query("SELECT member_ids FROM conversations WHERE id = $1")
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

    /// SendMessage - Create a new message with transaction
    /// Fix P1-1: Use transaction to ensure message + conversation update consistency
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

        // Start transaction for atomic message creation + conversation update
        let mut tx = self.state.db.begin().await.map_err(|e| {
            tracing::error!(error = %e, "Failed to begin transaction");
            Status::internal("Database error")
        })?;

        let message_id = uuid::Uuid::new_v4().to_string();
        let now = chrono::Utc::now().to_rfc3339();

        // Insert message in transaction
        let row = sqlx::query(
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
        .fetch_one(&mut *tx)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "Failed to insert message");
            Status::internal("Failed to send message")
        })?;

        // Update conversation updated_at in same transaction
        sqlx::query("UPDATE conversations SET updated_at = $1 WHERE id = $2")
            .bind(&now)
            .bind(&req.conversation_id)
            .execute(&mut *tx)
            .await
            .map_err(|e| {
                tracing::error!(error = %e, "Failed to update conversation");
                Status::internal("Failed to update conversation")
            })?;

        // Commit transaction atomically
        tx.commit().await.map_err(|e| {
            tracing::error!(error = %e, "Failed to commit transaction");
            Status::internal("Database error")
        })?;

        Ok(Response::new(SendMessageResponse {
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
        }))
    }

    /// UpdateMessage - Update message content with optimistic locking and transaction
    /// Fix P1-1: Use transaction to ensure message + conversation update consistency
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

        // Start transaction for atomic message update + conversation update
        let mut tx = self.state.db.begin().await.map_err(|e| {
            tracing::error!(error = %e, "Failed to begin transaction");
            Status::internal("Database error")
        })?;

        let now = chrono::Utc::now().to_rfc3339();

        // Update message with optimistic locking in transaction
        let row = sqlx::query(
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
        .fetch_optional(&mut *tx)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, "Failed to update message");
            Status::internal("Database error")
        })?;

        let updated_row = match row {
            Some(r) => r,
            None => {
                // Rollback will happen automatically when tx is dropped
                return Err(Status::not_found(
                    "Message not found or version mismatch (optimistic lock conflict)",
                ));
            }
        };

        let conversation_id: String = updated_row.get("conversation_id");

        // Update conversation updated_at in same transaction
        sqlx::query("UPDATE conversations SET updated_at = $1 WHERE id = $2")
            .bind(&now)
            .bind(&conversation_id)
            .execute(&mut *tx)
            .await
            .map_err(|e| {
                tracing::error!(error = %e, "Failed to update conversation");
                Status::internal("Failed to update conversation")
            })?;

        // Commit transaction atomically
        tx.commit().await.map_err(|e| {
            tracing::error!(error = %e, "Failed to commit transaction");
            Status::internal("Database error")
        })?;

        Ok(Response::new(UpdateMessageResponse {
            message: Some(Message {
                id: updated_row.get("id"),
                conversation_id: updated_row.get("conversation_id"),
                sender_id: updated_row.get("sender_id"),
                content: updated_row.get("content"),
                encrypted_content: updated_row.get("encrypted_content"),
                nonce: updated_row.get("nonce"),
                encryption_version: updated_row.get("encryption_version"),
                created_at: updated_row.get("created_at"),
                updated_at: updated_row.get("updated_at"),
                deleted_at: updated_row.get("deleted_at"),
                version_number: updated_row.get("version_number"),
            }),
        }))
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
            sqlx::query(
                "INSERT INTO message_reads (user_id, message_id, conversation_id, is_read)
                 VALUES ($1, $2, $3, true)
                 ON CONFLICT (user_id, message_id) DO UPDATE SET is_read = true",
            )
            .bind(&req.user_id)
            .bind(&req.message_id)
            .bind(&req.conversation_id)
            .execute(&self.state.db)
            .await
            .map_err(|e| {
                tracing::error!(
                    error = %e,
                    user_id = %req.user_id,
                    message_id = %req.message_id,
                    "Failed to mark message as read"
                );
                Status::internal("Failed to mark message as read")
            })?;
        } else {
            sqlx::query(
                "UPDATE message_reads SET is_read = true
                 WHERE user_id = $1 AND conversation_id = $2",
            )
            .bind(&req.user_id)
            .bind(&req.conversation_id)
            .execute(&self.state.db)
            .await
            .map_err(|e| {
                tracing::error!(
                    error = %e,
                    user_id = %req.user_id,
                    conversation_id = %req.conversation_id,
                    "Failed to mark conversation as read"
                );
                Status::internal("Failed to mark conversation as read")
            })?;
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
        .map_err(|e| {
            tracing::error!(
                error = %e,
                user_id = %req.user_id,
                conversation_id = %req.conversation_id,
                "Failed to get unread count after marking as read"
            );
            Status::internal("Failed to retrieve unread count")
        })?;

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
        .map_err(|e| {
            tracing::error!(
                error = %e,
                user_id = %req.user_id,
                conversation_id = %req.conversation_id,
                "Failed to get unread count"
            );
            Status::internal("Failed to retrieve unread count")
        })?;

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
        let total_count: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM conversations WHERE $1 = ANY(member_ids)")
                .bind(&req.user_id)
                .fetch_one(&self.state.db)
                .await
                .map_err(|e| {
                    tracing::error!(
                        error = %e,
                        user_id = %req.user_id,
                        "Failed to count conversations"
                    );
                    Status::internal("Failed to count conversations")
                })?;

        // Fix P0-3: Use single query with LEFT JOIN instead of N+1 queries
        // Get conversations with unread counts in a single query
        let rows = sqlx::query(
            "SELECT c.id, c.type, c.name, c.member_ids, c.created_at, c.updated_at,
                    COALESCE(COUNT(mr.id), 0)::bigint as unread_count
             FROM conversations c
             LEFT JOIN message_reads mr ON c.id = mr.conversation_id
                 AND mr.user_id = $1 AND mr.is_read = false
             WHERE $1 = ANY(c.member_ids)
             GROUP BY c.id, c.type, c.name, c.member_ids, c.created_at, c.updated_at
             ORDER BY c.updated_at DESC
             LIMIT $2 OFFSET $3",
        )
        .bind(&req.user_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.state.db)
        .await
        .map_err(|e| {
            tracing::error!(
                error = %e,
                user_id = %req.user_id,
                "Failed to fetch conversations with unread counts"
            );
            Status::internal("Failed to retrieve conversations")
        })?;

        let mut conversations = Vec::new();
        let mut unread_counts = Vec::new();

        for row in rows {
            conversations.push(Conversation {
                id: row.get("id"),
                r#type: row.get("type"),
                name: row.get("name"),
                member_ids: row.get::<Vec<String>, _>("member_ids"),
                created_at: row.get("created_at"),
                updated_at: row.get("updated_at"),
            });
            unread_counts.push(row.get::<i64, _>("unread_count") as i32);
        }

        Ok(Response::new(ListConversationsResponse {
            conversations,
            unread_counts,
            total_count: total_count as i32,
        }))
    }
}
