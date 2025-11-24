use actix_web::{get, post, web, HttpMessage, HttpRequest, HttpResponse};
use tracing::{error, warn};

use crate::clients::proto::chat::ConversationType;
use crate::clients::proto::chat::{
    CreateConversationRequest, GetConversationRequest, GetMessagesRequest,
    ListConversationsRequest, SendMessageRequest,
};
use crate::clients::ServiceClients;
use crate::middleware::jwt::AuthenticatedUser;

/// GET /api/v2/chat/conversations
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
        Ok(resp) => HttpResponse::Ok().json(resp),
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
