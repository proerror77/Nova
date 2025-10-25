use crate::error::AppError;
use crate::middleware::jwt_auth::UserId;
use crate::services::transcoding_progress_handler::{ProgressStreamActor, ProgressStreamRegistry};
use actix_web::{web, HttpMessage, HttpRequest, HttpResponse};
use actix_web_actors::ws;
use std::sync::Arc;
use uuid::Uuid;

/// State for WebSocket progress streaming
pub struct ProgressStreamState {
    pub registry: Arc<ProgressStreamRegistry>,
}

impl ProgressStreamState {
    pub fn new(registry: Arc<ProgressStreamRegistry>) -> Self {
        Self { registry }
    }
}

/// WebSocket handler for transcoding progress streaming
///
/// Usage: `GET /api/v1/videos/{video_id}/progress/stream?token={jwt}`
/// Requires JWT token in Authorization header or query param
///
/// Server sends progress updates in this format:
/// ```json
/// {
///   "video_id": "uuid",
///   "status": "processing",
///   "progress_percent": 42,
///   "current_stage": "transcoding_720p",
///   "estimated_remaining_seconds": 180,
///   "timestamp": "2025-10-25T12:34:58Z"
/// }
/// ```
pub async fn progress_stream_ws(
    req: HttpRequest,
    path: web::Path<Uuid>,
    payload: web::Payload,
    state: web::Data<ProgressStreamState>,
) -> actix_web::Result<HttpResponse> {
    let video_id = path.into_inner();

    // Extract user from JWT (middleware already validated, optional for public videos)
    let _user_id = req.extensions().get::<UserId>().map(|id| id.0);

    // TODO: Verify user has permission to access this video
    // For now, allow any authenticated user

    tracing::info!(
        "WebSocket progress stream connection for video {}",
        video_id
    );

    // Create the WebSocket actor
    let actor = ProgressStreamActor::new(video_id, state.registry.clone());

    // Upgrade HTTP to WebSocket
    ws::start(actor, &req, payload)
}
