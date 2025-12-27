//! Graph API endpoints
//!
//! GET /api/v2/graph/following - Get users the current user is following
//! GET /api/v2/graph/followers - Get users following the current user
//! GET /api/v2/graph/following/{user_id} - Get users a specific user is following
//! GET /api/v2/graph/followers/{user_id} - Get users following a specific user
//! POST /api/v2/graph/follow - Follow a user
//! DELETE /api/v2/graph/follow/{user_id} - Unfollow a user
//! GET /api/v2/graph/is-following/{user_id} - Check if following a user

#![allow(dead_code)]

use actix_web::{web, HttpMessage, HttpRequest, HttpResponse, Result};
use serde::{Deserialize, Serialize};
use tracing::{error, info};

use super::models::ErrorResponse;
use crate::clients::proto::graph::{
    CreateFollowRequest, DeleteFollowRequest, GetFollowersRequest, GetFollowingRequest,
    IsFollowingRequest,
};
use crate::clients::ServiceClients;
use crate::middleware::jwt::AuthenticatedUser;

/// User info with relationship status
#[derive(Debug, Serialize)]
pub struct FollowUserInfo {
    pub user_id: String,
    pub you_are_following: bool,
    pub follows_you: bool,
}

/// REST API response for user list
#[derive(Debug, Serialize)]
pub struct UserListResponse {
    pub user_ids: Vec<String>,
    pub total_count: i32,
    pub has_more: bool,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub users: Vec<FollowUserInfo>,
}

#[derive(Debug, Serialize)]
pub struct FollowActionResponse {
    pub success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct IsFollowingResponse {
    pub is_following: bool,
}

#[derive(Debug, Deserialize)]
pub struct GraphQueryParams {
    pub limit: Option<i32>,
    pub offset: Option<i32>,
}

#[derive(Debug, Deserialize)]
pub struct FollowRequest {
    pub user_id: String,
}

/// GET /api/v2/graph/following
/// Returns users the current user is following
pub async fn get_my_following(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
    query: web::Query<GraphQueryParams>,
) -> Result<HttpResponse> {
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    // When viewing own following list, use self as viewer for relationship status
    get_following_impl(&user_id, Some(&user_id), &clients, &query).await
}

/// GET /api/v2/graph/following/{user_id}
/// Returns users a specific user is following
pub async fn get_user_following(
    req: HttpRequest,
    path: web::Path<String>,
    clients: web::Data<ServiceClients>,
    query: web::Query<GraphQueryParams>,
) -> Result<HttpResponse> {
    let user_id = path.into_inner();
    // Use JWT user as viewer if authenticated
    let viewer_id = req
        .extensions()
        .get::<AuthenticatedUser>()
        .map(|auth| auth.0.to_string());
    get_following_impl(&user_id, viewer_id.as_deref(), &clients, &query).await
}

async fn get_following_impl(
    user_id: &str,
    viewer_id: Option<&str>,
    clients: &web::Data<ServiceClients>,
    query: &web::Query<GraphQueryParams>,
) -> Result<HttpResponse> {
    let limit = query.limit.unwrap_or(50).min(1000);
    let offset = query.offset.unwrap_or(0);

    info!(
        user_id = %user_id,
        viewer_id = ?viewer_id,
        limit = %limit,
        offset = %offset,
        "GET /api/v2/graph/following"
    );

    let mut graph_client = clients.graph_client();

    let grpc_request = tonic::Request::new(GetFollowingRequest {
        user_id: user_id.to_string(),
        limit,
        offset,
        viewer_id: viewer_id.unwrap_or_default().to_string(),
    });

    match graph_client.get_following(grpc_request).await {
        Ok(response) => {
            let grpc_response = response.into_inner();

            info!(
                user_id = %user_id,
                total_count = grpc_response.total_count,
                enriched = grpc_response.users.len(),
                "Following list retrieved"
            );

            // Convert gRPC users to REST response
            let users: Vec<FollowUserInfo> = grpc_response
                .users
                .into_iter()
                .map(|u| FollowUserInfo {
                    user_id: u.user_id,
                    you_are_following: u.you_are_following,
                    follows_you: u.follows_you,
                })
                .collect();

            Ok(HttpResponse::Ok().json(UserListResponse {
                user_ids: grpc_response.user_ids,
                total_count: grpc_response.total_count,
                has_more: grpc_response.has_more,
                users,
            }))
        }
        Err(status) => {
            error!(
                user_id = %user_id,
                error = %status,
                "Failed to get following list from graph-service"
            );

            Ok(
                HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Failed to get following list",
                    status.message(),
                )),
            )
        }
    }
}

