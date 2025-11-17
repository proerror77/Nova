use crate::error::AppError;
use crate::middleware::guards::ConversationMember;
use crate::nova::realtime_chat::v2::{
    realtime_chat_service_server::RealtimeChatService, CallStatus as ProtoCallStatus,
    CallType as ProtoCallType, Conversation, ConversationType, EndCallRequest, EndCallResponse,
    ExchangeKeysRequest, ExchangeKeysResponse, GetConversationRequest, GetConversationResponse,
    GetMessageHistoryRequest, GetMessageHistoryResponse, GetPublicKeyRequest, GetPublicKeyResponse,
    Message, MessageEvent, MessageType, SendMessageRequest, SendMessageResponse, StartCallRequest,
    StartCallResponse, StreamMessagesRequest, TypingIndicatorRequest, TypingIndicatorResponse,
    UpdateCallStatusRequest, UpdateCallStatusResponse,
};
use crate::routes::messages::MessageDto;
use crate::services::call_service::CallService;
use crate::services::conversation_service::{ConversationService, ConversationWithMembers};
use crate::services::key_exchange::KeyExchangeService;
use crate::services::message_service::MessageService;
use crate::state::AppState;
use crate::websocket::events::{broadcast_event, WebSocketEvent};
use base64::{engine::general_purpose, Engine as _};
use chrono::{DateTime, Utc};
use sqlx::Row;
use std::{convert::TryFrom, sync::Arc};
use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;
use tonic::{metadata::MetadataMap, Request, Response, Status};
use tracing::error;
use uuid::Uuid;

pub struct RealtimeChatServiceImpl {
    state: AppState,
}

impl RealtimeChatServiceImpl {
    pub fn new(state: AppState) -> Self {
        Self { state }
    }

    fn auth_user(metadata: &MetadataMap, override_id: Option<&str>) -> Result<Uuid, Status> {
        let auth_header = metadata
            .get("authorization")
            .ok_or_else(|| Status::unauthenticated("Missing authorization header"))?;

        let header_str = auth_header
            .to_str()
            .map_err(|_| Status::unauthenticated("Invalid authorization header"))?;

        let token = header_str
            .strip_prefix("Bearer ")
            .ok_or_else(|| Status::unauthenticated("Invalid authorization format"))?;

        let user_id = crypto_core::jwt::get_user_id_from_token(token)
            .map_err(|e| Status::unauthenticated(format!("Invalid token: {e}")))?;

        if let Some(expected) = override_id {
            if let Ok(expected_uuid) = Uuid::parse_str(expected) {
                if expected_uuid != user_id {
                    return Err(Status::permission_denied(
                        "User mismatch between token and request payload",
                    ));
                }
            }
        }

        Ok(user_id)
    }

    fn map_app_error(err: AppError) -> Status {
        match err {
            AppError::Unauthorized => Status::unauthenticated("unauthorized"),
            AppError::Forbidden => Status::permission_denied("forbidden"),
            AppError::NotFound => Status::not_found("not found"),
            AppError::BadRequest(msg) | AppError::Config(msg) => Status::invalid_argument(msg),
            AppError::AlreadyRecalled => Status::failed_precondition("message already recalled"),
            AppError::RecallWindowExpired { .. } | AppError::EditWindowExpired { .. } => {
                Status::failed_precondition(err.to_string())
            }
            AppError::Database(msg)
            | AppError::GrpcClient(msg)
            | AppError::StartServer(msg)
            | AppError::Encryption(msg) => Status::internal(msg),
            _ => Status::internal("internal error"),
        }
    }

    fn parse_uuid_field(value: &str, field: &str) -> Result<Uuid, Status> {
        Uuid::parse_str(value)
            .map_err(|_| Status::invalid_argument(format!("Invalid {field} UUID: {value}")))
    }

    fn convert_message_type(value: Option<&str>) -> MessageType {
        match value.unwrap_or_default() {
            "image" => MessageType::Image,
            "video" => MessageType::Video,
            "audio" => MessageType::Audio,
            "file" => MessageType::File,
            "location" => MessageType::Location,
            "call" => MessageType::Call,
            _ => MessageType::Text,
        }
    }

    fn convert_conversation_type(value: &str) -> ConversationType {
        if value.eq_ignore_ascii_case("group") {
            ConversationType::Group
        } else {
            ConversationType::Direct
        }
    }

