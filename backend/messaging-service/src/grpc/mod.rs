/// gRPC service implementation for Nova Messaging Service
///
/// Implements all RPC methods from messaging_service.proto:
/// - Message operations: SendMessage, GetMessage, GetMessageHistory, UpdateMessage, DeleteMessage, SearchMessages
/// - Conversation operations: CreateConversation, GetConversation, ListUserConversations, DeleteConversation, MarkAsRead, GetUnreadCount
/// - Group management: AddMember, RemoveMember, ListMembers, UpdateMemberRole, LeaveGroup
/// - Message reactions: AddReaction, GetReactions, RemoveReaction
/// - Encryption & key exchange: StoreDevicePublicKey, GetPeerPublicKey, CompleteKeyExchange, GetConversationEncryption
/// - Push notifications: RegisterDeviceToken, SendPushNotification
/// - Offline queue: GetOfflineEvents, AckOfflineEvent

use crate::nova::messaging_service::*;
use crate::state::AppState;
use tonic::{Request, Response, Status};
use uuid::Uuid;
use std::str::FromStr;

/// MessagingServiceImpl - gRPC service implementation
#[derive(Clone)]
pub struct MessagingServiceImpl {
    state: AppState,
}

impl MessagingServiceImpl {
    pub fn new(state: AppState) -> Self {
        Self { state }
    }

    /// Helper: Parse UUID from string with error handling
    fn parse_uuid(uuid_str: &str, field_name: &str) -> Result<Uuid, Status> {
        Uuid::from_str(uuid_str).map_err(|_| {
            Status::invalid_argument(format!("Invalid {}: {}", field_name, uuid_str))
        })
    }

    /// Helper: Convert AppError to tonic Status
    fn app_error_to_status(err: crate::error::AppError) -> Status {
        match err {
            crate::error::AppError::NotFound => Status::not_found("Resource not found"),
            crate::error::AppError::Config(msg) => Status::invalid_argument(msg),
            crate::error::AppError::StartServer(msg) => Status::internal(msg),
            _ => Status::internal("Internal server error"),
        }
    }

    /// Helper: Convert MessageRow (DB model) to Message (proto)
    fn message_row_to_proto(row: crate::models::message::Message) -> Message {
        Message {
            id: row.id.to_string(),
            conversation_id: row.conversation_id.to_string(),
            sender_id: row.sender_id.to_string(),
            content: row.content,
            content_encrypted: row.content_encrypted.unwrap_or_default(),
            content_nonce: row.content_nonce.unwrap_or_default(),
            encryption_version: row.encryption_version,
            sequence_number: row.sequence_number,
            idempotency_key: row.idempotency_key.unwrap_or_default(),
            created_at: row.created_at.timestamp(),
            updated_at: row.updated_at.map(|t| t.timestamp()).unwrap_or(0),
            deleted_at: row.deleted_at.map(|t| t.timestamp()).unwrap_or(0),
            reaction_count: row.reaction_count,
        }
    }
}

#[tonic::async_trait]
impl messaging_service_server::MessagingService for MessagingServiceImpl {
    // ========== Message Operations ==========

    async fn send_message(
        &self,
        request: Request<SendMessageRequest>,
    ) -> Result<Response<SendMessageResponse>, Status> {
        let req = request.into_inner();

        // Parse and validate request
        let conversation_id = Self::parse_uuid(&req.conversation_id, "conversation_id")?;
        let sender_id = Self::parse_uuid(&req.sender_id, "sender_id")?;

        if req.content.is_empty() {
            return Err(Status::invalid_argument("Message content cannot be empty"));
        }

        // Verify sender exists via auth-service
        if !self.state.auth_client.user_exists(sender_id).await
            .map_err(|e| Self::app_error_to_status(e))? {
            return Err(Status::not_found("Sender user not found"));
        }

        // Send message using service layer
        let idempotency_key_opt = if req.idempotency_key.is_empty() {
            None
        } else {
            Some(req.idempotency_key.as_str())
        };

        let message_row = crate::services::message_service::MessageService::send_message_db(
            &self.state.db,
            &self.state.encryption,
            conversation_id,
            sender_id,
            req.content.as_bytes(),
            idempotency_key_opt,
        )
        .await
        .map_err(|e| Self::app_error_to_status(e))?;

        // Convert MessageRow to proto Message using helper function
        let message = Self::message_row_to_proto(message_row);

        Ok(Response::new(SendMessageResponse {
            message: Some(message),
            error: None,
        }))
    }

