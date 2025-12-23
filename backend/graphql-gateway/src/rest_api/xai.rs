//! X.AI (Grok) API Proxy endpoints
//!
//! POST /api/v2/xai/chat - Send chat message to Grok
//! POST /api/v2/xai/chat/stream - Streaming chat with Grok (SSE)
//! GET /api/v2/xai/status - Get X.AI service status
//!
//! Proxies requests to X.AI API, keeping the API key secure on the server

use actix_web::{web, HttpResponse, Result};
use serde::{Deserialize, Serialize};
use std::env;
use std::time::Duration;
use tracing::{error, info, warn};

use crate::clients::ServiceClients;

// MARK: - Configuration

/// Get X.AI API configuration from environment
fn get_xai_config() -> (String, String) {
    let base_url = env::var("XAI_API_BASE_URL")
        .unwrap_or_else(|_| "https://api.x.ai/v1".to_string());
    let api_key = env::var("XAI_API_KEY").unwrap_or_else(|_| "".to_string());
    (base_url, api_key)
}

// MARK: - Request/Response Models

#[derive(Debug, Deserialize)]
pub struct XAIChatRequest {
    pub message: String,
    #[serde(default = "default_model")]
    pub model: String,
    #[serde(default)]
    pub system_prompt: Option<String>,
    #[serde(default = "default_temperature")]
    pub temperature: f64,
    #[serde(default)]
    pub conversation_history: Option<Vec<ChatMessage>>,
}

fn default_model() -> String {
    "grok-3-latest".to_string()
}