/// GET /api/v2/graph/followers
/// Returns users following the current user
pub async fn get_my_followers(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
    query: web::Query<GraphQueryParams>,
) -> Result<HttpResponse> {
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    // When viewing own followers list, use self as viewer for relationship status
    get_followers_impl(&user_id, Some(&user_id), &clients, &query).await
}

/// GET /api/v2/graph/followers/{user_id}
/// Returns users following a specific user
pub async fn get_user_followers(
    req: HttpRequest,
    path: web::Path<String>,
    clients: web::Data<ServiceClients>,
    query: web::Query<GraphQueryParams>,
) -> Result<HttpResponse> {
    let user_id = path.into_inner();
    // Use JWT user as viewer if authenticated
    let viewer_id = req
        .extensions()
        .get::<AuthenticatedUser>()
        .map(|auth| auth.0.to_string());
    get_followers_impl(&user_id, viewer_id.as_deref(), &clients, &query).await
}

async fn get_followers_impl(
    user_id: &str,
    viewer_id: Option<&str>,
    clients: &web::Data<ServiceClients>,
    query: &web::Query<GraphQueryParams>,
) -> Result<HttpResponse> {
    let limit = query.limit.unwrap_or(50).min(1000);
    let offset = query.offset.unwrap_or(0);

    info!(
        user_id = %user_id,
        viewer_id = ?viewer_id,
        limit = %limit,
        offset = %offset,
        "GET /api/v2/graph/followers"
    );

    let mut graph_client = clients.graph_client();

    let grpc_request = tonic::Request::new(GetFollowersRequest {
        user_id: user_id.to_string(),
        limit,
        offset,
        viewer_id: viewer_id.unwrap_or_default().to_string(),
    });

    match graph_client.get_followers(grpc_request).await {
        Ok(response) => {
            let grpc_response = response.into_inner();

            info!(
                user_id = %user_id,
                total_count = grpc_response.total_count,
                enriched = grpc_response.users.len(),
                "Followers list retrieved"
            );

            // Convert gRPC users to REST response
            let users: Vec<FollowUserInfo> = grpc_response
                .users
                .into_iter()
                .map(|u| FollowUserInfo {
                    user_id: u.user_id,
                    you_are_following: u.you_are_following,
                    follows_you: u.follows_you,
                })
                .collect();

            Ok(HttpResponse::Ok().json(UserListResponse {
                user_ids: grpc_response.user_ids,
                total_count: grpc_response.total_count,
                has_more: grpc_response.has_more,
                users,
            }))
        }
        Err(status) => {
            error!(
                user_id = %user_id,
                error = %status,
                "Failed to get followers list from graph-service"
            );

            Ok(
                HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Failed to get followers list",
                    status.message(),
                )),
            )
        }
    }
}

