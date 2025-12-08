/// Identity Service API endpoints - Password Management
///
/// POST /api/v2/identity/password/change - Change password (authenticated)
/// POST /api/v2/identity/password/reset/request - Request password reset (public)
/// POST /api/v2/identity/password/reset - Reset password with token (public)
use actix_web::{web, HttpMessage, HttpRequest, HttpResponse, Result};
use serde::Deserialize;
use tracing::{error, info};

use crate::clients::proto::identity::{
    ChangePasswordRequest, RequestPasswordResetRequest, ResetPasswordRequest,
};
use crate::clients::ServiceClients;
use crate::middleware::jwt::AuthenticatedUser;
use crate::rest_api::models::ErrorResponse;

// ============================================================================
// Request Models
// ============================================================================

#[derive(Debug, Deserialize)]
pub struct ChangePasswordBody {
    pub old_password: String,
    pub new_password: String,
}

#[derive(Debug, Deserialize)]
pub struct RequestPasswordResetBody {
    pub email: String,
}

#[derive(Debug, Deserialize)]
pub struct ResetPasswordBody {
    pub reset_token: String,
    pub new_password: String,
}

// ============================================================================
// Handlers
// ============================================================================

/// POST /api/v2/identity/password/change
/// Change password for authenticated user
pub async fn change_password(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
    body: web::Json<ChangePasswordBody>,
) -> Result<HttpResponse> {
    let user = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(u) => u,
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    let user_id = user.0.to_string();
    info!(user_id = %user_id, "POST /api/v2/identity/password/change");

    // Validate new password
    if body.new_password.len() < 8 {
        return Ok(HttpResponse::BadRequest().json(ErrorResponse::with_message(
            "Invalid password",
            "Password must be at least 8 characters",
        )));
    }

    let mut identity_client = clients.identity_client();

    let grpc_request = tonic::Request::new(ChangePasswordRequest {
        user_id: user_id.clone(),
        old_password: body.old_password.clone(),
        new_password: body.new_password.clone(),
    });

    match identity_client.change_password(grpc_request).await {
        Ok(_) => {
            info!(user_id = %user_id, "Password changed successfully");
            Ok(HttpResponse::Ok().json(serde_json::json!({
                "success": true,
                "message": "Password changed successfully"
            })))
        }
        Err(status) => {
            error!(user_id = %user_id, error = %status, "Failed to change password");

            let response = match status.code() {
                tonic::Code::InvalidArgument => HttpResponse::BadRequest().json(
                    ErrorResponse::with_message("Invalid password", status.message()),
                ),
                tonic::Code::Unauthenticated => HttpResponse::Unauthorized().json(
                    ErrorResponse::with_message("Current password is incorrect", status.message()),
                ),
                _ => HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Failed to change password",
                    status.message(),
                )),
            };

            Ok(response)
        }
    }
}

/// POST /api/v2/identity/password/reset/request
/// Request password reset email (public endpoint)
pub async fn request_password_reset(
    clients: web::Data<ServiceClients>,
    body: web::Json<RequestPasswordResetBody>,
) -> Result<HttpResponse> {
    info!(email = %body.email, "POST /api/v2/identity/password/reset/request");

    // Basic email validation
    if !body.email.contains('@') || body.email.len() < 5 {
        return Ok(HttpResponse::BadRequest().json(ErrorResponse::with_message(
            "Invalid email",
            "Please provide a valid email address",
        )));
    }

    let mut identity_client = clients.identity_client();

    let grpc_request = tonic::Request::new(RequestPasswordResetRequest {
        email: body.email.clone(),
    });

    match identity_client.request_password_reset(grpc_request).await {
        Ok(_) => {
            // Always return success to prevent email enumeration
            info!(email = %body.email, "Password reset requested");
            Ok(HttpResponse::Ok().json(serde_json::json!({
                "success": true,
                "message": "If an account with that email exists, a password reset link has been sent"
            })))
        }
        Err(status) => {
            // Log error but still return success to prevent enumeration
            error!(email = %body.email, error = %status, "Password reset request failed");

            // Return success anyway to prevent email enumeration attacks
            Ok(HttpResponse::Ok().json(serde_json::json!({
                "success": true,
                "message": "If an account with that email exists, a password reset link has been sent"
            })))
        }
    }
}

/// POST /api/v2/identity/password/reset
/// Reset password using reset token (public endpoint)
pub async fn reset_password(
    clients: web::Data<ServiceClients>,
    body: web::Json<ResetPasswordBody>,
) -> Result<HttpResponse> {
    info!("POST /api/v2/identity/password/reset");

    // Validate new password
    if body.new_password.len() < 8 {
        return Ok(HttpResponse::BadRequest().json(ErrorResponse::with_message(
            "Invalid password",
            "Password must be at least 8 characters",
        )));
    }

    // Validate token format
    if body.reset_token.is_empty() {
        return Ok(HttpResponse::BadRequest().json(ErrorResponse::with_message(
            "Invalid token",
            "Reset token is required",
        )));
    }

    let mut identity_client = clients.identity_client();

    let grpc_request = tonic::Request::new(ResetPasswordRequest {
        reset_token: body.reset_token.clone(),
        new_password: body.new_password.clone(),
    });

    match identity_client.reset_password(grpc_request).await {
        Ok(_) => {
            info!("Password reset successfully");
            Ok(HttpResponse::Ok().json(serde_json::json!({
                "success": true,
                "message": "Password has been reset successfully"
            })))
        }
        Err(status) => {
            error!(error = %status, "Failed to reset password");

            let response = match status.code() {
                tonic::Code::InvalidArgument | tonic::Code::NotFound => HttpResponse::BadRequest()
                    .json(ErrorResponse::with_message(
                        "Invalid or expired token",
                        "The reset token is invalid or has expired",
                    )),
                _ => HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Failed to reset password",
                    status.message(),
                )),
            };

            Ok(response)
        }
    }
}
