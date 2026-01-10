/// Authentication API endpoints
///
/// POST /api/v2/auth/register - Register new user
/// POST /api/v2/auth/login - Login user
/// POST /api/v2/auth/refresh - Refresh access token
/// POST /api/v2/auth/logout - Logout user
use actix_web::{web, HttpRequest, HttpResponse, Result};
use tracing::{error, info};

use super::models::{
    AuthResponse, ErrorResponse, LoginRequest, RefreshTokenRequest, RegisterRequest, UserProfile,
};
use crate::clients::{
    proto::auth::{LoginRequest as GrpcLoginRequest, RegisterRequest as GrpcRegisterRequest},
    // GetUserProfileRequest removed - user-service is deprecated
    ServiceClients,
};

/// POST /api/v2/auth/register
/// Register a new user account
pub async fn register(
    req: web::Json<RegisterRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(username = %req.username, email = %req.email, "POST /api/v2/auth/register");

    let mut auth_client = clients.auth_client();

    let request = tonic::Request::new(GrpcRegisterRequest {
        email: req.email.clone(),
        username: req.username.clone(),
        password: req.password.clone(),
        invite_code: req.invite_code.clone(),
        display_name: Some(req.display_name.clone()),
        // Pass device info for session tracking (best-effort)
        device_id: req.device_id.clone().unwrap_or_default(),
        device_name: req.device_name.clone().unwrap_or_default(),
        device_type: req.device_type.clone().unwrap_or_default(),
        os_version: req.os_version.clone().unwrap_or_default(),
        user_agent: req.user_agent.clone().unwrap_or_default(),
    });

    match auth_client.register(request).await {
        Ok(response) => {
            let auth_response = response.into_inner();

            // Create basic user profile from registration data
            let profile = UserProfile {
                id: auth_response.user_id.clone(),
                username: req.username.clone(),
                email: req.email.clone(),
                display_name: req.display_name.clone(),
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

            info!(user_id = %profile.id, username = %profile.username, "User registered successfully");

            Ok(HttpResponse::Ok().json(AuthResponse {
                token: auth_response.token,
                refresh_token: if auth_response.refresh_token.is_empty() {
                    None
                } else {
                    Some(auth_response.refresh_token)
                },
                user: profile,
            }))
        }
        Err(status) => {
            error!(
                username = %req.username,
                error = %status,
                "Registration failed"
            );

            let error_response = match status.code() {
                tonic::Code::AlreadyExists => {
                    HttpResponse::Conflict().json(ErrorResponse::with_message(
                        "User already exists",
                        "Username or email already taken",
                    ))
                }
                tonic::Code::InvalidArgument => HttpResponse::BadRequest().json(
                    ErrorResponse::with_message("Invalid request", status.message()),
                ),
                _ => HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Internal server error",
                    status.message(),
                )),
            };

            Ok(error_response)
        }
    }
}