/// POST /api/v2/graph/follow
/// Follow a user
pub async fn follow_user(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
    body: web::Json<FollowRequest>,
) -> Result<HttpResponse> {
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    let followee_id = &body.user_id;

    info!(
        follower_id = %user_id,
        followee_id = %followee_id,
        "POST /api/v2/graph/follow"
    );

    // Can't follow yourself
    if user_id == *followee_id {
        return Ok(HttpResponse::BadRequest().json(ErrorResponse::new("Cannot follow yourself")));
    }

    let mut graph_client = clients.graph_client();

    let mut grpc_request = tonic::Request::new(CreateFollowRequest {
        follower_id: user_id.clone(),
        followee_id: followee_id.clone(),
    });

    // Add internal token for write operations
    if let Ok(token) = std::env::var("INTERNAL_GRAPH_WRITE_TOKEN") {
        if let Ok(token_value) = token.parse() {
            grpc_request
                .metadata_mut()
                .insert("x-internal-token", token_value);
        }
    }

    match graph_client.create_follow(grpc_request).await {
        Ok(response) => {
            let grpc_response = response.into_inner();

            info!(
                follower_id = %user_id,
                followee_id = %followee_id,
                success = grpc_response.success,
                "Follow action completed"
            );

            Ok(HttpResponse::Ok().json(FollowActionResponse {
                success: grpc_response.success,
                message: if grpc_response.message.is_empty() {
                    None
                } else {
                    Some(grpc_response.message)
                },
            }))
        }
        Err(status) => {
            error!(
                follower_id = %user_id,
                followee_id = %followee_id,
                error = %status,
                "Failed to follow user"
            );

            let error_response = match status.code() {
                tonic::Code::NotFound => {
                    HttpResponse::NotFound().json(ErrorResponse::new("User not found"))
                }
                tonic::Code::AlreadyExists => {
                    HttpResponse::Conflict().json(ErrorResponse::new("Already following this user"))
                }
                _ => HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Failed to follow user",
                    status.message(),
                )),
            };

            Ok(error_response)
        }
    }
}

/// DELETE /api/v2/graph/follow/{user_id}
/// Unfollow a user
pub async fn unfollow_user(
    req: HttpRequest,
    path: web::Path<String>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    let followee_id = path.into_inner();

    info!(
        follower_id = %user_id,
        followee_id = %followee_id,
        "DELETE /api/v2/graph/follow/{user_id}"
    );

    let mut graph_client = clients.graph_client();

    let mut grpc_request = tonic::Request::new(DeleteFollowRequest {
        follower_id: user_id.clone(),
        followee_id: followee_id.clone(),
    });

    // Add internal token for write operations
    if let Ok(token) = std::env::var("INTERNAL_GRAPH_WRITE_TOKEN") {
        if let Ok(token_value) = token.parse() {
            grpc_request
                .metadata_mut()
                .insert("x-internal-token", token_value);
        }
    }

    match graph_client.delete_follow(grpc_request).await {
        Ok(response) => {
            let grpc_response = response.into_inner();

            info!(
                follower_id = %user_id,
                followee_id = %followee_id,
                success = grpc_response.success,
                "Unfollow action completed"
            );

            Ok(HttpResponse::Ok().json(FollowActionResponse {
                success: grpc_response.success,
                message: if grpc_response.message.is_empty() {
                    None
                } else {
                    Some(grpc_response.message)
                },
            }))
        }
        Err(status) => {
            error!(
                follower_id = %user_id,
                followee_id = %followee_id,
                error = %status,
                "Failed to unfollow user"
            );

            Ok(
                HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Failed to unfollow user",
                    status.message(),
                )),
            )
        }
    }
}

/// GET /api/v2/graph/is-following/{user_id}
/// Check if the current user is following a specific user
pub async fn check_is_following(
    req: HttpRequest,
    path: web::Path<String>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    let followee_id = path.into_inner();

    info!(
        follower_id = %user_id,
        followee_id = %followee_id,
        "GET /api/v2/graph/is-following/{user_id}"
    );

    let mut graph_client = clients.graph_client();

    let grpc_request = tonic::Request::new(IsFollowingRequest {
        follower_id: user_id.clone(),
        followee_id: followee_id.clone(),
    });

    match graph_client.is_following(grpc_request).await {
        Ok(response) => {
            let grpc_response = response.into_inner();

            Ok(HttpResponse::Ok().json(IsFollowingResponse {
                is_following: grpc_response.is_following,
            }))
        }
        Err(status) => {
            error!(
                follower_id = %user_id,
                followee_id = %followee_id,
                error = %status,
                "Failed to check following status"
            );

            Ok(
                HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Failed to check following status",
                    status.message(),
                )),
            )
        }
    }
}
