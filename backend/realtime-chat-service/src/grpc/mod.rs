use crate::nova::realtime_chat::v1::{
    realtime_chat_service_server::RealtimeChatService, Conversation, ConversationType,
    CreateConversationRequest, EndCallRequest, EndCallResponse, ExchangeKeysRequest,
    ExchangeKeysResponse, GetConversationRequest, GetConversationResponse,
    GetMessageHistoryRequest, GetMessageHistoryResponse, GetMessagesRequest, GetMessagesResponse,
    GetPublicKeyRequest, GetPublicKeyResponse, ListConversationsRequest, ListConversationsResponse,
    Message, MessageEvent, MessageType, SendMessageRequest, SendMessageResponse, StartCallRequest,
    StartCallResponse, StreamMessagesRequest, TypingIndicatorRequest, TypingIndicatorResponse,
    UpdateCallStatusRequest, UpdateCallStatusResponse,
};
use crate::services::conversation_service::ConversationService;
use crate::state::AppState;
use tonic::{Request, Response, Status};
use uuid::Uuid;

pub struct RealtimeChatServiceImpl {
    state: AppState,
}

impl RealtimeChatServiceImpl {
    pub fn new(state: AppState) -> Self {
        Self { state }
    }
}

#[tonic::async_trait]
impl RealtimeChatService for RealtimeChatServiceImpl {
    async fn create_conversation(
        &self,
        request: Request<CreateConversationRequest>,
    ) -> Result<Response<Conversation>, Status> {
        let req = request.into_inner();

        if req.participant_ids.len() < 2 {
            return Err(Status::invalid_argument(
                "participant_ids must contain at least two users",
            ));
        }

        let mut participant_ids: Vec<Uuid> = Vec::with_capacity(req.participant_ids.len());
        for pid in &req.participant_ids {
            participant_ids.push(
                Uuid::parse_str(pid)
                    .map_err(|_| Status::invalid_argument("invalid participant id"))?,
            );
        }

        // Use the first participant as the creator (gateway already injects caller)
        let creator_id = *participant_ids
            .first()
            .ok_or_else(|| Status::invalid_argument("missing participant ids"))?;

        let conversation_id = match ConversationType::try_from(req.conversation_type) {
            Ok(ConversationType::Group) => ConversationService::create_group_conversation(
                &self.state.db,
                &self.state.auth_client,
                creator_id,
                req.name.clone(),
                None,
                None,
                participant_ids.clone(),
                None,
            )
            .await
            .map_err(|e| Status::internal(format!("failed to create group: {e}")))?,
            _ => {
                // direct conversation only needs two participants
                let a = participant_ids[0];
                let b = participant_ids[1];
                // P0: Pass graph_client and identity_client for dm_permission check via identity-service SSOT
                ConversationService::create_direct_conversation(
                    &self.state.db,
                    &self.state.auth_client,
                    self.state.graph_client.as_ref(),
                    self.state.identity_client.as_ref(),
                    a,
                    b,
                )
                .await
                .map_err(|e| Status::internal(format!("failed to create direct: {e}")))?
            }
        };

        // Fetch metadata for response
        let client = self.state.db.get().await
            .map_err(|e| Status::internal(format!("db pool error: {e}")))?;

        let meta_row = client
            .query_one(
                "SELECT created_at, updated_at FROM conversations WHERE id = $1",
                &[&conversation_id],
            )
            .await
            .map_err(|e| Status::internal(format!("load conversation meta failed: {e}")))?;

        let created_at: chrono::DateTime<chrono::Utc> = meta_row.get("created_at");
        let updated_at: chrono::DateTime<chrono::Utc> = meta_row.get("updated_at");

        let member_rows = client
            .query(
                "SELECT user_id FROM conversation_members WHERE conversation_id = $1",
                &[&conversation_id],
            )
            .await
            .map_err(|e| Status::internal(format!("load members failed: {e}")))?;

        let members: Vec<Uuid> = member_rows.iter().map(|row| row.get("user_id")).collect();

        let conversation = Conversation {
            id: conversation_id.to_string(),
            name: req.name.clone(),
            conversation_type: req.conversation_type,
            participant_ids: members.into_iter().map(|u| u.to_string()).collect(),
            created_at: created_at.timestamp(),
            updated_at: updated_at.timestamp(),
            last_message: None,
        };

        Ok(Response::new(conversation))
    }

