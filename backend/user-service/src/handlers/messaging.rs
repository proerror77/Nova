use actix_web::{error::ResponseError, web, HttpResponse, Responder};
use redis::aio::ConnectionManager;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use uuid::Uuid;

use crate::db::{messaging::*, user_repo};
use crate::middleware::rate_limit::{RateLimitConfig, RateLimiter};
use crate::middleware::UserId;
use crate::services::messaging::{ConversationService, MessageService};
use crate::AppError;
use crate::Config;

// ============================================
// Request/Response DTOs
// ============================================

#[derive(Debug, Deserialize)]
pub struct CreateConversationRequest {
    #[serde(rename = "type")]
    pub conv_type: String, // "direct" | "group"
    pub name: Option<String>,
    pub participant_ids: Vec<Uuid>,
}

#[derive(Debug, Serialize)]
pub struct ConversationMemberDto {
    pub user_id: Uuid,
    pub username: Option<String>,
    pub role: MemberRole,
    pub joined_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Serialize)]
pub struct CreateConversationResponse {
    pub id: Uuid,
    #[serde(rename = "type")]
    pub conversation_type: ConversationType,
    pub name: Option<String>,
    pub created_by: Uuid,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub updated_at: chrono::DateTime<chrono::Utc>,
    pub members: Vec<ConversationMemberDto>,
}

