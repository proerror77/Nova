use actix_web::{get, post, web, HttpMessage, HttpRequest, HttpResponse};
use chrono::{TimeZone, Utc};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use tracing::{error, warn};

use crate::clients::proto::auth::{GetUserProfilesByIdsRequest, UserProfile as AuthUserProfile};
use crate::clients::proto::chat::ConversationType;
use crate::clients::proto::chat::{
    CreateConversationRequest, GetConversationRequest, GetMessagesRequest,
    ListConversationsRequest, SendMessageRequest,
};
use crate::clients::ServiceClients;
use crate::middleware::jwt::AuthenticatedUser;

async fn fetch_user_profiles(
    clients: &ServiceClients,
    user_ids: Vec<String>,
) -> HashMap<String, AuthUserProfile> {
    if user_ids.is_empty() {
        return HashMap::new();
    }

    let mut auth = clients.auth_client();
    let req = tonic::Request::new(GetUserProfilesByIdsRequest { user_ids });

    match auth.get_user_profiles_by_ids(req).await {
        Ok(resp) => resp
            .into_inner()
            .profiles
            .into_iter()
            .map(|p| (p.user_id.clone(), p))
            .collect(),
        Err(e) => {
            warn!("Failed to fetch user profiles for chat enrichment: {}", e);
            HashMap::new()
        }
    }
}

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
            // Batch fetch participant profiles once to populate usernames/avatars.
            let participant_ids: Vec<String> = resp
                .conversations
                .iter()
                .flat_map(|c| c.participant_ids.iter().cloned())
                .collect::<HashSet<_>>()
                .into_iter()
                .collect();
            let profiles = fetch_user_profiles(&clients, participant_ids).await;

            // Transform gRPC response to REST API format (direct array)
            // Note: call_chat already extracts inner response via into_inner()
            let conversations: Vec<RestConversation> = resp
                .conversations
                .into_iter()
                .map(|c| RestConversation::from_proto(c, &profiles, &user_id))
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
        Ok(resp) => {
            // Convert minimal gRPC response into full REST message payload expected by iOS
            // Fail-safe: some older implementations may return 0; normalize to "now"
            let ts = if resp.timestamp > 0 {
                resp.timestamp
            } else {
                Utc::now().timestamp()
            };
            let created_iso = timestamp_to_iso8601(ts);

            let rest = RestMessage {
                id: resp.message_id.clone(),
                conversation_id: payload.conversation_id.clone(),
                sender_id: user_id.clone(),
                content: payload.content.clone(),
                message_type: payload.message_type,
                r#type: message_type_to_string(payload.message_type),
                media_url: payload.media_url.clone(),
                encrypted_content: String::new(),
                reply_to_message_id: payload.reply_to_message_id.clone(),
                status: resp.status.clone(),
                created_at: created_iso.clone(),
                updated_at: created_iso,
            };

            #[derive(Serialize)]
            struct RestSendMessageResponse {
                message: RestMessage,
            }

            HttpResponse::Ok().json(RestSendMessageResponse { message: rest })
        }
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
        Ok(resp) => {
            let messages: Vec<RestMessage> =
                resp.messages.into_iter().map(RestMessage::from).collect();

            #[derive(Serialize)]
            struct RestMessagesResponse {
                messages: Vec<RestMessage>,
                has_more: bool,
            }

            HttpResponse::Ok().json(RestMessagesResponse {
                messages,
                has_more: resp.has_more,
            })
        }
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
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let conversation_id = path.into_inner();
    let req = GetConversationRequest {
        conversation_id,
        user_id: user_id.clone(),
    };

    match clients
        .call_chat(|| {
            let mut chat = clients.chat_client();
            async move { chat.get_conversation(req).await }
        })
        .await
    {
        Ok(resp) => {
            let Some(conv) = resp.conversation else {
                return HttpResponse::NotFound().finish();
            };
            let profiles = fetch_user_profiles(&clients, conv.participant_ids.clone()).await;
            HttpResponse::Ok().json(RestConversation::from_proto(conv, &profiles, &user_id))
        }
        Err(e) => {
            error!("get_conversation failed: {}", e);
            HttpResponse::ServiceUnavailable().finish()
        }
    }
}

/// POST /api/v2/chat/conversations
/// Creates a new conversation and returns iOS-compatible format
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

    // Determine conversation type: direct (1:1) if only 2 participants, otherwise group
    let conv_type = payload.conversation_type.unwrap_or_else(|| {
        if participants.len() == 2 {
            ConversationType::Direct as i32
        } else {
            ConversationType::Group as i32
        }
    });

    let req = CreateConversationRequest {
        name: payload.name.clone().unwrap_or_default(),
        conversation_type: conv_type,
        participant_ids: participants.clone(),
    };
    match clients
        .call_chat(|| {
            let mut chat = clients.chat_client();
            async move { chat.create_conversation(req).await }
        })
        .await
    {
        Ok(resp) => {
            // Transform gRPC Conversation to iOS-compatible format
            // CreateConversation returns Conversation directly (not wrapped)
            let profiles = fetch_user_profiles(&clients, participants).await;
            let rest_conv = RestConversation::from_proto(resp, &profiles, &user_id);
            HttpResponse::Ok().json(rest_conv)
        }
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
    pub members: Vec<RestConversationMember>, // iOS expects members array
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_message: Option<RestLastMessage>,
    pub created_at: String, // ISO8601
    pub updated_at: String, // ISO8601
    #[serde(skip_serializing_if = "Option::is_none")]
    pub avatar_url: Option<String>,
    #[serde(default)]
    pub unread_count: i32,
    #[serde(default)]
    pub is_muted: bool,
    #[serde(default)]
    pub is_archived: bool,
    #[serde(default)]
    pub is_encrypted: bool,
}