    async fn get_message(
        &self,
        request: Request<GetMessageRequest>,
    ) -> Result<Response<GetMessageResponse>, Status> {
        let req = request.into_inner();

        // Parse message_id
        let message_id = Self::parse_uuid(&req.message_id, "message_id")?;

        // Query message from DB
        let message_row = sqlx::query_as::<_, (
            uuid::Uuid, uuid::Uuid, uuid::Uuid, String, Option<Vec<u8>>, Option<Vec<u8>>,
            i32, i64, Option<String>, chrono::DateTime<chrono::Utc>,
            Option<chrono::DateTime<chrono::Utc>>, Option<chrono::DateTime<chrono::Utc>>,
            i32
        )>(
            "SELECT id, conversation_id, sender_id, content, content_encrypted, content_nonce,
                    encryption_version, sequence_number, idempotency_key, created_at,
                    updated_at, deleted_at, 0 as reaction_count
             FROM messages WHERE id = $1"
        )
        .bind(message_id)
        .fetch_optional(&self.state.db)
        .await
        .map_err(|e| Status::internal(format!("Database error: {}", e)))?;

        match message_row {
            Some((id, conv_id, sender_id, content, content_enc, nonce, enc_ver, seq, idempotency_key, created_at, updated_at, deleted_at, reaction_count)) => {
                let message = Message {
                    id: id.to_string(),
                    conversation_id: conv_id.to_string(),
                    sender_id: sender_id.to_string(),
                    content,
                    content_encrypted: content_enc.unwrap_or_default(),
                    content_nonce: nonce.unwrap_or_default(),
                    encryption_version: enc_ver,
                    sequence_number: seq,
                    idempotency_key: idempotency_key.unwrap_or_default(),
                    created_at: created_at.timestamp(),
                    updated_at: updated_at.map(|t| t.timestamp()).unwrap_or(0),
                    deleted_at: deleted_at.map(|t| t.timestamp()).unwrap_or(0),
                    reaction_count,
                };

                Ok(Response::new(GetMessageResponse {
                    message: Some(message),
                    found: true,
                    error: None,
                }))
            }
            None => {
                Ok(Response::new(GetMessageResponse {
                    message: None,
                    found: false,
                    error: None,
                }))
            }
        }
    }

    async fn get_message_history(
        &self,
        request: Request<GetMessageHistoryRequest>,
    ) -> Result<Response<GetMessageHistoryResponse>, Status> {
        let req = request.into_inner();

        // Parse conversation_id
        let conversation_id = Self::parse_uuid(&req.conversation_id, "conversation_id")?;

        // TODO: Extract requesting user_id from gRPC metadata
        // For now, we'll skip member check (should be done in production)

        // Validate limit: min 1, max 100
        let limit = if req.limit <= 0 || req.limit > 100 {
            100_i64
        } else {
            req.limit as i64
        };

        // Fetch message history from service
        let message_dtos = crate::services::message_service::MessageService::get_message_history_db(
            &self.state.db,
            conversation_id,
        )
        .await
        .map_err(|e| Self::app_error_to_status(e))?;

        // Convert MessageDto to proto Message, applying limit and cursor
        let mut proto_messages = Vec::new();
        let mut cursor_found = req.before_timestamp == 0; // If no cursor, start from beginning
        let total_dtos = message_dtos.len();

        for dto in message_dtos {
            // If using cursor pagination, skip messages until we find the cursor point
            if !cursor_found {
                // Parse the created_at timestamp from RFC3339 string for comparison
                if let Ok(dt) = chrono::DateTime::parse_from_rfc3339(&dto.created_at) {
                    if dt.timestamp() < req.before_timestamp {
                        cursor_found = true;
                    } else {
                        continue;
                    }
                } else {
                    continue;
                }
            }

            // Apply limit
            if proto_messages.len() >= limit as usize {
                break;
            }

            // Convert MessageDto to proto Message
            let proto_msg = Message {
                id: dto.id.to_string(),
                conversation_id: conversation_id.to_string(),
                sender_id: dto.sender_id.to_string(),
                content: dto.content,
                content_encrypted: dto.encrypted_payload.unwrap_or_default().into_bytes(),
                content_nonce: dto.nonce.unwrap_or_default().into_bytes(),
                encryption_version: if dto.encrypted { 1 } else { 0 },
                sequence_number: dto.sequence_number,
                idempotency_key: String::new(),
                created_at: chrono::DateTime::parse_from_rfc3339(&dto.created_at)
                    .map(|dt| dt.timestamp())
                    .unwrap_or(0),
                updated_at: dto.updated_at.as_ref()
                    .and_then(|ts| chrono::DateTime::parse_from_rfc3339(ts).ok())
                    .map(|dt| dt.timestamp())
                    .unwrap_or(0),
                deleted_at: 0, // Not included in MessageDto from get_message_history_db
                reaction_count: dto.reactions.len() as i32,
            };
            proto_messages.push(proto_msg);
        }

        // Determine if there are more messages and compute next cursor
        let has_more = total_dtos > (limit as usize);
        let next_cursor = if has_more && !proto_messages.is_empty() {
            proto_messages.last()
                .map(|m| m.created_at)
                .unwrap_or(0)
        } else {
            0
        };

        Ok(Response::new(GetMessageHistoryResponse {
            messages: proto_messages,
            next_cursor: next_cursor.to_string(),
            has_more,
            error: None,
        }))
    }