/// POST /api/v2/auth/login
/// Authenticate user and return access token
pub async fn login(
    req: web::Json<LoginRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(username = %req.username, "POST /api/v2/auth/login");

    let mut auth_client = clients.auth_client();

    let request = tonic::Request::new(GrpcLoginRequest {
        email: req.username.clone(), // REST API uses "username" but gRPC expects "email"
        password: req.password.clone(),
        // Pass device info for session tracking
        device_id: req.device_id.clone().unwrap_or_default(),
        device_name: req.device_name.clone().unwrap_or_default(),
        device_type: req.device_type.clone().unwrap_or_default(),
        os_version: req.os_version.clone().unwrap_or_default(),
        user_agent: req.user_agent.clone().unwrap_or_default(),
    });

    match auth_client.login(request).await {
        Ok(response) => {
            let auth_response = response.into_inner();

            // Extract email from JWT token for profile
            // LoginResponse doesn't include user details, need to decode token
            let email = crypto_core::jwt::get_email_from_token(&auth_response.token)
                .unwrap_or_else(|_| String::new());
            let username = crypto_core::jwt::get_username_from_token(&auth_response.token)
                .unwrap_or_else(|_| email.split('@').next().unwrap_or("").to_string());

            // Create basic user profile from login response
            let profile = UserProfile {
                id: auth_response.user_id.clone(),
                username: username.clone(),
                email: email.clone(),
                display_name: username.clone(), // Use username as default display name
                bio: None,
                avatar_url: None,
                cover_url: None,
                website: None,
                location: None,
                is_verified: false, // Not available in LoginResponse
                is_private: false,
                follower_count: 0,
                following_count: 0,
                post_count: 0,
                created_at: chrono::Utc::now().timestamp(),
                updated_at: chrono::Utc::now().timestamp(),
                deleted_at: None,
            };

            info!(user_id = %profile.id, username = %profile.username, "User logged in successfully");

            Ok(HttpResponse::Ok().json(AuthResponse {
                token: auth_response.token,
                refresh_token: if auth_response.refresh_token.is_empty() {
                    None
                } else {
                    Some(auth_response.refresh_token)
                },
                user: profile,
            }))
        }
        Err(status) => {
            error!(
                username = %req.username,
                error = %status,
                "Login failed"
            );

            let error_response = match status.code() {
                tonic::Code::Unauthenticated => HttpResponse::Unauthorized().json(
                    ErrorResponse::with_message("Unauthorized", "Invalid username or password"),
                ),
                tonic::Code::NotFound => HttpResponse::NotFound().json(
                    ErrorResponse::with_message("User not found", "No user with this username"),
                ),
                tonic::Code::PermissionDenied => HttpResponse::Forbidden().json(
                    ErrorResponse::with_message("Account locked", "Account is temporarily locked"),
                ),
                _ => HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Internal server error",
                    status.message(),
                )),
            };

            Ok(error_response)
        }
    }
}

/// POST /api/v2/auth/refresh
/// Refresh access token using refresh token
pub async fn refresh_token(
    req: web::Json<RefreshTokenRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!("POST /api/v2/auth/refresh");

    let mut auth_client = clients.auth_client();

    let request = tonic::Request::new(crate::clients::proto::auth::RefreshTokenRequest {
        refresh_token: req.refresh_token.clone(),
    });

    match auth_client.refresh(request).await {
        Ok(response) => {
            let auth_response = response.into_inner();

            // Extract user_id from the new JWT token
            let user_id =
                crypto_core::jwt::get_user_id_from_token(&auth_response.token).map_err(|e| {
                    error!(error = %e, "Failed to extract user_id from token");
                    actix_web::error::ErrorInternalServerError("Invalid token")
                })?;

            // Create basic user profile from token data
            // Full profile can be fetched separately if needed via GET /api/v2/users/{id}
            let profile = UserProfile {
                id: user_id.to_string(),
                username: String::new(),     // Not available in refresh token
                email: String::new(),        // Not available in refresh token
                display_name: String::new(), // Not available in refresh token
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

            info!(user_id = %user_id, "Token refreshed successfully");

            Ok(HttpResponse::Ok().json(AuthResponse {
                token: auth_response.token,
                refresh_token: if auth_response.refresh_token.is_empty() {
                    None
                } else {
                    Some(auth_response.refresh_token) // Token rotation: new refresh_token each time (like IG/Twitter)
                },
                user: profile,
            }))
        }
        Err(status) => {
            error!(error = %status, "Token refresh failed");

            let error_response = match status.code() {
                tonic::Code::Unauthenticated => HttpResponse::Unauthorized().json(
                    ErrorResponse::with_message("Unauthorized", "Invalid or expired refresh token"),
                ),
                _ => HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Internal server error",
                    status.message(),
                )),
            };

            Ok(error_response)
        }
    }
}

