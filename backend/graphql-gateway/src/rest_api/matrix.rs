/// Matrix API Proxy Module
///
/// Proxies Matrix E2EE integration requests to realtime-chat-service
/// Endpoints:
/// - POST /api/v2/matrix/token - Get Matrix access token for authenticated user
/// - GET  /api/v2/matrix/config - Get Matrix configuration
/// - GET  /api/v2/matrix/rooms - Get all room mappings
/// - POST /api/v2/matrix/rooms - Save room mapping
/// - GET  /api/v2/matrix/rooms/{conversation_id} - Get room mapping by conversation
/// - GET  /api/v2/matrix/conversations - Get conversation by room_id query param
/// - GET  /api/v2/matrix/encryption/status - Get encryption status
/// - GET  /api/v2/matrix/conversations/{conversation_id}/room-status - Get room status
use actix_web::{get, post, web, HttpMessage, HttpRequest, HttpResponse};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::env;
use std::sync::OnceLock;
use tracing::{error, info, warn};

use crate::middleware::jwt::AuthenticatedUser;

// HTTP client singleton for Matrix API proxy
static HTTP_CLIENT: OnceLock<Client> = OnceLock::new();

fn get_http_client() -> &'static Client {
    HTTP_CLIENT.get_or_init(|| {
        Client::builder()
            .timeout(std::time::Duration::from_secs(30))
            .connect_timeout(std::time::Duration::from_secs(10))
            .build()
            .expect("Failed to create HTTP client for Matrix proxy")
    })
}

/// Get the chat service HTTP URL for Matrix API proxying
fn get_chat_service_url() -> String {
    env::var("CHAT_SERVICE_HTTP_URL").unwrap_or_else(|_| {
        // Fallback to default realtime-chat-service HTTP URL (port 8080 in K8s)
        "http://realtime-chat-service:8080".to_string()
    })
}

// =============================================================================
// Request/Response Types (matching realtime-chat-service)
// =============================================================================

