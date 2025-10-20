use actix_web::{get, web, HttpMessage, HttpRequest, HttpResponse};
use base64::{engine::general_purpose, Engine as _};
use serde::Deserialize;
use std::sync::Arc;
use tracing::{debug, error};

use crate::error::{AppError, Result};
use crate::middleware::jwt_auth::UserId;
use crate::models::FeedResponse;
use crate::services::feed_ranking::FeedRankingService;

/// Feed query parameters
#[derive(Debug, Deserialize)]
pub struct FeedQueryParams {
    /// Algorithm: "ch" (ClickHouse) or "time" (timeline fallback)
    #[serde(default = "default_algo")]
    pub algo: String,

    /// Page limit (max 100)
    #[serde(default = "default_limit")]
    pub limit: u32,

    /// Cursor for pagination (base64 encoded offset)
    pub cursor: Option<String>,
}

fn default_algo() -> String {
    "ch".to_string()
}

fn default_limit() -> u32 {
    20
}

impl FeedQueryParams {
    /// Decode cursor to offset
    fn decode_cursor(&self) -> Result<usize> {
        match &self.cursor {
            Some(cursor) => {
                let decoded = general_purpose::STANDARD.decode(cursor).map_err(|e| {
                    error!("Failed to decode cursor: {}", e);
                    AppError::BadRequest("Invalid cursor format".to_string())
                })?;

                let offset_str = String::from_utf8(decoded).map_err(|e| {
                    error!("Failed to parse cursor string: {}", e);
                    AppError::BadRequest("Invalid cursor encoding".to_string())
                })?;

                offset_str.parse::<usize>().map_err(|e| {
                    error!("Failed to parse offset from cursor: {}", e);
                    AppError::BadRequest("Invalid cursor value".to_string())
                })
            }
            None => Ok(0),
        }
    }

    /// Encode offset to cursor
    fn encode_cursor(offset: usize) -> String {
        general_purpose::STANDARD.encode(offset.to_string())
    }
}

/// Feed handler state
pub struct FeedHandlerState {
    pub feed_ranking: Arc<FeedRankingService>,
}

/// GET /api/v1/feed
///
/// Get personalized feed for the authenticated user
///
/// Query Parameters:
/// - algo: "ch" (ClickHouse) or "time" (timeline) - default: "ch"
/// - limit: Number of posts (1-100) - default: 20
/// - cursor: Pagination cursor (base64 encoded)
///
/// Response:
/// ```json
/// {
///   "posts": ["uuid1", "uuid2", ...],
///   "cursor": "base64_encoded_offset",
///   "has_more": true,
///   "total_count": 50
/// }
/// ```
#[get("")]
pub async fn get_feed(
    query: web::Query<FeedQueryParams>,
    http_req: HttpRequest,
    state: web::Data<FeedHandlerState>,
) -> Result<HttpResponse> {
    let user_id = http_req
        .extensions()
        .get::<UserId>()
        .map(|u| u.0)
        .ok_or_else(|| AppError::Authentication("Missing user context".into()))?;
    let offset = query.decode_cursor()?;
    let limit = query.limit.min(100).max(1) as usize; // Clamp to [1, 100]

    debug!(
        "Feed request: user={} algo={} limit={} offset={}",
        user_id, query.algo, limit, offset
    );

    // Validate algorithm
    if query.algo != "ch" && query.algo != "time" {
        return Err(AppError::BadRequest(
            "Invalid algo parameter. Must be 'ch' or 'time'".to_string(),
        ));
    }

    // Get feed from ranking service
    let (post_ids, has_more) = state
        .feed_ranking
        .get_feed(user_id, limit, offset)
        .await
        .map_err(|e| {
            error!("Failed to get feed for user {}: {}", user_id, e);
            e
        })?;

    // Build response
    let response = FeedResponse {
        posts: post_ids.clone(),
        cursor: if has_more {
            Some(FeedQueryParams::encode_cursor(offset + limit))
        } else {
            None
        },
        has_more,
        total_count: post_ids.len(),
    };

    debug!(
        "Feed response: user={} count={} has_more={}",
        user_id,
        post_ids.len(),
        has_more
    );

    Ok(HttpResponse::Ok().json(response))
}

