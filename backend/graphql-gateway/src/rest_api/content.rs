//! Content API endpoints
//!
//! GET /api/v2/content/{id} - Get a specific post
//! GET /api/v2/content/user/{user_id} - Get posts by user
//! POST /api/v2/content - Create a new post
//! PUT /api/v2/content/{id} - Update a post
//! DELETE /api/v2/content/{id} - Delete a post
//!
//! Response DTOs prepared for JSON serialization

#![allow(dead_code)]

use actix_web::{web, HttpMessage, HttpRequest, HttpResponse, Result};
use resilience::retry::{with_retry, RetryConfig};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::time::Duration;
use tracing::{error, info, warn};

use super::models::ErrorResponse;
use crate::clients::proto::auth::GetUserProfilesByIdsRequest;
use crate::clients::proto::content::{
    CreatePostRequest, DeletePostRequest, GetPostRequest, GetUserLikedPostsRequest,
    GetUserPostsRequest, GetUserSavedPostsRequest, UpdatePostRequest,
};
use crate::clients::ServiceClients;
use crate::middleware::jwt::AuthenticatedUser;

/// REST API response for post
#[derive(Debug, Serialize)]
pub struct PostResponse {
    pub id: String,
    pub author_id: String,
    pub content: String,
    pub created_at: i64,
    pub updated_at: i64,
    pub status: String,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub media_urls: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub media_type: Option<String>,
    // Author information (enriched from auth-service)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub author_username: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub author_display_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub author_avatar_url: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct GetPostResponse {
    pub post: Option<PostResponse>,
    pub found: bool,
}

#[derive(Debug, Serialize)]
pub struct GetUserPostsResponse {
    pub posts: Vec<PostResponse>,
    pub total_count: i32,
    pub has_more: bool,
}

#[derive(Debug, Serialize)]
pub struct CreatePostResponse {
    pub post: PostResponse,
}

#[derive(Debug, Serialize)]
pub struct DeletePostResponse {
    pub post_id: String,
    pub deleted_at: i64,
}

#[derive(Debug, Deserialize)]
pub struct CreatePostBody {
    pub content: String,
    pub media_urls: Option<Vec<String>>,
    pub media_type: Option<String>,
    pub channel_ids: Option<Vec<String>>, // Channel UUIDs or slugs (max 3)
}

#[derive(Debug, Deserialize)]
pub struct UpdatePostBody {
    pub content: Option<String>,
    pub visibility: Option<String>,
    pub comments_enabled: Option<bool>,
}

#[derive(Debug, Deserialize)]
pub struct UserPostsQueryParams {
    pub limit: Option<i32>,
    pub offset: Option<i32>,
}

fn status_to_string(status: i32) -> String {
    match status {
        1 => "draft".to_string(),
        2 => "published".to_string(),
        3 => "moderated".to_string(),
        4 => "deleted".to_string(),
        _ => "unknown".to_string(),
    }
}

/// Helper struct to hold author information
#[derive(Debug, Clone, Default)]
struct AuthorInfo {
    username: Option<String>,
    display_name: Option<String>,
    avatar_url: Option<String>,
}

/// Fetch author info for a list of author IDs
/// Returns a HashMap mapping author_id to AuthorInfo
async fn fetch_author_info(
    author_ids: Vec<String>,
    clients: &ServiceClients,
) -> HashMap<String, AuthorInfo> {
    if author_ids.is_empty() {
        return HashMap::new();
    }

    let mut auth_client = clients.auth_client();
    let request = tonic::Request::new(GetUserProfilesByIdsRequest {
        user_ids: author_ids,
    });

    match auth_client.get_user_profiles_by_ids(request).await {
        Ok(response) => {
            let profiles = response.into_inner().profiles;
            profiles
                .into_iter()
                .map(|p| {
                    // Use display_name if available, otherwise username
                    let display_name = p.display_name.clone().or_else(|| {
                        if !p.username.is_empty() {
                            Some(p.username.clone())
                        } else {
                            None
                        }
                    });

                    (
                        p.user_id.clone(),
                        AuthorInfo {
                            username: Some(p.username),
                            display_name,
                            avatar_url: p.avatar_url,
                        },
                    )
                })
                .collect()
        }
        Err(status) => {
            warn!(
                error = %status,
                "Failed to fetch author profiles from auth-service"
            );
            HashMap::new()
        }
    }
}

