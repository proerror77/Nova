use actix_web::{web, HttpMessage, HttpRequest, HttpResponse, Responder};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use uuid::Uuid;

use crate::db::{comment_repo, post_repo, user_repo};
use crate::handlers::auth::ErrorResponse;
use crate::middleware::UserId;
use crate::models::CommentResponse;

// ============================================
// Request/Response Structs
// ============================================

#[derive(Debug, Deserialize)]
pub struct CreateCommentRequest {
    pub content: String,
    pub parent_comment_id: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateCommentRequest {
    pub content: String,
}

#[derive(Debug, Serialize)]
pub struct CommentListResponse {
    pub comments: Vec<CommentResponse>,
    pub total_count: i32,
    pub limit: i64,
    pub offset: i64,
}

// ============================================
// Constants
// ============================================

const MAX_COMMENT_LENGTH: usize = 5000;
const MIN_COMMENT_LENGTH: usize = 1;

// ============================================
// Handler Functions
// ============================================

/// Create a comment on a post
/// POST /api/v1/posts/{post_id}/comments
pub async fn create_comment(
    http_req: HttpRequest,
    pool: web::Data<PgPool>,
    path: web::Path<String>,
    req: web::Json<CreateCommentRequest>,
) -> impl Responder {
    let user_id = match http_req.extensions().get::<UserId>() {
        Some(user_id_wrapper) => user_id_wrapper.0,
        None => {
            return HttpResponse::Unauthorized().json(ErrorResponse {
                error: "Unauthorized".to_string(),
                details: Some("User ID not found in request".to_string()),
            })
        }
    };

    let post_id_str = path.into_inner();
    let post_id = match Uuid::parse_str(&post_id_str) {
        Ok(id) => id,
        Err(_) => {
            return HttpResponse::BadRequest().json(ErrorResponse {
                error: "Invalid post ID format".to_string(),
                details: None,
            })
        }
    };

    // Validation
    if req.content.trim().is_empty() || req.content.len() < MIN_COMMENT_LENGTH {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Comment content cannot be empty".to_string(),
            details: None,
        });
    }

    if req.content.len() > MAX_COMMENT_LENGTH {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: format!("Comment content exceeds maximum length of {}", MAX_COMMENT_LENGTH),
            details: None,
        });
    }

    // Check if post exists
    match post_repo::find_post_by_id(&pool, post_id).await {
        Ok(Some(_)) => {},
        Ok(None) => {
            return HttpResponse::NotFound().json(ErrorResponse {
                error: "Post not found".to_string(),
                details: None,
            })
        }
        Err(_) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Database error".to_string(),
                details: None,
            })
        }
    }

    // Parse parent_comment_id if provided
    let parent_comment_id = match &req.parent_comment_id {
        Some(id_str) => match Uuid::parse_str(id_str) {
            Ok(id) => Some(id),
            Err(_) => {
                return HttpResponse::BadRequest().json(ErrorResponse {
                    error: "Invalid parent comment ID format".to_string(),
                    details: None,
                })
            }
        },
        None => None,
    };

    // Verify parent comment exists if provided
    if let Some(parent_id) = parent_comment_id {
        match comment_repo::get_comment_by_id(&pool, parent_id).await {
            Ok(Some(_)) => {},
            Ok(None) => {
                return HttpResponse::NotFound().json(ErrorResponse {
                    error: "Parent comment not found".to_string(),
                    details: None,
                })
            }
            Err(_) => {
                return HttpResponse::InternalServerError().json(ErrorResponse {
                    error: "Database error".to_string(),
                    details: None,
                })
            }
        }
    }

    // Create comment
    match comment_repo::create_comment(&pool, post_id, user_id, &req.content, parent_comment_id)
        .await
    {
        Ok(comment) => {
            // Get user info for response
            let user_info = user_repo::find_by_id(&pool, user_id).await.ok().flatten();

            HttpResponse::Created().json(CommentResponse {
                id: comment.id.to_string(),
                post_id: comment.post_id.to_string(),
                user_id: comment.user_id.to_string(),
                username: user_info.as_ref().map(|u| u.username.clone()),
                avatar_url: None, // TODO: Add avatar URL from user profile
                content: comment.content,
                parent_comment_id: comment.parent_comment_id.map(|id| id.to_string()),
                created_at: comment.created_at.to_rfc3339(),
                updated_at: comment.updated_at.to_rfc3339(),
                is_edited: false,
            })
        }
        Err(_) => HttpResponse::InternalServerError().json(ErrorResponse {
            error: "Failed to create comment".to_string(),
            details: None,
        }),
    }
}

