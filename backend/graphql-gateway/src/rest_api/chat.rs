use actix_web::{get, post, web, HttpMessage, HttpRequest, HttpResponse};
use chrono::{TimeZone, Utc};
use serde::{Deserialize, Serialize};
use tracing::{error, warn};

use crate::clients::proto::chat::ConversationType;
use crate::clients::proto::chat::{
    CreateConversationRequest, GetConversationRequest, GetMessagesRequest,
    ListConversationsRequest, SendMessageRequest,
};
use crate::clients::ServiceClients;
use crate::middleware::jwt::AuthenticatedUser;

/// GET /api/v2/chat/conversations
/// Returns an array of conversations (iOS-compatible format)
#[get("/api/v2/chat/conversations")]
pub async fn get_conversations(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    query: web::Query<ConversationQuery>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let req = ListConversationsRequest {
        user_id: user_id.clone(),
        limit: query.limit.unwrap_or(20) as i32,
        cursor: query.cursor.clone().unwrap_or_default(),
    };
    match clients
        .call_chat(|| {
            let mut chat = clients.chat_client();
            async move { chat.list_conversations(req).await }
        })
        .await
    {
        Ok(resp) => {
            // Transform gRPC response to REST API format (direct array)
            // Note: call_chat already extracts inner response via into_inner()
            let conversations: Vec<RestConversation> = resp
                .conversations
                .into_iter()
                .map(RestConversation::from)
                .collect();

            HttpResponse::Ok().json(conversations)
        }
        Err(e) => {
            error!("list_conversations failed: {}", e);
            HttpResponse::ServiceUnavailable().finish()
        }
    }
}

/// POST /api/v2/chat/messages
#[post("/api/v2/chat/messages")]
pub async fn send_chat_message(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    payload: web::Json<SendMessageBody>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let mut req: SendMessageRequest = payload.0.clone().into();
    req.sender_id = user_id.clone();

    match clients
        .call_chat(|| {
            let mut chat = clients.chat_client();
            async move { chat.send_message(tonic::Request::new(req)).await }
        })
        .await
    {
        Ok(resp) => HttpResponse::Ok().json(resp),
        Err(e) => {
            warn!(%user_id, "send_message failed: {}", e);
            HttpResponse::ServiceUnavailable().finish()
        }
    }
}

/// GET /api/v2/chat/messages
#[get("/api/v2/chat/messages")]
pub async fn get_messages(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    query: web::Query<GetMessagesQuery>,
) -> HttpResponse {
    if http_req
        .extensions()
        .get::<AuthenticatedUser>()
        .copied()
        .is_none()
    {
        return HttpResponse::Unauthorized().finish();
    }

    let req = GetMessagesRequest {
        conversation_id: query.conversation_id.clone(),
        limit: query.limit.unwrap_or(50) as i32,
        before_message_id: query.before_message_id.clone().unwrap_or_default(),
        user_id: http_req
            .extensions()
            .get::<AuthenticatedUser>()
            .copied()
            .map(|u| u.0.to_string())
            .unwrap_or_default(),
    };
    match clients
        .call_chat(|| {
            let mut chat = clients.chat_client();
            async move { chat.get_messages(req).await }
        })
        .await
    {
        Ok(resp) => HttpResponse::Ok().json(resp),
        Err(e) => {
            error!("get_messages failed: {}", e);
            HttpResponse::ServiceUnavailable().finish()
        }
    }
}

/// GET /api/v2/chat/conversations/{id}
pub async fn get_conversation_by_id(
    http_req: HttpRequest,
    path: web::Path<String>,
    clients: web::Data<ServiceClients>,
) -> HttpResponse {
    let user = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let conversation_id = path.into_inner();
    let req = GetConversationRequest {
        conversation_id,
        user_id: user,
    };

    match clients
        .call_chat(|| {
            let mut chat = clients.chat_client();
            async move { chat.get_conversation(req).await }
        })
        .await
    {
        Ok(resp) => HttpResponse::Ok().json(resp),
        Err(e) => {
            error!("get_conversation failed: {}", e);
            HttpResponse::ServiceUnavailable().finish()
        }
    }
}

