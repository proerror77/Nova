//! Alice AI Assistant API endpoints
//!
//! GET /api/v2/alice/status - Get Alice service status
//! POST /api/v2/alice/chat - Send chat message to Alice
//! POST /api/v2/alice/voice - Activate voice mode
//!
//! Integrates with tu-zi.com OpenAI-compatible API

#![allow(dead_code)]

use actix_web::{web, HttpResponse, Result};
use serde::{Deserialize, Serialize};
use tracing::{info, warn, error};
use std::env;

use crate::clients::ServiceClients;

// MARK: - Request/Response Models

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

// MARK: - OpenAI API Models (tu-zi.com compatible)

#[derive(Debug, Serialize)]
struct OpenAIChatRequest {
    model: String,
    messages: Vec<OpenAIChatMessage>,
}

#[derive(Debug, Serialize, Deserialize)]
struct OpenAIChatMessage {
    role: String,
    content: String,
}

#[derive(Debug, Deserialize)]
struct OpenAIChatResponse {
    id: String,
    choices: Vec<OpenAIChoice>,
}

#[derive(Debug, Deserialize)]
struct OpenAIChoice {
    message: OpenAIChatMessage,
}

// MARK: - Configuration

/// Get OpenAI API configuration from environment
fn get_api_config() -> (String, String) {
    let base_url = env::var("OPENAI_API_BASE_URL")
        .unwrap_or_else(|_| "https://api.tu-zi.com/v1".to_string());
    let api_key = env::var("OPENAI_API_KEY")
        .unwrap_or_else(|_| "".to_string());
    (base_url, api_key)
}

// MARK: - API Handlers

/// GET /api/v2/alice/status
/// Get Alice service status
pub async fn get_status(_clients: web::Data<ServiceClients>) -> Result<HttpResponse> {
    info!("GET /api/v2/alice/status");

    let (_, api_key) = get_api_config();
    let available = !api_key.is_empty();

    if available {
        Ok(HttpResponse::Ok().json(AliceStatusResponse {
            status: "available".to_string(),
            version: "1.0.0".to_string(),
            available: true,
        }))
    } else {
        warn!("Alice API key not configured");
        Ok(HttpResponse::ServiceUnavailable().json(serde_json::json!({
            "status": "unavailable",
            "version": "1.0.0",
            "available": false,
            "message": "OpenAI API key not configured"
        })))
    }
}

/// POST /api/v2/alice/chat
/// Send chat message to Alice
pub async fn send_message(
    req: web::Json<AliceChatRequest>,
    _clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(message = %req.message, "POST /api/v2/alice/chat");

    let (base_url, api_key) = get_api_config();

    if api_key.is_empty() {
        warn!("Alice API key not configured");
        return Ok(HttpResponse::ServiceUnavailable().json(serde_json::json!({
            "status": "unavailable",
            "message": "OpenAI API key not configured",
        })));
    }

    // Build OpenAI chat completion request
    let openai_request = OpenAIChatRequest {
        model: "gpt-4o-all".to_string(),
        messages: vec![OpenAIChatMessage {
            role: "user".to_string(),
            content: req.message.clone(),
        }],
    };

    // Call tu-zi.com API
    let client = reqwest::Client::new();
    let api_url = format!("{}/chat/completions", base_url);

    match client
        .post(&api_url)
        .header("Authorization", format!("Bearer {}", api_key))
        .header("Content-Type", "application/json")
        .json(&openai_request)
        .send()
        .await
    {
        Ok(response) => {
            let status = response.status();

            if status.is_success() {
                match response.json::<OpenAIChatResponse>().await {
                    Ok(openai_response) => {
                        if let Some(choice) = openai_response.choices.first() {
                            let response_message = AliceChatResponse {
                                id: openai_response.id,
                                message: choice.message.content.clone(),
                                timestamp: chrono::Utc::now().timestamp(),
                            };

                            info!("Alice response generated successfully");
                            Ok(HttpResponse::Ok().json(response_message))
                        } else {
                            error!("No choices in OpenAI response");
                            Ok(HttpResponse::InternalServerError().json(serde_json::json!({
                                "status": "error",
                                "message": "No response from AI model",
                            })))
                        }
                    }
                    Err(e) => {
                        error!("Failed to parse OpenAI response: {}", e);
                        Ok(HttpResponse::InternalServerError().json(serde_json::json!({
                            "status": "error",
                            "message": format!("Failed to parse AI response: {}", e),
                        })))
                    }
                }
            } else {
                let error_text = response.text().await.unwrap_or_default();
                error!("OpenAI API error: {} - {}", status, error_text);
                Ok(HttpResponse::BadGateway().json(serde_json::json!({
                    "status": "error",
                    "message": format!("AI API error: {}", status),
                    "details": error_text,
                })))
            }
        }
        Err(e) => {
            error!("Failed to call OpenAI API: {}", e);
            Ok(HttpResponse::BadGateway().json(serde_json::json!({
                "status": "error",
                "message": format!("Failed to connect to AI service: {}", e),
            })))
        }
    }
}

/// POST /api/v2/alice/voice
/// Activate voice mode
pub async fn voice_mode(_clients: web::Data<ServiceClients>) -> Result<HttpResponse> {
    info!("POST /api/v2/alice/voice");

    // Voice mode requires TEN Agent integration
    Ok(HttpResponse::ServiceUnavailable().json(serde_json::json!({
        "status": "unavailable",
        "message": "Alice voice mode requires TEN Agent integration. Please use the TEN Agent service directly.",
    })))
}
