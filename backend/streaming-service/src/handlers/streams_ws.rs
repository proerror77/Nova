//! WebSocket handler for stream chat
//!
//! Handles WebSocket upgrade for `/ws/streams/{stream_id}/chat`
//! - JWT authentication
//! - Stream validation
//! - Connection initialization
//! - Message broadcasting

use actix_web::{web, HttpMessage, HttpRequest, HttpResponse};
use actix_web_actors::ws;
use crate::AppError;
use uuid::Uuid;

use crate::services::streaming::{StreamChatActor, StreamChatHandlerState};

/// JWT-extracted user ID (from middleware)
#[derive(Debug, Clone, Copy)]
pub struct UserId(pub Uuid);

/// WebSocket handler for stream chat
///
/// Usage: `GET /ws/streams/{stream_id}/chat`
/// Requires JWT token in Authorization header
///
/// Client should send messages in this format:
/// ```json
/// {"type": "message", "text": "Hello world"}
/// ```
///
/// Server broadcasts in this format:
/// ```json
/// {"comment": {"id": "...", "stream_id": "...", "user_id": "...", "message": "...", "created_at": "..."}}
/// ```
pub async fn stream_chat_ws(
    req: HttpRequest,
    path: web::Path<Uuid>,
    payload: web::Payload,
    state: web::Data<StreamChatHandlerState>,
) -> actix_web::Result<HttpResponse> {
    let stream_id = path.into_inner();

    // Extract user from JWT (middleware already validated)
    let user_id = req
        .extensions()
        .get::<UserId>()
        .map(|id| id.0)
        .ok_or_else(|| AppError::Authentication("Missing user context".into()))?;

    // Fetch username from database
    let username = state
        .get_username(user_id)
        .await
        .unwrap_or_else(|| format!("user_{}", user_id));

    tracing::info!(
        "WebSocket chat connection from user {} ({}) to stream {}",
        user_id,
        username,
        stream_id
    );

    // Create the WebSocket actor with all dependencies
    let actor = StreamChatActor::new(
        stream_id,
        user_id,
        username,
        state.registry.clone(),
        state.chat_store.clone(),
        state.kafka_producer.clone(),
    );

    // Upgrade HTTP to WebSocket
    ws::start(actor, &req, payload)
}