#[derive(Debug, Deserialize)]
pub struct SendMessageRequest {
    pub conversation_id: Uuid,
    pub encrypted_content: String,
    pub nonce: String,        // base64, 32 chars (24 bytes)
    pub message_type: String, // "text" | "system"
    pub search_text: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct MarkReadRequest {
    pub message_id: Uuid,
}

#[derive(Debug, Serialize)]
pub struct SimpleOkResponse {
    pub message: String,
}

// ============================================
// Helpers
// ============================================

fn parse_conversation_type(s: &str) -> Option<ConversationType> {
    match s.to_ascii_lowercase().as_str() {
        "direct" => Some(ConversationType::Direct),
        "group" => Some(ConversationType::Group),
        _ => None,
    }
}

fn parse_message_type(s: &str) -> Option<MessageType> {
    match s.to_ascii_lowercase().as_str() {
        "text" => Some(MessageType::Text),
        "system" => Some(MessageType::System),
        _ => None,
    }
}

// ============================================
// Handlers
// ============================================

/// POST /api/v1/conversations
pub async fn create_conversation(
    pool: web::Data<PgPool>,
    user: UserId,
    req: web::Json<CreateConversationRequest>,
) -> impl Responder {
    let conv_type = match parse_conversation_type(&req.conv_type) {
        Some(t) => t,
        None => {
            return HttpResponse::BadRequest().json(crate::handlers::auth::ErrorResponse {
                error: "Invalid conversation type".to_string(),
                details: Some("type must be 'direct' or 'group'".to_string()),
            });
        }
    };

    let service = ConversationService::new(pool.get_ref().clone());

    let result = service
        .create_conversation(
            user.0,
            conv_type.clone(),
            req.name.clone(),
            req.participant_ids.clone(),
        )
        .await;

    let conversation = match result {
        Ok(c) => c,
        Err(e) => return e.error_response(),
    };

    // Collect members with usernames
    let repo = MessagingRepository::new(pool.get_ref());
    let members = match repo.get_conversation_members(conversation.id).await {
        Ok(m) => m,
        Err(e) => return e.error_response(),
    };

    let mut members_dto = Vec::with_capacity(members.len());
    for m in members {
        let username = match user_repo::find_by_id(pool.get_ref(), m.user_id).await {
            Ok(Some(u)) => Some(u.username),
            Ok(None) => None,
            Err(_) => None,
        };
        members_dto.push(ConversationMemberDto {
            user_id: m.user_id,
            username,
            role: m.role,
            joined_at: m.joined_at,
        });
    }

    HttpResponse::Created().json(CreateConversationResponse {
        id: conversation.id,
        conversation_type: conv_type,
        name: conversation.name,
        created_by: conversation.created_by,
        created_at: conversation.created_at,
        updated_at: conversation.updated_at,
        members: members_dto,
    })
}

/// GET /api/v1/conversations
pub async fn list_conversations(
    pool: web::Data<PgPool>,
    user: UserId,
    query: web::Query<ListConversationsQuery>,
) -> impl Responder {
    use sqlx::Row;

    let limit = query.limit.unwrap_or(20).clamp(1, 100) as i64;
    let offset = query.offset.unwrap_or(0).max(0) as i64;
    let include_archived = query.archived.unwrap_or(false);

    // Total count for pagination (respects archived filter)
    let total_row = sqlx::query(
        r#"
        SELECT COUNT(*) AS total
        FROM conversation_members cm
        JOIN conversations c ON c.id = cm.conversation_id
        WHERE cm.user_id = $1
          AND ($2::bool = TRUE OR cm.is_archived = FALSE)
        "#,
    )
    .bind(user.0)
    .bind(include_archived)
    .fetch_one(pool.get_ref())
    .await;

    let total: i64 = match total_row {
        Ok(r) => r.try_get::<i64, _>("total").unwrap_or(0),
        Err(e) => return AppError::Database(e).error_response(),
    };

    // Single optimized query: last_message via LATERAL, unread_count via function, user settings from cm
    let rows = sqlx::query(
        r#"
        SELECT 
            c.id,
            c.conversation_type,
            c.name,
            c.updated_at,
            cm.is_muted,
            cm.is_archived,
            lm.id               AS last_message_id,
            lm.sender_id        AS last_message_sender_id,
            lm.encrypted_content AS last_message_encrypted_content,
            lm.nonce            AS last_message_nonce,
            lm.created_at       AS last_message_created_at,
            get_unread_count(c.id, $1) AS unread_count
        FROM conversation_members cm
        JOIN conversations c ON c.id = cm.conversation_id
        LEFT JOIN LATERAL (
            SELECT m.id, m.sender_id, m.encrypted_content, m.nonce, m.created_at
            FROM messages m
            WHERE m.conversation_id = c.id
            ORDER BY m.created_at DESC
            LIMIT 1
        ) lm ON TRUE
        WHERE cm.user_id = $1
          AND ($2::bool = TRUE OR cm.is_archived = FALSE)
        ORDER BY c.updated_at DESC
        LIMIT $3 OFFSET $4
        "#,
    )
    .bind(user.0)
    .bind(include_archived)
    .bind(limit)
    .bind(offset)
    .fetch_all(pool.get_ref())
    .await;

    let rows = match rows {
        Ok(r) => r,
        Err(e) => return AppError::Database(e).error_response(),
    };

    let mut items = Vec::with_capacity(rows.len());
    for row in rows {
        let conv_id: Uuid = row.try_get("id").unwrap();
        let conv_type_str: String = row.try_get::<String, _>("conversation_type").unwrap();
        let conv_type = match conv_type_str.as_str() {
            "direct" => "direct",
            _ => "group",
        };
        let name: Option<String> = row.try_get("name").ok();
        let updated_at: chrono::DateTime<chrono::Utc> = row.try_get("updated_at").unwrap();
        let is_muted: bool = row.try_get("is_muted").unwrap_or(false);
        let is_archived: bool = row.try_get("is_archived").unwrap_or(false);
        let unread_count: i64 = row.try_get("unread_count").unwrap_or(0);

        let last_message_id: Option<Uuid> = row.try_get("last_message_id").ok();
        let last_message = if let Some(mid) = last_message_id {
            let sender_id: Uuid = row.try_get("last_message_sender_id").unwrap();
            let encrypted_content: String = row
                .try_get::<String, _>("last_message_encrypted_content")
                .unwrap();
            let nonce: String = row.try_get("last_message_nonce").unwrap();
            let created_at: chrono::DateTime<chrono::Utc> =
                row.try_get("last_message_created_at").unwrap();

            Some(serde_json::json!({
                "id": mid,
                "sender_id": sender_id,
                "encrypted_content": encrypted_content,
                "nonce": nonce,
                "created_at": created_at,
            }))
        } else {
            None
        };

        items.push(serde_json::json!({
            "id": conv_id,
            "type": conv_type,
            "name": name,
            "updated_at": updated_at,
            "last_message": last_message,
            "unread_count": unread_count,
            "is_muted": is_muted,
            "is_archived": is_archived,
        }));
    }

    HttpResponse::Ok().json(serde_json::json!({
        "conversations": items,
        "total": total,
        "limit": limit,
        "offset": offset,
    }))
}

/// GET /api/v1/conversations/{id}
pub async fn get_conversation(
    pool: web::Data<PgPool>,
    user: UserId,
    path: web::Path<Uuid>,
) -> impl Responder {
    let conversation_id = path.into_inner();
    let service = ConversationService::new(pool.get_ref().clone());
    match service.get_conversation(conversation_id, user.0).await {
        Ok(data) => {
            // 组装成员详情（附用户名）
            let mut members = Vec::with_capacity(data.members.len());
            for m in data.members {
                let username = match user_repo::find_by_id(pool.get_ref(), m.user_id).await {
                    Ok(Some(u)) => u.username,
                    _ => "".to_string(),
                };
                members.push(serde_json::json!({
                    "user_id": m.user_id,
                    "username": username,
                    "role": match m.role { MemberRole::Owner => "owner", MemberRole::Admin => "admin", MemberRole::Member => "member" },
                    "joined_at": m.joined_at,
                }));
            }
            HttpResponse::Ok().json(serde_json::json!({
                "id": data.conversation.id,
                "type": match data.conversation.conversation_type { ConversationType::Direct => "direct", ConversationType::Group => "group" },
                "name": data.conversation.name,
                "created_by": data.conversation.created_by,
                "created_at": data.conversation.created_at,
                "updated_at": data.conversation.updated_at,
                "members": members,
            }))
        }
        Err(e) => e.error_response(),
    }
}

/// PATCH /api/v1/conversations/{id}/settings
pub async fn update_conversation_settings(
    pool: web::Data<PgPool>,
    user: UserId,
    path: web::Path<Uuid>,
    body: web::Json<UpdateSettingsRequest>,
) -> impl Responder {
    let conversation_id = path.into_inner();
    let service = ConversationService::new(pool.get_ref().clone());
    let mut resp = serde_json::Map::new();

    if body.is_muted.is_some() || body.is_archived.is_some() {
        match service
            .update_member_settings(conversation_id, user.0, body.is_muted, body.is_archived)
            .await
        {
            Ok(member) => {
                resp.insert("is_muted".into(), serde_json::json!(member.is_muted));
                resp.insert("is_archived".into(), serde_json::json!(member.is_archived));
            }
            Err(e) => return e.error_response(),
        }
    }

    if let Some(mode) = &body.privacy_mode {
        match service
            .update_privacy_mode(conversation_id, user.0, mode.clone())
            .await
        {
            Ok(()) => {
                resp.insert("privacy_mode".into(), serde_json::json!(mode));
            }
            Err(e) => return e.error_response(),
        }
    }

    HttpResponse::Ok().json(serde_json::Value::Object(resp))
}

/// POST /api/v1/conversations/{id}/members
pub async fn add_conversation_members(
    pool: web::Data<PgPool>,
    user: UserId,
    path: web::Path<Uuid>,
    body: web::Json<AddMembersRequest>,
) -> impl Responder {
    let conversation_id = path.into_inner();
    // Handler-level pre-checks to avoid bypass and return precise errors earlier
    let repo = MessagingRepository::new(pool.get_ref());

    // Must be group conversation
    let conversation = match repo.get_conversation(conversation_id).await {
        Ok(c) => c,
        Err(e) => return e.error_response(),
    };
    if conversation.conversation_type != ConversationType::Group {
        return AppError::BadRequest("Cannot add members to direct conversations".to_string())
            .error_response();
    }

    // Requester must be owner or admin
    let requester_member = match repo.get_conversation_member(conversation_id, user.0).await {
        Ok(m) => m,
        Err(_) => {
            return AppError::Authorization("You are not a member of this conversation".to_string())
                .error_response()
        }
    };
    if requester_member.role != MemberRole::Owner && requester_member.role != MemberRole::Admin {
        return AppError::Authorization("Only owners and admins can add members".to_string())
            .error_response();
    }

    // Basic input validation
    if body.user_ids.is_empty() {
        return AppError::BadRequest("user_ids cannot be empty".to_string()).error_response();
    }

    let service = ConversationService::new(pool.get_ref().clone());
    match service
        .add_members(conversation_id, user.0, body.user_ids.clone())
        .await
    {
        Ok(members) => {
            let added: Vec<_> = members
                .into_iter()
                .map(|m| serde_json::json!({
                    "user_id": m.user_id,
                    "role": match m.role { MemberRole::Owner => "owner", MemberRole::Admin => "admin", MemberRole::Member => "member" },
                    "joined_at": m.joined_at,
                }))
                .collect();
            HttpResponse::Ok().json(serde_json::json!({ "added_members": added }))
        }
        Err(e) => e.error_response(),
    }
}

/// DELETE /api/v1/conversations/{id}/members/{user_id}
pub async fn remove_conversation_member(
    pool: web::Data<PgPool>,
    user: UserId,
    path: web::Path<(Uuid, Uuid)>,
) -> impl Responder {
    let (conversation_id, target_user_id) = path.into_inner();
    let service = ConversationService::new(pool.get_ref().clone());
    match service
        .remove_member(conversation_id, user.0, target_user_id)
        .await
    {
        Ok(()) => HttpResponse::NoContent().finish(),
        Err(e) => e.error_response(),
    }
}

#[derive(Debug, Deserialize)]
pub struct ListConversationsQuery {
    pub limit: Option<usize>,
    pub offset: Option<usize>,
    pub archived: Option<bool>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateSettingsRequest {
    pub is_muted: Option<bool>,
    pub is_archived: Option<bool>,
    pub privacy_mode: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct AddMembersRequest {
    pub user_ids: Vec<Uuid>,
}

/// GET /api/v1/conversations/{id}/messages
pub async fn get_message_history(
    pool: web::Data<PgPool>,
    user: UserId,
    path: web::Path<Uuid>,
    query: web::Query<MessageHistoryQuery>,
) -> impl Responder {
    let conversation_id = path.into_inner();
    let limit = query.limit.unwrap_or(50).clamp(1, 100);
    let before = query.before;

    let service = MessageService::new(pool.get_ref().clone());
    match service
        .get_message_history(conversation_id, user.0, limit, before)
        .await
    {
        Ok(res) => HttpResponse::Ok().json(res),
        Err(e) => e.error_response(),
    }
}

#[derive(Debug, Deserialize)]
pub struct MessageHistoryQuery {
    pub limit: Option<i64>,
    pub before: Option<Uuid>,
}

/// POST /api/v1/messages
pub async fn send_message(
    pool: web::Data<PgPool>,
    user: UserId,
    redis: web::Data<ConnectionManager>,
    config: web::Data<Config>,
    req: web::Json<SendMessageRequest>,
) -> impl Responder {
    // Rate limit per user+conversation (overrides via env)
    let send_max: u32 = std::env::var("MSG_SEND_MAX_REQUESTS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(config.rate_limit.max_requests);
    let send_window: u64 = std::env::var("MSG_SEND_WINDOW_SECS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(config.rate_limit.window_secs);
    let limiter = RateLimiter::new(
        redis.get_ref().clone(),
        RateLimitConfig {
            max_requests: send_max,
            window_seconds: send_window,
        },
    );
    let rl_key = format!("msg:send:{}:{}", user.0, req.conversation_id);
    if limiter.is_rate_limited(&rl_key).await.unwrap_or(false) {
        return crate::error::AppError::RateLimitExceeded.error_response();
    }
    let msg_type = match parse_message_type(&req.message_type) {
        Some(t) => t,
        None => {
            return HttpResponse::BadRequest().json(crate::handlers::auth::ErrorResponse {
                error: "Invalid message type".to_string(),
                details: Some("message_type must be 'text' or 'system'".to_string()),
            });
        }
    };

    // Create MessageService with WebSocket support for real-time delivery
    let service =
        MessageService::with_websocket(pool.get_ref().clone(), std::sync::Arc::new(redis.get_ref().clone()));

    match service
        .send_message(
            user.0,
            req.conversation_id,
            req.encrypted_content.clone(),
            req.nonce.clone(),
            msg_type,
            req.search_text.clone(),
        )
        .await
    {
        Ok(message) => HttpResponse::Created().json(message),
        Err(e) => e.error_response(),
    }
}

#[derive(Debug, Deserialize)]
pub struct EditMessageRequest {
    pub encrypted_content: String,
    pub nonce: String,
    pub search_text: Option<String>,
}

/// PATCH /api/v1/messages/{id}
pub async fn edit_message(
    pool: web::Data<PgPool>,
    user: UserId,
    redis: web::Data<ConnectionManager>,
    config: web::Data<Config>,
    path: web::Path<Uuid>,
    body: web::Json<EditMessageRequest>,
) -> impl Responder {
    let edit_max: u32 = std::env::var("MSG_EDIT_MAX_REQUESTS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(config.rate_limit.max_requests);
    let edit_window: u64 = std::env::var("MSG_EDIT_WINDOW_SECS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(config.rate_limit.window_secs);
    let limiter = RateLimiter::new(
        redis.get_ref().clone(),
        RateLimitConfig {
            max_requests: edit_max,
            window_seconds: edit_window,
        },
    );
    let rl_key = format!("msg:edit:{}", user.0);
    if limiter.is_rate_limited(&rl_key).await.unwrap_or(false) {
        return crate::error::AppError::RateLimitExceeded.error_response();
    }
    let message_id = path.into_inner();
    let service =
        MessageService::with_websocket(pool.get_ref().clone(), std::sync::Arc::new(redis.get_ref().clone()));

    match service
        .edit_message(
            message_id,
            user.0,
            body.encrypted_content.clone(),
            body.nonce.clone(),
        )
        .await
    {
        Ok(updated) => {
            if let Some(text) = &body.search_text {
                let repo = MessagingRepository::new(pool.get_ref());
                let _ = repo
                    .upsert_message_search(
                        updated.id,
                        updated.conversation_id,
                        updated.sender_id,
                        text,
                    )
                    .await;
            }
            HttpResponse::Ok().json(updated)
        }
        Err(e) => e.error_response(),
    }
}

/// DELETE /api/v1/messages/{id}
pub async fn delete_message(
    pool: web::Data<PgPool>,
    user: UserId,
    redis: web::Data<ConnectionManager>,
    config: web::Data<Config>,
    path: web::Path<Uuid>,
) -> impl Responder {
    let del_max: u32 = std::env::var("MSG_DELETE_MAX_REQUESTS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(config.rate_limit.max_requests);
    let del_window: u64 = std::env::var("MSG_DELETE_WINDOW_SECS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(config.rate_limit.window_secs);
    let limiter = RateLimiter::new(
        redis.get_ref().clone(),
        RateLimitConfig {
            max_requests: del_max,
            window_seconds: del_window,
        },
    );
    let rl_key = format!("msg:delete:{}", user.0);
    if limiter.is_rate_limited(&rl_key).await.unwrap_or(false) {
        return crate::error::AppError::RateLimitExceeded.error_response();
    }
    let message_id = path.into_inner();
    let service =
        MessageService::with_websocket(pool.get_ref().clone(), std::sync::Arc::new(redis.get_ref().clone()));

    match service.delete_message(message_id, user.0).await {
        Ok(()) => HttpResponse::NoContent().finish(),
        Err(e) => e.error_response(),
    }
}

#[derive(Debug, Deserialize)]
pub struct MessageSearchQuery {
    pub conversation_id: Uuid,
    pub q: String,
    pub limit: Option<i64>,
}

/// GET /api/v1/messages/search
pub async fn search_messages(
    pool: web::Data<PgPool>,
    user: UserId,
    query: web::Query<MessageSearchQuery>,
) -> impl Responder {
    let conversation_id = query.conversation_id;
    let q = query.q.trim();
    if q.is_empty() {
        return HttpResponse::BadRequest().json(crate::handlers::auth::ErrorResponse {
            error: "Query cannot be empty".to_string(),
            details: None,
        });
    }

    let repo = MessagingRepository::new(pool.get_ref());
    match repo.is_conversation_member(conversation_id, user.0).await {
        Ok(true) => {}
        Ok(false) => {
            return AppError::Authorization("You are not a member of this conversation".to_string())
                .error_response()
        }
        Err(e) => return e.error_response(),
    }

    let limit = query.limit.unwrap_or(20).clamp(1, 100);
    // Enforce privacy: disallow searching strict_e2e
    if let Ok(mode) = repo.get_conversation_privacy(conversation_id).await {
        if mode == "strict_e2e" {
            return AppError::Authorization("Search is disabled for this conversation".to_string())
                .error_response();
        }
    }

    match repo.search_messages(conversation_id, q, limit).await {
        Ok(rows) => HttpResponse::Ok().json(serde_json::json!({
            "messages": rows,
            "count": rows.len(),
        })),
        Err(e) => e.error_response(),
    }
}

/// POST /api/v1/conversations/{id}/read
pub async fn mark_as_read(
    pool: web::Data<PgPool>,
    user: UserId,
    path: web::Path<Uuid>,
    redis: web::Data<ConnectionManager>,
    req: web::Json<MarkReadRequest>,
) -> impl Responder {
    let conversation_id = path.into_inner();
    let service =
        MessageService::with_websocket(pool.get_ref().clone(), std::sync::Arc::new(redis.get_ref().clone()));

    match service
        .mark_as_read(conversation_id, user.0, req.message_id)
        .await
    {
        Ok(()) => HttpResponse::Ok().json(SimpleOkResponse {
            message: "Read status updated".to_string(),
        }),
        Err(e) => e.error_response(),
    }
}
