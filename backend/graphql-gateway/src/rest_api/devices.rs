/// Device Management API endpoints
///
/// GET /api/v2/devices - List user's devices
/// GET /api/v2/devices/current - Get current device info
/// POST /api/v2/devices/logout - Logout device(s)
use actix_web::{web, HttpMessage, HttpRequest, HttpResponse, Result};
use serde::{Deserialize, Serialize};
use tracing::{error, info};

use crate::clients::proto::auth::{
    GetCurrentDeviceRequest, ListDevicesRequest, LogoutDeviceRequest,
};
use crate::clients::ServiceClients;
use crate::middleware::jwt::AuthenticatedUser;
use crate::rest_api::models::ErrorResponse;

// ============================================================================
// Response Models
// ============================================================================

#[derive(Debug, Serialize)]
pub struct DeviceResponse {
    pub id: String,
    pub name: String,
    pub device_type: String,
    pub os: String,
    pub last_active: i64,
    pub is_current: bool,
}

#[derive(Debug, Serialize)]
pub struct ListDevicesResponse {
    pub devices: Vec<DeviceResponse>,
    pub total: i32,
}

#[derive(Debug, Serialize)]
pub struct CurrentDeviceResponse {
    pub device: Option<DeviceResponse>,
}

#[derive(Debug, Serialize)]
pub struct LogoutDeviceResponseBody {
    pub success: bool,
}

// ============================================================================
// Request Models
// ============================================================================

#[derive(Debug, Deserialize)]
pub struct ListDevicesQuery {
    pub limit: Option<i32>,
    pub offset: Option<i32>,
}

#[derive(Debug, Deserialize)]
pub struct LogoutDeviceRequestBody {
    pub device_id: Option<String>,
    pub all: Option<bool>,
}

// ============================================================================
// Handlers
// ============================================================================

/// GET /api/v2/devices
/// List current user's devices (active sessions)
pub async fn list_devices(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
    query: web::Query<ListDevicesQuery>,
) -> Result<HttpResponse> {
    let user = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(u) => u,
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    let user_id = user.0.to_string();
    info!(user_id = %user_id, "GET /api/v2/devices");

    let mut auth_client = clients.auth_client();

    let grpc_request = tonic::Request::new(ListDevicesRequest {
        user_id: user_id.clone(),
        limit: query.limit.unwrap_or(20),
        offset: query.offset.unwrap_or(0),
    });

    match auth_client.list_devices(grpc_request).await {
        Ok(response) => {
            let inner = response.into_inner();
            let devices: Vec<DeviceResponse> = inner
                .devices
                .into_iter()
                .map(|d| DeviceResponse {
                    id: d.id,
                    name: d.name,
                    device_type: d.device_type,
                    os: d.os,
                    last_active: d.last_active,
                    is_current: d.is_current,
                })
                .collect();

            Ok(HttpResponse::Ok().json(ListDevicesResponse {
                devices,
                total: inner.total,
            }))
        }
        Err(status) => {
            error!(error = %status, "Failed to list devices");
            Ok(
                HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Failed to list devices",
                    status.message(),
                )),
            )
        }
    }
}

/// GET /api/v2/devices/current
/// Get current device info
pub async fn get_current_device(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let user = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(u) => u,
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    let user_id = user.0.to_string();
    info!(user_id = %user_id, "GET /api/v2/devices/current");

    let mut auth_client = clients.auth_client();

    // Get device_id from request header if available
    let device_id = req
        .headers()
        .get("X-Device-ID")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string());

    let grpc_request = tonic::Request::new(GetCurrentDeviceRequest {
        user_id: user_id.clone(),
        device_id,
    });

    match auth_client.get_current_device(grpc_request).await {
        Ok(response) => {
            let inner = response.into_inner();
            let device = inner.device.map(|d| DeviceResponse {
                id: d.id,
                name: d.name,
                device_type: d.device_type,
                os: d.os,
                last_active: d.last_active,
                is_current: d.is_current,
            });

            Ok(HttpResponse::Ok().json(CurrentDeviceResponse { device }))
        }
        Err(status) => {
            error!(error = %status, "Failed to get current device");
            Ok(
                HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Failed to get current device",
                    status.message(),
                )),
            )
        }
    }
}

/// POST /api/v2/devices/logout
/// Logout a specific device or all devices
pub async fn logout_device(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
    body: web::Json<LogoutDeviceRequestBody>,
) -> Result<HttpResponse> {
    let user = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(u) => u,
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    let user_id = user.0.to_string();
    let device_id = body.device_id.clone().unwrap_or_default();
    let all = body.all.unwrap_or(false);

    info!(
        user_id = %user_id,
        device_id = %device_id,
        all = %all,
        "POST /api/v2/devices/logout"
    );

    // Validate request - must specify either device_id or all=true
    if device_id.is_empty() && !all {
        return Ok(HttpResponse::BadRequest().json(ErrorResponse::with_message(
            "Invalid request",
            "Must specify either device_id or all=true",
        )));
    }

    let mut auth_client = clients.auth_client();

    let grpc_request = tonic::Request::new(LogoutDeviceRequest {
        user_id: user_id.clone(),
        device_id,
        all,
    });

    match auth_client.logout_device(grpc_request).await {
        Ok(response) => {
            let inner = response.into_inner();
            info!(
                user_id = %user_id,
                success = %inner.success,
                "Device logout completed"
            );
            Ok(HttpResponse::Ok().json(LogoutDeviceResponseBody {
                success: inner.success,
            }))
        }
        Err(status) => {
            error!(error = %status, "Failed to logout device");
            Ok(
                HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Failed to logout device",
                    status.message(),
                )),
            )
        }
    }
}