    fn convert_message(dto: &MessageDto, conversation_id: Uuid) -> Result<Message, Status> {
        let created_at = DateTime::parse_from_rfc3339(&dto.created_at)
            .map_err(|_| Status::internal("Invalid created_at format"))?
            .with_timezone(&Utc)
            .timestamp();
        let updated_at = dto
            .updated_at
            .as_deref()
            .and_then(|s| DateTime::parse_from_rfc3339(s).ok())
            .map(|dt| dt.timestamp())
            .unwrap_or(created_at);

        Ok(Message {
            id: dto.id.to_string(),
            conversation_id: conversation_id.to_string(),
            sender_id: dto.sender_id.to_string(),
            content: dto.content.clone(),
            message_type: Self::convert_message_type(dto.message_type.as_deref()) as i32,
            media_url: String::new(),
            location: None,
            created_at,
            updated_at,
            status: "delivered".to_string(),
            encrypted_content: dto.encrypted_payload.clone().unwrap_or_default(),
            ephemeral_public_key: String::new(),
            reply_to_message_id: String::new(),
        })
    }

    async fn load_conversation_metadata(
        &self,
        conversation_id: Uuid,
    ) -> Result<(String, String, DateTime<Utc>, DateTime<Utc>), Status> {
        let row = sqlx::query(
            "SELECT COALESCE(name, '') AS name, conversation_type, created_at, updated_at \
             FROM conversations \
             WHERE id = $1",
        )
        .bind(conversation_id)
        .fetch_one(&self.state.db)
        .await
        .map_err(|e| {
            error!(conversation_id=%conversation_id, error=%e, "failed to load conversation metadata");
            Status::internal("Failed to load conversation metadata")
        })?;

        let name: String = row.get("name");
        let conversation_type: String = row.get("conversation_type");
        let created_at: DateTime<Utc> = row.get("created_at");
        let updated_at: DateTime<Utc> = row.get("updated_at");

        Ok((name, conversation_type, created_at, updated_at))
    }

    async fn fetch_last_message(&self, message_id: Uuid) -> Result<Option<Message>, Status> {
        let row = sqlx::query(
            "SELECT id, conversation_id, sender_id, content, message_type, created_at, updated_at \
             FROM messages WHERE id = $1",
        )
        .bind(message_id)
        .fetch_optional(&self.state.db)
        .await
        .map_err(|e| {
            error!(message_id=%message_id, error=%e, "failed to load last message");
            Status::internal("Failed to load last message")
        })?;

        if let Some(row) = row {
            let created_at: DateTime<Utc> = row.get("created_at");
            let updated_at: Option<DateTime<Utc>> = row.try_get("updated_at").ok();
            let message_type_str = row
                .try_get::<Option<String>, _>("message_type")
                .ok()
                .flatten();

            let message = Message {
                id: row.get::<Uuid, _>("id").to_string(),
                conversation_id: row.get::<Uuid, _>("conversation_id").to_string(),
                sender_id: row.get::<Uuid, _>("sender_id").to_string(),
                content: row.get::<String, _>("content"),
                message_type: Self::convert_message_type(message_type_str.as_deref()) as i32,
                media_url: String::new(),
                location: None,
                created_at: created_at.timestamp(),
                updated_at: updated_at
                    .map(|ts| ts.timestamp())
                    .unwrap_or(created_at.timestamp()),
                status: "delivered".into(),
                encrypted_content: String::new(),
                ephemeral_public_key: String::new(),
                reply_to_message_id: String::new(),
            };
            Ok(Some(message))
        } else {
            Ok(None)
        }
    }

    fn key_exchange_service(&self) -> Result<&Arc<KeyExchangeService>, Status> {
        self.state
            .key_exchange_service
            .as_ref()
            .ok_or_else(|| Status::failed_precondition("Key exchange service unavailable"))
    }
}