/// Get comments for a post
/// GET /api/v1/posts/{post_id}/comments?limit=50&offset=0
pub async fn get_comments(
    pool: web::Data<PgPool>,
    path: web::Path<String>,
    query: web::Query<std::collections::HashMap<String, String>>,
) -> impl Responder {
    let post_id_str = path.into_inner();
    let post_id = match Uuid::parse_str(&post_id_str) {
        Ok(id) => id,
        Err(_) => {
            return HttpResponse::BadRequest().json(ErrorResponse {
                error: "Invalid post ID format".to_string(),
                details: None,
            })
        }
    };

    let limit = query
        .get("limit")
        .and_then(|l| l.parse::<i64>().ok())
        .unwrap_or(50)
        .min(100);

    let offset = query
        .get("offset")
        .and_then(|o| o.parse::<i64>().ok())
        .unwrap_or(0)
        .max(0);

    // Check if post exists
    match post_repo::find_post_by_id(&pool, post_id).await {
        Ok(Some(_)) => {},
        Ok(None) => {
            return HttpResponse::NotFound().json(ErrorResponse {
                error: "Post not found".to_string(),
                details: None,
            })
        }
        Err(_) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Database error".to_string(),
                details: None,
            })
        }
    }

    match tokio::try_join!(
        comment_repo::get_comments_by_post(&pool, post_id, limit, offset),
        comment_repo::count_comments_by_post(&pool, post_id)
    ) {
        Ok((comments, count)) => {
            let mut response_comments = Vec::new();

            for comment in comments {
                let user_info = user_repo::find_by_id(&pool, comment.user_id)
                    .await
                    .ok()
                    .flatten();

                response_comments.push(CommentResponse {
                    id: comment.id.to_string(),
                    post_id: comment.post_id.to_string(),
                    user_id: comment.user_id.to_string(),
                    username: user_info.as_ref().map(|u| u.username.clone()),
                    avatar_url: None,
                    content: comment.content,
                    parent_comment_id: comment.parent_comment_id.map(|id| id.to_string()),
                    created_at: comment.created_at.to_rfc3339(),
                    updated_at: comment.updated_at.to_rfc3339(),
                    is_edited: false,
                });
            }

            HttpResponse::Ok().json(CommentListResponse {
                comments: response_comments,
                total_count: count,
                limit,
                offset,
            })
        }
        Err(_) => HttpResponse::InternalServerError().json(ErrorResponse {
            error: "Failed to fetch comments".to_string(),
            details: None,
        }),
    }
}