    async fn send_message(
        &self,
        request: Request<SendMessageRequest>,
    ) -> Result<Response<SendMessageResponse>, Status> {
        let req = request.into_inner();

        let conversation_id = Uuid::parse_str(&req.conversation_id)
            .map_err(|_| Status::invalid_argument("invalid conversation id"))?;
        let sender_id = Uuid::parse_str(&req.sender_id)
            .map_err(|_| Status::invalid_argument("invalid sender id"))?;

        // Authorization: sender must be a member
        let is_member = ConversationService::is_member(&self.state.db, conversation_id, sender_id)
            .await
            .map_err(|e| Status::internal(format!("membership check failed: {e}")))?;

        if !is_member {
            return Err(Status::permission_denied(
                "not a member of this conversation",
            ));
        }

        // Basic payload selection: prefer content, fallback to media_url
        let body = if !req.content.is_empty() {
            req.content
        } else if !req.media_url.is_empty() {
            req.media_url
        } else {
            return Err(Status::invalid_argument(
                "content or media_url must be provided",
            ));
        };

        let content_bytes = body.as_bytes();
        let message_id = crate::services::message_service::MessageService::send_message(
            &self.state.db,
            &self.state.encryption,
            conversation_id,
            sender_id,
            content_bytes,
        )
        .await
        .map_err(|e| Status::internal(format!("failed to send message: {e}")))?;

        Ok(Response::new(SendMessageResponse {
            message_id: message_id.to_string(),
            timestamp: chrono::Utc::now().timestamp(),
            status: "sent".to_string(),
        }))
    }

    async fn get_conversation(
        &self,
        request: Request<GetConversationRequest>,
    ) -> Result<Response<GetConversationResponse>, Status> {
        let req = request.into_inner();
        let conversation_id = Uuid::parse_str(&req.conversation_id)
            .map_err(|_| Status::invalid_argument("invalid conversation id"))?;

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("invalid user id"))?;

        // Authorization: requester must be a member
        let is_member = ConversationService::is_member(&self.state.db, conversation_id, user_id)
            .await
            .map_err(|e| Status::internal(format!("membership check failed: {e}")))?;

        if !is_member {
            return Err(Status::permission_denied(
                "not a member of this conversation",
            ));
        }

        let client = self.state.db.get().await
            .map_err(|e| Status::internal(format!("db pool error: {e}")))?;

        let meta_row = client
            .query_opt(
                "SELECT id, conversation_type, name, created_at, updated_at FROM conversations WHERE id = $1",
                &[&conversation_id],
            )
            .await
            .map_err(|e| Status::internal(format!("fetch conversation failed: {e}")))?;

        let row = match meta_row {
            Some(r) => r,
            None => return Err(Status::not_found("conversation not found")),
        };

        let conv_type_str: String = row.get("conversation_type");
        let proto_type = match conv_type_str.as_str() {
            "group" => ConversationType::Group as i32,
            _ => ConversationType::Direct as i32,
        };

        let member_rows = client
            .query(
                "SELECT user_id FROM conversation_members WHERE conversation_id = $1",
                &[&conversation_id],
            )
            .await
            .map_err(|e| Status::internal(format!("load members failed: {e}")))?;

        let members: Vec<Uuid> = member_rows.iter().map(|r| r.get("user_id")).collect();

        let created_at: chrono::DateTime<chrono::Utc> = row.get("created_at");
        let updated_at: chrono::DateTime<chrono::Utc> = row.get("updated_at");
        let name: Option<String> = row.get("name");

        let conversation = Conversation {
            id: conversation_id.to_string(),
            name: name.unwrap_or_default(),
            conversation_type: proto_type,
            participant_ids: members.into_iter().map(|u| u.to_string()).collect(),
            created_at: created_at.timestamp(),
            updated_at: updated_at.timestamp(),
            last_message: None,
        };

