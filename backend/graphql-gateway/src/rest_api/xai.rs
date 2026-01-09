//! X.AI (Grok) API Proxy endpoints
//!
//! POST /api/v2/xai/chat - Send chat message to Grok
//! POST /api/v2/xai/chat/stream - Streaming chat with Grok (SSE)
//! GET /api/v2/xai/status - Get X.AI service status
//! POST /api/v2/xai/voice/token - Get ephemeral token for Voice Agent WebSocket
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
    let base_url =
        env::var("XAI_API_BASE_URL").unwrap_or_else(|_| "https://api.x.ai/v1".to_string());
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
    /// Enable live search for real-time data from X, web, and news
    #[serde(default)]
    pub enable_search: Option<bool>,
    /// Search sources: "web", "news", "x", "rss"
    #[serde(default)]
    pub search_sources: Option<Vec<String>>,
    /// Search date range start (YYYY-MM-DD)
    #[serde(default)]
    pub search_from_date: Option<String>,
    /// Search date range end (YYYY-MM-DD)
    #[serde(default)]
    pub search_to_date: Option<String>,
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

// MARK: - Live Search Configuration

#[derive(Debug, Serialize)]
struct SearchConfig {
    mode: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    return_citations: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    from_date: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    to_date: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    sources: Option<Vec<SearchSource>>,
}

#[derive(Debug, Serialize)]
struct SearchSource {
    #[serde(rename = "type")]
    source_type: String,
}

#[derive(Debug, Serialize)]
struct XAICompletionRequest {
    model: String,
    messages: Vec<ChatMessage>,
    temperature: f64,
    stream: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    search: Option<SearchConfig>,
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

const ALICE_SYSTEM_PROMPT: &str = r#"You are Alice, the AI assistant for Icered social platform.

Your characteristics:
- Friendly, helpful, and professional
- Communicate naturally and fluently with users
- Expert at providing social media related advice
- Help users create posts, reply to comments, and analyze trends

Respond in the same language the user uses.
Keep responses concise and impactful, avoid being overly verbose."#;

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
            models: vec!["grok-3-latest".to_string(), "grok-beta".to_string()],
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
    let system_prompt = req
        .system_prompt
        .clone()
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

    // Build search config if enabled
    let search_config = if req.enable_search.unwrap_or(false) {
        let sources = req.search_sources.as_ref().map(|sources| {
            sources
                .iter()
                .map(|s| SearchSource {
                    source_type: s.clone(),
                })
                .collect()
        });

        Some(SearchConfig {
            mode: "on".to_string(),
            return_citations: Some(true),
            from_date: req.search_from_date.clone(),
            to_date: req.search_to_date.clone(),
            sources,
        })
    } else {
        None
    };

