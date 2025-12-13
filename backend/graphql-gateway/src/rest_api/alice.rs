//! Alice AI Assistant API endpoints
//!
//! GET /api/v2/alice/status - Get Alice service status
//! POST /api/v2/alice/chat - Send chat message to Alice
//! POST /api/v2/alice/voice - Activate voice mode
//! POST /api/v2/alice/enhance - Analyze image and suggest post content
//!
//! Integrates with tu-zi.com OpenAI-compatible API

#![allow(dead_code)]

use actix_web::{web, HttpResponse, Result};
use serde::{Deserialize, Serialize};
use std::env;
use tracing::{error, info, warn};

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

#[derive(Debug, Deserialize)]
pub struct AliceEnhanceRequest {
    pub image_base64: String,
    pub existing_text: Option<String>,
    pub include_trending: Option<bool>,
}

#[derive(Debug, Serialize)]
pub struct AliceEnhanceResponse {
    pub description: String,
    pub hashtags: Vec<String>,
    pub trending_topics: Option<Vec<String>>,
    pub alternative_descriptions: Option<Vec<String>>,
}

// MARK: - OpenAI API Models (tu-zi.com compatible)

#[derive(Debug, Serialize)]
struct OpenAIChatRequest {
    model: String,
    messages: Vec<OpenAIChatMessage>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
struct OpenAIChatMessage {
    role: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    content: Option<String>,
    #[serde(rename = "content", skip_serializing_if = "Option::is_none")]
    content_parts: Option<Vec<OpenAIContentPart>>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(tag = "type")]
enum OpenAIContentPart {
    #[serde(rename = "text")]
    Text { text: String },
    #[serde(rename = "image_url")]
    ImageUrl { image_url: ImageUrl },
}

#[derive(Debug, Serialize, Deserialize, Clone)]
struct ImageUrl {
    url: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    detail: Option<String>,
}

// Vision-compatible request
#[derive(Debug, Serialize)]
struct OpenAIVisionRequest {
    model: String,
    messages: Vec<OpenAIVisionMessage>,
    max_tokens: Option<i32>,
}

#[derive(Debug, Serialize)]
struct OpenAIVisionMessage {
    role: String,
    content: Vec<OpenAIContentPart>,
}

#[derive(Debug, Deserialize)]
struct OpenAIChatResponse {
    id: String,
    choices: Vec<OpenAIChoice>,
}

#[derive(Debug, Deserialize)]
struct OpenAIChoice {
    message: OpenAIResponseMessage,
}

#[derive(Debug, Deserialize)]
struct OpenAIResponseMessage {
    role: String,
    content: String,
}

// MARK: - Configuration

/// Get OpenAI API configuration from environment
fn get_api_config() -> (String, String) {
    let base_url =
        env::var("OPENAI_API_BASE_URL").unwrap_or_else(|_| "https://api.tu-zi.com/v1".to_string());
    let api_key = env::var("OPENAI_API_KEY").unwrap_or_else(|_| "".to_string());
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

/// POST /api/v2/alice/enhance
/// Analyze image and suggest post content with trending topics
pub async fn enhance_post(
    req: web::Json<AliceEnhanceRequest>,
    _clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!("POST /api/v2/alice/enhance");

    let (base_url, api_key) = get_api_config();

    if api_key.is_empty() {
        warn!("Alice API key not configured");
        return Ok(HttpResponse::ServiceUnavailable().json(serde_json::json!({
            "status": "unavailable",
            "message": "OpenAI API key not configured",
        })));
    }

    let include_trending = req.include_trending.unwrap_or(true);

    // Build the prompt for image analysis
    let prompt = build_enhance_prompt(req.existing_text.as_deref(), include_trending);

    // Build vision request with image
    let image_url = format!("data:image/jpeg;base64,{}", req.image_base64);

    let vision_request = OpenAIVisionRequest {
        model: "gpt-4o-all".to_string(),
        messages: vec![OpenAIVisionMessage {
            role: "user".to_string(),
            content: vec![
                OpenAIContentPart::Text { text: prompt },
                OpenAIContentPart::ImageUrl {
                    image_url: ImageUrl {
                        url: image_url,
                        detail: Some("low".to_string()), // Use low detail for faster processing
                    },
                },
            ],
        }],
        max_tokens: Some(1000),
    };

    // Call OpenAI Vision API
    let client = reqwest::Client::new();
    let api_url = format!("{}/chat/completions", base_url);

    match client
        .post(&api_url)
        .header("Authorization", format!("Bearer {}", api_key))
        .header("Content-Type", "application/json")
        .json(&vision_request)
        .send()
        .await
    {
        Ok(response) => {
            let status = response.status();

            if status.is_success() {
                match response.json::<OpenAIChatResponse>().await {
                    Ok(openai_response) => {
                        if let Some(choice) = openai_response.choices.first() {
                            // Parse the structured response from AI
                            match parse_enhance_response(&choice.message.content) {
                                Ok(enhance_response) => {
                                    info!("Enhancement generated successfully");
                                    Ok(HttpResponse::Ok().json(enhance_response))
                                }
                                Err(e) => {
                                    error!("Failed to parse enhancement response: {}", e);
                                    // Fallback: return raw content as description
                                    Ok(HttpResponse::Ok().json(AliceEnhanceResponse {
                                        description: choice.message.content.clone(),
                                        hashtags: vec![],
                                        trending_topics: None,
                                        alternative_descriptions: None,
                                    }))
                                }
                            }
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

/// Build the prompt for image enhancement
fn build_enhance_prompt(existing_text: Option<&str>, include_trending: bool) -> String {
    let base_prompt = r#"Analyze this image and suggest social media post content.

Please respond in the following JSON format:
{
    "description": "A engaging caption for this image (1-2 sentences)",
    "hashtags": ["relevant", "hashtags", "without", "the", "hash", "symbol"],
    "trending_topics": ["related trending topics if applicable"],
    "alternative_descriptions": ["alternative caption 1", "alternative caption 2"]
}

Guidelines:
- Make the description engaging and authentic
- Include 4-6 relevant hashtags
- Keep the tone casual and friendly
- Don't use excessive emojis
"#;

    let mut prompt = base_prompt.to_string();

    if let Some(text) = existing_text {
        prompt.push_str(&format!(
            "\n\nThe user has already written: \"{}\"\nPlease enhance or suggest improvements while keeping their original intent.",
            text
        ));
    }

    if include_trending {
        prompt.push_str("\n\nAlso suggest 2-3 relevant trending topics that could make this post more discoverable.");
    } else {
        prompt.push_str("\n\nSet trending_topics to null in the response.");
    }

    prompt
}

/// Parse the AI response into structured format
fn parse_enhance_response(content: &str) -> std::result::Result<AliceEnhanceResponse, String> {
    // Try to extract JSON from the response
    let json_start = content.find('{');
    let json_end = content.rfind('}');

    if let (Some(start), Some(end)) = (json_start, json_end) {
        let json_str = &content[start..=end];
        match serde_json::from_str::<serde_json::Value>(json_str) {
            Ok(json) => {
                let description = json["description"]
                    .as_str()
                    .unwrap_or("Check out this photo!")
                    .to_string();

                let hashtags: Vec<String> = json["hashtags"]
                    .as_array()
                    .map(|arr| {
                        arr.iter()
                            .filter_map(|v| v.as_str().map(|s| s.to_string()))
                            .collect()
                    })
                    .unwrap_or_default();

                let trending_topics: Option<Vec<String>> = json["trending_topics"]
                    .as_array()
                    .map(|arr| {
                        arr.iter()
                            .filter_map(|v| v.as_str().map(|s| s.to_string()))
                            .collect()
                    });

                let alternative_descriptions: Option<Vec<String>> =
                    json["alternative_descriptions"].as_array().map(|arr| {
                        arr.iter()
                            .filter_map(|v| v.as_str().map(|s| s.to_string()))
                            .collect()
                    });

                Ok(AliceEnhanceResponse {
                    description,
                    hashtags,
                    trending_topics,
                    alternative_descriptions,
                })
            }
            Err(e) => Err(format!("JSON parse error: {}", e)),
        }
    } else {
        Err("No JSON found in response".to_string())
    }
}
