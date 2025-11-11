/// Trending/Discovery API Handlers
///
/// HTTP endpoints for trending content discovery
use actix_web::{get, post, web, HttpMessage, HttpRequest, HttpResponse};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use std::sync::Arc;
use tracing::{debug, error, warn};
use uuid::Uuid;

use crate::db::trending_repo::{ContentType, EventType, TimeWindow};
use crate::error::{AppError, Result};
use crate::middleware::jwt_auth::UserId;
use crate::middleware::CircuitBreaker;
use crate::services::trending::TrendingService;
use crate::utils::redis_timeout::run_with_timeout;

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

/// Trending handler state with Circuit Breaker protection
pub struct TrendingHandlerState {
    pub clickhouse_cb: Arc<CircuitBreaker>, // ClickHouse circuit breaker for trending queries
    pub redis_cb: Arc<CircuitBreaker>,      // Redis circuit breaker for cache
}

/// Engagement event request
#[derive(Debug, Deserialize)]
pub struct EngagementRequest {
    pub content_id: String,
    pub content_type: String, // "video", "post", "stream"
    pub event_type: String,   // "view", "like", "share", "comment"
}

/// Get cached trending results from Redis
async fn get_cached_trending(
    redis: &Arc<redis::aio::ConnectionManager>,
    window: &str,
    category: Option<&str>,
) -> Result<Option<String>> {
    let cache_key = if let Some(cat) = category {
        format!("nova:trending:{}:{}", window, cat)
    } else {
        format!("nova:trending:{}", window)
    };

    let mut conn = redis.as_ref().clone();

    match run_with_timeout(
        redis::cmd("GET")
            .arg(&cache_key)
            .query_async::<_, Option<String>>(&mut conn),
    )
    .await
    {
        Ok(Some(json_str)) => {
            debug!(
                "Cache hit for trending (window={}, category={:?})",
                window, category
            );
            Ok(Some(json_str))
        }
        Ok(None) => {
            debug!(
                "Cache miss for trending (window={}, category={:?})",
                window, category
            );
            Ok(None)
        }
        Err(e) => {
            error!("Redis error while fetching cached trending: {}", e);
            Ok(None) // Don't fail - just return None to indicate no cache
        }
    }
}

/// Create empty trending response
fn empty_trending_response() -> serde_json::Value {
    serde_json::json!({
        "items": [],
        "count": 0,
        "time_window": "24h",
        "category": null
    })
}

/// GET /api/v1/trending
///
/// Get trending content across all types or filtered by category
#[get("/api/v1/trending")]
pub async fn get_trending(
    query: web::Query<TrendingQuery>,
    pool: web::Data<PgPool>,
    redis: Option<web::Data<redis::aio::ConnectionManager>>,
    state: web::Data<TrendingHandlerState>,
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
    let service = TrendingService::new(
        pool.get_ref().clone(),
        redis.as_ref().map(|r| r.get_ref().clone()),
    );

    // Get trending content with Circuit Breaker protection
    let response = match state
        .clickhouse_cb
        .call(|| async {
            service
                .get_trending(time_window, query.category.as_deref(), limit)
                .await
        })
        .await
    {
        Ok(response) => response,
        Err(e) => {
            match &e {
                AppError::Internal(msg) if msg.contains("Circuit breaker is OPEN") => {
                    warn!(
                        "ClickHouse circuit is OPEN for trending query, attempting fallback strategies"
                    );

                    // Strategy 1: Try to get cached trending results from Redis
                    if let Some(redis_mgr) = &redis {
                        match get_cached_trending(
                            redis_mgr,
                            &query.time_window,
                            query.category.as_deref(),
                        )
                        .await
                        {
                            Ok(Some(json_str)) => {
                                debug!("Successfully returned cached trending results");
                                return Ok(HttpResponse::Ok().json(
                                    serde_json::from_str::<serde_json::Value>(&json_str)
                                        .unwrap_or_else(|_| empty_trending_response()),
                                ));
                            }
                            Ok(None) => {
                                debug!("No cached trending available, returning empty results");
                            }
                            Err(cache_err) => {
                                warn!("Redis cache lookup failed for trending: {}", cache_err);
                            }
                        }
                    }

                    // Strategy 2: Return empty results with graceful degradation
                    debug!("Returning empty trending results due to ClickHouse circuit open");
                    return Ok(HttpResponse::Ok().json(empty_trending_response()));
                }
                _ => {
                    error!("Failed to get trending content: {}", e);
                    return Err(e);
                }
            }
        }
    };

    Ok(HttpResponse::Ok().json(response))
}