    // Build X.AI request
    let xai_request = XAICompletionRequest {
        model: req.model.clone(),
        messages,
        temperature: req.temperature,
        stream: false,
        search: search_config,
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
                            let content = choice.message.content.clone().unwrap_or_default();

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

                // Handle specific error codes with user-friendly messages
                if status.as_u16() == 429 {
                    // Rate limit or quota exceeded
                    warn!("X.AI API quota exceeded or rate limited");
                    Ok(HttpResponse::TooManyRequests().json(serde_json::json!({
                        "status": "quota_exceeded",
                        "error_code": "QUOTA_EXCEEDED",
                        "message": "AI service quota exceeded. Please try again later.",
                        "message_zh": "AI 服務配額已用完，請稍後再試。",
                        "details": error_text,
                    })))
                } else if status.as_u16() == 401 || status.as_u16() == 403 {
                    // Authentication error
                    Ok(HttpResponse::ServiceUnavailable().json(serde_json::json!({
                        "status": "auth_error",
                        "error_code": "AUTH_ERROR",
                        "message": "AI service authentication failed.",
                        "message_zh": "AI 服務認證失敗。",
                    })))
                } else {
                    Ok(HttpResponse::BadGateway().json(serde_json::json!({
                        "status": "error",
                        "error_code": "API_ERROR",
                        "message": format!("AI API error: {}", status),
                        "details": error_text,
                    })))
                }
            }
        }
        Err(e) => {
            error!("Failed to call X.AI API: {}", e);
            Ok(HttpResponse::BadGateway().json(serde_json::json!({
                "status": "error",
                "error_code": "CONNECTION_ERROR",
                "message": "Failed to connect to AI service. Please try again.",
                "message_zh": "無法連接 AI 服務，請稍後再試。",
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
    let system_prompt = req
        .system_prompt
        .clone()
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

    // Build search config if enabled
    let search_config = if req.enable_search.unwrap_or(false) {
        let sources = req.search_sources.as_ref().map(|sources| {
            sources
                .iter()
                .map(|s| SearchSource {
                    source_type: s.clone(),
                })
                .collect()
        });

        Some(SearchConfig {
            mode: "on".to_string(),
            return_citations: Some(true),
            from_date: req.search_from_date.clone(),
            to_date: req.search_to_date.clone(),
            sources,
        })
    } else {
        None
    };

    // Build X.AI streaming request
    let xai_request = XAICompletionRequest {
        model: req.model.clone(),
        messages,
        temperature: req.temperature,
        stream: true,
        search: search_config,
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

                // Handle specific error codes with user-friendly messages
                if status.as_u16() == 429 {
                    warn!("X.AI API quota exceeded or rate limited");
                    return Ok(HttpResponse::TooManyRequests().json(serde_json::json!({
                        "status": "quota_exceeded",
                        "error_code": "QUOTA_EXCEEDED",
                        "message": "AI service quota exceeded. Please try again later.",
                        "message_zh": "AI 服務配額已用完，請稍後再試。",
                        "details": error_text,
                    })));
                } else if status.as_u16() == 401 || status.as_u16() == 403 {
                    return Ok(HttpResponse::ServiceUnavailable().json(serde_json::json!({
                        "status": "auth_error",
                        "error_code": "AUTH_ERROR",
                        "message": "AI service authentication failed.",
                        "message_zh": "AI 服務認證失敗。",
                    })));
                }

                return Ok(HttpResponse::BadGateway().json(serde_json::json!({
                    "status": "error",
                    "error_code": "API_ERROR",
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
                "error_code": "CONNECTION_ERROR",
                "message": "Failed to connect to AI service. Please try again.",
                "message_zh": "無法連接 AI 服務，請稍後再試。",
            })))
        }
    }
}

// MARK: - Voice Agent Token

#[derive(Debug, Serialize)]
pub struct VoiceTokenResponse {
    pub client_secret: ClientSecret,
    pub websocket_url: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ClientSecret {
    pub value: String,
    pub expires_at: i64,
}

// xAI API returns the token directly at top level (not nested)
// Response format: {"value": "xai-realtime-client-secret-...", "expires_at": 1234567890}
#[derive(Debug, Deserialize)]
struct XAIClientSecretResponse {
    value: String,
    expires_at: i64,
}

/// POST /api/v2/xai/voice/token
/// Get ephemeral token for Voice Agent WebSocket connection
///
/// This endpoint fetches a short-lived token from xAI that the client
/// can use to authenticate WebSocket connections without exposing the API key.
pub async fn get_voice_token(_clients: web::Data<ServiceClients>) -> Result<HttpResponse> {
    info!("POST /api/v2/xai/voice/token");

    let (base_url, api_key) = get_xai_config();

    if api_key.is_empty() {
        warn!("X.AI API key not configured");
        return Ok(HttpResponse::ServiceUnavailable().json(serde_json::json!({
            "status": "unavailable",
            "message": "X.AI API key not configured",
        })));
    }

    // Request ephemeral token from xAI
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(30))
        .build()
        .unwrap_or_else(|_| reqwest::Client::new());

    let api_url = format!("{}/realtime/client_secrets", base_url);

    // Request body with token expiration (5 minutes = 300 seconds)
    let request_body = serde_json::json!({
        "expires_after": {
            "seconds": 300
        }
    });

    match client
        .post(&api_url)
        .header("Authorization", format!("Bearer {}", api_key))
        .header("Content-Type", "application/json")
        .json(&request_body)
        .send()
        .await
    {
        Ok(response) => {
            let status = response.status();

            // Get response body as text first for debugging
            let response_text = response.text().await.unwrap_or_default();
            info!(
                "xAI voice token response status: {}, body: {}",
                status, &response_text
            );

            if status.is_success() {
                match serde_json::from_str::<XAIClientSecretResponse>(&response_text) {
                    Ok(xai_response) => {
                        info!(
                            "Voice token generated successfully, expires_at: {}",
                            xai_response.expires_at
                        );
                        Ok(HttpResponse::Ok().json(VoiceTokenResponse {
                            client_secret: ClientSecret {
                                value: xai_response.value,
                                expires_at: xai_response.expires_at,
                            },
                            websocket_url: "wss://api.x.ai/v1/realtime".to_string(),
                        }))
                    }
                    Err(e) => {
                        error!(
                            "Failed to parse xAI token response: {} - Raw response: {}",
                            e, &response_text
                        );
                        Ok(HttpResponse::InternalServerError().json(serde_json::json!({
                            "status": "error",
                            "message": format!("Failed to parse token response: {}", e),
                            "raw_response": &response_text,
                        })))
                    }
                }
            } else {
                error!("xAI API error: {} - {}", status, &response_text);
                Ok(HttpResponse::BadGateway().json(serde_json::json!({
                    "status": "error",
                    "message": format!("Failed to get voice token: {}", status),
                    "details": &response_text,
                })))
            }
        }
        Err(e) => {
            error!("Failed to call xAI API: {}", e);
            Ok(HttpResponse::BadGateway().json(serde_json::json!({
                "status": "error",
                "message": format!("Failed to connect to xAI service: {}", e),
            })))
        }
    }
}