        Ok(Response::new(GetConversationResponse {
            conversation: Some(conversation),
        }))
    }

    async fn list_conversations(
        &self,
        request: Request<ListConversationsRequest>,
    ) -> Result<Response<ListConversationsResponse>, Status> {
        let req = request.into_inner();
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("invalid user id"))?;
        let limit = req.limit.clamp(1, 50) as i64;

        let client = self.state.db.get().await
            .map_err(|e| Status::internal(format!("db pool error: {e}")))?;

        let conv_id_rows = client
            .query(
                "SELECT conversation_id FROM conversation_members WHERE user_id = $1 ORDER BY joined_at DESC LIMIT $2",
                &[&user_id, &(limit + 1)],
            )
            .await
            .map_err(|e| Status::internal(format!("fetch conversations failed: {e}")))?;

        let conv_ids: Vec<Uuid> = conv_id_rows.iter().map(|row| row.get("conversation_id")).collect();

        if conv_ids.is_empty() {
            return Ok(Response::new(ListConversationsResponse {
                conversations: vec![],
                next_cursor: String::new(),
                has_more: false,
            }));
        }

        let has_more = conv_ids.len() as i64 > limit;
        let conv_ids: Vec<Uuid> = conv_ids.into_iter().take(limit as usize).collect();

        let rows = client
            .query(
                "SELECT id, name, conversation_type, created_at, updated_at FROM conversations WHERE id = ANY($1::uuid[]) ORDER BY updated_at DESC",
                &[&conv_ids],
            )
            .await
            .map_err(|e| Status::internal(format!("load conversation rows failed: {e}")))?;

        // Load members for all conversations in one go
        let member_rows = client
            .query(
                "SELECT conversation_id, user_id FROM conversation_members WHERE conversation_id = ANY($1::uuid[])",
                &[&conv_ids],
            )
            .await
            .map_err(|e| Status::internal(format!("load conversation members failed: {e}")))?;

        use std::collections::HashMap;
        let mut members_map: HashMap<Uuid, Vec<String>> = HashMap::new();
        for row in member_rows {
            let cid: Uuid = row.get("conversation_id");
            let uid: Uuid = row.get("user_id");
            members_map.entry(cid).or_default().push(uid.to_string());
        }

        let conversations: Vec<Conversation> = rows
            .into_iter()
            .map(|row| {
                let cid: Uuid = row.get("id");
                let conv_type_str: String = row.get("conversation_type");
                let proto_type = match conv_type_str.as_str() {
                    "group" => ConversationType::Group as i32,
                    _ => ConversationType::Direct as i32,
                };

                let created_at: chrono::DateTime<chrono::Utc> = row.get("created_at");
                let updated_at: chrono::DateTime<chrono::Utc> = row.get("updated_at");
                let name: Option<String> = row.get("name");

                Conversation {
                    id: cid.to_string(),
                    name: name.unwrap_or_default(),
                    conversation_type: proto_type,
                    participant_ids: members_map.remove(&cid).unwrap_or_default(),
                    created_at: created_at.timestamp(),
                    updated_at: updated_at.timestamp(),
                    last_message: None,
                }
            })
            .collect();

        Ok(Response::new(ListConversationsResponse {
            conversations,
            next_cursor: String::new(),
            has_more,
        }))
    }

    async fn get_messages(
        &self,
        request: Request<GetMessagesRequest>,
    ) -> Result<Response<GetMessagesResponse>, Status> {
        let req = request.into_inner();
        let conversation_id = Uuid::parse_str(&req.conversation_id)
            .map_err(|_| Status::invalid_argument("invalid conversation id"))?;
        let limit = req.limit.clamp(1, 100) as usize;

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("invalid user id"))?;

        // Authorization: requester must be a member
        let is_member = ConversationService::is_member(&self.state.db, conversation_id, user_id)
            .await
            .map_err(|e| Status::internal(format!("membership check failed: {e}")))?;

        if !is_member {
            return Err(Status::permission_denied(
                "not a member of this conversation",
            ));
        }

        let client = self.state.db.get().await
            .map_err(|e| Status::internal(format!("db pool error: {e}")))?;

        let before_ts = if req.before_message_id.is_empty() {
            None
        } else {
            let mid = Uuid::parse_str(&req.before_message_id)
                .map_err(|_| Status::invalid_argument("invalid before_message_id"))?;

            let ts_row = client
                .query_opt("SELECT created_at FROM messages WHERE id = $1", &[&mid])
                .await
                .map_err(|e| Status::internal(format!("lookup message failed: {e}")))?;

            ts_row.map(|r| r.get::<_, chrono::DateTime<chrono::Utc>>("created_at"))
        };

        let rows = client
            .query(
                "SELECT id, sender_id, content, content_encrypted, content_nonce, encryption_version, created_at, updated_at, message_type, media_url, reply_to_message_id, status FROM messages WHERE conversation_id = $1 AND ($2::timestamptz IS NULL OR created_at < $2) ORDER BY created_at DESC LIMIT $3",
                &[&conversation_id, &before_ts, &((limit + 1) as i64)],
            )
            .await
            .map_err(|e| Status::internal(format!("fetch messages failed: {e}")))?;

        let has_more = rows.len() > limit;
        let rows = rows.into_iter().take(limit).collect::<Vec<_>>();

        let mut messages: Vec<Message> = Vec::with_capacity(rows.len());
        for row in rows {
            let mid: Uuid = row.get("id");
            let sender: Uuid = row.get("sender_id");
            let content: String = row.get("content");
            let content_encrypted: Option<Vec<u8>> = row.get("content_encrypted");
            let content_nonce: Option<Vec<u8>> = row.get("content_nonce");
            let encryption_version: i32 = row.get("encryption_version");
            let created_at: chrono::DateTime<chrono::Utc> = row.get("created_at");
            let updated_at: chrono::DateTime<chrono::Utc> = row.get("updated_at");
            let message_type_str: Option<String> = row.get("message_type");
            let media_url: String = row.get("media_url");
            let reply_to_message_id: String = row.get("reply_to_message_id");
            let status: String = row.get("status");

            let message_type = match message_type_str.as_deref() {
                Some("image") => MessageType::Image as i32,
                Some("video") => MessageType::Video as i32,
                Some("audio") => MessageType::Audio as i32,
                Some("file") => MessageType::File as i32,
                Some("location") => MessageType::Location as i32,
                _ => MessageType::Text as i32,
            };

            // For E2EE messages, encode encrypted content as base64 with nonce prepended
            let encrypted_content =
                if let (Some(ciphertext), Some(nonce)) = (content_encrypted, content_nonce) {
                    use base64::Engine;
                    // Format: base64(nonce || ciphertext) for client to parse
                    let mut combined = nonce;
                    combined.extend(ciphertext);
                    base64::engine::general_purpose::STANDARD.encode(&combined)
                } else {
                    String::new()
                };

            messages.push(Message {
                id: mid.to_string(),
                conversation_id: conversation_id.to_string(),
                sender_id: sender.to_string(),
                content,
                message_type,
                media_url,
                location: None,
                created_at: created_at.timestamp(),
                updated_at: updated_at.timestamp(),
                status: if encryption_version > 0 {
                    "encrypted".into()
                } else {
                    status
                },
                encrypted_content,
                ephemeral_public_key: String::new(),
                reply_to_message_id,
            });
        }

        Ok(Response::new(GetMessagesResponse { messages, has_more }))
    }

    async fn get_message_history(
        &self,
        request: Request<GetMessageHistoryRequest>,
    ) -> Result<Response<GetMessageHistoryResponse>, Status> {
        let _req = request.into_inner();
        // TODO: Implement get_message_history logic
        Err(Status::unimplemented(
            "get_message_history not yet implemented",
        ))
    }

    type StreamMessagesStream =
        tokio_stream::wrappers::ReceiverStream<Result<MessageEvent, Status>>;

    async fn stream_messages(
        &self,
        request: Request<StreamMessagesRequest>,
    ) -> Result<Response<Self::StreamMessagesStream>, Status> {
        let _req = request.into_inner();
        // TODO: Implement stream_messages logic
        Err(Status::unimplemented("stream_messages not yet implemented"))
    }

    async fn exchange_keys(
        &self,
        request: Request<ExchangeKeysRequest>,
    ) -> Result<Response<ExchangeKeysResponse>, Status> {
        let _req = request.into_inner();
        // TODO: Implement exchange_keys logic
        Err(Status::unimplemented("exchange_keys not yet implemented"))
    }

    async fn get_public_key(
        &self,
        request: Request<GetPublicKeyRequest>,
    ) -> Result<Response<GetPublicKeyResponse>, Status> {
        let _req = request.into_inner();
        // TODO: Implement get_public_key logic
        Err(Status::unimplemented("get_public_key not yet implemented"))
    }

    async fn send_typing_indicator(
        &self,
        request: Request<TypingIndicatorRequest>,
    ) -> Result<Response<TypingIndicatorResponse>, Status> {
        let _req = request.into_inner();
        // TODO: Implement send_typing_indicator logic
        Err(Status::unimplemented(
            "send_typing_indicator not yet implemented",
        ))
    }

    async fn start_call(
        &self,
        request: Request<StartCallRequest>,
    ) -> Result<Response<StartCallResponse>, Status> {
        let _req = request.into_inner();
        // TODO: Implement start_call logic
        Err(Status::unimplemented("start_call not yet implemented"))
    }

    async fn end_call(
        &self,
        request: Request<EndCallRequest>,
    ) -> Result<Response<EndCallResponse>, Status> {
        let _req = request.into_inner();
        // TODO: Implement end_call logic
        Err(Status::unimplemented("end_call not yet implemented"))
    }

    async fn update_call_status(
        &self,
        request: Request<UpdateCallStatusRequest>,
    ) -> Result<Response<UpdateCallStatusResponse>, Status> {
        let _req = request.into_inner();
        // TODO: Implement update_call_status logic
        Err(Status::unimplemented(
            "update_call_status not yet implemented",
        ))
    }
}
