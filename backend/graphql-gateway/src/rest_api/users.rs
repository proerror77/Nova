/// User API endpoints
///
/// GET /api/v2/users/{id} - Get user profile by ID
/// PUT /api/v2/users/{id} - Update user profile

use actix_web::{web, HttpResponse, Result};
use tracing::{error, info};

use crate::clients::{proto::user::{GetUserProfileRequest, UpdateUserProfileRequest}, ServiceClients};
use super::models::{ErrorResponse, GetUserResponse, UpdateUserRequest, UpdateUserResponse, UserProfile};

/// GET /api/v2/users/{id}
/// Returns user profile information
pub async fn get_user(
    user_id: web::Path<String>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let user_id_str = user_id.into_inner();

    info!(user_id = %user_id_str, "GET /api/v2/users/{{id}}");

    // Call user-service via gRPC
    let mut user_client = clients.user_client();

    let request = tonic::Request::new(GetUserProfileRequest {
        user_id: user_id_str.clone(),
    });

    match user_client.get_user_profile(request).await {
        Ok(response) => {
            let user = response.into_inner().profile.ok_or_else(|| {
                error!(user_id = %user_id_str, "User not found in response");
                actix_web::error::ErrorNotFound("User not found")
            })?;

            // Convert gRPC UserProfile to REST UserProfile
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

            info!(user_id = %user_id_str, username = %profile.username, "User retrieved successfully");

            Ok(HttpResponse::Ok().json(GetUserResponse { user: profile }))
        }
        Err(status) => {
            error!(
                user_id = %user_id_str,
                error = %status,
                "Failed to get user from identity-service"
            );

            let error_response = match status.code() {
                tonic::Code::NotFound => {
                    HttpResponse::NotFound().json(ErrorResponse::new("User not found"))
                }
                tonic::Code::Unauthenticated => {
                    HttpResponse::Unauthorized().json(ErrorResponse::new("Unauthorized"))
                }
                _ => {
                    HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                        "Internal server error",
                        status.message(),
                    ))
                }
            };

            Ok(error_response)
        }
    }
}

/// PUT /api/v2/users/{id}
/// Update user profile
pub async fn update_user(
    user_id: web::Path<String>,
    update_req: web::Json<UpdateUserRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let user_id_str = user_id.into_inner();

    info!(user_id = %user_id_str, "PUT /api/v2/users/{{id}}");

    // Call user-service via gRPC
    let mut user_client = clients.user_client();

    let request = tonic::Request::new(UpdateUserProfileRequest {
        user_id: user_id_str.clone(),
        display_name: update_req.display_name.clone().unwrap_or_default(),
        bio: update_req.bio.clone().unwrap_or_default(),
        avatar_url: update_req.avatar_url.clone().unwrap_or_default(),
        cover_url: update_req.cover_url.clone().unwrap_or_default(),
        website: update_req.website.clone().unwrap_or_default(),
        location: update_req.location.clone().unwrap_or_default(),
        is_private: false, // Not included in REST request for now
    });

    match user_client.update_user_profile(request).await {
        Ok(response) => {
            let user = response.into_inner().profile.ok_or_else(|| {
                error!(user_id = %user_id_str, "User not found in response");
                actix_web::error::ErrorNotFound("User not found")
            })?;

            // Convert gRPC UserProfile to REST UserProfile
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

            info!(user_id = %user_id_str, "User updated successfully");

            Ok(HttpResponse::Ok().json(UpdateUserResponse { user: profile }))
        }
        Err(status) => {
            error!(
                user_id = %user_id_str,
                error = %status,
                "Failed to update user"
            );

            let error_response = match status.code() {
                tonic::Code::NotFound => {
                    HttpResponse::NotFound().json(ErrorResponse::new("User not found"))
                }
                tonic::Code::Unauthenticated => {
                    HttpResponse::Unauthorized().json(ErrorResponse::new("Unauthorized"))
                }
                tonic::Code::InvalidArgument => {
                    HttpResponse::BadRequest().json(ErrorResponse::with_message(
                        "Invalid request",
                        status.message(),
                    ))
                }
                _ => {
                    HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                        "Internal server error",
                        status.message(),
                    ))
                }
            };

            Ok(error_response)
        }
    }
}
