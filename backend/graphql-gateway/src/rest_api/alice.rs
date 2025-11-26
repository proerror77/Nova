//! Alice AI Assistant API endpoints
//!
//! GET /api/v2/alice/status - Get Alice service status
//! POST /api/v2/alice/chat - Send chat message to Alice
//! POST /api/v2/alice/voice - Activate voice mode
//!
//! Alice AI Assistant is a stub implementation pending AI service integration

#![allow(dead_code)]

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

    // Alice 尚未接通，明確返回 503 並標註為 mock
    Ok(HttpResponse::ServiceUnavailable()
        .insert_header(("X-Nova-Mock", "true"))
        .json(serde_json::json!({
            "status": "unavailable",
            "version": "mock",
            "available": false,
            "message": "Alice service not integrated yet"
        })))
}

/// POST /api/v2/alice/chat
/// Send chat message to Alice
pub async fn send_message(
    req: web::Json<AliceChatRequest>,
    _clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(message = %req.message, "POST /api/v2/alice/chat");

    Ok(HttpResponse::ServiceUnavailable()
        .insert_header(("X-Nova-Mock", "true"))
        .json(serde_json::json!({
            "status": "unavailable",
            "message": "Alice service not integrated yet",
            "echo": req.message,
        })))
}

/// POST /api/v2/alice/voice
/// Activate voice mode
pub async fn voice_mode(_clients: web::Data<ServiceClients>) -> Result<HttpResponse> {
    info!("POST /api/v2/alice/voice");

    Ok(HttpResponse::ServiceUnavailable()
        .insert_header(("X-Nova-Mock", "true"))
        .json(serde_json::json!({
            "status": "unavailable",
            "message": "Alice voice mode not integrated yet",
        })))
}
