/// Email Authentication API endpoints
///
/// POST /api/v2/auth/email/send-code - Send email verification code
/// POST /api/v2/auth/email/verify - Verify email code
/// POST /api/v2/auth/email/register - Register with verified email
/// POST /api/v2/auth/email/login - Login with verified email
use actix_web::{web, HttpResponse, Result};
use serde::{Deserialize, Serialize};
use tracing::{error, info};

use super::models::{ErrorResponse, UserProfile};
use crate::clients::ServiceClients;

// ============================================================================
// Request/Response Types
// ============================================================================

#[derive(Debug, Deserialize)]
pub struct SendEmailCodeRequest {
    pub email: String,
}

#[derive(Debug, Serialize)]
pub struct SendEmailCodeResponse {
    pub success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
    pub expires_in: i32,
}

#[derive(Debug, Deserialize)]
pub struct VerifyEmailCodeRequest {
    pub email: String,
    pub code: String,
}

#[derive(Debug, Serialize)]
pub struct VerifyEmailCodeResponse {
    pub success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub verification_token: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct EmailRegisterRequest {
    pub email: String,
    pub verification_token: String,
    pub username: String,
    pub password: String,
    pub display_name: Option<String>,
    pub invite_code: Option<String>,
    // Device information for session tracking (optional)
    pub device_id: Option<String>,
    pub device_name: Option<String>,
    pub device_type: Option<String>,
    pub os_version: Option<String>,
    pub user_agent: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct EmailLoginRequest {
    pub email: String,
    pub verification_token: String,
    // Device information for session tracking (optional)
    pub device_id: Option<String>,
    pub device_name: Option<String>,
    pub device_type: Option<String>,
    pub os_version: Option<String>,
    pub user_agent: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct EmailAuthResponse {
    pub user_id: String,
    pub token: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub refresh_token: Option<String>,
    pub expires_in: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub user: Option<UserProfile>,
}

// ============================================================================
// API Handlers
// ============================================================================

/// POST /api/v2/auth/email/send-code
/// Send verification code to email address
pub async fn send_email_code(
    req: web::Json<SendEmailCodeRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(email = %mask_email(&req.email), "POST /api/v2/auth/email/send-code");

    // Validate email format
    if !is_valid_email(&req.email) {
        return Ok(HttpResponse::BadRequest().json(ErrorResponse::with_message(
            "Invalid email",
            "Email address format is invalid",
        )));
    }

    let mut auth_client = clients.auth_client();

    let grpc_request = tonic::Request::new(crate::clients::proto::auth::SendEmailCodeRequest {
        email: req.email.clone(),
    });

    match auth_client.send_email_code(grpc_request).await {
        Ok(response) => {
            let resp = response.into_inner();
            info!(
                email = %mask_email(&req.email),
                success = resp.success,
                "Email code sent"
            );

            Ok(HttpResponse::Ok().json(SendEmailCodeResponse {
                success: resp.success,
                message: resp.message,
                expires_in: resp.expires_in,
            }))
        }
        Err(status) => {
            error!(
                email = %mask_email(&req.email),
                error = %status,
                "Failed to send email code"
            );

            let error_response = match status.code() {
                tonic::Code::ResourceExhausted => {
                    HttpResponse::TooManyRequests().json(ErrorResponse::with_message(
                        "Rate limited",
                        "Too many attempts. Please try again later.",
                    ))
                }
                tonic::Code::InvalidArgument => HttpResponse::BadRequest().json(
                    ErrorResponse::with_message("Invalid request", status.message()),
                ),
                _ => HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Internal server error",
                    "Failed to send verification code",
                )),
            };

            Ok(error_response)
        }
    }
}

/// POST /api/v2/auth/email/verify
/// Verify the email code
pub async fn verify_email_code(
    req: web::Json<VerifyEmailCodeRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(email = %mask_email(&req.email), "POST /api/v2/auth/email/verify");

    // Validate code format (6 digits)
    if req.code.len() != 6 || !req.code.chars().all(|c| c.is_ascii_digit()) {
        return Ok(HttpResponse::BadRequest().json(ErrorResponse::with_message(
            "Invalid code",
            "Verification code must be 6 digits",
        )));
    }

    let mut auth_client = clients.auth_client();

    let grpc_request = tonic::Request::new(crate::clients::proto::auth::VerifyEmailCodeRequest {
        email: req.email.clone(),
        code: req.code.clone(),
    });

    match auth_client.verify_email_code(grpc_request).await {
        Ok(response) => {
            let resp = response.into_inner();
            info!(
                email = %mask_email(&req.email),
                success = resp.success,
                "Email code verification completed"
            );

            if resp.success {
                Ok(HttpResponse::Ok().json(VerifyEmailCodeResponse {
                    success: true,
                    verification_token: resp.verification_token,
                    message: None,
                }))
            } else {
                Ok(HttpResponse::BadRequest().json(VerifyEmailCodeResponse {
                    success: false,
                    verification_token: None,
                    message: resp
                        .message
                        .or(Some("Invalid verification code".to_string())),
                }))
            }
        }
        Err(status) => {
            error!(
                email = %mask_email(&req.email),
                error = %status,
                "Email code verification failed"
            );

            let error_response = match status.code() {
                tonic::Code::InvalidArgument => HttpResponse::BadRequest().json(
                    ErrorResponse::with_message("Invalid code", status.message()),
                ),
                tonic::Code::DeadlineExceeded => HttpResponse::Gone().json(
                    ErrorResponse::with_message("Code expired", "Verification code has expired"),
                ),
                _ => HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Internal server error",
                    "Verification failed",
                )),
            };

            Ok(error_response)
        }
    }
}