/// GET /api/v2/content/{id}
/// Returns a specific post by ID with enriched author information
pub async fn get_post(
    path: web::Path<String>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let post_id = path.into_inner();

    info!(post_id = %post_id, "GET /api/v2/content/{{id}}");

    let mut content_client = clients.content_client();

    let grpc_request = tonic::Request::new(GetPostRequest {
        post_id: post_id.clone(),
    });

    match content_client.get_post(grpc_request).await {
        Ok(response) => {
            let grpc_response = response.into_inner();

            // Enrich post with author information if post exists
            let post = if let Some(p) = grpc_response.post {
                let author_id = p.author_id.clone();

                // Fetch author info
                let author_map = fetch_author_info(vec![author_id.clone()], &clients).await;
                let author_info = author_map.get(&author_id).cloned().unwrap_or_default();

                Some(PostResponse {
                    id: p.id,
                    author_id: p.author_id,
                    content: p.content,
                    created_at: p.created_at,
                    updated_at: p.updated_at,
                    status: status_to_string(p.status),
                    media_urls: p.media_urls,
                    media_type: if p.media_type.is_empty() {
                        None
                    } else {
                        Some(p.media_type)
                    },
                    author_username: author_info.username,
                    author_display_name: author_info.display_name,
                    author_avatar_url: author_info.avatar_url,
                })
            } else {
                None
            };

            info!(post_id = %post_id, found = grpc_response.found, "Post retrieved");

            Ok(HttpResponse::Ok().json(GetPostResponse {
                post,
                found: grpc_response.found,
            }))
        }
        Err(status) => {
            error!(
                post_id = %post_id,
                error = %status,
                "Failed to get post from content-service"
            );

            let error_response = match status.code() {
                tonic::Code::NotFound => {
                    HttpResponse::NotFound().json(ErrorResponse::new("Post not found"))
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

/// GET /api/v2/content/user/{user_id}
/// Returns posts by a specific user with enriched author information
pub async fn get_user_posts(
    path: web::Path<String>,
    clients: web::Data<ServiceClients>,
    query: web::Query<UserPostsQueryParams>,
) -> Result<HttpResponse> {
    let user_id = path.into_inner();
    let limit = query.limit.unwrap_or(20).min(100);
    let offset = query.offset.unwrap_or(0);

    info!(
        user_id = %user_id,
        limit = %limit,
        offset = %offset,
        "GET /api/v2/content/user/{user_id}"
    );

    let mut content_client = clients.content_client();

    let grpc_request = tonic::Request::new(GetUserPostsRequest {
        user_id: user_id.clone(),
        limit,
        offset,
        status: 2, // PUBLISHED
    });

    match content_client.get_user_posts(grpc_request).await {
        Ok(response) => {
            let grpc_response = response.into_inner();

            // All posts are from the same user, so fetch author info once
            let author_map = fetch_author_info(vec![user_id.clone()], &clients).await;
            let author_info = author_map.get(&user_id).cloned().unwrap_or_default();

            let posts = grpc_response
                .posts
                .into_iter()
                .map(|p| PostResponse {
                    id: p.id,
                    author_id: p.author_id,
                    content: p.content,
                    created_at: p.created_at,
                    updated_at: p.updated_at,
                    status: status_to_string(p.status),
                    media_urls: p.media_urls,
                    media_type: if p.media_type.is_empty() {
                        None
                    } else {
                        Some(p.media_type)
                    },
                    author_username: author_info.username.clone(),
                    author_display_name: author_info.display_name.clone(),
                    author_avatar_url: author_info.avatar_url.clone(),
                })
                .collect();

            info!(
                user_id = %user_id,
                total_count = grpc_response.total_count,
                "User posts retrieved"
            );

            Ok(HttpResponse::Ok().json(GetUserPostsResponse {
                posts,
                total_count: grpc_response.total_count,
                has_more: grpc_response.has_more,
            }))
        }
        Err(status) => {
            error!(
                user_id = %user_id,
                error = %status,
                "Failed to get user posts from content-service"
            );

            Ok(
                HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Failed to get user posts",
                    status.message(),
                )),
            )
        }
    }
}

/// POST /api/v2/content
/// Create a new post
pub async fn create_post(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
    body: web::Json<CreatePostBody>,
) -> Result<HttpResponse> {
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    info!(user_id = %user_id, "POST /api/v2/content");

    let mut content_client = clients.content_client();

    // Validate channel_ids limit (max 3)
    let channel_ids = body.channel_ids.clone().unwrap_or_default();
    if channel_ids.len() > 3 {
        return Ok(HttpResponse::BadRequest()
            .json(ErrorResponse::new("Maximum 3 channels allowed per post")));
    }

    let grpc_request = tonic::Request::new(CreatePostRequest {
        author_id: user_id.clone(),
        content: body.content.clone(),
        media_urls: body.media_urls.clone().unwrap_or_default(),
        media_type: body.media_type.clone().unwrap_or_else(|| {
            if body
                .media_urls
                .as_ref()
                .map(|urls| !urls.is_empty())
                .unwrap_or(false)
            {
                "image".to_string()
            } else {
                "text".to_string() // Text-only post
            }
        }),
        channel_ids,
        author_account_type: String::new(), // Default to primary (Issue #259)
    });

    // Retry config for transient failures (503 Service Unavailable)
    let retry_config = RetryConfig {
        max_retries: 3,
        initial_backoff: Duration::from_millis(100),
        max_backoff: Duration::from_secs(2),
        backoff_multiplier: 2.0,
        jitter: true,
    };

    // Clone values needed for retry closure
    let user_id_for_retry = user_id.clone();

    // Execute with retry for transient errors
    let result = with_retry(retry_config, || {
        let mut client = clients.content_client();
        let request = tonic::Request::new(grpc_request.get_ref().clone());
        let user_id = user_id_for_retry.clone();

        async move {
            match client.create_post(request).await {
                Ok(response) => Ok(response),
                Err(status) => {
                    // Only retry on transient errors (Unavailable = 503)
                    match status.code() {
                        tonic::Code::Unavailable | tonic::Code::ResourceExhausted => {
                            warn!(
                                user_id = %user_id,
                                code = ?status.code(),
                                "Content service temporarily unavailable, will retry"
                            );
                            Err(status)
                        }
                        // Don't retry other errors
                        _ => Err(status),
                    }
                }
            }
        }
    })
    .await;

    match result {
        Ok(response) => {
            let grpc_response = response.into_inner();

            if let Some(post) = grpc_response.post {
                info!(
                    user_id = %user_id,
                    post_id = %post.id,
                    "Post created successfully"
                );

                // Fetch author info for the newly created post
                let author_map = fetch_author_info(vec![user_id.clone()], &clients).await;
                let author_info = author_map.get(&user_id).cloned().unwrap_or_default();

                Ok(HttpResponse::Created().json(CreatePostResponse {
                    post: PostResponse {
                        id: post.id,
                        author_id: post.author_id,
                        content: post.content,
                        created_at: post.created_at,
                        updated_at: post.updated_at,
                        status: status_to_string(post.status),
                        media_urls: post.media_urls,
                        media_type: if post.media_type.is_empty() {
                            None
                        } else {
                            Some(post.media_type)
                        },
                        author_username: author_info.username,
                        author_display_name: author_info.display_name,
                        author_avatar_url: author_info.avatar_url,
                    },
                }))
            } else {
                error!(user_id = %user_id, "Post creation returned empty response");
                Ok(HttpResponse::InternalServerError()
                    .json(ErrorResponse::new("Failed to create post")))
            }
        }
        Err(retry_err) => {
            // Extract the original gRPC error if available
            let error_response = match retry_err {
                resilience::retry::RetryError::MaxRetriesExceeded(_) => {
                    error!(
                        user_id = %user_id,
                        "Content service unavailable after retries"
                    );
                    HttpResponse::ServiceUnavailable().json(ErrorResponse::with_message(
                        "Service temporarily unavailable",
                        "Content service is not responding. Please try again later.",
                    ))
                }
                resilience::retry::RetryError::OperationFailed(status) => {
                    error!(
                        user_id = %user_id,
                        error = %status,
                        "Failed to create post"
                    );

                    match status.code() {
                        tonic::Code::InvalidArgument => HttpResponse::BadRequest().json(
                            ErrorResponse::with_message("Invalid request", status.message()),
                        ),
                        tonic::Code::Unavailable => {
                            HttpResponse::ServiceUnavailable().json(ErrorResponse::with_message(
                                "Service temporarily unavailable",
                                status.message(),
                            ))
                        }
                        _ => HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                            "Failed to create post",
                            status.message(),
                        )),
                    }
                }
            };

            Ok(error_response)
        }
    }
}

/// PUT /api/v2/content/{id}
/// Update an existing post
pub async fn update_post(
    req: HttpRequest,
    path: web::Path<String>,
    clients: web::Data<ServiceClients>,
    body: web::Json<UpdatePostBody>,
) -> Result<HttpResponse> {
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    let post_id = path.into_inner();

    info!(
        user_id = %user_id,
        post_id = %post_id,
        "PUT /api/v2/content/{{id}}"
    );

    let mut content_client = clients.content_client();

    // Convert visibility string to enum value
    let visibility = body
        .visibility
        .as_ref()
        .map(|v| match v.as_str() {
            "public" => 1,
            "followers" => 2,
            "private" => 3,
            _ => 0,
        })
        .unwrap_or(0);

    let grpc_request = tonic::Request::new(UpdatePostRequest {
        post_id: post_id.clone(),
        content: body.content.clone().unwrap_or_default(),
        visibility,
        comments_enabled: body.comments_enabled.unwrap_or(true),
    });

    match content_client.update_post(grpc_request).await {
        Ok(response) => {
            let grpc_response = response.into_inner();

            if let Some(post) = grpc_response.post {
                info!(
                    user_id = %user_id,
                    post_id = %post.id,
                    "Post updated successfully"
                );

                // Fetch author info for the updated post
                let author_id = post.author_id.clone();
                let author_map = fetch_author_info(vec![author_id.clone()], &clients).await;
                let author_info = author_map.get(&author_id).cloned().unwrap_or_default();

                Ok(HttpResponse::Ok().json(CreatePostResponse {
                    post: PostResponse {
                        id: post.id,
                        author_id: post.author_id,
                        content: post.content,
                        created_at: post.created_at,
                        updated_at: post.updated_at,
                        status: status_to_string(post.status),
                        media_urls: post.media_urls,
                        media_type: if post.media_type.is_empty() {
                            None
                        } else {
                            Some(post.media_type)
                        },
                        author_username: author_info.username,
                        author_display_name: author_info.display_name,
                        author_avatar_url: author_info.avatar_url,
                    },
                }))
            } else {
                Ok(HttpResponse::NotFound().json(ErrorResponse::new("Post not found")))
            }
        }
        Err(status) => {
            error!(
                user_id = %user_id,
                post_id = %post_id,
                error = %status,
                "Failed to update post"
            );

            let error_response = match status.code() {
                tonic::Code::NotFound => {
                    HttpResponse::NotFound().json(ErrorResponse::new("Post not found"))
                }
                tonic::Code::PermissionDenied => HttpResponse::Forbidden()
                    .json(ErrorResponse::new("Not authorized to update this post")),
                _ => HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Failed to update post",
                    status.message(),
                )),
            };

            Ok(error_response)
        }
    }
}

