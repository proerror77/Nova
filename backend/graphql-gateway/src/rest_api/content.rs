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
use serde::{Deserialize, Serialize};
use tracing::{error, info};

use super::models::ErrorResponse;
use crate::clients::proto::content::{
    CreatePostRequest, DeletePostRequest, GetPostRequest, GetUserPostsRequest, UpdatePostRequest,
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

/// GET /api/v2/content/{id}
/// Returns a specific post by ID
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

            let post = grpc_response.post.map(|p| PostResponse {
                id: p.id,
                author_id: p.author_id,
                content: p.content,
                created_at: p.created_at,
                updated_at: p.updated_at,
                status: status_to_string(p.status),
            });

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
/// Returns posts by a specific user
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

    let grpc_request = tonic::Request::new(CreatePostRequest {
        author_id: user_id.clone(),
        content: body.content.clone(),
    });

    match content_client.create_post(grpc_request).await {
        Ok(response) => {
            let grpc_response = response.into_inner();

            if let Some(post) = grpc_response.post {
                info!(
                    user_id = %user_id,
                    post_id = %post.id,
                    "Post created successfully"
                );

                Ok(HttpResponse::Created().json(CreatePostResponse {
                    post: PostResponse {
                        id: post.id,
                        author_id: post.author_id,
                        content: post.content,
                        created_at: post.created_at,
                        updated_at: post.updated_at,
                        status: status_to_string(post.status),
                    },
                }))
            } else {
                error!(user_id = %user_id, "Post creation returned empty response");
                Ok(HttpResponse::InternalServerError()
                    .json(ErrorResponse::new("Failed to create post")))
            }
        }
        Err(status) => {
            error!(
                user_id = %user_id,
                error = %status,
                "Failed to create post"
            );

            let error_response = match status.code() {
                tonic::Code::InvalidArgument => HttpResponse::BadRequest().json(
                    ErrorResponse::with_message("Invalid request", status.message()),
                ),
                _ => HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Failed to create post",
                    status.message(),
                )),
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

                Ok(HttpResponse::Ok().json(CreatePostResponse {
                    post: PostResponse {
                        id: post.id,
                        author_id: post.author_id,
                        content: post.content,
                        created_at: post.created_at,
                        updated_at: post.updated_at,
                        status: status_to_string(post.status),
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