#[tonic::async_trait]
impl RealtimeChatService for RealtimeChatServiceImpl {
    async fn send_message(
        &self,
        request: Request<SendMessageRequest>,
    ) -> Result<Response<SendMessageResponse>, Status> {
        let user_id = Self::auth_user(request.metadata(), None)?;
        let req = request.into_inner();
        let conversation_id = Self::parse_uuid_field(&req.conversation_id, "conversation_id")?;

        let member = ConversationMember::verify(&self.state.db, user_id, conversation_id)
            .await
            .map_err(Self::map_app_error)?;
        member.can_send().map_err(Self::map_app_error)?;

        let plaintext = if !req.content.is_empty() {
            req.content.into_bytes()
        } else if let Some(location) = req.location {
            serde_json::json!({
                "latitude": location.latitude,
                "longitude": location.longitude,
                "address": location.address
            })
            .to_string()
            .into_bytes()
        } else {
            return Err(Status::invalid_argument(
                "content is required for send_message RPC",
            ));
        };

        let message = MessageService::send_message_db(
            &self.state.db,
            &self.state.encryption,
            conversation_id,
            user_id,
            &plaintext,
            None,
        )
        .await
        .map_err(Self::map_app_error)?;

        let _ = broadcast_event(
            &self.state.registry,
            &self.state.redis,
            conversation_id,
            user_id,
            WebSocketEvent::MessageNew {
                id: message.id,
                sender_id: user_id,
                sequence_number: message.sequence_number,
                conversation_id,
            },
        )
        .await;

        Ok(Response::new(SendMessageResponse {
            message_id: message.id.to_string(),
            timestamp: message.created_at.timestamp(),
            status: "sent".to_string(),
        }))
    }

    async fn get_conversation(
        &self,
        request: Request<GetConversationRequest>,
    ) -> Result<Response<GetConversationResponse>, Status> {
        let user_id = Self::auth_user(request.metadata(), None)?;
        let req = request.into_inner();
        let conversation_id = Self::parse_uuid_field(&req.conversation_id, "conversation_id")?;

        let convo: ConversationWithMembers = ConversationService::get_conversation_with_members(
            &self.state.db,
            conversation_id,
            user_id,
        )
        .await
        .map_err(Self::map_app_error)?;

        let (name, conversation_type, created_at, updated_at) =
            self.load_conversation_metadata(conversation_id).await?;

        let participants = convo
            .members
            .iter()
            .map(|m| m.user_id.to_string())
            .collect();

        let last_message = if let Some(message_id) = convo.last_message_id {
            self.fetch_last_message(message_id).await?
        } else {
            None
        };

        let conversation = Conversation {
            id: conversation_id.to_string(),
            name,
            conversation_type: Self::convert_conversation_type(&conversation_type) as i32,
            participant_ids: participants,
            created_at: created_at.timestamp(),
            updated_at: updated_at.timestamp(),
            last_message,
        };

        Ok(Response::new(GetConversationResponse {
            conversation: Some(conversation),
        }))
    }

    async fn get_message_history(
        &self,
        request: Request<GetMessageHistoryRequest>,
    ) -> Result<Response<GetMessageHistoryResponse>, Status> {
        let user_id = Self::auth_user(request.metadata(), None)?;
        let req = request.into_inner();
        let conversation_id = Self::parse_uuid_field(&req.conversation_id, "conversation_id")?;

        ConversationMember::verify(&self.state.db, user_id, conversation_id)
            .await
            .map_err(Self::map_app_error)?;

        let limit = if req.limit <= 0 { 50 } else { req.limit }.min(200) as i64;

        let messages = MessageService::get_message_history_with_details(
            &self.state.db,
            &self.state.encryption,
            conversation_id,
            user_id,
            limit,
            0,
            false,
        )
        .await
        .map_err(Self::map_app_error)?;

        let proto_messages = messages
            .iter()
            .filter_map(|dto| Self::convert_message(dto, conversation_id).ok())
            .collect::<Vec<_>>();

        let has_more = proto_messages.len() as i64 == limit;

        Ok(Response::new(GetMessageHistoryResponse {
            messages: proto_messages,
            has_more,
        }))
    }

    type StreamMessagesStream = ReceiverStream<Result<MessageEvent, Status>>;

    async fn stream_messages(
        &self,
        request: Request<StreamMessagesRequest>,
    ) -> Result<Response<Self::StreamMessagesStream>, Status> {
        let metadata = request.metadata().clone();
        let req = request.into_inner();
        let user_id = Self::auth_user(&metadata, Some(&req.user_id))?;

        let conversations = ConversationService::list_conversations(&self.state.db, user_id)
            .await
            .map_err(Self::map_app_error)?;

        let (tx, rx) = mpsc::channel(32);
        let db = self.state.db.clone();

        tokio::spawn(async move {
            for conversation in conversations {
                match MessageService::get_message_history_db(&db, conversation.id).await {
                    Ok(history) => {
                        for dto in history {
                            if let Ok(message) = Self::convert_message(&dto, conversation.id) {
                                let event = MessageEvent {
                                    event_type: "message.history".to_string(),
                                    message: Some(message),
                                    typing: None,
                                    conversation_id: conversation.id.to_string(),
                                };

                                if tx.send(Ok(event)).await.is_err() {
                                    return;
                                }
                            }
                        }
                    }
                    Err(err) => {
                        let _ = tx.send(Err(Self::map_app_error(err))).await;
                        return;
                    }
                }
            }
        });

        Ok(Response::new(ReceiverStream::new(rx)))
    }