/// GET /api/v1/trending/videos
#[get("/api/v1/trending/videos")]
pub async fn get_trending_videos(
    query: web::Query<TrendingQuery>,
    pool: web::Data<PgPool>,
    redis: Option<web::Data<redis::aio::ConnectionManager>>,
    state: web::Data<TrendingHandlerState>,
) -> Result<HttpResponse> {
    let time_window = parse_time_window(&query.time_window)?;
    let limit = query.limit.clamp(1, 100);

    let service = TrendingService::new(
        pool.get_ref().clone(),
        redis.as_ref().map(|r| r.get_ref().clone()),
    );

    let response = match state
        .clickhouse_cb
        .call(|| async {
            service
                .get_trending_by_type(ContentType::Video, time_window, limit)
                .await
        })
        .await
    {
        Ok(response) => response,
        Err(e) => match &e {
            AppError::Internal(msg) if msg.contains("Circuit breaker is OPEN") => {
                warn!("ClickHouse circuit is OPEN for trending videos query, falling back to empty results");
                return Ok(HttpResponse::Ok().json(empty_trending_response()));
            }
            _ => {
                error!("Failed to get trending videos: {}", e);
                return Err(e);
            }
        },
    };

    Ok(HttpResponse::Ok().json(response))
}

/// GET /api/v1/trending/posts
#[get("/api/v1/trending/posts")]
pub async fn get_trending_posts(
    query: web::Query<TrendingQuery>,
    pool: web::Data<PgPool>,
    redis: Option<web::Data<redis::aio::ConnectionManager>>,
    state: web::Data<TrendingHandlerState>,
) -> Result<HttpResponse> {
    let time_window = parse_time_window(&query.time_window)?;
    let limit = query.limit.clamp(1, 100);

    let service = TrendingService::new(
        pool.get_ref().clone(),
        redis.as_ref().map(|r| r.get_ref().clone()),
    );

    let response = match state
        .clickhouse_cb
        .call(|| async {
            service
                .get_trending_by_type(ContentType::Post, time_window, limit)
                .await
        })
        .await
    {
        Ok(response) => response,
        Err(e) => match &e {
            AppError::Internal(msg) if msg.contains("Circuit breaker is OPEN") => {
                warn!("ClickHouse circuit is OPEN for trending posts query, falling back to empty results");
                return Ok(HttpResponse::Ok().json(empty_trending_response()));
            }
            _ => {
                error!("Failed to get trending posts: {}", e);
                return Err(e);
            }
        },
    };

    Ok(HttpResponse::Ok().json(response))
}

/// GET /api/v1/trending/streams
#[get("/api/v1/trending/streams")]
pub async fn get_trending_streams(
    query: web::Query<TrendingQuery>,
    pool: web::Data<PgPool>,
    redis: Option<web::Data<redis::aio::ConnectionManager>>,
    state: web::Data<TrendingHandlerState>,
) -> Result<HttpResponse> {
    let time_window = parse_time_window(&query.time_window)?;
    let limit = query.limit.clamp(1, 100);

    let service = TrendingService::new(
        pool.get_ref().clone(),
        redis.as_ref().map(|r| r.get_ref().clone()),
    );

    let response = match state
        .clickhouse_cb
        .call(|| async {
            service
                .get_trending_by_type(ContentType::Stream, time_window, limit)
                .await
        })
        .await
    {
        Ok(response) => response,
        Err(e) => match &e {
            AppError::Internal(msg) if msg.contains("Circuit breaker is OPEN") => {
                warn!("ClickHouse circuit is OPEN for trending streams query, falling back to empty results");
                return Ok(HttpResponse::Ok().json(empty_trending_response()));
            }
            _ => {
                error!("Failed to get trending streams: {}", e);
                return Err(e);
            }
        },
    };

    Ok(HttpResponse::Ok().json(response))
}

/// GET /api/v1/trending/categories
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
#[post("/api/v1/trending/engagement")]
pub async fn record_engagement(
    req: HttpRequest,
    body: web::Json<EngagementRequest>,
    pool: web::Data<PgPool>,
    redis: Option<web::Data<redis::aio::ConnectionManager>>,
    state: web::Data<TrendingHandlerState>,
) -> Result<HttpResponse> {
    let user_id = req
        .extensions()
        .get::<UserId>()
        .map(|u| u.0)
        .ok_or_else(|| AppError::Authentication("Missing user context".into()))?;

    let content_id = Uuid::parse_str(&body.content_id)
        .map_err(|_| AppError::BadRequest("Invalid content_id format".to_string()))?;

    let content_type = parse_content_type(&body.content_type)?;
    let event_type = parse_event_type(&body.event_type)?;

    debug!(
        "Recording engagement: user={}, content={}, type={}, event={}",
        user_id, content_id, body.content_type, body.event_type
    );

    let service = TrendingService::new(
        pool.get_ref().clone(),
        redis.as_ref().map(|r| r.get_ref().clone()),
    );

    match state
        .redis_cb
        .call(|| async {
            service
                .record_engagement(content_id, content_type, user_id, event_type)
                .await
        })
        .await
    {
        Ok(_) => {
            debug!(
                "Engagement recorded successfully for user {} on content {}",
                user_id, content_id
            );
        }
        Err(e) => match &e {
            AppError::Internal(msg) if msg.contains("Circuit breaker is OPEN") => {
                warn!(
                        "Redis circuit is OPEN for engagement recording (user={}), engagement accepted but cache not updated",
                        user_id
                    );
                return Ok(HttpResponse::Accepted().json(serde_json::json!({
                    "success": true,
                    "message": "Engagement recorded (cache pending)",
                    "status": "queued"
                })));
            }
            _ => {
                error!("Failed to record engagement for user {}: {}", user_id, e);
                return Err(e);
            }
        },
    }

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
