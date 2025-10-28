use actix_web::{get, web, HttpMessage, HttpRequest, HttpResponse};
use base64::{engine::general_purpose, Engine as _};
use serde::Deserialize;
use std::sync::Arc;
use tracing::{debug, error, warn};
use uuid::Uuid;

use crate::error::{AppError, Result};
use crate::middleware::jwt_auth::UserId;
use crate::middleware::CircuitBreaker;
use crate::models::FeedResponse;
use crate::services::feed_ranking::FeedRankingService;
use crate::services::recommendation_v2::RecommendationServiceV2;

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
    pub rec_v2: Option<Arc<RecommendationServiceV2>>, // optional re-ranker
    pub clickhouse_cb: Arc<CircuitBreaker>,           // ClickHouse circuit breaker for fault tolerance
    pub redis: Option<Arc<redis::aio::ConnectionManager>>, // Redis for cache fallback
}

/// Get cached feed from Redis
async fn get_cached_feed(
    redis: &Arc<redis::aio::ConnectionManager>,
    user_id: Uuid,
    algo: &str,
) -> Result<Option<Vec<Uuid>>> {
    let cache_key = format!("nova:feed:{}:{}", user_id, algo);
    let mut conn = redis.get_ref().clone();

    match redis::cmd("GET")
        .arg(&cache_key)
        .query_async::<_, Option<String>>(&mut conn)
        .await
    {
        Ok(Some(json_str)) => {
            debug!("Cache hit for feed (user={}, algo={})", user_id, algo);
            match serde_json::from_str::<Vec<Uuid>>(&json_str) {
                Ok(posts) => Ok(Some(posts)),
                Err(_) => {
                    debug!("Failed to parse cached feed data, ignoring");
                    Ok(None)
                }
            }
        }
        Ok(None) => {
            debug!("Cache miss for feed (user={}, algo={})", user_id, algo);
            Ok(None)
        }
        Err(e) => {
            error!("Redis error while fetching cached feed: {}", e);
            // Don't fail - just return None to let caller decide next step
            Ok(None)
        }
    }
}

/// Get timeline feed (most recent posts) as fallback
fn get_timeline_fallback(limit: usize) -> Vec<Uuid> {
    // TODO: Implement actual timeline query from PostgreSQL
    // For now, return empty to indicate fallback unavailable
    // In production, this should fetch the most recent posts from PostgreSQL
    // based on created_at timestamp
    debug!(
        "Using timeline fallback (empty for now - requires DB query implementation)"
    );
    Vec::new()
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

    // Get feed from ranking service with Circuit Breaker protection
    // CB protects against ClickHouse failures and cascading errors
    let (mut post_ids, has_more) = match state
        .clickhouse_cb
        .call(|| async {
            state
                .feed_ranking
                .get_feed(user_id, limit, offset)
                .await
        })
        .await
    {
        Ok((posts, more)) => (posts, more),
        Err(e) => {
            match &e {
                AppError::Internal(msg) if msg.contains("Circuit breaker is OPEN") => {
                    // Circuit is open - ClickHouse is experiencing issues
                    warn!(
                        "ClickHouse circuit is OPEN for user {}, attempting fallback strategies",
                        user_id
                    );

                    // Strategy 1: Try to get cached feed from Redis
                    if let Some(redis) = &state.redis {
                        match get_cached_feed(redis, user_id, &query.algo).await {
                            Ok(Some(cached_posts)) => {
                                debug!(
                                    "Successfully returned {} cached posts for user {}",
                                    cached_posts.len(),
                                    user_id
                                );
                                // Return cached posts with no more indicator (incomplete pagination)
                                return Ok(HttpResponse::Ok().json(FeedResponse {
                                    posts: cached_posts.iter().skip(offset).take(limit).cloned().collect(),
                                    cursor: None, // Don't provide cursor for cached data
                                    has_more: false,
                                    total_count: cached_posts.len(),
                                }));
                            }
                            Ok(None) => {
                                debug!("No cached feed available for user {}, trying timeline fallback", user_id);
                            }
                            Err(cache_err) => {
                                warn!("Redis cache lookup failed for user {}: {}", user_id, cache_err);
                            }
                        }
                    }

                    // Strategy 2: Return timeline fallback (most recent posts)
                    let timeline_posts = get_timeline_fallback(limit);
                    if !timeline_posts.is_empty() {
                        debug!(
                            "Successfully returned {} timeline fallback posts for user {}",
                            timeline_posts.len(),
                            user_id
                        );
                        return Ok(HttpResponse::Ok().json(FeedResponse {
                            posts: timeline_posts.clone(),
                            cursor: None,
                            has_more: false,
                            total_count: timeline_posts.len(),
                        }));
                    }

                    // Strategy 3: Return 503 Service Unavailable
                    warn!(
                        "All fallback strategies exhausted for user {}, returning 503",
                        user_id
                    );
                    return Err(AppError::Internal(
                        "Feed service temporarily unavailable. Please try again later.".into(),
                    ));
                }
                _ => {
                    error!("Failed to get feed for user {}: {}", user_id, e);
                    return Err(e);
                }
            }
        }
    };

    // Optional: Re-rank using Recommendation V2 (graceful, best-effort)
    if let Some(rec) = &state.rec_v2 {
        // Feature flag via env
        let enable =
            std::env::var("RECOMMENDATION_V2_ENABLED").unwrap_or_else(|_| "false".into()) == "true";
        if enable {
            if let Ok(prioritized) = rec.get_recommendations(user_id, post_ids.len()).await {
                if !prioritized.is_empty() {
                    // Stable reorder: move items in `prioritized` to front, keep others order
                    let set: std::collections::HashSet<uuid::Uuid> =
                        prioritized.iter().cloned().collect();
                    let mut front: Vec<uuid::Uuid> = Vec::new();
                    let mut back: Vec<uuid::Uuid> = Vec::new();
                    for id in &post_ids {
                        if set.contains(id) {
                            front.push(*id);
                        } else {
                            back.push(*id);
                        }
                    }
                    front.extend(back);
                    post_ids = front;
                }
            }
        }
    }

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