    async fn exchange_keys(
        &self,
        request: Request<ExchangeKeysRequest>,
    ) -> Result<Response<ExchangeKeysResponse>, Status> {
        let metadata = request.metadata().clone();
        let req = request.into_inner();
        let user_id = Self::auth_user(&metadata, Some(&req.user_id))?;
        let device_id = if req.device_id.is_empty() {
            return Err(Status::invalid_argument("device_id is required"));
        } else {
            req.device_id
        };

        let public_key = general_purpose::STANDARD
            .decode(req.public_key.as_bytes())
            .map_err(|_| Status::invalid_argument("public_key must be base64 encoded"))?;

        if public_key.len() != 32 {
            return Err(Status::invalid_argument("public_key must be 32 bytes"));
        }

        let key_service = self.key_exchange_service()?;
        let private_key_encrypted = format!("encrypted_{}", Uuid::new_v4());

        key_service
            .store_device_key(
                user_id,
                device_id.clone(),
                public_key,
                private_key_encrypted.into_bytes(),
            )
            .await
            .map_err(Self::map_app_error)?;

        Ok(Response::new(ExchangeKeysResponse {
            key_id: format!("{}:{}", user_id, device_id),
            created_at: Utc::now().timestamp(),
        }))
    }

    async fn get_public_key(
        &self,
        request: Request<GetPublicKeyRequest>,
    ) -> Result<Response<GetPublicKeyResponse>, Status> {
        let req = request.into_inner();
        let user_id = Self::parse_uuid_field(&req.user_id, "user_id")?;
        let device_id = if req.device_id.is_empty() {
            return Err(Status::invalid_argument("device_id is required"));
        } else {
            req.device_id
        };

        let key_service = self.key_exchange_service()?;
        let public_key = key_service
            .get_device_public_key(user_id, device_id.clone())
            .await
            .map_err(Self::map_app_error)?
            .ok_or_else(|| Status::not_found("public key not found"))?;

        Ok(Response::new(GetPublicKeyResponse {
            public_key: general_purpose::STANDARD.encode(public_key),
            key_id: format!("{}:{}", user_id, device_id),
            created_at: Utc::now().timestamp(),
        }))
    }

    async fn send_typing_indicator(
        &self,
        request: Request<TypingIndicatorRequest>,
    ) -> Result<Response<TypingIndicatorResponse>, Status> {
        let metadata = request.metadata().clone();
        let req = request.into_inner();
        let user_id = Self::auth_user(&metadata, Some(&req.user_id))?;
        let conversation_id = Self::parse_uuid_field(&req.conversation_id, "conversation_id")?;

        ConversationMember::verify(&self.state.db, user_id, conversation_id)
            .await
            .map_err(Self::map_app_error)?;

        let event = if req.is_typing {
            WebSocketEvent::TypingStarted { conversation_id }
        } else {
            WebSocketEvent::TypingStopped { conversation_id }
        };

        let _ = broadcast_event(
            &self.state.registry,
            &self.state.redis,
            conversation_id,
            user_id,
            event,
        )
        .await;

        Ok(Response::new(TypingIndicatorResponse { success: true }))
    }