/// POST /api/v1/feed/invalidate
///
/// Invalidate feed cache for the authenticated user
///
/// Use case: After user follows/unfollows someone, invalidate their feed cache
#[actix_web::post("/invalidate")]
pub async fn invalidate_feed_cache(
    http_req: HttpRequest,
    state: web::Data<FeedHandlerState>,
) -> Result<HttpResponse> {
    let user_id = http_req
        .extensions()
        .get::<UserId>()
        .map(|u| u.0)
        .ok_or_else(|| AppError::Authentication("Missing user context".into()))?;

    debug!("Invalidating feed cache for user {}", user_id);

    if let Err(e) = state.feed_ranking.invalidate_cache(user_id).await {
        error!("Failed to invalidate cache for user {}: {}", user_id, e);
        return Err(e);
    }

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "success": true,
        "message": "Feed cache invalidated"
    })))
}

/// Trending posts response
#[derive(Debug, Serialize, Deserialize)]
pub struct TrendingResponse {
    pub posts: Vec<String>, // Post IDs (UUIDs as strings)
    pub window: String,     // Time window: "1h", "24h", "7d"
    pub count: usize,
}

/// GET /api/v1/feed/trending
///
/// Get trending posts for the authenticated user
///
/// Query Parameters:
/// - window: "1h" (hourly) | "24h" (daily) | "7d" (weekly) - default: "24h"
///
/// Response:
/// ```json
/// {
///   "posts": ["uuid1", "uuid2", ...],
///   "window": "24h",
///   "count": 50
/// }
/// ```
#[get("/trending")]
pub async fn get_trending(
    query: web::Query<std::collections::HashMap<String, String>>,
    redis_manager: web::Data<redis::aio::ConnectionManager>,
    http_req: HttpRequest,
) -> Result<HttpResponse> {
    // Verify user is authenticated
    let _user_id = http_req
        .extensions()
        .get::<UserId>()
        .map(|u| u.0)
        .ok_or_else(|| AppError::Authentication("Missing user context".into()))?;

    // Determine time window (default: 24h)
    let window = query.get("window").map(|s| s.as_str()).unwrap_or("24h");

    let valid_windows = ["1h", "24h", "7d"];
    if !valid_windows.contains(&window) {
        return Err(AppError::BadRequest(
            "Invalid window parameter. Must be '1h', '24h', or '7d'".to_string(),
        ));
    }

    debug!("Trending request: window={}", window);

    // Build Redis key based on window
    let redis_key = format!("nova:cache:trending:{}", window);

    // Get trending posts from Redis
    let mut conn = redis_manager.get_connection().await.map_err(|e| {
        error!("Redis connection failed: {}", e);
        AppError::InternalServerError("Failed to connect to cache".to_string())
    })?;

    // Try to get from cache
    let cached: Option<String> = redis::cmd("GET")
        .arg(&redis_key)
        .query_async(&mut conn)
        .await
        .map_err(|e| {
            error!("Failed to query Redis for trending: {}", e);
            AppError::InternalServerError("Cache lookup failed".to_string())
        })?;

    let posts = if let Some(json_str) = cached {
        // Parse cached JSON array
        serde_json::from_str::<Vec<String>>(&json_str).unwrap_or_else(|_| {
            debug!("Failed to parse cached trending data, returning empty list");
            Vec::new()
        })
    } else {
        debug!("No cached trending data found for window: {}", window);
        Vec::new()
    };

    let count = posts.len();

    debug!(
        "Trending response: window={} count={}",
        window, count
    );

    let response = TrendingResponse {
        posts,
        window: window.to_string(),
        count,
    };

    Ok(HttpResponse::Ok().json(response))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cursor_encoding_decoding() {
        let offset = 100;
        let cursor = FeedQueryParams::encode_cursor(offset);
        let query = FeedQueryParams {
            algo: "ch".to_string(),
            limit: 20,
            cursor: Some(cursor),
        };

        let decoded = query.decode_cursor().unwrap();
        assert_eq!(decoded, offset);
    }

    #[test]
    fn test_cursor_none_returns_zero() {
        let query = FeedQueryParams {
            algo: "ch".to_string(),
            limit: 20,
            cursor: None,
        };

        let decoded = query.decode_cursor().unwrap();
        assert_eq!(decoded, 0);
    }

    #[test]
    fn test_default_params() {
        let query = FeedQueryParams {
            algo: default_algo(),
            limit: default_limit(),
            cursor: None,
        };

        assert_eq!(query.algo, "ch");
        assert_eq!(query.limit, 20);
    }
}
