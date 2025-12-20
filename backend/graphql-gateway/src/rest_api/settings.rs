/// User Settings API endpoints
///
/// GET /api/v2/settings - Get user settings
/// PUT /api/v2/settings - Update user settings
use actix_web::{web, HttpMessage, HttpRequest, HttpResponse, Result};
use serde::{Deserialize, Serialize};
use tracing::{error, info};

use crate::clients::proto::auth::{
    DmPermission, GetUserSettingsRequest, PrivacyLevel, UpdateUserSettingsRequest,
};
use crate::clients::ServiceClients;
use crate::middleware::jwt::AuthenticatedUser;
use crate::rest_api::models::ErrorResponse;

// ============================================================================
// Enum Conversion Helpers
// ============================================================================

/// Convert DmPermission enum (i32) to display string
fn dm_permission_to_string(dm_permission: i32) -> String {
    match DmPermission::try_from(dm_permission) {
        Ok(DmPermission::Anyone) => "anyone".to_string(),
        Ok(DmPermission::Followers) => "followers".to_string(),
        Ok(DmPermission::Mutuals) => "mutuals".to_string(),
        Ok(DmPermission::Nobody) => "nobody".to_string(),
        Ok(DmPermission::Unspecified) | Err(_) => "mutuals".to_string(), // Default to mutuals
    }
}

/// Convert string to DmPermission enum (i32)
fn string_to_dm_permission(s: Option<&String>) -> Option<i32> {
    s.map(|s| match s.to_lowercase().as_str() {
        "anyone" => DmPermission::Anyone as i32,
        "followers" => DmPermission::Followers as i32,
        "mutuals" => DmPermission::Mutuals as i32,
        "nobody" => DmPermission::Nobody as i32,
        _ => DmPermission::Mutuals as i32, // Default to mutuals
    })
}

/// Convert PrivacyLevel enum (i32) to display string
fn privacy_level_to_string(privacy_level: i32) -> String {
    match PrivacyLevel::try_from(privacy_level) {
        Ok(PrivacyLevel::Public) => "public".to_string(),
        Ok(PrivacyLevel::FriendsOnly) => "friends_only".to_string(),
        Ok(PrivacyLevel::Private) => "private".to_string(),
        Ok(PrivacyLevel::Unspecified) | Err(_) => "public".to_string(), // Default to public
    }
}

/// Convert string to PrivacyLevel enum (i32)
fn string_to_privacy_level(s: Option<&String>) -> Option<i32> {
    s.map(|s| match s.to_lowercase().as_str() {
        "public" => PrivacyLevel::Public as i32,
        "friends_only" | "friends" => PrivacyLevel::FriendsOnly as i32,
        "private" => PrivacyLevel::Private as i32,
        _ => PrivacyLevel::Public as i32, // Default to public
    })
}

// ============================================================================
// Response Models
// ============================================================================

#[derive(Debug, Serialize)]
pub struct UserSettingsResponse {
    pub user_id: String,
    pub dm_permission: String,
    pub email_notifications: bool,
    pub push_notifications: bool,
    pub marketing_emails: bool,
    pub timezone: String,
    pub language: String,
    pub dark_mode: bool,
    pub privacy_level: String,
    pub show_online_status: bool,
}

#[derive(Debug, Deserialize)]
pub struct UpdateSettingsRequest {
    pub dm_permission: Option<String>,
    pub email_notifications: Option<bool>,
    pub push_notifications: Option<bool>,
    pub marketing_emails: Option<bool>,
    pub timezone: Option<String>,
    pub language: Option<String>,
    pub dark_mode: Option<bool>,
    pub privacy_level: Option<String>,
    pub show_online_status: Option<bool>,
}

// ============================================================================
// Handlers
// ============================================================================