/// POST /api/v2/auth/logout
/// Invalidate user session
pub async fn logout(_clients: web::Data<ServiceClients>) -> Result<HttpResponse> {
    info!("POST /api/v2/auth/logout");

    // For now, just return success
    // In production, this should invalidate the session/token
    Ok(HttpResponse::Ok().json(serde_json::json!({
        "message": "Logged out successfully"
    })))
}

/// GET /api/v2/auth/invites/validate?code=XXXXX
/// Validate an invite code (public endpoint - no auth required)
/// Used by mobile clients before registration to check if invite code is valid
pub async fn validate_invite_code(
    query: web::Query<ValidateInviteQuery>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(code = %query.code, "GET /api/v2/auth/invites/validate");

    let mut auth_client = clients.auth_client();

    let request = tonic::Request::new(crate::clients::proto::auth::ValidateInviteRequest {
        code: query.code.clone(),
    });

    match auth_client.validate_invite(request).await {
        Ok(response) => {
            let validation = response.into_inner();
            info!(
                code = %query.code,
                is_valid = validation.is_valid,
                "Invite code validation completed"
            );

            Ok(HttpResponse::Ok().json(InviteValidationResponse {
                is_valid: validation.is_valid,
                issuer_username: validation.issuer_username.filter(|s| !s.is_empty()),
                expires_at: validation.expires_at.filter(|&t| t != 0),
                error: validation.error.filter(|s| !s.is_empty()),
            }))
        }
        Err(status) => {
            error!(
                code = %query.code,
                error = %status,
                "Invite code validation failed"
            );

            // Return a structured error response for client handling
            Ok(HttpResponse::BadRequest().json(InviteValidationResponse {
                is_valid: false,
                issuer_username: None,
                expires_at: None,
                error: Some(status.message().to_string()),
            }))
        }
    }
}

/// Query parameters for invite validation
#[derive(Debug, serde::Deserialize)]
pub struct ValidateInviteQuery {
    pub code: String,
}

/// Response for invite validation
#[derive(Debug, serde::Serialize)]
pub struct InviteValidationResponse {
    pub is_valid: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub issuer_username: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub expires_at: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

/// Request body for waitlist signup
#[derive(Debug, serde::Deserialize)]
pub struct WaitlistRequest {
    pub email: String,
}

/// Response for waitlist signup
#[derive(Debug, serde::Serialize)]
pub struct WaitlistResponse {
    pub success: bool,
    pub is_new: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

/// POST /api/v2/auth/waitlist
/// Add email to waitlist (public endpoint - no auth required)
/// Used by mobile clients when user doesn't have an invite code
pub async fn add_to_waitlist(
    req: HttpRequest,
    body: web::Json<WaitlistRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!(email = %body.email, "POST /api/v2/auth/waitlist");

    // Extract IP address and user agent from request
    let ip_address = req
        .connection_info()
        .realip_remote_addr()
        .map(|s| s.to_string());
    let user_agent = req
        .headers()
        .get("user-agent")
        .and_then(|h| h.to_str().ok())
        .map(|s| s.to_string());

    let mut auth_client = clients.auth_client();

    let request = tonic::Request::new(crate::clients::proto::auth::AddToWaitlistRequest {
        email: body.email.clone(),
        ip_address,
        user_agent,
        source: Some("ios_app".to_string()),
    });

    match auth_client.add_to_waitlist(request).await {
        Ok(response) => {
            let result = response.into_inner();
            info!(
                email = %body.email,
                is_new = result.is_new,
                "Waitlist signup completed"
            );

            Ok(HttpResponse::Ok().json(WaitlistResponse {
                success: result.success,
                is_new: result.is_new,
                message: if result.is_new {
                    Some("You've been added to the waitlist!".to_string())
                } else {
                    Some("You're already on the waitlist.".to_string())
                },
            }))
        }
        Err(status) => {
            error!(
                email = %body.email,
                error = %status,
                "Waitlist signup failed"
            );

            Ok(HttpResponse::BadRequest().json(WaitlistResponse {
                success: false,
                is_new: false,
                message: Some(status.message().to_string()),
            }))
        }
    }
}