/// POST /api/v2/auth/email/register
/// Register new user with verified email
pub async fn email_register(
    req: web::Json<EmailRegisterRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(
        email = %mask_email(&req.email),
        username = %req.username,
        "POST /api/v2/auth/email/register"
    );

    // Validate username
    if req.username.len() < 3 || req.username.len() > 32 {
        return Ok(HttpResponse::BadRequest().json(ErrorResponse::with_message(
            "Invalid username",
            "Username must be 3-32 characters",
        )));
    }

    // Validate password
    if req.password.len() < 6 {
        return Ok(HttpResponse::BadRequest().json(ErrorResponse::with_message(
            "Invalid password",
            "Password must be at least 6 characters",
        )));
    }

    let mut auth_client = clients.auth_client();

    let grpc_request = tonic::Request::new(crate::clients::proto::auth::EmailRegisterRequest {
        email: req.email.clone(),
        verification_token: req.verification_token.clone(),
        username: req.username.clone(),
        password: req.password.clone(),
        display_name: req.display_name.clone(),
        invite_code: req.invite_code.clone(),
        device_id: req.device_id.clone().unwrap_or_default(),
        device_name: req.device_name.clone().unwrap_or_default(),
        device_type: req.device_type.clone().unwrap_or_default(),
        os_version: req.os_version.clone().unwrap_or_default(),
        user_agent: req.user_agent.clone().unwrap_or_default(),
    });

    match auth_client.email_register(grpc_request).await {
        Ok(response) => {
            let resp = response.into_inner();
            info!(
                user_id = %resp.user_id,
                username = %resp.username,
                is_new_user = resp.is_new_user,
                "Email registration successful"
            );

            // Create basic user profile
            let profile = UserProfile {
                id: resp.user_id.clone(),
                username: resp.username.clone(),
                email: req.email.clone(),
                display_name: req.display_name.clone().unwrap_or(resp.username.clone()),
                bio: None,
                avatar_url: None,
                cover_url: None,
                website: None,
                location: None,
                is_verified: false,
                is_private: false,
                follower_count: 0,
                following_count: 0,
                post_count: 0,
                created_at: chrono::Utc::now().timestamp(),
                updated_at: chrono::Utc::now().timestamp(),
                deleted_at: None,
            };

            Ok(HttpResponse::Created().json(EmailAuthResponse {
                user_id: resp.user_id,
                token: resp.token,
                refresh_token: if resp.refresh_token.is_empty() {
                    None
                } else {
                    Some(resp.refresh_token)
                },
                expires_in: resp.expires_in,
                user: Some(profile),
            }))
        }
        Err(status) => {
            error!(
                email = %mask_email(&req.email),
                error = %status,
                "Email registration failed"
            );

            let error_response = match status.code() {
                tonic::Code::AlreadyExists => {
                    HttpResponse::Conflict().json(ErrorResponse::with_message(
                        "Already registered",
                        "This email or username is already registered",
                    ))
                }
                tonic::Code::InvalidArgument => HttpResponse::BadRequest().json(
                    ErrorResponse::with_message("Invalid request", status.message()),
                ),
                tonic::Code::Unauthenticated => {
                    HttpResponse::Unauthorized().json(ErrorResponse::with_message(
                        "Invalid token",
                        "Verification token is invalid or expired",
                    ))
                }
                _ => HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Internal server error",
                    "Registration failed",
                )),
            };

            Ok(error_response)
        }
    }
}