/// Update a comment
/// PATCH /api/v1/comments/{comment_id}
pub async fn update_comment(
    http_req: HttpRequest,
    pool: web::Data<PgPool>,
    path: web::Path<String>,
    req: web::Json<UpdateCommentRequest>,
) -> impl Responder {
    let user_id = match http_req.extensions().get::<UserId>() {
        Some(user_id_wrapper) => user_id_wrapper.0,
        None => {
            return HttpResponse::Unauthorized().json(ErrorResponse {
                error: "Unauthorized".to_string(),
                details: None,
            })
        }
    };

    let comment_id_str = path.into_inner();
    let comment_id = match Uuid::parse_str(&comment_id_str) {
        Ok(id) => id,
        Err(_) => {
            return HttpResponse::BadRequest().json(ErrorResponse {
                error: "Invalid comment ID format".to_string(),
                details: None,
            })
        }
    };

    // Validation
    if req.content.trim().is_empty() || req.content.len() < MIN_COMMENT_LENGTH {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: "Comment content cannot be empty".to_string(),
            details: None,
        });
    }

    if req.content.len() > MAX_COMMENT_LENGTH {
        return HttpResponse::BadRequest().json(ErrorResponse {
            error: format!("Comment content exceeds maximum length of {}", MAX_COMMENT_LENGTH),
            details: None,
        });
    }

    // Get comment
    let comment = match comment_repo::get_comment_by_id(&pool, comment_id).await {
        Ok(Some(c)) => c,
        Ok(None) => {
            return HttpResponse::NotFound().json(ErrorResponse {
                error: "Comment not found".to_string(),
                details: None,
            })
        }
        Err(_) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Database error".to_string(),
                details: None,
            })
        }
    };

    // Check ownership
    if comment.user_id != user_id {
        return HttpResponse::Forbidden().json(ErrorResponse {
            error: "You can only edit your own comments".to_string(),
            details: None,
        });
    }

    // Update comment
    match comment_repo::update_comment(&pool, comment_id, &req.content).await {
        Ok(_) => {
            let user_info = user_repo::find_by_id(&pool, comment.user_id)
                .await
                .ok()
                .flatten();

            HttpResponse::Ok().json(CommentResponse {
                id: comment.id.to_string(),
                post_id: comment.post_id.to_string(),
                user_id: comment.user_id.to_string(),
                username: user_info.as_ref().map(|u| u.username.clone()),
                avatar_url: None,
                content: req.content.to_string(),
                parent_comment_id: comment.parent_comment_id.map(|id| id.to_string()),
                created_at: comment.created_at.to_rfc3339(),
                updated_at: chrono::Utc::now().to_rfc3339(),
                is_edited: true,
            })
        }
        Err(_) => HttpResponse::InternalServerError().json(ErrorResponse {
            error: "Failed to update comment".to_string(),
            details: None,
        }),
    }
}

/// Delete a comment
/// DELETE /api/v1/comments/{comment_id}
pub async fn delete_comment(
    http_req: HttpRequest,
    pool: web::Data<PgPool>,
    path: web::Path<String>,
) -> impl Responder {
    let user_id = match http_req.extensions().get::<UserId>() {
        Some(user_id_wrapper) => user_id_wrapper.0,
        None => {
            return HttpResponse::Unauthorized().json(ErrorResponse {
                error: "Unauthorized".to_string(),
                details: None,
            })
        }
    };

    let comment_id_str = path.into_inner();
    let comment_id = match Uuid::parse_str(&comment_id_str) {
        Ok(id) => id,
        Err(_) => {
            return HttpResponse::BadRequest().json(ErrorResponse {
                error: "Invalid comment ID format".to_string(),
                details: None,
            })
        }
    };

    // Get comment
    let comment = match comment_repo::get_comment_by_id(&pool, comment_id).await {
        Ok(Some(c)) => c,
        Ok(None) => {
            return HttpResponse::NotFound().json(ErrorResponse {
                error: "Comment not found".to_string(),
                details: None,
            })
        }
        Err(_) => {
            return HttpResponse::InternalServerError().json(ErrorResponse {
                error: "Database error".to_string(),
                details: None,
            })
        }
    };

    // Check ownership
    if comment.user_id != user_id {
        return HttpResponse::Forbidden().json(ErrorResponse {
            error: "You can only delete your own comments".to_string(),
            details: None,
        });
    }

    // Delete comment (soft delete)
    match comment_repo::soft_delete_comment(&pool, comment_id).await {
        Ok(_) => HttpResponse::NoContent().finish(),
        Err(_) => HttpResponse::InternalServerError().json(ErrorResponse {
            error: "Failed to delete comment".to_string(),
            details: None,
        }),
    }
}