#[derive(Debug, Serialize, Deserialize)]
pub struct MatrixTokenResponse {
    pub access_token: String,
    pub matrix_user_id: String,
    pub device_id: String,
    pub homeserver_url: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct MatrixConfigResponse {
    pub enabled: bool,
    pub homeserver_url: Option<String>,
    pub e2ee_enabled: bool,
    pub voip_enabled: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct RoomMappingResponse {
    pub room_id: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ConversationMappingResponse {
    pub conversation_id: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct AllMappingsResponse {
    pub mappings: Vec<MappingEntry>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct MappingEntry {
    pub conversation_id: String,
    pub room_id: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SaveRoomMappingRequest {
    pub conversation_id: String,
    pub room_id: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct EncryptionStatusResponse {
    pub e2ee_enabled: bool,
    pub backup_enabled: bool,
    pub recovery_key_status: String,
    pub device_verified: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct RoomStatusResponse {
    pub room_id: Option<String>,
    pub is_encrypted: bool,
    pub members_synced: i32,
    pub matrix_enabled: bool,
}

// =============================================================================
// Matrix API Handlers (Proxy to realtime-chat-service)
// =============================================================================

/// Request body for Matrix token endpoint
#[derive(Debug, Serialize, Deserialize, Default)]
pub struct MatrixTokenRequest {
    /// Optional user_id (usually extracted from JWT, not from body)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub user_id: Option<String>,
    /// Device ID to bind the Matrix session to (for seamless iOS E2EE)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub device_id: Option<String>,
}

/// POST /api/v2/matrix/token
/// Get Matrix access token for the authenticated user
#[post("/api/v2/matrix/token")]
pub async fn get_matrix_token(
    http_req: HttpRequest,
    body: Option<web::Json<MatrixTokenRequest>>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let base_url = get_chat_service_url();
    let url = format!("{}/api/v2/matrix/token", base_url);

    // Extract device_id from request body if provided
    let device_id = body.as_ref().and_then(|b| b.device_id.clone());

    info!(
        user_id = %user_id,
        device_id = ?device_id,
        "Proxying Matrix token request"
    );

    // Forward the request with user authentication and device_id
    let client = get_http_client();

    // Build the request body, including device_id if provided by client
    let request_body = MatrixTokenRequest {
        user_id: Some(user_id.clone()),
        device_id,
    };

    match client
        .post(&url)
        .header("X-User-Id", &user_id)
        .header("Content-Type", "application/json")
        .json(&request_body)
        .send()
        .await
    {
        Ok(resp) => {
            let status = resp.status();
            match resp.text().await {
                Ok(body) => {
                    if status.is_success() {
                        HttpResponse::Ok()
                            .content_type("application/json")
                            .body(body)
                    } else {
                        warn!(status = %status, "Matrix token request failed");
                        HttpResponse::build(
                            actix_web::http::StatusCode::from_u16(status.as_u16())
                                .unwrap_or(actix_web::http::StatusCode::INTERNAL_SERVER_ERROR),
                        )
                        .content_type("application/json")
                        .body(body)
                    }
                }
                Err(e) => {
                    error!(error = %e, "Failed to read Matrix token response");
                    HttpResponse::InternalServerError().json(serde_json::json!({
                        "error": "Failed to read response from Matrix service"
                    }))
                }
            }
        }
        Err(e) => {
            error!(error = %e, url = %url, "Failed to proxy Matrix token request");
            HttpResponse::ServiceUnavailable().json(serde_json::json!({
                "error": "Matrix service unavailable",
                "details": e.to_string()
            }))
        }
    }
}

/// GET /api/v2/matrix/config
/// Get Matrix configuration (homeserver URL, enabled status, etc.)
#[get("/api/v2/matrix/config")]
pub async fn get_matrix_config(http_req: HttpRequest) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let base_url = get_chat_service_url();
    let url = format!("{}/api/v2/matrix/config", base_url);

    let client = get_http_client();
    match client.get(&url).header("X-User-Id", &user_id).send().await {
        Ok(resp) => {
            let status = resp.status();
            match resp.text().await {
                Ok(body) => {
                    if status.is_success() {
                        HttpResponse::Ok()
                            .content_type("application/json")
                            .body(body)
                    } else {
                        HttpResponse::build(
                            actix_web::http::StatusCode::from_u16(status.as_u16())
                                .unwrap_or(actix_web::http::StatusCode::INTERNAL_SERVER_ERROR),
                        )
                        .content_type("application/json")
                        .body(body)
                    }
                }
                Err(e) => {
                    error!(error = %e, "Failed to read Matrix config response");
                    HttpResponse::InternalServerError().json(serde_json::json!({
                        "error": "Failed to read response from Matrix service"
                    }))
                }
            }
        }
        Err(e) => {
            error!(error = %e, url = %url, "Failed to proxy Matrix config request");
            HttpResponse::ServiceUnavailable().json(serde_json::json!({
                "error": "Matrix service unavailable"
            }))
        }
    }
}

/// GET /api/v2/matrix/rooms
/// Get all room mappings for the current user
#[get("/api/v2/matrix/rooms")]
pub async fn get_all_room_mappings(http_req: HttpRequest) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let base_url = get_chat_service_url();
    let url = format!("{}/api/v2/matrix/rooms", base_url);

    let client = get_http_client();
    match client.get(&url).header("X-User-Id", &user_id).send().await {
        Ok(resp) => {
            let status = resp.status();
            match resp.text().await {
                Ok(body) => {
                    if status.is_success() {
                        HttpResponse::Ok()
                            .content_type("application/json")
                            .body(body)
                    } else {
                        HttpResponse::build(
                            actix_web::http::StatusCode::from_u16(status.as_u16())
                                .unwrap_or(actix_web::http::StatusCode::INTERNAL_SERVER_ERROR),
                        )
                        .content_type("application/json")
                        .body(body)
                    }
                }
                Err(e) => {
                    error!(error = %e, "Failed to read Matrix rooms response");
                    HttpResponse::InternalServerError().finish()
                }
            }
        }
        Err(e) => {
            error!(error = %e, "Failed to proxy Matrix rooms request");
            HttpResponse::ServiceUnavailable().finish()
        }
    }
}

/// POST /api/v2/matrix/rooms
/// Save a new room mapping
#[post("/api/v2/matrix/rooms")]
pub async fn save_room_mapping(
    http_req: HttpRequest,
    body: web::Json<SaveRoomMappingRequest>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let base_url = get_chat_service_url();
    let url = format!("{}/api/v2/matrix/rooms", base_url);

    let client = get_http_client();
    match client
        .post(&url)
        .header("X-User-Id", &user_id)
        .header("Content-Type", "application/json")
        .json(&body.into_inner())
        .send()
        .await
    {
        Ok(resp) => {
            let status = resp.status();
            match resp.text().await {
                Ok(body) => {
                    if status.is_success() {
                        HttpResponse::Created()
                            .content_type("application/json")
                            .body(body)
                    } else {
                        HttpResponse::build(
                            actix_web::http::StatusCode::from_u16(status.as_u16())
                                .unwrap_or(actix_web::http::StatusCode::INTERNAL_SERVER_ERROR),
                        )
                        .content_type("application/json")
                        .body(body)
                    }
                }
                Err(e) => {
                    error!(error = %e, "Failed to read save room mapping response");
                    HttpResponse::InternalServerError().finish()
                }
            }
        }
        Err(e) => {
            error!(error = %e, "Failed to proxy save room mapping request");
            HttpResponse::ServiceUnavailable().finish()
        }
    }
}

/// GET /api/v2/matrix/rooms/{conversation_id}
/// Get Matrix room ID for a Nova conversation
#[get("/api/v2/matrix/rooms/{conversation_id}")]
pub async fn get_room_mapping(http_req: HttpRequest, path: web::Path<String>) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let conversation_id = path.into_inner();
    let base_url = get_chat_service_url();
    let url = format!("{}/api/v2/matrix/rooms/{}", base_url, conversation_id);

    let client = get_http_client();
    match client.get(&url).header("X-User-Id", &user_id).send().await {
        Ok(resp) => {
            let status = resp.status();
            match resp.text().await {
                Ok(body) => {
                    if status.is_success() {
                        HttpResponse::Ok()
                            .content_type("application/json")
                            .body(body)
                    } else {
                        HttpResponse::build(
                            actix_web::http::StatusCode::from_u16(status.as_u16())
                                .unwrap_or(actix_web::http::StatusCode::INTERNAL_SERVER_ERROR),
                        )
                        .content_type("application/json")
                        .body(body)
                    }
                }
                Err(e) => {
                    error!(error = %e, "Failed to read room mapping response");
                    HttpResponse::InternalServerError().finish()
                }
            }
        }
        Err(e) => {
            error!(error = %e, "Failed to proxy room mapping request");
            HttpResponse::ServiceUnavailable().finish()
        }
    }
}

/// GET /api/v2/matrix/conversations
/// Get Nova conversation ID for a Matrix room ID (query param: room_id)
#[derive(Debug, Deserialize)]
pub struct ConversationQuery {
    pub room_id: String,
}

#[get("/api/v2/matrix/conversations")]
pub async fn get_conversation_mapping(
    http_req: HttpRequest,
    query: web::Query<ConversationQuery>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let base_url = get_chat_service_url();
    let url = format!(
        "{}/api/v2/matrix/conversations?room_id={}",
        base_url,
        urlencoding::encode(&query.room_id)
    );

    let client = get_http_client();
    match client.get(&url).header("X-User-Id", &user_id).send().await {
        Ok(resp) => {
            let status = resp.status();
            match resp.text().await {
                Ok(body) => {
                    if status.is_success() {
                        HttpResponse::Ok()
                            .content_type("application/json")
                            .body(body)
                    } else {
                        HttpResponse::build(
                            actix_web::http::StatusCode::from_u16(status.as_u16())
                                .unwrap_or(actix_web::http::StatusCode::INTERNAL_SERVER_ERROR),
                        )
                        .content_type("application/json")
                        .body(body)
                    }
                }
                Err(e) => {
                    error!(error = %e, "Failed to read conversation mapping response");
                    HttpResponse::InternalServerError().finish()
                }
            }
        }
        Err(e) => {
            error!(error = %e, "Failed to proxy conversation mapping request");
            HttpResponse::ServiceUnavailable().finish()
        }
    }
}

/// GET /api/v2/matrix/encryption/status
/// Get encryption status for the current user
#[get("/api/v2/matrix/encryption/status")]
pub async fn get_encryption_status(http_req: HttpRequest) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let base_url = get_chat_service_url();
    let url = format!("{}/api/v2/matrix/encryption/status", base_url);

    let client = get_http_client();
    match client.get(&url).header("X-User-Id", &user_id).send().await {
        Ok(resp) => {
            let status = resp.status();
            match resp.text().await {
                Ok(body) => {
                    if status.is_success() {
                        HttpResponse::Ok()
                            .content_type("application/json")
                            .body(body)
                    } else {
                        HttpResponse::build(
                            actix_web::http::StatusCode::from_u16(status.as_u16())
                                .unwrap_or(actix_web::http::StatusCode::INTERNAL_SERVER_ERROR),
                        )
                        .content_type("application/json")
                        .body(body)
                    }
                }
                Err(e) => {
                    error!(error = %e, "Failed to read encryption status response");
                    HttpResponse::InternalServerError().finish()
                }
            }
        }
        Err(e) => {
            error!(error = %e, "Failed to proxy encryption status request");
            HttpResponse::ServiceUnavailable().finish()
        }
    }
}

/// GET /api/v2/matrix/conversations/{conversation_id}/room-status
/// Get detailed Matrix room status for a conversation
#[get("/api/v2/matrix/conversations/{conversation_id}/room-status")]
pub async fn get_room_status(http_req: HttpRequest, path: web::Path<String>) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return HttpResponse::Unauthorized().finish(),
    };

    let conversation_id = path.into_inner();
    let base_url = get_chat_service_url();
    let url = format!(
        "{}/api/v2/matrix/conversations/{}/room-status",
        base_url, conversation_id
    );

    let client = get_http_client();
    match client.get(&url).header("X-User-Id", &user_id).send().await {
        Ok(resp) => {
            let status = resp.status();
            match resp.text().await {
                Ok(body) => {
                    if status.is_success() {
                        HttpResponse::Ok()
                            .content_type("application/json")
                            .body(body)
                    } else {
                        HttpResponse::build(
                            actix_web::http::StatusCode::from_u16(status.as_u16())
                                .unwrap_or(actix_web::http::StatusCode::INTERNAL_SERVER_ERROR),
                        )
                        .content_type("application/json")
                        .body(body)
                    }
                }
                Err(e) => {
                    error!(error = %e, "Failed to read room status response");
                    HttpResponse::InternalServerError().finish()
                }
            }
        }
        Err(e) => {
            error!(error = %e, "Failed to proxy room status request");
            HttpResponse::ServiceUnavailable().finish()
        }
    }
}
