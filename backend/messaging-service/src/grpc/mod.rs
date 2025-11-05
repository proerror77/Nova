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

        // Construct Message proto from returned data
        let message = crate::messaging_service::Message {
            id: message_row.id.to_string(),
            conversation_id: message_row.conversation_id.to_string(),
            sender_id: message_row.sender_id.to_string(),
            content: message_row.content.clone(),
            content_encrypted: message_row.content_encrypted.unwrap_or_default(),
            content_nonce: message_row.content_nonce.unwrap_or_default(),
            encryption_version: message_row.encryption_version,
            sequence_number: message_row.sequence_number,
            idempotency_key: message_row.idempotency_key.clone().unwrap_or_default(),
            created_at: message_row.created_at.timestamp(),
            updated_at: message_row.updated_at.map(|t| t.timestamp()).unwrap_or(0),
            deleted_at: message_row.deleted_at.map(|t| t.timestamp()).unwrap_or(0),
            reaction_count: 0,
        };

        Ok(Response::new(SendMessageResponse {
            message: Some(message),
            error: None,
        }))
    }

    async fn get_message(
        &self,
        request: Request<GetMessageRequest>,
    ) -> Result<Response<GetMessageResponse>, Status> {
        let _req = request.into_inner();
        Err(Status::unimplemented("get_message not yet implemented"))
    }

    async fn get_message_history(
        &self,
        request: Request<GetMessageHistoryRequest>,
    ) -> Result<Response<GetMessageHistoryResponse>, Status> {
        let _req = request.into_inner();
        Err(Status::unimplemented("get_message_history not yet implemented"))
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
