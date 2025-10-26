/// Trending/Discovery API Handlers
///
/// HTTP endpoints for trending content discovery
use actix_web::{get, post, web, HttpMessage, HttpRequest, HttpResponse};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use tracing::{debug, error};
use uuid::Uuid;

use crate::db::trending_repo::{ContentType, EventType, TimeWindow};
use crate::error::{AppError, Result};
use crate::middleware::jwt_auth::UserId;
use crate::services::trending::TrendingService;

/// Query parameters for GET /trending
#[derive(Debug, Deserialize)]
pub struct TrendingQuery {
    /// Time window: "1h", "24h", "7d", "all"
    #[serde(default = "default_time_window")]
    pub time_window: String,

    /// Category filter (optional)
    pub category: Option<String>,

    /// Limit (default: 20, max: 100)
    #[serde(default = "default_limit")]
    pub limit: usize,
}

fn default_time_window() -> String {
    "24h".to_string()
}

fn default_limit() -> usize {
    20
}

/// Engagement event request
#[derive(Debug, Deserialize)]
pub struct EngagementRequest {
    pub content_id: String,
    pub content_type: String, // "video", "post", "stream"
    pub event_type: String,   // "view", "like", "share", "comment"
}

/// GET /api/v1/trending
///
/// Get trending content across all types or filtered by category
///
/// Query parameters:
/// - time_window: "1h", "24h", "7d", "all" (default: "24h")
/// - category: Optional category filter
/// - limit: Max results (default: 20, max: 100)
///
/// Response:
/// ```json
/// {
///   "items": [
///     {
///       "rank": 1,
///       "content_id": "uuid",
///       "content_type": "video",
///       "score": 450.23,
///       "views_count": 15000,
///       "likes_count": 1200,
///       "shares_count": 450,
///       "comments_count": 300,
///       "title": "Amazing Video",
///       "creator_username": "johndoe",
///       "thumbnail_url": "https://..."
///     }
///   ],
///   "count": 20,
///   "time_window": "24h",
///   "category": null
/// }
/// ```
#[get("/api/v1/trending")]
pub async fn get_trending(
    query: web::Query<TrendingQuery>,
    pool: web::Data<PgPool>,
    redis: Option<web::Data<redis::aio::ConnectionManager>>,
) -> Result<HttpResponse> {
    debug!(
        "Trending request: window={}, category={:?}, limit={}",
        query.time_window, query.category, query.limit
    );

    // Parse time window
    let time_window = parse_time_window(&query.time_window)?;

    // Validate limit
    let limit = query.limit.clamp(1, 100);

    // Create service
    let service = TrendingService::new(pool.get_ref().clone(), redis.map(|r| r.get_ref().clone()));

    // Get trending content
    let response = service
        .get_trending(time_window, query.category.as_deref(), limit)
        .await?;

    Ok(HttpResponse::Ok().json(response))
}

/// GET /api/v1/trending/videos
///
/// Get trending videos only
#[get("/api/v1/trending/videos")]
pub async fn get_trending_videos(
    query: web::Query<TrendingQuery>,
    pool: web::Data<PgPool>,
    redis: Option<web::Data<redis::aio::ConnectionManager>>,
) -> Result<HttpResponse> {
    let time_window = parse_time_window(&query.time_window)?;
    let limit = query.limit.clamp(1, 100);

    let service = TrendingService::new(pool.get_ref().clone(), redis.map(|r| r.get_ref().clone()));

    let response = service
        .get_trending_by_type(ContentType::Video, time_window, limit)
        .await?;

    Ok(HttpResponse::Ok().json(response))
}

/// GET /api/v1/trending/posts
///
/// Get trending posts only
#[get("/api/v1/trending/posts")]
pub async fn get_trending_posts(
    query: web::Query<TrendingQuery>,
    pool: web::Data<PgPool>,
    redis: Option<web::Data<redis::aio::ConnectionManager>>,
) -> Result<HttpResponse> {
    let time_window = parse_time_window(&query.time_window)?;
    let limit = query.limit.clamp(1, 100);

    let service = TrendingService::new(pool.get_ref().clone(), redis.map(|r| r.get_ref().clone()));

    let response = service
        .get_trending_by_type(ContentType::Post, time_window, limit)
        .await?;

    Ok(HttpResponse::Ok().json(response))
}

/// GET /api/v1/trending/streams
///
/// Get trending live streams only
#[get("/api/v1/trending/streams")]
pub async fn get_trending_streams(
    query: web::Query<TrendingQuery>,
    pool: web::Data<PgPool>,
    redis: Option<web::Data<redis::aio::ConnectionManager>>,
) -> Result<HttpResponse> {
    let time_window = parse_time_window(&query.time_window)?;
    let limit = query.limit.clamp(1, 100);

    let service = TrendingService::new(pool.get_ref().clone(), redis.map(|r| r.get_ref().clone()));

    let response = service
        .get_trending_by_type(ContentType::Stream, time_window, limit)
        .await?;

    Ok(HttpResponse::Ok().json(response))
}