/// POST /api/v2/auth/email/login
/// Login with verified email
pub async fn email_login(
    req: web::Json<EmailLoginRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(email = %mask_email(&req.email), "POST /api/v2/auth/email/login");

    let mut auth_client = clients.auth_client();

    let grpc_request = tonic::Request::new(crate::clients::proto::auth::EmailLoginRequest {
        email: req.email.clone(),
        verification_token: req.verification_token.clone(),
        device_id: req.device_id.clone().unwrap_or_default(),
        device_name: req.device_name.clone().unwrap_or_default(),
        device_type: req.device_type.clone().unwrap_or_default(),
        os_version: req.os_version.clone().unwrap_or_default(),
        user_agent: req.user_agent.clone().unwrap_or_default(),
    });

    match auth_client.email_login(grpc_request).await {
        Ok(response) => {
            let resp = response.into_inner();
            info!(
                user_id = %resp.user_id,
                username = %resp.username,
                "Email login successful"
            );

            // Create basic user profile
            let profile = UserProfile {
                id: resp.user_id.clone(),
                username: resp.username.clone(),
                email: req.email.clone(),
                display_name: resp.username.clone(),
                bio: None,
                avatar_url: None,
                cover_url: None,
                website: None,
                location: None,
                is_verified: false,
                is_private: false,
                follower_count: 0,
                following_count: 0,
                post_count: 0,
                created_at: chrono::Utc::now().timestamp(),
                updated_at: chrono::Utc::now().timestamp(),
                deleted_at: None,
            };

            Ok(HttpResponse::Ok().json(EmailAuthResponse {
                user_id: resp.user_id,
                token: resp.token,
                refresh_token: if resp.refresh_token.is_empty() {
                    None
                } else {
                    Some(resp.refresh_token)
                },
                expires_in: resp.expires_in,
                user: Some(profile),
            }))
        }
        Err(status) => {
            error!(
                email = %mask_email(&req.email),
                error = %status,
                "Email login failed"
            );

            let error_response = match status.code() {
                tonic::Code::NotFound => {
                    HttpResponse::NotFound().json(ErrorResponse::with_message(
                        "Not found",
                        "No account found with this email address",
                    ))
                }
                tonic::Code::Unauthenticated => {
                    HttpResponse::Unauthorized().json(ErrorResponse::with_message(
                        "Invalid token",
                        "Verification token is invalid or expired",
                    ))
                }
                _ => HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Internal server error",
                    "Login failed",
                )),
            };

            Ok(error_response)
        }
    }
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Validate email format
fn is_valid_email(email: &str) -> bool {
    email.contains('@') && email.len() >= 5 && email.len() <= 254
}

/// Mask email for logging
fn mask_email(email: &str) -> String {
    if let Some(at_pos) = email.find('@') {
        let local = &email[..at_pos];
        let domain = &email[at_pos..];
        if local.len() <= 2 {
            format!("**{}", domain)
        } else {
            format!("{}***{}", &local[..1], domain)
        }
    } else {
        "***@***".to_string()
    }
}
