//! LiveKit API endpoints
//!
//! POST /api/v2/livekit/token - Generate LiveKit access token for voice chat
//!
//! Architecture:
//! iOS App → This endpoint → LiveKit Cloud → Python Agent → xAI Grok Voice API

use actix_web::{web, HttpResponse, Result};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD as BASE64_URL, Engine};
use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use std::env;
use std::time::{SystemTime, UNIX_EPOCH};
use tracing::{error, info};

type HmacSha256 = Hmac<Sha256>;

// MARK: - Configuration

fn get_livekit_config() -> (String, String, String) {
    let url = env::var("LIVEKIT_URL")
        .unwrap_or_else(|_| "wss://kok-fjbuamt4.livekit.cloud".to_string());
    let api_key = env::var("LIVEKIT_API_KEY")
        .unwrap_or_else(|_| "".to_string());
    let api_secret = env::var("LIVEKIT_API_SECRET")
        .unwrap_or_else(|_| "".to_string());
    (url, api_key, api_secret)
}

// MARK: - Request/Response Models

#[derive(Debug, Deserialize)]
pub struct LiveKitTokenRequest {
    /// Room name for the voice session
    pub room_name: String,
    /// Participant identity (usually user ID)
    pub participant_name: String,
    /// Agent name to dispatch (e.g., "alice")
    #[serde(default)]
    pub agent_name: Option<String>,
    /// Optional metadata (voice preference, etc.)
    #[serde(default)]
    pub metadata: Option<serde_json::Value>,
}

#[derive(Debug, Serialize)]
pub struct LiveKitTokenResponse {
    /// JWT access token
    pub token: String,
    /// LiveKit server URL
    pub url: String,
    /// Room name
    pub room: String,
}

#[derive(Debug, Serialize)]
pub struct ErrorResponse {
    pub error: String,
    pub code: String,
}

// MARK: - JWT Claims

#[derive(Debug, Serialize)]
struct LiveKitClaims {
    /// Token issuer (API Key)
    iss: String,
    /// Subject (participant identity)
    sub: String,
    /// Issued at
    iat: u64,
    /// Not before
    nbf: u64,
    /// Expiration (1 hour)
    exp: u64,
    /// LiveKit video grants
    video: VideoGrant,
    /// Room configuration (for agent dispatch)
    #[serde(rename = "roomConfig", skip_serializing_if = "Option::is_none")]
    room_config: Option<RoomConfig>,
    /// Participant metadata
    #[serde(skip_serializing_if = "Option::is_none")]
    metadata: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct VideoGrant {
    /// Room name
    room: String,
    /// Can join room
    room_join: bool,
    /// Can publish audio
    can_publish: bool,
    /// Can publish video (false for voice-only)
    can_publish_video: bool,
    /// Can subscribe to tracks
    can_subscribe: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct RoomAgentDispatch {
    /// Agent name to dispatch (serializes to "agentName")
    agent_name: String,
}

#[derive(Debug, Serialize)]
struct RoomConfig {
    /// Agents to dispatch when participant joins
    agents: Vec<RoomAgentDispatch>,
}

// MARK: - Token Generation

fn generate_livekit_token(
    api_key: &str,
    api_secret: &str,
    room_name: &str,
    participant_name: &str,
    agent_name: Option<String>,
    metadata: Option<String>,
) -> Result<String, String> {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| e.to_string())?
        .as_secs();

    // Create room_config with agent dispatch if agent_name is provided
    let room_config = agent_name.map(|agent| RoomConfig {
        agents: vec![RoomAgentDispatch {
            agent_name: agent,
        }],
    });

    let claims = LiveKitClaims {
        iss: api_key.to_string(),
        sub: participant_name.to_string(),
        iat: now,
        nbf: now,
        exp: now + 3600, // 1 hour expiry
        video: VideoGrant {
            room: room_name.to_string(),
            room_join: true,
            can_publish: true,
            can_publish_video: false, // Voice only
            can_subscribe: true,
        },
        room_config,
        metadata,
    };

    // Create JWT header
    let header = serde_json::json!({
        "alg": "HS256",
        "typ": "JWT"
    });

    let header_b64 = BASE64_URL.encode(serde_json::to_string(&header).map_err(|e| e.to_string())?);
    let claims_b64 = BASE64_URL.encode(serde_json::to_string(&claims).map_err(|e| e.to_string())?);

    let message = format!("{}.{}", header_b64, claims_b64);

    // Sign with HMAC-SHA256
    let mut mac = HmacSha256::new_from_slice(api_secret.as_bytes())
        .map_err(|e| e.to_string())?;
    mac.update(message.as_bytes());
    let signature = mac.finalize().into_bytes();
    let signature_b64 = BASE64_URL.encode(signature);

    Ok(format!("{}.{}", message, signature_b64))
}

// MARK: - HTTP Handler

/// Generate LiveKit access token for voice chat
///
/// POST /api/v2/livekit/token
pub async fn generate_token(
    body: web::Json<LiveKitTokenRequest>,
) -> Result<HttpResponse> {
    let (url, api_key, api_secret) = get_livekit_config();

    if api_key.is_empty() || api_secret.is_empty() {
        error!("LiveKit credentials not configured");
        return Ok(HttpResponse::InternalServerError().json(ErrorResponse {
            error: "LiveKit not configured".to_string(),
            code: "LIVEKIT_NOT_CONFIGURED".to_string(),
        }));
    }

    info!(
        "Generating LiveKit token for room: {}, participant: {}, agent: {:?}",
        body.room_name, body.participant_name, body.agent_name
    );

    // Convert metadata to JSON string if present
    let metadata_str = body.metadata.as_ref().map(|m| m.to_string());

    match generate_livekit_token(
        &api_key,
        &api_secret,
        &body.room_name,
        &body.participant_name,
        body.agent_name.clone(),
        metadata_str,
    ) {
        Ok(token) => {
            info!("LiveKit token generated successfully");
            Ok(HttpResponse::Ok().json(LiveKitTokenResponse {
                token,
                url,
                room: body.room_name.clone(),
            }))
        }
        Err(e) => {
            error!("Failed to generate LiveKit token: {}", e);
            Ok(HttpResponse::InternalServerError().json(ErrorResponse {
                error: format!("Token generation failed: {}", e),
                code: "TOKEN_GENERATION_FAILED".to_string(),
            }))
        }
    }
}

/// Configure LiveKit routes
pub fn configure(cfg: &mut web::ServiceConfig) {
    cfg.service(
        web::resource("/api/v2/livekit/token")
            .route(web::post().to(generate_token))
    );
}