/// DELETE /api/v2/content/{id}
/// Delete a post
pub async fn delete_post(
    req: HttpRequest,
    path: web::Path<String>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    let post_id = path.into_inner();

    info!(
        user_id = %user_id,
        post_id = %post_id,
        "DELETE /api/v2/content/{{id}}"
    );

    let mut content_client = clients.content_client();

    let grpc_request = tonic::Request::new(DeletePostRequest {
        post_id: post_id.clone(),
        user_id: user_id.clone(),
    });

    match content_client.delete_post(grpc_request).await {
        Ok(response) => {
            let grpc_response = response.into_inner();

            info!(
                user_id = %user_id,
                post_id = %grpc_response.post_id,
                "Post deleted successfully"
            );

            Ok(HttpResponse::Ok().json(DeletePostResponse {
                post_id: grpc_response.post_id,
                deleted_at: grpc_response.deleted_at,
            }))
        }
        Err(status) => {
            error!(
                user_id = %user_id,
                post_id = %post_id,
                error = %status,
                "Failed to delete post"
            );

            let error_response = match status.code() {
                tonic::Code::NotFound => {
                    HttpResponse::NotFound().json(ErrorResponse::new("Post not found"))
                }
                tonic::Code::PermissionDenied => HttpResponse::Forbidden()
                    .json(ErrorResponse::new("Not authorized to delete this post")),
                _ => HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Failed to delete post",
                    status.message(),
                )),
            };

            Ok(error_response)
        }
    }
}