    async fn start_call(
        &self,
        request: Request<StartCallRequest>,
    ) -> Result<Response<StartCallResponse>, Status> {
        let metadata = request.metadata().clone();
        let req = request.into_inner();
        let user_id = Self::auth_user(&metadata, Some(&req.initiator_user_id))?;
        let conversation_id = Self::parse_uuid_field(&req.conversation_id, "conversation_id")?;

        let member = ConversationMember::verify(&self.state.db, user_id, conversation_id)
            .await
            .map_err(Self::map_app_error)?;

        let call_type = if member.is_group() { "group" } else { "direct" };
        let max_participants = if member.is_group() { 50 } else { 2 };

        let call_id = CallService::initiate_call(
            &self.state.db,
            conversation_id,
            user_id,
            "",
            call_type,
            max_participants,
        )
        .await
        .map_err(Self::map_app_error)?;

        let _ = broadcast_event(
            &self.state.registry,
            &self.state.redis,
            conversation_id,
            user_id,
            WebSocketEvent::CallInitiated {
                call_id,
                initiator_id: user_id,
                call_type: match ProtoCallType::try_from(req.call_type)
                    .unwrap_or(ProtoCallType::Voice)
                {
                    ProtoCallType::Video => "video".to_string(),
                    _ => "voice".to_string(),
                },
                max_participants,
            },
        )
        .await;

        Ok(Response::new(StartCallResponse {
            call_id: call_id.to_string(),
            started_at: Utc::now().timestamp(),
        }))
    }

    async fn end_call(
        &self,
        request: Request<EndCallRequest>,
    ) -> Result<Response<EndCallResponse>, Status> {
        let metadata = request.metadata().clone();
        let req = request.into_inner();
        let user_id = Self::auth_user(&metadata, Some(&req.user_id))?;
        let call_id = Self::parse_uuid_field(&req.call_id, "call_id")?;

        CallService::end_call(&self.state.db, call_id)
            .await
            .map_err(Self::map_app_error)?;

        let row = sqlx::query(
            "SELECT conversation_id, ended_at, duration_ms FROM call_sessions WHERE id = $1",
        )
        .bind(call_id)
        .fetch_optional(&self.state.db)
        .await
        .map_err(|e| {
            error!(call_id=%call_id, error=%e, "failed to fetch call metadata");
            Status::internal("Failed to fetch call metadata")
        })?;

        if let Some(row) = row {
            let conversation_id: Uuid = row.get("conversation_id");
            let _ = broadcast_event(
                &self.state.registry,
                &self.state.redis,
                conversation_id,
                user_id,
                WebSocketEvent::CallEnded {
                    call_id,
                    ended_by: user_id,
                },
            )
            .await;

            let ended_at: Option<DateTime<Utc>> = row.try_get("ended_at").ok();
            let duration_ms: Option<i32> = row.try_get("duration_ms").ok();

            return Ok(Response::new(EndCallResponse {
                success: true,
                ended_at: ended_at
                    .map(|ts| ts.timestamp())
                    .unwrap_or_else(|| Utc::now().timestamp()),
                duration_seconds: duration_ms.unwrap_or_default() as i64 / 1000,
            }));
        }

        Ok(Response::new(EndCallResponse {
            success: true,
            ended_at: Utc::now().timestamp(),
            duration_seconds: 0,
        }))
    }

    async fn update_call_status(
        &self,
        request: Request<UpdateCallStatusRequest>,
    ) -> Result<Response<UpdateCallStatusResponse>, Status> {
        let metadata = request.metadata().clone();
        let req = request.into_inner();
        let user_id = Self::auth_user(&metadata, Some(&req.user_id))?;
        let call_id = Self::parse_uuid_field(&req.call_id, "call_id")?;

        let call_status = ProtoCallStatus::try_from(req.status).unwrap_or(ProtoCallStatus::Ringing);
        let connection_state = match call_status {
            ProtoCallStatus::Ringing => "connecting",
            ProtoCallStatus::Accepted => "connected",
            ProtoCallStatus::Declined => "failed",
            ProtoCallStatus::Ended => "closed",
            ProtoCallStatus::Missed => "failed",
        };

        let participant_id = sqlx::query_scalar::<_, Uuid>(
            "SELECT id FROM call_participants WHERE call_id = $1 AND user_id = $2 LIMIT 1",
        )
        .bind(call_id)
        .bind(user_id)
        .fetch_optional(&self.state.db)
        .await
        .map_err(|e| {
            error!(call_id=%call_id, error=%e, "failed to find call participant");
            Status::internal("Failed to update participant")
        })?;

        if let Some(participant_id) = participant_id {
            CallService::update_participant_state(&self.state.db, participant_id, connection_state)
                .await
                .map_err(Self::map_app_error)?;
        }

        if matches!(call_status, ProtoCallStatus::Ended) {
            CallService::end_call(&self.state.db, call_id)
                .await
                .map_err(Self::map_app_error)?;
        }

        Ok(Response::new(UpdateCallStatusResponse { success: true }))
    }
}
