//! REST API handlers for timeline feed

use actix_web::{web, HttpRequest, HttpResponse, get, post};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use redis::aio::Connection;

use crate::services::feed_timeline::{
    timeline_sort, timeline_sort_with_engagement,
    TimelinePost,
};
use crate::services::feed_timeline::cache::{
    get_feed_cached, invalidate_feed_cache,
};
use crate::error::AppError;
use crate::middleware::jwt::extract_user_id;

/// Query parameters for feed endpoint
#[derive(Debug, Deserialize)]
pub struct FeedQuery {
    /// Number of posts to return (default: 20, max: 100)
    pub limit: Option<i32>,
    /// Pagination offset (default: 0)
    pub offset: Option<i32>,
    /// Sort strategy: \"recent\" or \"engagement\" (default: \"recent\")
    pub sort: Option<String>,
}

/// Feed response wrapper
#[derive(Debug, Serialize)]
pub struct FeedResponse {
    pub posts: Vec<FeedPostDto>,
    pub total: i32,
    pub limit: i32,
}

/// Feed post DTO (Data Transfer Object)
#[derive(Debug, Serialize, Deserialize)]
pub struct FeedPostDto {
    pub id: i32,
    pub user_id: i32,
    pub content: String,
    pub created_at: String,
    pub like_count: i32,
}

impl From<TimelinePost> for FeedPostDto {
    fn from(post: TimelinePost) -> Self {
        FeedPostDto {
            id: post.id,
            user_id: post.user_id,
            content: post.content,
            created_at: post.created_at.to_rfc3339(),
            like_count: post.like_count,
        }
    }
}

/// Get timeline feed for authenticated user
/// 
/// # Query Parameters
/// - `limit`: Number of posts (default: 20, max: 100)
/// - `offset`: Pagination offset (default: 0)
/// - `sort`: Sort strategy - \"recent\" or \"engagement\" (default: \"recent\")
/// 
/// # Returns
/// 200 OK with feed posts, or 401 Unauthorized if not authenticated
#[get(\"/api/v1/feed\")]
pub async fn get_timeline_feed(
    req: HttpRequest,
    query: web::Query<FeedQuery>,
    db: web::Data<PgPool>,
    redis: web::Data<redis::Client>,
) -> Result<HttpResponse, AppError> {
    let user_id = extract_user_id(&req)?;
    
    let limit = query.limit.unwrap_or(20).min(100).max(1);
    let _offset = query.offset.unwrap_or(0).max(0);

    // Get feed from cache or database
    let mut redis_conn = redis.get_async_connection()
        .await
        .map_err(|e| AppError::CacheError(format!(\"Redis connection failed: {}\", e)))?;

    let mut posts = get_feed_cached(user_id, limit, &mut redis_conn, db.get_ref()).await?;

    // Apply sorting strategy
    let sort_strategy = query.sort.as_deref().unwrap_or(\"recent\");
    posts = match sort_strategy {
        \"engagement\" => timeline_sort_with_engagement(posts),
        \"recent\" | _ => timeline_sort(posts),
    };

    let total = posts.len() as i32;
    let posts_dto: Vec<FeedPostDto> = posts.into_iter().map(|p| p.into()).collect();

    Ok(HttpResponse::Ok().json(FeedResponse {
        posts: posts_dto,
        total,
        limit,
    }))
}

/// Get recent timeline feed (shorthand endpoint)
#[get(\"/api/v1/feed/timeline\")]
pub async fn get_recent_feed(
    req: HttpRequest,
    db: web::Data<PgPool>,
    redis: web::Data<redis::Client>,
) -> Result<HttpResponse, AppError> {
    let user_id = extract_user_id(&req)?;
    
    let limit = 20i32;

    let mut redis_conn = redis.get_async_connection()
        .await
        .map_err(|e| AppError::CacheError(format!(\"Redis connection failed: {}\", e)))?;

    let posts = get_feed_cached(user_id, limit, &mut redis_conn, db.get_ref()).await?;
    let sorted_posts = timeline_sort(posts);

    let total = sorted_posts.len() as i32;
    let posts_dto: Vec<FeedPostDto> = sorted_posts.into_iter().map(|p| p.into()).collect();

    Ok(HttpResponse::Ok().json(FeedResponse {
        posts: posts_dto,
        total,
        limit,
    }))
}

/// Refresh feed cache (invalidate cached data)
/// 
/// # Returns
/// 200 OK with success message
#[post(\"/api/v1/feed/refresh\")]
pub async fn refresh_feed_cache(
    req: HttpRequest,
    redis: web::Data<redis::Client>,
) -> Result<HttpResponse, AppError> {
    let user_id = extract_user_id(&req)?;

    let mut redis_conn = redis.get_async_connection()
        .await
        .map_err(|e| AppError::CacheError(format!(\"Redis connection failed: {}\", e)))?;

    invalidate_feed_cache(user_id, &mut redis_conn).await?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        \"status\": \"success\",
        \"message\": \"Feed cache refreshed\",
        \"user_id\": user_id,
    })))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_feed_query_defaults() {
        let query = FeedQuery {
            limit: None,
            offset: None,
            sort: None,
        };
        
        let limit = query.limit.unwrap_or(20).min(100);
        assert_eq!(limit, 20);
        
        let sort = query.sort.as_deref().unwrap_or(\"recent\");
        assert_eq!(sort, \"recent\");
    }

    #[test]
    fn test_feed_response_serialization() {
        let response = FeedResponse {
            posts: vec![],
            total: 0,
            limit: 20,
        };
        
        let json = serde_json::to_string(&response).unwrap();
        assert!(json.contains(\"\\\"total\\\":0\"));
        assert!(json.contains(\"\\\"limit\\\":20\"));
    }

    #[test]
    fn test_feed_post_dto_conversion() {
        let post = TimelinePost {
            id: 1,
            user_id: 123,
            content: \"Test post\".to_string(),
            created_at: chrono::Utc::now(),
            like_count: 42,
        };

        let dto = FeedPostDto::from(post);
        assert_eq!(dto.id, 1);
        assert_eq!(dto.user_id, 123);
        assert_eq!(dto.like_count, 42);
    }
}