// ============================================================================
// SQL JOIN OPTIMIZED ENDPOINTS FOR LIKED/SAVED POSTS
// ============================================================================

/// GET /api/v1/posts/user/{user_id}/liked
///
/// ⚠️ DEPRECATED: This endpoint reads from nova_content.likes which is no longer updated.
/// Use GET /api/v2/social/users/{user_id}/liked-posts instead, which reads from nova_social.likes.
///
/// This endpoint will be removed after 2026-04-01.
///
/// Background:
/// - Writes go to nova_social.likes via POST /api/v2/social/like
/// - This endpoint reads from nova_content.likes (stale data)
/// - iOS clients have been updated to use social-service endpoints
///
/// Get posts liked by a user using SQL JOIN for single-query efficiency
/// Returns full Post objects with author information (not just IDs)
#[deprecated(
    since = "2026-01-09",
    note = "Use GET /api/v2/social/users/{user_id}/liked-posts instead. This endpoint reads from stale data."
)]
pub async fn get_user_liked_posts(
    path: web::Path<String>,
    clients: web::Data<ServiceClients>,
    query: web::Query<UserPostsQueryParams>,
) -> Result<HttpResponse> {
    let user_id = path.into_inner();
    let limit = query.limit.unwrap_or(20).min(100);
    let offset = query.offset.unwrap_or(0);

    info!(
        user_id = %user_id,
        limit = %limit,
        offset = %offset,
        "GET /api/v1/posts/user/{user_id}/liked"
    );

    let mut content_client = clients.content_client();

    let grpc_request = tonic::Request::new(GetUserLikedPostsRequest {
        user_id: user_id.clone(),
        limit,
        offset,
    });

    match content_client.get_user_liked_posts(grpc_request).await {
        Ok(response) => {
            let grpc_response = response.into_inner();

            // Collect unique author IDs for batch profile lookup
            let author_ids: Vec<String> = grpc_response
                .posts
                .iter()
                .map(|p| p.author_id.clone())
                .collect::<std::collections::HashSet<_>>()
                .into_iter()
                .collect();

            // Batch fetch author info
            let author_map = fetch_author_info(author_ids, &clients).await;

            let posts: Vec<PostResponse> = grpc_response
                .posts
                .into_iter()
                .map(|p| {
                    let author_info = author_map.get(&p.author_id).cloned().unwrap_or_default();
                    PostResponse {
                        id: p.id,
                        author_id: p.author_id,
                        content: p.content,
                        created_at: p.created_at,
                        updated_at: p.updated_at,
                        status: status_to_string(p.status),
                        media_urls: p.media_urls,
                        media_type: if p.media_type.is_empty() {
                            None
                        } else {
                            Some(p.media_type)
                        },
                        author_username: author_info.username,
                        author_display_name: author_info.display_name,
                        author_avatar_url: author_info.avatar_url,
                    }
                })
                .collect();

            info!(
                user_id = %user_id,
                total_count = grpc_response.total_count,
                returned = posts.len(),
                "User liked posts retrieved"
            );

            Ok(HttpResponse::Ok().json(GetUserPostsResponse {
                posts,
                total_count: grpc_response.total_count,
                has_more: grpc_response.has_more,
            }))
        }
        Err(status) => {
            error!(
                user_id = %user_id,
                error = %status,
                "Failed to get user liked posts from content-service"
            );

            Ok(
                HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Failed to get liked posts",
                    status.message(),
                )),
            )
        }
    }
}