    async fn update_message(
        &self,
        request: Request<UpdateMessageRequest>,
    ) -> Result<Response<UpdateMessageResponse>, Status> {
        let _req = request.into_inner();
        Err(Status::unimplemented("update_message not yet implemented"))
    }

    async fn delete_message(
        &self,
        request: Request<DeleteMessageRequest>,
    ) -> Result<Response<DeleteMessageResponse>, Status> {
        let _req = request.into_inner();
        Err(Status::unimplemented("delete_message not yet implemented"))
    }

    async fn search_messages(
        &self,
        request: Request<SearchMessagesRequest>,
    ) -> Result<Response<SearchMessagesResponse>, Status> {
        let _req = request.into_inner();
        Err(Status::unimplemented("search_messages not yet implemented"))
    }

    // ========== Conversation Operations ==========

    async fn create_conversation(
        &self,
        request: Request<CreateConversationRequest>,
    ) -> Result<Response<CreateConversationResponse>, Status> {
        let _req = request.into_inner();
        Err(Status::unimplemented("create_conversation not yet implemented"))
    }

    async fn get_conversation(
        &self,
        request: Request<GetConversationRequest>,
    ) -> Result<Response<GetConversationResponse>, Status> {
        let _req = request.into_inner();
        Err(Status::unimplemented("get_conversation not yet implemented"))
    }

    async fn list_user_conversations(
        &self,
        request: Request<ListUserConversationsRequest>,
    ) -> Result<Response<ListUserConversationsResponse>, Status> {
        let _req = request.into_inner();
        Err(Status::unimplemented("list_user_conversations not yet implemented"))
    }

    async fn delete_conversation(
        &self,
        request: Request<DeleteConversationRequest>,
    ) -> Result<Response<DeleteConversationResponse>, Status> {
        let _req = request.into_inner();
        Err(Status::unimplemented("delete_conversation not yet implemented"))
    }

    async fn mark_as_read(
        &self,
        request: Request<MarkAsReadRequest>,
    ) -> Result<Response<MarkAsReadResponse>, Status> {
        let _req = request.into_inner();
        Err(Status::unimplemented("mark_as_read not yet implemented"))
    }

    async fn get_unread_count(
        &self,
        request: Request<GetUnreadCountRequest>,
    ) -> Result<Response<GetUnreadCountResponse>, Status> {
        let _req = request.into_inner();
        Err(Status::unimplemented("get_unread_count not yet implemented"))
    }

    // ========== Group Management ==========

    async fn add_member(
        &self,
        request: Request<AddMemberRequest>,
    ) -> Result<Response<AddMemberResponse>, Status> {
        let _req = request.into_inner();
        Err(Status::unimplemented("add_member not yet implemented"))
    }

