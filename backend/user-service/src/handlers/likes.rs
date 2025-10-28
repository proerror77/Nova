use actix_web::{web, HttpMessage, HttpRequest, HttpResponse, Responder};
use serde::Serialize;
use sqlx::PgPool;
use std::sync::Arc;
use tracing::{debug, error, warn};
use uuid::Uuid;

use crate::db::{like_repo, post_repo};
use crate::error::AppError;
use crate::handlers::auth::ErrorResponse;
use crate::middleware::{CircuitBreaker, UserId};
use crate::models::LikeResponse;

// ============================================
// Likes handler state with Circuit Breaker protection
// ============================================

pub struct LikesHandlerState {
    pub postgres_cb: Arc<CircuitBreaker>, // PostgreSQL circuit breaker for database queries
}

// ============================================
// Response Structs
// ============================================

#[derive(Debug, Serialize)]
pub struct LikeListResponse {
    pub likes: Vec<LikeResponse>,
    pub total_count: i32,
    pub limit: i64,
    pub offset: i64,
}

#[derive(Debug, Serialize)]
pub struct LikeStatusResponse {
    pub post_id: String,
    pub user_id: String,
    pub has_liked: bool,
    pub total_likes: i32,
}

// ============================================
// Handler Functions
// ============================================

/// Like a post
/// POST /api/v1/posts/{post_id}/like
pub async fn like_post(
    http_req: HttpRequest,
    pool: web::Data<PgPool>,
    path: web::Path<String>,
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

    // Check if post exists
    match post_repo::find_post_by_id(&pool, post_id).await {
        Ok(Some(_)) => {}
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

    // Create like
    match like_repo::create_like(&pool, post_id, user_id).await {
        Ok(like) => {
            // Get total likes count
            let total_likes = like_repo::count_likes_by_post(&pool, post_id)
                .await
                .unwrap_or(1);

            HttpResponse::Created().json(LikeResponse {
                id: like.id.to_string(),
                post_id: like.post_id.to_string(),
                user_id: like.user_id.to_string(),
                created_at: like.created_at.to_rfc3339(),
            })
        }
        Err(_) => HttpResponse::InternalServerError().json(ErrorResponse {
            error: "Failed to like post".to_string(),
            details: None,
        }),
    }
}

/// Unlike a post
/// DELETE /api/v1/posts/{post_id}/like
pub async fn unlike_post(
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

    // Check if post exists
    match post_repo::find_post_by_id(&pool, post_id).await {
        Ok(Some(_)) => {}
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

    // Delete like
    match like_repo::delete_like(&pool, post_id, user_id).await {
        Ok(_) => HttpResponse::NoContent().finish(),
        Err(_) => HttpResponse::InternalServerError().json(ErrorResponse {
            error: "Failed to unlike post".to_string(),
            details: None,
        }),
    }
}

/// Get likes for a post
/// GET /api/v1/posts/{post_id}/likes?limit=50&offset=0
pub async fn get_post_likes(
    pool: web::Data<PgPool>,
    path: web::Path<String>,
    query: web::Query<std::collections::HashMap<String, String>>,
    state: web::Data<LikesHandlerState>,
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

    debug!("Getting likes for post: post_id={} limit={} offset={}", post_id, limit, offset);

    // Check if post exists with CB protection
    match state
        .postgres_cb
        .call(|| {
            let pool_clone = pool.clone();
            async move {
                post_repo::find_post_by_id(&pool_clone, post_id)
                    .await
                    .map_err(|e| AppError::Internal(e.to_string()))
            }
        })
        .await
    {
        Ok(Some(_)) => {}
        Ok(None) => {
            return HttpResponse::NotFound().json(ErrorResponse {
                error: "Post not found".to_string(),
                details: None,
            })
        }
        Err(e) => {
            match &e {
                AppError::Internal(msg) if msg.contains("Circuit breaker is OPEN") => {
                    warn!("PostgreSQL circuit is OPEN for post lookup, returning empty likes");
                    // Graceful degradation: return empty likes list
                    return HttpResponse::Ok().json(LikeListResponse {
                        likes: Vec::new(),
                        total_count: 0,
                        limit,
                        offset,
                    });
                }
                _ => {
                    error!("Failed to check if post exists: {}", e);
                    return HttpResponse::InternalServerError().json(ErrorResponse {
                        error: "Database error".to_string(),
                        details: None,
                    })
                }
            }
        }
    }

    // Fetch likes with CB protection
    match state
        .postgres_cb
        .call(|| {
            let pool_clone = pool.clone();
            async move {
                tokio::try_join!(
                    like_repo::get_likes_by_post(&pool_clone, post_id, limit, offset),
                    like_repo::count_likes_by_post(&pool_clone, post_id)
                )
                .map_err(|e| AppError::Internal(e.to_string()))
            }
        })
        .await
    {
        Ok((likes, count)) => {
            let response_likes: Vec<LikeResponse> = likes
                .into_iter()
                .map(|like| LikeResponse {
                    id: like.id.to_string(),
                    post_id: like.post_id.to_string(),
                    user_id: like.user_id.to_string(),
                    created_at: like.created_at.to_rfc3339(),
                })
                .collect();

            debug!("Fetched {} likes for post: {}", response_likes.len(), post_id);

            HttpResponse::Ok().json(LikeListResponse {
                likes: response_likes,
                total_count: count,
                limit,
                offset,
            })
        }
        Err(e) => {
            match &e {
                AppError::Internal(msg) if msg.contains("Circuit breaker is OPEN") => {
                    warn!("PostgreSQL circuit is OPEN for likes query, returning empty results");
                    HttpResponse::Ok().json(LikeListResponse {
                        likes: Vec::new(),
                        total_count: 0,
                        limit,
                        offset,
                    })
                }
                _ => {
                    error!("Failed to fetch likes: {}", e);
                    HttpResponse::InternalServerError().json(ErrorResponse {
                        error: "Failed to fetch likes".to_string(),
                        details: None,
                    })
                }
            }
        }
    }
}

/// Check if current user likes a post and get total count
/// GET /api/v1/posts/{post_id}/like/status
pub async fn check_like_status(
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

    // Check if post exists
    match post_repo::find_post_by_id(&pool, post_id).await {
        Ok(Some(_)) => {}
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
        like_repo::has_liked(&pool, post_id, user_id),
        like_repo::count_likes_by_post(&pool, post_id)
    ) {
        Ok((has_liked, total_likes)) => HttpResponse::Ok().json(LikeStatusResponse {
            post_id: post_id.to_string(),
            user_id: user_id.to_string(),
            has_liked,
            total_likes,
        }),
        Err(_) => HttpResponse::InternalServerError().json(ErrorResponse {
            error: "Failed to check like status".to_string(),
            details: None,
        }),
    }
}