/// GET /api/v1/posts/user/{user_id}/saved
///
/// ⚠️ DEPRECATED: This endpoint reads from nova_content.bookmarks which is no longer updated.
/// Use GET /api/v2/social/saved-posts instead, which reads from nova_social.saved_posts.
///
/// This endpoint will be removed after 2026-04-01.
///
/// Background:
/// - Writes go to nova_social.saved_posts via POST /api/v2/social/save
/// - This endpoint reads from nova_content.bookmarks (stale data)
/// - iOS clients have been updated to use social-service endpoints
///
/// Get posts saved/bookmarked by a user using SQL JOIN for single-query efficiency
/// Returns full Post objects with author information (not just IDs)
#[deprecated(
    since = "2026-01-09",
    note = "Use GET /api/v2/social/saved-posts instead. This endpoint reads from stale data."
)]
pub async fn get_user_saved_posts(
    path: web::Path<String>,
    clients: web::Data<ServiceClients>,
    query: web::Query<UserPostsQueryParams>,
) -> Result<HttpResponse> {
    let user_id = path.into_inner();
    let limit = query.limit.unwrap_or(20).min(100);
    let offset = query.offset.unwrap_or(0);

    info!(
        user_id = %user_id,
        limit = %limit,
        offset = %offset,
        "GET /api/v1/posts/user/{user_id}/saved"
    );

    let mut content_client = clients.content_client();

    let grpc_request = tonic::Request::new(GetUserSavedPostsRequest {
        user_id: user_id.clone(),
        limit,
        offset,
    });

    match content_client.get_user_saved_posts(grpc_request).await {
        Ok(response) => {
            let grpc_response = response.into_inner();

            // Collect unique author IDs for batch profile lookup
            let author_ids: Vec<String> = grpc_response
                .posts
                .iter()
                .map(|p| p.author_id.clone())
                .collect::<std::collections::HashSet<_>>()
                .into_iter()
                .collect();

            // Batch fetch author info
            let author_map = fetch_author_info(author_ids, &clients).await;

            let posts: Vec<PostResponse> = grpc_response
                .posts
                .into_iter()
                .map(|p| {
                    let author_info = author_map.get(&p.author_id).cloned().unwrap_or_default();
                    PostResponse {
                        id: p.id,
                        author_id: p.author_id,
                        content: p.content,
                        created_at: p.created_at,
                        updated_at: p.updated_at,
                        status: status_to_string(p.status),
                        media_urls: p.media_urls,
                        media_type: if p.media_type.is_empty() {
                            None
                        } else {
                            Some(p.media_type)
                        },
                        author_username: author_info.username,
                        author_display_name: author_info.display_name,
                        author_avatar_url: author_info.avatar_url,
                    }
                })
                .collect();

            info!(
                user_id = %user_id,
                total_count = grpc_response.total_count,
                returned = posts.len(),
                "User saved posts retrieved"
            );

            Ok(HttpResponse::Ok().json(GetUserPostsResponse {
                posts,
                total_count: grpc_response.total_count,
                has_more: grpc_response.has_more,
            }))
        }
        Err(status) => {
            error!(
                user_id = %user_id,
                error = %status,
                "Failed to get user saved posts from content-service"
            );

            Ok(
                HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Failed to get saved posts",
                    status.message(),
                )),
            )
        }
    }
}