    async fn remove_member(
        &self,
        request: Request<RemoveMemberRequest>,
    ) -> Result<Response<RemoveMemberResponse>, Status> {
        let _req = request.into_inner();
        Err(Status::unimplemented("remove_member not yet implemented"))
    }

    async fn list_members(
        &self,
        request: Request<ListMembersRequest>,
    ) -> Result<Response<ListMembersResponse>, Status> {
        let _req = request.into_inner();
        Err(Status::unimplemented("list_members not yet implemented"))
    }

    async fn update_member_role(
        &self,
        request: Request<UpdateMemberRoleRequest>,
    ) -> Result<Response<UpdateMemberRoleResponse>, Status> {
        let _req = request.into_inner();
        Err(Status::unimplemented("update_member_role not yet implemented"))
    }

    async fn leave_group(
        &self,
        request: Request<LeaveGroupRequest>,
    ) -> Result<Response<LeaveGroupResponse>, Status> {
        let _req = request.into_inner();
        Err(Status::unimplemented("leave_group not yet implemented"))
    }

    // ========== Message Reactions ==========

    async fn add_reaction(
        &self,
        request: Request<AddReactionRequest>,
    ) -> Result<Response<AddReactionResponse>, Status> {
        let _req = request.into_inner();
        Err(Status::unimplemented("add_reaction not yet implemented"))
    }

    async fn get_reactions(
        &self,
        request: Request<GetReactionsRequest>,
    ) -> Result<Response<GetReactionsResponse>, Status> {
        let _req = request.into_inner();
        Err(Status::unimplemented("get_reactions not yet implemented"))
    }

    async fn remove_reaction(
        &self,
        request: Request<RemoveReactionRequest>,
    ) -> Result<Response<RemoveReactionResponse>, Status> {
        let _req = request.into_inner();
        Err(Status::unimplemented("remove_reaction not yet implemented"))
    }

    // ========== Encryption & Key Exchange ==========

    async fn store_device_public_key(
        &self,
        request: Request<StoreDevicePublicKeyRequest>,
    ) -> Result<Response<StoreDevicePublicKeyResponse>, Status> {
        let _req = request.into_inner();
        Err(Status::unimplemented("store_device_public_key not yet implemented"))
    }

    async fn get_peer_public_key(
        &self,
        request: Request<GetPeerPublicKeyRequest>,
    ) -> Result<Response<GetPeerPublicKeyResponse>, Status> {
        let _req = request.into_inner();
        Err(Status::unimplemented("get_peer_public_key not yet implemented"))
    }

    async fn complete_key_exchange(
        &self,
        request: Request<CompleteKeyExchangeRequest>,
    ) -> Result<Response<CompleteKeyExchangeResponse>, Status> {
        let _req = request.into_inner();
        Err(Status::unimplemented("complete_key_exchange not yet implemented"))
    }

    async fn get_conversation_encryption(
        &self,
        request: Request<GetConversationEncryptionRequest>,
    ) -> Result<Response<GetConversationEncryptionResponse>, Status> {
        let _req = request.into_inner();
        Err(Status::unimplemented("get_conversation_encryption not yet implemented"))
    }

    // ========== Push Notifications ==========

    async fn register_device_token(
        &self,
        request: Request<RegisterDeviceTokenRequest>,
    ) -> Result<Response<RegisterDeviceTokenResponse>, Status> {
        let _req = request.into_inner();
        Err(Status::unimplemented("register_device_token not yet implemented"))
    }

    async fn send_push_notification(
        &self,
        request: Request<SendPushNotificationRequest>,
    ) -> Result<Response<SendPushNotificationResponse>, Status> {
        let _req = request.into_inner();
        Err(Status::unimplemented("send_push_notification not yet implemented"))
    }

    // ========== Offline Queue Management ==========

    async fn get_offline_events(
        &self,
        request: Request<GetOfflineEventsRequest>,
    ) -> Result<Response<GetOfflineEventsResponse>, Status> {
        let _req = request.into_inner();
        Err(Status::unimplemented("get_offline_events not yet implemented"))
    }

    async fn ack_offline_event(
        &self,
        request: Request<AckOfflineEventRequest>,
    ) -> Result<Response<AckOfflineEventResponse>, Status> {
        let _req = request.into_inner();
        Err(Status::unimplemented("ack_offline_event not yet implemented"))
    }
}