/// GET /api/v1/trending/categories
///
/// Get available trending categories
///
/// Response:
/// ```json
/// {
///   "categories": [
///     { "name": "entertainment", "label": "Entertainment" },
///     { "name": "news", "label": "News" },
///     { "name": "sports", "label": "Sports" }
///   ]
/// }
/// ```
#[get("/api/v1/trending/categories")]
pub async fn get_trending_categories() -> HttpResponse {
    #[derive(Serialize)]
    struct Category {
        name: String,
        label: String,
    }

    let categories = vec![
        Category {
            name: "entertainment".to_string(),
            label: "Entertainment".to_string(),
        },
        Category {
            name: "news".to_string(),
            label: "News".to_string(),
        },
        Category {
            name: "sports".to_string(),
            label: "Sports".to_string(),
        },
        Category {
            name: "gaming".to_string(),
            label: "Gaming".to_string(),
        },
        Category {
            name: "music".to_string(),
            label: "Music".to_string(),
        },
        Category {
            name: "education".to_string(),
            label: "Education".to_string(),
        },
        Category {
            name: "technology".to_string(),
            label: "Technology".to_string(),
        },
    ];

    HttpResponse::Ok().json(serde_json::json!({ "categories": categories }))
}

/// POST /api/v1/trending/engagement
///
/// Record an engagement event (authenticated endpoint)
///
/// Request body:
/// ```json
/// {
///   "content_id": "uuid",
///   "content_type": "video",
///   "event_type": "view"
/// }
/// ```
#[post("/api/v1/trending/engagement")]
pub async fn record_engagement(
    req: HttpRequest,
    body: web::Json<EngagementRequest>,
    pool: web::Data<PgPool>,
    redis: Option<web::Data<redis::aio::ConnectionManager>>,
) -> Result<HttpResponse> {
    // Get authenticated user
    let user_id = req
        .extensions()
        .get::<UserId>()
        .map(|u| u.0)
        .ok_or_else(|| AppError::Authentication("Missing user context".into()))?;

    // Parse content_id
    let content_id = Uuid::parse_str(&body.content_id)
        .map_err(|_| AppError::BadRequest("Invalid content_id format".to_string()))?;

    // Parse content_type
    let content_type = parse_content_type(&body.content_type)?;

    // Parse event_type
    let event_type = parse_event_type(&body.event_type)?;

    debug!(
        "Recording engagement: user={}, content={}, type={}, event={}",
        user_id, content_id, body.content_type, body.event_type
    );

    // Create service
    let service = TrendingService::new(pool.get_ref().clone(), redis.map(|r| r.get_ref().clone()));

    // Record engagement
    service
        .record_engagement(content_id, content_type, user_id, event_type)
        .await?;

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "success": true,
        "message": "Engagement recorded"
    })))
}

/// Parse time window string
fn parse_time_window(s: &str) -> Result<TimeWindow> {
    match s {
        "1h" => Ok(TimeWindow::OneHour),
        "24h" => Ok(TimeWindow::TwentyFourHours),
        "7d" => Ok(TimeWindow::SevenDays),
        "all" => Ok(TimeWindow::All),
        _ => Err(AppError::BadRequest(format!(
            "Invalid time_window: {}. Must be one of: 1h, 24h, 7d, all",
            s
        ))),
    }
}

/// Parse content type string
fn parse_content_type(s: &str) -> Result<ContentType> {
    match s.to_lowercase().as_str() {
        "video" => Ok(ContentType::Video),
        "post" => Ok(ContentType::Post),
        "stream" => Ok(ContentType::Stream),
        _ => Err(AppError::BadRequest(format!(
            "Invalid content_type: {}. Must be one of: video, post, stream",
            s
        ))),
    }
}

/// Parse event type string
fn parse_event_type(s: &str) -> Result<EventType> {
    match s.to_lowercase().as_str() {
        "view" => Ok(EventType::View),
        "like" => Ok(EventType::Like),
        "share" => Ok(EventType::Share),
        "comment" => Ok(EventType::Comment),
        _ => Err(AppError::BadRequest(format!(
            "Invalid event_type: {}. Must be one of: view, like, share, comment",
            s
        ))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_time_window() {
        assert!(parse_time_window("1h").is_ok());
        assert!(parse_time_window("24h").is_ok());
        assert!(parse_time_window("7d").is_ok());
        assert!(parse_time_window("all").is_ok());
        assert!(parse_time_window("invalid").is_err());
    }

    #[test]
    fn test_parse_content_type() {
        assert!(parse_content_type("video").is_ok());
        assert!(parse_content_type("post").is_ok());
        assert!(parse_content_type("stream").is_ok());
        assert!(parse_content_type("invalid").is_err());
    }

    #[test]
    fn test_parse_event_type() {
        assert!(parse_event_type("view").is_ok());
        assert!(parse_event_type("like").is_ok());
        assert!(parse_event_type("share").is_ok());
        assert!(parse_event_type("comment").is_ok());
        assert!(parse_event_type("invalid").is_err());
    }
}
