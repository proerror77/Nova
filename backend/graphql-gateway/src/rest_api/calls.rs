//! Video/Voice Call API Proxy
//!
//! Proxies video call requests to realtime-chat-service REST API.
//! These endpoints handle WebRTC signaling for voice and video calls.

use actix_web::{get, post, web, HttpMessage, HttpRequest, HttpResponse};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::sync::OnceLock;
use tracing::error;

use crate::middleware::jwt::AuthenticatedUser;

/// HTTP client for proxying requests to realtime-chat-service
static HTTP_CLIENT: OnceLock<Client> = OnceLock::new();

fn get_client() -> &'static Client {
    HTTP_CLIENT.get_or_init(|| {
        Client::builder()
            .timeout(std::time::Duration::from_secs(30))
            .build()
            .expect("Failed to create HTTP client")
    })
}

/// Get the realtime-chat-service base URL
fn chat_service_url() -> String {
    std::env::var("REALTIME_CHAT_SERVICE_URL")
        .unwrap_or_else(|_| "http://realtime-chat-service:8080".to_string())
}

// ============================================================================
// Request/Response Models
// ============================================================================

#[derive(Debug, Serialize, Deserialize)]
pub struct InitiateCallRequest {
    pub is_video: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct IceCandidateRequest {
    pub call_id: String,
    pub candidate: String,
}

// ============================================================================
// Proxy Endpoints
// ============================================================================

/// POST /conversations/{conversation_id}/calls - Initiate a call
#[post("/conversations/{conversation_id}/calls")]
pub async fn initiate_call(
    req: HttpRequest,
    path: web::Path<String>,
    body: web::Json<InitiateCallRequest>,
) -> HttpResponse {
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => {
            return HttpResponse::Unauthorized().json(serde_json::json!({"error": "Unauthorized"}))
        }
    };

    let conversation_id = path.into_inner();
    let url = format!(
        "{}/conversations/{}/calls",
        chat_service_url(),
        conversation_id
    );

    proxy_post_request(&url, &user_id, &body.into_inner()).await
}

/// POST /calls/{call_id}/answer - Answer a call
#[post("/calls/{call_id}/answer")]
pub async fn answer_call(req: HttpRequest, path: web::Path<String>) -> HttpResponse {
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => {
            return HttpResponse::Unauthorized().json(serde_json::json!({"error": "Unauthorized"}))
        }
    };

    let call_id = path.into_inner();
    let url = format!("{}/calls/{}/answer", chat_service_url(), call_id);

    proxy_post_request(&url, &user_id, &serde_json::json!({})).await
}

/// POST /calls/{call_id}/reject - Reject a call
#[post("/calls/{call_id}/reject")]
pub async fn reject_call(req: HttpRequest, path: web::Path<String>) -> HttpResponse {
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => {
            return HttpResponse::Unauthorized().json(serde_json::json!({"error": "Unauthorized"}))
        }
    };

    let call_id = path.into_inner();
    let url = format!("{}/calls/{}/reject", chat_service_url(), call_id);

    proxy_post_request(&url, &user_id, &serde_json::json!({})).await
}

/// POST /calls/{call_id}/end - End a call
#[post("/calls/{call_id}/end")]
pub async fn end_call(req: HttpRequest, path: web::Path<String>) -> HttpResponse {
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => {
            return HttpResponse::Unauthorized().json(serde_json::json!({"error": "Unauthorized"}))
        }
    };

    let call_id = path.into_inner();
    let url = format!("{}/calls/{}/end", chat_service_url(), call_id);

    proxy_post_request(&url, &user_id, &serde_json::json!({})).await
}

/// POST /calls/ice-candidate - Send ICE candidate
#[post("/calls/ice-candidate")]
pub async fn send_ice_candidate(
    req: HttpRequest,
    body: web::Json<IceCandidateRequest>,
) -> HttpResponse {
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => {
            return HttpResponse::Unauthorized().json(serde_json::json!({"error": "Unauthorized"}))
        }
    };

    let url = format!("{}/calls/ice-candidate", chat_service_url());

    proxy_post_request(&url, &user_id, &body.into_inner()).await
}

/// GET /calls/ice-servers - Get ICE server configuration
#[get("/calls/ice-servers")]
pub async fn get_ice_servers(req: HttpRequest) -> HttpResponse {
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => {
            return HttpResponse::Unauthorized().json(serde_json::json!({"error": "Unauthorized"}))
        }
    };

    let url = format!("{}/calls/ice-servers", chat_service_url());

    proxy_get_request(&url, &user_id).await
}

// ============================================================================
// Proxy Helpers
// ============================================================================

async fn proxy_post_request<T: Serialize>(url: &str, user_id: &str, body: &T) -> HttpResponse {
    let client = get_client();

    match client
        .post(url)
        .header("X-User-Id", user_id)
        .header("Content-Type", "application/json")
        .json(body)
        .send()
        .await
    {
        Ok(resp) => {
            let status = resp.status();
            match resp.bytes().await {
                Ok(bytes) => HttpResponse::build(
                    actix_web::http::StatusCode::from_u16(status.as_u16())
                        .unwrap_or(actix_web::http::StatusCode::INTERNAL_SERVER_ERROR),
                )
                .content_type("application/json")
                .body(bytes.to_vec()),
                Err(e) => {
                    error!("Failed to read response body: {}", e);
                    HttpResponse::InternalServerError()
                        .json(serde_json::json!({"error": "Failed to read response"}))
                }
            }
        }
        Err(e) => {
            error!("Proxy request failed: {}", e);
            HttpResponse::ServiceUnavailable()
                .json(serde_json::json!({"error": "Service unavailable"}))
        }
    }
}

async fn proxy_get_request(url: &str, user_id: &str) -> HttpResponse {
    let client = get_client();

    match client.get(url).header("X-User-Id", user_id).send().await {
        Ok(resp) => {
            let status = resp.status();
            match resp.bytes().await {
                Ok(bytes) => HttpResponse::build(
                    actix_web::http::StatusCode::from_u16(status.as_u16())
                        .unwrap_or(actix_web::http::StatusCode::INTERNAL_SERVER_ERROR),
                )
                .content_type("application/json")
                .body(bytes.to_vec()),
                Err(e) => {
                    error!("Failed to read response body: {}", e);
                    HttpResponse::InternalServerError()
                        .json(serde_json::json!({"error": "Failed to read response"}))
                }
            }
        }
        Err(e) => {
            error!("Proxy request failed: {}", e);
            HttpResponse::ServiceUnavailable()
                .json(serde_json::json!({"error": "Service unavailable"}))
        }
    }
}