fn default_temperature() -> f64 {
    0.7
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ChatMessage {
    pub role: String,
    pub content: String,
}

#[derive(Debug, Serialize)]
pub struct XAIChatResponse {
    pub id: String,
    pub message: String,
    pub model: String,
    pub usage: Option<UsageInfo>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct UsageInfo {
    pub prompt_tokens: i32,
    pub completion_tokens: i32,
    pub total_tokens: i32,
}

#[derive(Debug, Serialize)]
pub struct XAIStatusResponse {
    pub status: String,
    pub available: bool,
    pub models: Vec<String>,
}

// MARK: - X.AI API Models

#[derive(Debug, Serialize)]
struct XAICompletionRequest {
    model: String,
    messages: Vec<ChatMessage>,
    temperature: f64,
    stream: bool,
}

#[derive(Debug, Deserialize)]
struct XAICompletionResponse {
    id: String,
    model: String,
    choices: Vec<XAIChoice>,
    usage: Option<XAIUsage>,
}

#[derive(Debug, Deserialize)]
struct XAIChoice {
    message: XAIMessage,
    #[allow(dead_code)]
    finish_reason: Option<String>,
}

#[derive(Debug, Deserialize)]
struct XAIMessage {
    #[allow(dead_code)]
    role: String,
    content: Option<String>,
}

#[derive(Debug, Deserialize)]
struct XAIUsage {
    prompt_tokens: i32,
    completion_tokens: i32,
    total_tokens: i32,
}

#[derive(Debug, Deserialize)]
struct XAIStreamChunk {
    choices: Vec<XAIStreamChoice>,
}

#[derive(Debug, Deserialize)]
struct XAIStreamChoice {
    delta: XAIStreamDelta,
}

#[derive(Debug, Deserialize)]
struct XAIStreamDelta {
    content: Option<String>,
}

// MARK: - Default System Prompt

const ALICE_SYSTEM_PROMPT: &str = r#"你是 Alice，ICERED 社交平台的 AI 助理。

你的特點：
- 友善、有幫助、專業
- 能夠用自然流暢的方式與用戶對話
- 擅長提供社交媒體相關的建議
- 可以幫助用戶創作貼文、回覆留言、分析趨勢

請用繁體中文回應，除非用戶使用其他語言。
保持回應簡潔有力，避免過於冗長。"#;

// MARK: - API Handlers

/// GET /api/v2/xai/status
/// Get X.AI service status
pub async fn get_status(_clients: web::Data<ServiceClients>) -> Result<HttpResponse> {
    info!("GET /api/v2/xai/status");

    let (_, api_key) = get_xai_config();
    let available = !api_key.is_empty();

    if available {
        Ok(HttpResponse::Ok().json(XAIStatusResponse {
            status: "available".to_string(),
            available: true,
            models: vec![
                "grok-3-latest".to_string(),
                "grok-beta".to_string(),
            ],
        }))
    } else {
        warn!("X.AI API key not configured");
        Ok(HttpResponse::ServiceUnavailable().json(serde_json::json!({
            "status": "unavailable",
            "available": false,
            "message": "X.AI API key not configured"
        })))
    }
}

/// POST /api/v2/xai/chat
/// Send chat message to Grok
pub async fn chat(
    req: web::Json<XAIChatRequest>,
    _clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(message = %req.message, model = %req.model, "POST /api/v2/xai/chat");

    let (base_url, api_key) = get_xai_config();

    if api_key.is_empty() {
        warn!("X.AI API key not configured");
        return Ok(HttpResponse::ServiceUnavailable().json(serde_json::json!({
            "status": "unavailable",
            "message": "X.AI API key not configured",
        })));
    }

    // Build messages array
    let mut messages: Vec<ChatMessage> = vec![];

    // Add system prompt
    let system_prompt = req.system_prompt.clone()
        .unwrap_or_else(|| ALICE_SYSTEM_PROMPT.to_string());
    messages.push(ChatMessage {
        role: "system".to_string(),
        content: system_prompt,
    });

    // Add conversation history if provided
    if let Some(history) = &req.conversation_history {
        messages.extend(history.clone());
    }

    // Add current user message
    messages.push(ChatMessage {
        role: "user".to_string(),
        content: req.message.clone(),
    });

    // Build X.AI request
    let xai_request = XAICompletionRequest {
        model: req.model.clone(),
        messages,
        temperature: req.temperature,
        stream: false,
    };

    // Call X.AI API
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(60))
        .build()
        .unwrap_or_else(|_| reqwest::Client::new());

    let api_url = format!("{}/chat/completions", base_url);

    match client
        .post(&api_url)
        .header("Authorization", format!("Bearer {}", api_key))
        .header("Content-Type", "application/json")
        .json(&xai_request)
        .send()
        .await
    {
        Ok(response) => {
            let status = response.status();

            if status.is_success() {
                match response.json::<XAICompletionResponse>().await {
                    Ok(xai_response) => {
                        if let Some(choice) = xai_response.choices.first() {
                            let content = choice.message.content.clone()
                                .unwrap_or_default();

                            let chat_response = XAIChatResponse {
                                id: xai_response.id,
                                message: content,
                                model: xai_response.model,
                                usage: xai_response.usage.map(|u| UsageInfo {
                                    prompt_tokens: u.prompt_tokens,
                                    completion_tokens: u.completion_tokens,
                                    total_tokens: u.total_tokens,
                                }),
                            };

                            info!("X.AI response generated successfully");
                            Ok(HttpResponse::Ok().json(chat_response))
                        } else {
                            error!("No choices in X.AI response");
                            Ok(HttpResponse::InternalServerError().json(serde_json::json!({
                                "status": "error",
                                "message": "No response from AI model",
                            })))
                        }
                    }
                    Err(e) => {
                        error!("Failed to parse X.AI response: {}", e);
                        Ok(HttpResponse::InternalServerError().json(serde_json::json!({
                            "status": "error",
                            "message": format!("Failed to parse AI response: {}", e),
                        })))
                    }
                }
            } else {
                let error_text = response.text().await.unwrap_or_default();
                error!("X.AI API error: {} - {}", status, error_text);
                Ok(HttpResponse::BadGateway().json(serde_json::json!({
                    "status": "error",
                    "message": format!("AI API error: {}", status),
                    "details": error_text,
                })))
            }
        }
        Err(e) => {
            error!("Failed to call X.AI API: {}", e);
            Ok(HttpResponse::BadGateway().json(serde_json::json!({
                "status": "error",
                "message": format!("Failed to connect to AI service: {}", e),
            })))
        }
    }
}

/// POST /api/v2/xai/chat/stream
/// Streaming chat with Grok - returns full response (simulated streaming for simplicity)
/// For true SSE streaming, use WebSocket or implement chunked transfer
pub async fn chat_stream(
    req: web::Json<XAIChatRequest>,
    _clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(message = %req.message, model = %req.model, "POST /api/v2/xai/chat/stream");

    let (base_url, api_key) = get_xai_config();

    if api_key.is_empty() {
        warn!("X.AI API key not configured");
        return Ok(HttpResponse::ServiceUnavailable().json(serde_json::json!({
            "status": "unavailable",
            "message": "X.AI API key not configured",
        })));
    }

    // Build messages array
    let mut messages: Vec<ChatMessage> = vec![];

    // Add system prompt
    let system_prompt = req.system_prompt.clone()
        .unwrap_or_else(|| ALICE_SYSTEM_PROMPT.to_string());
    messages.push(ChatMessage {
        role: "system".to_string(),
        content: system_prompt,
    });

    // Add conversation history if provided
    if let Some(history) = &req.conversation_history {
        messages.extend(history.clone());
    }

    // Add current user message
    messages.push(ChatMessage {
        role: "user".to_string(),
        content: req.message.clone(),
    });

    // Build X.AI streaming request
    let xai_request = XAICompletionRequest {
        model: req.model.clone(),
        messages,
        temperature: req.temperature,
        stream: true,
    };

    // Call X.AI API with streaming
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(120))
        .build()
        .unwrap_or_else(|_| reqwest::Client::new());

    let api_url = format!("{}/chat/completions", base_url);

    match client
        .post(&api_url)
        .header("Authorization", format!("Bearer {}", api_key))
        .header("Content-Type", "application/json")
        .json(&xai_request)
        .send()
        .await
    {
        Ok(response) => {
            let status = response.status();

            if !status.is_success() {
                let error_text = response.text().await.unwrap_or_default();
                error!("X.AI API error: {} - {}", status, error_text);
                return Ok(HttpResponse::BadGateway().json(serde_json::json!({
                    "status": "error",
                    "message": format!("AI API error: {}", status),
                    "details": error_text,
                })));
            }

            // Read the streaming response and parse chunks
            let body = response.text().await.unwrap_or_default();
            let mut full_content = String::new();

            // Parse SSE data lines
            for line in body.lines() {
                if let Some(data) = line.strip_prefix("data: ") {
                    if data == "[DONE]" {
                        continue;
                    }
                    if let Ok(chunk) = serde_json::from_str::<XAIStreamChunk>(data) {
                        if let Some(choice) = chunk.choices.first() {
                            if let Some(content) = &choice.delta.content {
                                full_content.push_str(content);
                            }
                        }
                    }
                }
            }

            // Return as SSE format for client compatibility
            let sse_response = format!(
                "data: {}\n\ndata: [DONE]\n\n",
                serde_json::json!({"content": full_content})
            );

            Ok(HttpResponse::Ok()
                .content_type("text/event-stream")
                .body(sse_response))
        }
        Err(e) => {
            error!("Failed to call X.AI API: {}", e);
            Ok(HttpResponse::BadGateway().json(serde_json::json!({
                "status": "error",
                "message": format!("Failed to connect to AI service: {}", e),
            })))
        }
    }
}
