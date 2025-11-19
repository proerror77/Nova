/// Authentication API endpoints
///
/// POST /api/v2/auth/register - Register new user
/// POST /api/v2/auth/login - Login user
/// POST /api/v2/auth/refresh - Refresh access token
/// POST /api/v2/auth/logout - Logout user

use actix_web::{web, HttpResponse, Result};
use tracing::{error, info};

use crate::clients::{
    proto::auth::{LoginRequest as GrpcLoginRequest, RegisterRequest as GrpcRegisterRequest},
    proto::user::GetUserProfileRequest,
    ServiceClients,
};
use super::models::{
    AuthResponse, ErrorResponse, LoginRequest, RefreshTokenRequest, RegisterRequest, UserProfile,
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
        // Note: display_name is not in gRPC RegisterRequest - user must update profile separately
    });

    match auth_client.register(request).await {
        Ok(response) => {
            let auth_response = response.into_inner();

            // Now get full user profile from user-service
            let mut user_client = clients.user_client();
            let user_request = tonic::Request::new(GetUserProfileRequest {
                user_id: auth_response.user_id.clone(),
            });

            match user_client.get_user_profile(user_request).await {
                Ok(user_response) => {
                    let user = user_response.into_inner().profile.ok_or_else(|| {
                        error!(user_id = %auth_response.user_id, "User not found after registration");
                        actix_web::error::ErrorInternalServerError("Registration failed")
                    })?;

                    let profile = UserProfile {
                        id: user.id,
                        username: user.username,
                        email: user.email,
                        display_name: user.display_name,
                        bio: if user.bio.is_empty() { None } else { Some(user.bio) },
                        avatar_url: if user.avatar_url.is_empty() { None } else { Some(user.avatar_url) },
                        cover_url: if user.cover_url.is_empty() { None } else { Some(user.cover_url) },
                        website: if user.website.is_empty() { None } else { Some(user.website) },
                        location: if user.location.is_empty() { None } else { Some(user.location) },
                        is_verified: user.is_verified,
                        is_private: user.is_private,
                        follower_count: user.follower_count,
                        following_count: user.following_count,
                        post_count: user.post_count,
                        created_at: user.created_at,
                        updated_at: user.updated_at,
                        deleted_at: if user.deleted_at == 0 { None } else { Some(user.deleted_at) },
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
                Err(user_status) => {
                    error!(
                        user_id = %auth_response.user_id,
                        error = %user_status,
                        "Failed to get user profile after registration"
                    );
                    Err(actix_web::error::ErrorInternalServerError("Failed to get user profile"))
                }
            }
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
    });

    match auth_client.login(request).await {
        Ok(response) => {
            let auth_response = response.into_inner();

            // Now get full user profile from user-service
            let mut user_client = clients.user_client();
            let user_request = tonic::Request::new(GetUserProfileRequest {
                user_id: auth_response.user_id.clone(),
            });

            match user_client.get_user_profile(user_request).await {
                Ok(user_response) => {
                    let user = user_response.into_inner().profile.ok_or_else(|| {
                        error!(user_id = %auth_response.user_id, "User not found after login");
                        actix_web::error::ErrorInternalServerError("Login failed")
                    })?;

                    let profile = UserProfile {
                        id: user.id,
                        username: user.username,
                        email: user.email,
                        display_name: user.display_name,
                        bio: if user.bio.is_empty() { None } else { Some(user.bio) },
                        avatar_url: if user.avatar_url.is_empty() { None } else { Some(user.avatar_url) },
                        cover_url: if user.cover_url.is_empty() { None } else { Some(user.cover_url) },
                        website: if user.website.is_empty() { None } else { Some(user.website) },
                        location: if user.location.is_empty() { None } else { Some(user.location) },
                        is_verified: user.is_verified,
                        is_private: user.is_private,
                        follower_count: user.follower_count,
                        following_count: user.following_count,
                        post_count: user.post_count,
                        created_at: user.created_at,
                        updated_at: user.updated_at,
                        deleted_at: if user.deleted_at == 0 { None } else { Some(user.deleted_at) },
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
                Err(user_status) => {
                    error!(
                        user_id = %auth_response.user_id,
                        error = %user_status,
                        "Failed to get user profile after login"
                    );
                    Err(actix_web::error::ErrorInternalServerError("Failed to get user profile"))
                }
            }
        }
        Err(status) => {
            error!(
                username = %req.username,
                error = %status,
                "Login failed"
            );

            let error_response = match status.code() {
                tonic::Code::Unauthenticated => {
                    HttpResponse::Unauthorized().json(ErrorResponse::with_message(
                        "Unauthorized",
                        "Invalid username or password",
                    ))
                }
                tonic::Code::NotFound => {
                    HttpResponse::NotFound().json(ErrorResponse::with_message(
                        "User not found",
                        "No user with this username",
                    ))
                }
                tonic::Code::PermissionDenied => {
                    HttpResponse::Forbidden().json(ErrorResponse::with_message(
                        "Account locked",
                        "Account is temporarily locked",
                    ))
                }
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
            let user_id = crypto_core::jwt::get_user_id_from_token(&auth_response.token)
                .map_err(|e| {
                    error!(error = %e, "Failed to extract user_id from token");
                    actix_web::error::ErrorInternalServerError("Invalid token")
                })?;

            // Now get full user profile from user-service
            let mut user_client = clients.user_client();
            let user_request = tonic::Request::new(GetUserProfileRequest {
                user_id: user_id.to_string(),
            });

            match user_client.get_user_profile(user_request).await {
                Ok(user_response) => {
                    let user = user_response.into_inner().profile.ok_or_else(|| {
                        error!(user_id = %user_id, "User not found after token refresh");
                        actix_web::error::ErrorInternalServerError("Refresh failed")
                    })?;

                    let profile = UserProfile {
                        id: user.id,
                        username: user.username,
                        email: user.email,
                        display_name: user.display_name,
                        bio: if user.bio.is_empty() { None } else { Some(user.bio) },
                        avatar_url: if user.avatar_url.is_empty() { None } else { Some(user.avatar_url) },
                        cover_url: if user.cover_url.is_empty() { None } else { Some(user.cover_url) },
                        website: if user.website.is_empty() { None } else { Some(user.website) },
                        location: if user.location.is_empty() { None } else { Some(user.location) },
                        is_verified: user.is_verified,
                        is_private: user.is_private,
                        follower_count: user.follower_count,
                        following_count: user.following_count,
                        post_count: user.post_count,
                        created_at: user.created_at,
                        updated_at: user.updated_at,
                        deleted_at: if user.deleted_at == 0 { None } else { Some(user.deleted_at) },
                    };

                    info!(user_id = %profile.id, "Token refreshed successfully");

                    Ok(HttpResponse::Ok().json(AuthResponse {
                        token: auth_response.token,
                        refresh_token: None, // RefreshTokenResponse doesn't include new refresh_token
                        user: profile,
                    }))
                }
                Err(user_status) => {
                    error!(
                        user_id = %user_id,
                        error = %user_status,
                        "Failed to get user profile after token refresh"
                    );
                    Err(actix_web::error::ErrorInternalServerError("Failed to get user profile"))
                }
            }
        }
        Err(status) => {
            error!(error = %status, "Token refresh failed");

            let error_response = match status.code() {
                tonic::Code::Unauthenticated => {
                    HttpResponse::Unauthorized().json(ErrorResponse::with_message(
                        "Unauthorized",
                        "Invalid or expired refresh token",
                    ))
                }
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
pub async fn logout(
    _clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    info!("POST /api/v2/auth/logout");

    // For now, just return success
    // In production, this should invalidate the session/token
    Ok(HttpResponse::Ok().json(serde_json::json!({
        "message": "Logged out successfully"
    })))
}
