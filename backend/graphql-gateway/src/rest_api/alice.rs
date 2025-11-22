/// Alice AI Assistant API endpoints
///
/// GET /api/v2/alice/status - Get Alice service status
/// POST /api/v2/alice/chat - Send chat message to Alice
/// POST /api/v2/alice/voice - Activate voice mode
use actix_web::{web, HttpResponse, Result};
use serde::{Deserialize, Serialize};
use tracing::info;

use crate::clients::ServiceClients;

#[derive(Debug, Deserialize)]
pub struct AliceChatRequest {
    pub message: String,
    pub mode: Option<String>, // "text" or "voice"
}

#[derive(Debug, Serialize)]
pub struct AliceChatResponse {
    pub id: String,
    pub message: String,
    pub timestamp: i64,
}

#[derive(Debug, Serialize)]
pub struct AliceStatusResponse {
    pub status: String,
    pub version: String,
    pub available: bool,
}

/// GET /api/v2/alice/status
/// Get Alice service status
pub async fn get_status(_clients: web::Data<ServiceClients>) -> Result<HttpResponse> {
    info!("GET /api/v2/alice/status");

    // For now, return mock response
    // TODO: Implement actual Alice service status check when alice-service is available
    let response = AliceStatusResponse {
        status: "operational".to_string(),
        version: "5.1".to_string(),
        available: true,
    };

    Ok(HttpResponse::Ok().json(response))
}

/// POST /api/v2/alice/chat
/// Send chat message to Alice
pub async fn send_message(
    req: web::Json<AliceChatRequest>,
    _clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(message = %req.message, "POST /api/v2/alice/chat");

    // For now, return mock response
    // TODO: Implement actual message forwarding to alice-service when available
    let response = AliceChatResponse {
        id: uuid::Uuid::new_v4().to_string(),
        message: format!("Echo: {}", req.message),
        timestamp: chrono::Utc::now().timestamp(),
    };

    Ok(HttpResponse::Ok().json(response))
}

/// POST /api/v2/alice/voice
/// Activate voice mode
pub async fn voice_mode(_clients: web::Data<ServiceClients>) -> Result<HttpResponse> {
    info!("POST /api/v2/alice/voice");

    // For now, return success
    // TODO: Implement actual voice mode setup when alice-service is available
    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "voice_mode_activated",
        "session_id": uuid::Uuid::new_v4().to_string(),
    })))
}