/// Member in a conversation (matches iOS ConversationMember model)
#[derive(Debug, Serialize, Deserialize)]
pub struct RestConversationMember {
    pub user_id: String,
    pub username: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub avatar_url: Option<String>,
    pub role: String,      // "owner", "admin", "member"
    pub joined_at: String, // ISO8601
}

/// Last message preview (matches iOS LastMessage model)
#[derive(Debug, Serialize, Deserialize)]
pub struct RestLastMessage {
    pub content: String,
    pub sender_id: String,
    pub timestamp: String, // ISO8601
}

/// REST API message model (matches iOS Message model fields)
#[derive(Debug, Serialize, Deserialize)]
pub struct RestMessage {
    pub id: String,
    pub conversation_id: String,
    pub sender_id: String,
    pub content: String,
    pub message_type: i32,
    #[serde(rename = "type")]
    pub r#type: String,
    pub media_url: String,
    #[serde(skip_serializing_if = "String::is_empty", default)]
    pub encrypted_content: String,
    pub reply_to_message_id: String,
    pub status: String,
    pub created_at: String, // ISO8601
    pub updated_at: String, // ISO8601
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

fn message_type_to_string(t: i32) -> String {
    match t {
        0 => "text".to_string(),
        1 => "image".to_string(),
        2 => "video".to_string(),
        3 => "audio".to_string(),
        4 => "file".to_string(),
        5 => "location".to_string(),
        _ => "text".to_string(),
    }
}

/// Convert gRPC Conversation to REST API format
impl RestConversation {
    fn from_proto(
        conv: crate::clients::proto::chat::Conversation,
        profiles: &HashMap<String, AuthUserProfile>,
        current_user_id: &str,
    ) -> Self {
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

        // Convert participant_ids to members array (iOS format)
        let members: Vec<RestConversationMember> = conv
            .participant_ids
            .iter()
            .enumerate()
            .map(|(idx, user_id)| RestConversationMember {
                user_id: user_id.clone(),
                username: profiles
                    .get(user_id)
                    .map(|p| {
                        p.display_name
                            .clone()
                            .filter(|s| !s.is_empty())
                            .unwrap_or_else(|| p.username.clone())
                    })
                    .unwrap_or_default(),
                avatar_url: profiles.get(user_id).and_then(|p| p.avatar_url.clone()),
                role: if idx == 0 {
                    "owner".to_string()
                } else {
                    "member".to_string()
                },
                joined_at: timestamp_to_iso8601(created_ts),
            })
            .collect();

        // Prefer a meaningful name + avatar for direct conversations when conv.name is empty.
        let (name, avatar_url) = if conversation_type_to_string(conv.conversation_type) == "direct"
            && conv.name.is_empty()
        {
            let other_id = conv
                .participant_ids
                .iter()
                .find(|id| *id != current_user_id)
                .cloned();
            let other_profile = other_id.as_ref().and_then(|id| profiles.get(id));
            let name = other_profile.map(|p| {
                p.display_name
                    .clone()
                    .filter(|s| !s.is_empty())
                    .unwrap_or_else(|| p.username.clone())
            });
            let avatar = other_profile.and_then(|p| p.avatar_url.clone());
            (name, avatar)
        } else {
            (
                if conv.name.is_empty() {
                    None
                } else {
                    Some(conv.name.clone())
                },
                None,
            )
        };

        RestConversation {
            id: conv.id,
            conversation_type: conversation_type_to_string(conv.conversation_type),
            name,
            members,
            last_message,
            created_at: timestamp_to_iso8601(created_ts),
            updated_at: timestamp_to_iso8601(updated_ts),
            avatar_url,      // Derived from the other participant (direct chats)
            unread_count: 0, // Not present in this proto version
            is_muted: false,
            is_archived: false,
            is_encrypted: false,
        }
    }
}

impl From<crate::clients::proto::chat::Message> for RestMessage {
    fn from(msg: crate::clients::proto::chat::Message) -> Self {
        let created_ts = if msg.created_at > 0 {
            msg.created_at
        } else {
            Utc::now().timestamp()
        };
        let updated_ts = if msg.updated_at > 0 {
            msg.updated_at
        } else {
            created_ts
        };

        RestMessage {
            id: msg.id,
            conversation_id: msg.conversation_id,
            sender_id: msg.sender_id,
            content: msg.content,
            message_type: msg.message_type,
            r#type: message_type_to_string(msg.message_type),
            media_url: msg.media_url,
            encrypted_content: msg.encrypted_content,
            reply_to_message_id: msg.reply_to_message_id,
            status: msg.status,
            created_at: timestamp_to_iso8601(created_ts),
            updated_at: timestamp_to_iso8601(updated_ts),
        }
    }
}