/// GET /api/v2/settings
/// Get current user's settings
pub async fn get_settings(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let user = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(u) => u,
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    let user_id = user.0.to_string();
    info!(user_id = %user_id, "GET /api/v2/settings");

    let mut auth_client = clients.auth_client();

    let grpc_request = tonic::Request::new(GetUserSettingsRequest {
        user_id: user_id.clone(),
    });

    match auth_client.get_user_settings(grpc_request).await {
        Ok(response) => {
            let inner = response.into_inner();

            if let Some(settings) = inner.settings {
                Ok(HttpResponse::Ok().json(UserSettingsResponse {
                    user_id: settings.user_id,
                    dm_permission: dm_permission_to_string(settings.dm_permission),
                    email_notifications: settings.email_notifications,
                    push_notifications: settings.push_notifications,
                    marketing_emails: settings.marketing_emails,
                    timezone: settings.timezone,
                    language: settings.language,
                    dark_mode: settings.dark_mode,
                    privacy_level: privacy_level_to_string(settings.privacy_level),
                    show_online_status: settings.show_online_status,
                }))
            } else if let Some(err) = inner.error {
                error!(error = %err.message, "Failed to get user settings");
                Ok(
                    HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                        "Failed to get settings",
                        &err.message,
                    )),
                )
            } else {
                // Return default settings if none exist
                // P1: Default to "mutuals" (more restrictive) for security
                Ok(HttpResponse::Ok().json(UserSettingsResponse {
                    user_id: user_id.clone(),
                    dm_permission: "mutuals".to_string(),
                    email_notifications: true,
                    push_notifications: true,
                    marketing_emails: false,
                    timezone: "UTC".to_string(),
                    language: "en".to_string(),
                    dark_mode: false,
                    privacy_level: "public".to_string(),
                    show_online_status: true,
                }))
            }
        }
        Err(status) => {
            error!(error = %status, "Failed to get user settings");
            Ok(
                HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Failed to get settings",
                    status.message(),
                )),
            )
        }
    }
}

/// PUT /api/v2/settings
/// Update current user's settings
pub async fn update_settings(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
    body: web::Json<UpdateSettingsRequest>,
) -> Result<HttpResponse> {
    let user = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(u) => u,
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    let user_id = user.0.to_string();
    info!(user_id = %user_id, "PUT /api/v2/settings");

    let mut auth_client = clients.auth_client();

    let grpc_request = tonic::Request::new(UpdateUserSettingsRequest {
        user_id: user_id.clone(),
        dm_permission: string_to_dm_permission(body.dm_permission.as_ref()),
        email_notifications: body.email_notifications,
        push_notifications: body.push_notifications,
        marketing_emails: body.marketing_emails,
        timezone: body.timezone.clone(),
        language: body.language.clone(),
        dark_mode: body.dark_mode,
        privacy_level: string_to_privacy_level(body.privacy_level.as_ref()),
        show_online_status: body.show_online_status,
    });

    match auth_client.update_user_settings(grpc_request).await {
        Ok(response) => {
            let inner = response.into_inner();

            if let Some(settings) = inner.settings {
                info!(user_id = %user_id, "User settings updated successfully");
                Ok(HttpResponse::Ok().json(UserSettingsResponse {
                    user_id: settings.user_id,
                    dm_permission: dm_permission_to_string(settings.dm_permission),
                    email_notifications: settings.email_notifications,
                    push_notifications: settings.push_notifications,
                    marketing_emails: settings.marketing_emails,
                    timezone: settings.timezone,
                    language: settings.language,
                    dark_mode: settings.dark_mode,
                    privacy_level: privacy_level_to_string(settings.privacy_level),
                    show_online_status: settings.show_online_status,
                }))
            } else if let Some(err) = inner.error {
                error!(error = %err.message, "Failed to update user settings");
                Ok(
                    HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                        "Failed to update settings",
                        &err.message,
                    )),
                )
            } else {
                Ok(
                    HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                        "Failed to update settings",
                        "Unexpected empty response",
                    )),
                )
            }
        }
        Err(status) => {
            error!(error = %status, "Failed to update user settings");
            Ok(
                HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Failed to update settings",
                    status.message(),
                )),
            )
        }
    }
}
