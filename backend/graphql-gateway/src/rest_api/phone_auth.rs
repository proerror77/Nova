/// Phone Authentication API endpoints
///
/// POST /api/v2/auth/phone/send-code - Send SMS verification code
/// POST /api/v2/auth/phone/verify - Verify SMS code
/// POST /api/v2/auth/phone/register - Register with verified phone
/// POST /api/v2/auth/phone/login - Login with verified phone
use actix_web::{web, HttpResponse, Result};
use serde::{Deserialize, Serialize};
use tracing::{error, info};

use super::models::{ErrorResponse, UserProfile};
use crate::clients::ServiceClients;

// ============================================================================
// Request/Response Types
// ============================================================================

#[derive(Debug, Deserialize)]
pub struct SendPhoneCodeRequest {
    pub phone_number: String,
}

#[derive(Debug, Serialize)]
pub struct SendPhoneCodeResponse {
    pub success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
    pub expires_in: i32,
}

#[derive(Debug, Deserialize)]
pub struct VerifyPhoneCodeRequest {
    pub phone_number: String,
    pub code: String,
}

#[derive(Debug, Serialize)]
pub struct VerifyPhoneCodeResponse {
    pub success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub verification_token: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct PhoneRegisterRequest {
    pub phone_number: String,
    pub verification_token: String,
    pub username: String,
    pub password: String,
    pub display_name: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct PhoneLoginRequest {
    pub phone_number: String,
    pub verification_token: String,
}

#[derive(Debug, Serialize)]
pub struct PhoneAuthResponse {
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

/// POST /api/v2/auth/phone/send-code
/// Send verification code to phone number via SMS
pub async fn send_phone_code(
    req: web::Json<SendPhoneCodeRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(phone_number = %mask_phone(&req.phone_number), "POST /api/v2/auth/phone/send-code");

    // Validate phone number format (E.164)
    if !is_valid_e164(&req.phone_number) {
        return Ok(HttpResponse::BadRequest().json(ErrorResponse::with_message(
            "Invalid phone number",
            "Phone number must be in E.164 format (e.g., +14155551234)",
        )));
    }

    let mut auth_client = clients.auth_client();

    let grpc_request = tonic::Request::new(crate::clients::proto::auth::SendPhoneCodeRequest {
        phone_number: req.phone_number.clone(),
    });

    match auth_client.send_phone_code(grpc_request).await {
        Ok(response) => {
            let resp = response.into_inner();
            info!(
                phone = %mask_phone(&req.phone_number),
                success = resp.success,
                "SMS code sent"
            );

            Ok(HttpResponse::Ok().json(SendPhoneCodeResponse {
                success: resp.success,
                message: resp.message,
                expires_in: resp.expires_in,
            }))
        }
        Err(status) => {
            error!(
                phone = %mask_phone(&req.phone_number),
                error = %status,
                "Failed to send SMS code"
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

/// POST /api/v2/auth/phone/verify
/// Verify the SMS code
pub async fn verify_phone_code(
    req: web::Json<VerifyPhoneCodeRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(phone_number = %mask_phone(&req.phone_number), "POST /api/v2/auth/phone/verify");

    // Validate code format (6 digits)
    if req.code.len() != 6 || !req.code.chars().all(|c| c.is_ascii_digit()) {
        return Ok(HttpResponse::BadRequest().json(ErrorResponse::with_message(
            "Invalid code",
            "Verification code must be 6 digits",
        )));
    }

    let mut auth_client = clients.auth_client();

    let grpc_request = tonic::Request::new(crate::clients::proto::auth::VerifyPhoneCodeRequest {
        phone_number: req.phone_number.clone(),
        code: req.code.clone(),
    });

    match auth_client.verify_phone_code(grpc_request).await {
        Ok(response) => {
            let resp = response.into_inner();
            info!(
                phone = %mask_phone(&req.phone_number),
                success = resp.success,
                "Phone code verification completed"
            );

            if resp.success {
                Ok(HttpResponse::Ok().json(VerifyPhoneCodeResponse {
                    success: true,
                    verification_token: resp.verification_token,
                    message: None,
                }))
            } else {
                Ok(HttpResponse::BadRequest().json(VerifyPhoneCodeResponse {
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
                phone = %mask_phone(&req.phone_number),
                error = %status,
                "Phone code verification failed"
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

/// POST /api/v2/auth/phone/register
/// Register new user with verified phone number
pub async fn phone_register(
    req: web::Json<PhoneRegisterRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(
        phone = %mask_phone(&req.phone_number),
        username = %req.username,
        "POST /api/v2/auth/phone/register"
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

    let grpc_request = tonic::Request::new(crate::clients::proto::auth::PhoneRegisterRequest {
        phone_number: req.phone_number.clone(),
        verification_token: req.verification_token.clone(),
        username: req.username.clone(),
        password: req.password.clone(),
        display_name: req.display_name.clone(),
    });

    match auth_client.phone_register(grpc_request).await {
        Ok(response) => {
            let resp = response.into_inner();
            info!(
                user_id = %resp.user_id,
                username = %resp.username,
                is_new_user = resp.is_new_user,
                "Phone registration successful"
            );

            // Create basic user profile
            let profile = UserProfile {
                id: resp.user_id.clone(),
                username: resp.username.clone(),
                email: String::new(),
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

            Ok(HttpResponse::Created().json(PhoneAuthResponse {
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
                phone = %mask_phone(&req.phone_number),
                error = %status,
                "Phone registration failed"
            );

            let error_response = match status.code() {
                tonic::Code::AlreadyExists => {
                    HttpResponse::Conflict().json(ErrorResponse::with_message(
                        "Already registered",
                        "This phone number or username is already registered",
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

/// POST /api/v2/auth/phone/login
/// Login with verified phone number
pub async fn phone_login(
    req: web::Json<PhoneLoginRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(phone_number = %mask_phone(&req.phone_number), "POST /api/v2/auth/phone/login");

    let mut auth_client = clients.auth_client();

    let grpc_request = tonic::Request::new(crate::clients::proto::auth::PhoneLoginRequest {
        phone_number: req.phone_number.clone(),
        verification_token: req.verification_token.clone(),
    });

    match auth_client.phone_login(grpc_request).await {
        Ok(response) => {
            let resp = response.into_inner();
            info!(
                user_id = %resp.user_id,
                username = %resp.username,
                "Phone login successful"
            );

            // Create basic user profile
            let profile = UserProfile {
                id: resp.user_id.clone(),
                username: resp.username.clone(),
                email: String::new(),
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

            Ok(HttpResponse::Ok().json(PhoneAuthResponse {
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
                phone = %mask_phone(&req.phone_number),
                error = %status,
                "Phone login failed"
            );

            let error_response = match status.code() {
                tonic::Code::NotFound => {
                    HttpResponse::NotFound().json(ErrorResponse::with_message(
                        "Not found",
                        "No account found with this phone number",
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

/// Validate E.164 phone number format
fn is_valid_e164(phone: &str) -> bool {
    // E.164: + followed by 7-15 digits
    if !phone.starts_with('+') {
        return false;
    }
    let digits = &phone[1..];
    digits.len() >= 7 && digits.len() <= 15 && digits.chars().all(|c| c.is_ascii_digit())
}

/// Mask phone number for logging (show last 4 digits)
fn mask_phone(phone: &str) -> String {
    if phone.len() <= 4 {
        return "****".to_string();
    }
    let visible = &phone[phone.len() - 4..];
    format!("****{}", visible)
}
