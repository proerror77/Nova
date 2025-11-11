use super::ApiResponse;
use crate::models::NotificationChannel;
use crate::services::NotificationService;
/// Device token management handlers
use actix_web::{web, HttpResponse, Result as ActixResult};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use uuid::Uuid;

/// Register device token request
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct RegisterDevicePayload {
    pub user_id: Uuid,
    pub token: String,
    pub channel: String,     // "fcm", "apns", "websocket"
    pub device_type: String, // "ios", "android", "web"
}

/// Unregister device token request
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct UnregisterDevicePayload {
    pub user_id: Uuid,
    pub token: String,
}

/// Register a device token
///
/// POST /api/v1/devices/register
pub async fn register_device(
    service: web::Data<Arc<NotificationService>>,
    req: web::Json<RegisterDevicePayload>,
) -> ActixResult<HttpResponse> {
    let channel = parse_channel(&req.channel);

    match service
        .register_device_token(
            req.user_id,
            req.token.clone(),
            channel,
            req.device_type.clone(),
        )
        .await
    {
        Ok(device_id) => Ok(HttpResponse::Ok().json(ApiResponse::ok(serde_json::json!({
            "device_id": device_id,
            "success": true
        })))),
        Err(e) => Ok(HttpResponse::InternalServerError().json(ApiResponse::<String>::err(e))),
    }
}

/// Unregister a device token
///
/// POST /api/v1/devices/unregister
pub async fn unregister_device(
    service: web::Data<Arc<NotificationService>>,
    req: web::Json<UnregisterDevicePayload>,
) -> ActixResult<HttpResponse> {
    match service
        .unregister_device_token(req.user_id, &req.token)
        .await
    {
        Ok(_) => Ok(HttpResponse::Ok().json(ApiResponse::ok(serde_json::json!({
            "success": true
        })))),
        Err(e) => Ok(HttpResponse::InternalServerError().json(ApiResponse::<String>::err(e))),
    }
}

/// Get user's devices
///
/// GET /api/v1/devices/user/{user_id}
pub async fn get_user_devices(
    service: web::Data<Arc<NotificationService>>,
    path: web::Path<Uuid>,
) -> ActixResult<HttpResponse> {
    let user_id = path.into_inner();

    match service.get_user_devices(user_id).await {
        Ok(devices) => Ok(HttpResponse::Ok().json(ApiResponse::ok(devices))),
        Err(e) => Ok(HttpResponse::InternalServerError().json(ApiResponse::<String>::err(e))),
    }
}

/// Helper function to parse channel string
fn parse_channel(s: &str) -> NotificationChannel {
    match s.to_lowercase().as_str() {
        "fcm" => NotificationChannel::FCM,
        "apns" => NotificationChannel::APNs,
        "websocket" => NotificationChannel::WebSocket,
        "email" => NotificationChannel::Email,
        "sms" => NotificationChannel::SMS,
        _ => NotificationChannel::FCM,
    }
}

/// Register routes
pub fn register_routes(cfg: &mut web::ServiceConfig) {
    cfg.service(
        web::scope("/api/v1/devices")
            .route("/register", web::post().to(register_device))
            .route("/unregister", web::post().to(unregister_device))
            .route("/user/{user_id}", web::get().to(get_user_devices)),
    );
}