/// POST /api/v2/chat/conversations
#[post("/api/v2/chat/conversations")]
pub async fn create_conversation(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    payload: web::Json<CreateConversationBody>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let mut participants = payload.participant_ids.clone();
    if !participants.iter().any(|p| p == &user_id) {
        participants.push(user_id.clone());
    }
    let req = CreateConversationRequest {
        name: payload.name.clone().unwrap_or_default(),
        conversation_type: payload
            .conversation_type
            .unwrap_or(ConversationType::Group as i32),
        participant_ids: participants,
    };
    match clients
        .call_chat(|| {
            let mut chat = clients.chat_client();
            async move { chat.create_conversation(req).await }
        })
        .await
    {
        Ok(resp) => HttpResponse::Ok().json(resp),
        Err(e) => {
            error!("create_conversation failed: {}", e);
            HttpResponse::ServiceUnavailable().finish()
        }
    }
}

#[derive(Debug, serde::Deserialize)]
pub struct ConversationQuery {
    pub limit: Option<u32>,
    pub cursor: Option<String>,
}

#[derive(Debug, serde::Deserialize)]
pub struct GetMessagesQuery {
    pub conversation_id: String,
    pub limit: Option<u32>,
    pub before_message_id: Option<String>,
}

#[derive(Debug, serde::Deserialize)]
pub struct CreateConversationBody {
    pub name: Option<String>,
    pub conversation_type: Option<i32>,
    pub participant_ids: Vec<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, Clone)]
pub struct SendMessageBody {
    pub conversation_id: String,
    pub content: String,
    pub message_type: i32,
    pub media_url: String,
    pub reply_to_message_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sender_id: Option<String>,
}

impl From<SendMessageBody> for SendMessageRequest {
    fn from(body: SendMessageBody) -> Self {
        Self {
            conversation_id: body.conversation_id,
            content: body.content,
            message_type: body.message_type,
            media_url: body.media_url,
            reply_to_message_id: body.reply_to_message_id,
            sender_id: body.sender_id.unwrap_or_default(),
            ..Default::default()
        }
    }
}

// ============================================================================
// REST API Response Models (iOS-compatible)
// ============================================================================

/// REST API response for conversation (matches iOS Conversation model)
#[derive(Debug, Serialize, Deserialize)]
pub struct RestConversation {
    pub id: String,
    #[serde(rename = "type")]
    pub conversation_type: String, // "direct" or "group"
    pub name: Option<String>,
    pub participants: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_message: Option<RestLastMessage>,
    pub created_at: String, // ISO8601
    pub updated_at: String, // ISO8601
    #[serde(skip_serializing_if = "Option::is_none")]
    pub avatar_url: Option<String>,
    #[serde(default)]
    pub unread_count: i32,
}

/// Last message preview (matches iOS LastMessage model)
#[derive(Debug, Serialize, Deserialize)]
pub struct RestLastMessage {
    pub content: String,
    pub sender_id: String,
    pub timestamp: String, // ISO8601
}

/// Helper to convert Unix epoch timestamp (i64 seconds) to ISO8601 string
fn timestamp_to_iso8601(ts: i64) -> String {
    let ts = if ts > 0 { ts } else { Utc::now().timestamp() };

    Utc.timestamp_opt(ts, 0)
        .single()
        .map(|dt| dt.to_rfc3339())
        .unwrap_or_else(|| Utc::now().to_rfc3339())
}

/// Convert gRPC ConversationType enum to string
fn conversation_type_to_string(t: i32) -> String {
    match ConversationType::try_from(t) {
        Ok(ConversationType::Direct) => "direct".to_string(),
        Ok(ConversationType::Group) => "group".to_string(),
        _ => "direct".to_string(), // default to direct
    }
}

/// Convert gRPC Conversation to REST API format
impl From<crate::clients::proto::chat::Conversation> for RestConversation {
    fn from(conv: crate::clients::proto::chat::Conversation) -> Self {
        // Fail-safe: some older rows may have missing/zero timestamps; normalize to now()
        let created_ts = if conv.created_at > 0 {
            conv.created_at
        } else {
            Utc::now().timestamp()
        };
        let updated_ts = if conv.updated_at > 0 {
            conv.updated_at
        } else {
            created_ts
        };

        let last_message = conv.last_message.map(|msg| RestLastMessage {
            content: msg.content,
            sender_id: msg.sender_id,
            timestamp: timestamp_to_iso8601(msg.created_at),
        });

        RestConversation {
            id: conv.id,
            conversation_type: conversation_type_to_string(conv.conversation_type),
            name: if conv.name.is_empty() {
                None
            } else {
                Some(conv.name)
            },
            participants: conv.participant_ids,
            last_message,
            created_at: timestamp_to_iso8601(created_ts),
            updated_at: timestamp_to_iso8601(updated_ts),
            avatar_url: None, // Not present in this proto version
            unread_count: 0,  // Not present in this proto version
        }
    }
}
