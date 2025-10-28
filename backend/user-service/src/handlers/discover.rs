use actix_web::{get, web, HttpMessage, HttpRequest, HttpResponse};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::{debug, error, warn};

use crate::error::{AppError, Result};
use crate::middleware::jwt_auth::UserId;
use crate::middleware::CircuitBreaker;
use crate::services::graph::GraphService;

/// Discover handler state with Circuit Breaker protection
pub struct DiscoverHandlerState {
    pub neo4j_cb: Arc<CircuitBreaker>, // Neo4j circuit breaker for graph queries
    pub redis_cb: Arc<CircuitBreaker>, // Redis circuit breaker for cache
}

/// Suggested user response
#[derive(Debug, Serialize, Deserialize)]
pub struct UserWithScore {
    pub user_id: String, // UUID as string
    pub score: f64,
    pub reason: String, // e.g., "3 mutual connections"
}

/// Suggested users response
#[derive(Debug, Serialize, Deserialize)]
pub struct SuggestedUsersResponse {
    pub users: Vec<UserWithScore>,
    pub count: usize,
}

/// GET /api/v1/discover/suggested-users
///
/// Get personalized user suggestions for the authenticated user
///
/// Based on:
/// - Second-degree connections (friends of friends)
/// - Mutual follow counts
/// - User activity (last 7 days)
///
/// Response:
/// ```json
/// {
///   "users": [
///     {
///       "user_id": "uuid1",
///       "score": 0.95,
///       "reason": "3 mutual connections"
///     },
///     ...
///   ],
///   "count": 20
/// }
/// ```
#[get("/api/v1/discover/suggested-users")]
pub async fn get_suggested_users(
    query: web::Query<std::collections::HashMap<String, String>>,
    redis_manager: web::Data<redis::aio::ConnectionManager>,
    graph: web::Data<GraphService>,
    http_req: HttpRequest,
    state: web::Data<DiscoverHandlerState>,
) -> Result<HttpResponse> {
    // Get authenticated user
    let user_id = http_req
        .extensions()
        .get::<UserId>()
        .map(|u| u.0)
        .ok_or_else(|| AppError::Authentication("Missing user context".into()))?;

    debug!("Suggested users request: user={}", user_id);

    // Determine limit (default: 20, max: 100)
    let limit = query
        .get("limit")
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(20)
        .min(100)
        .max(1);

    // Build Redis key
    let redis_key = format!("nova:cache:suggested_users:{}", user_id);

    // Cascade fallback: Try Neo4j -> Redis cache -> empty
    let users: Vec<UserWithScore> = if graph.is_enabled() {
        // Strategy 1: Get Neo4j suggestions with Circuit Breaker protection
        match state
            .neo4j_cb
            .call(|| {
                let graph_clone = graph.clone();
                async move {
                    graph_clone
                        .suggested_friends(user_id, limit)
                        .await
                        .map_err(|e| AppError::Internal(e.to_string()))
                }
            })
            .await
        {
            Ok(list) => {
                debug!("Neo4j suggestions retrieved for user {}", user_id);
                list.into_iter()
                    .map(|(uid, mutuals)| UserWithScore {
                        user_id: uid.to_string(),
                        score: mutuals as f64,
                        reason: if mutuals == 1 {
                            "1 mutual connection".to_string()
                        } else {
                            format!("{} mutual connections", mutuals)
                        },
                    })
                    .collect()
            }
            Err(e) => {
                match &e {
                    AppError::Internal(msg) if msg.contains("Circuit breaker is OPEN") => {
                        warn!(
                            "Neo4j circuit is OPEN for user {}, falling back to Redis cache",
                            user_id
                        );
                        // Strategy 2: Fall back to Redis cache when Neo4j is down
                        let conn = redis_manager.get_ref().clone();
                        match state
                            .redis_cb
                            .call(|| {
                                let mut conn_clone = conn.clone();
                                let key = redis_key.clone();
                                async move {
                                    redis::cmd("GET")
                                        .arg(&key)
                                        .query_async::<_, Option<String>>(&mut conn_clone)
                                        .await
                                        .map_err(|e| AppError::Internal(e.to_string()))
                                }
                            })
                            .await
                        {
                            Ok(Some(json_str)) => {
                                debug!("Cache hit for suggestions (user={})", user_id);
                                serde_json::from_str::<Vec<UserWithScore>>(&json_str)
                                    .unwrap_or_else(|_| {
                                        debug!("Failed to parse cached suggestions data, returning empty list");
                                        Vec::new()
                                    })
                                    .into_iter()
                                    .take(limit)
                                    .collect()
                            }
                            Ok(None) => {
                                debug!("Cache miss for suggestions (user={})", user_id);
                                Vec::new()
                            }
                            Err(cache_err) => {
                                match &cache_err {
                                    AppError::Internal(msg)
                                        if msg.contains("Circuit breaker is OPEN") =>
                                    {
                                        warn!(
                                            "Redis circuit is OPEN for cached suggestions (user={}), returning empty results",
                                            user_id
                                        );
                                    }
                                    _ => {
                                        error!(
                                            "Failed to query Redis for suggestions (user={}): {}",
                                            user_id, cache_err
                                        );
                                    }
                                }
                                Vec::new()
                            }
                        }
                    }
                    _ => {
                        error!("Neo4j suggestion error for user {}: {}", user_id, e);
                        // Fallback to Redis cache on other errors too
                        let conn = redis_manager.get_ref().clone();
                        match state
                            .redis_cb
                            .call(|| {
                                let mut conn_clone = conn.clone();
                                let key = redis_key.clone();
                                async move {
                                    redis::cmd("GET")
                                        .arg(&key)
                                        .query_async::<_, Option<String>>(&mut conn_clone)
                                        .await
                                        .map_err(|e| AppError::Internal(e.to_string()))
                                }
                            })
                            .await
                        {
                            Ok(Some(json_str)) => {
                                serde_json::from_str::<Vec<UserWithScore>>(&json_str)
                                    .unwrap_or_else(|_| Vec::new())
                                    .into_iter()
                                    .take(limit)
                                    .collect()
                            }
                            _ => Vec::new(),
                        }
                    }
                }
            }
        }
    } else {
        // Neo4j disabled: Use Redis cache directly
        debug!("Neo4j disabled, using Redis cache for suggestions");
        let conn = redis_manager.get_ref().clone();
        match state
            .redis_cb
            .call(|| {
                let mut conn_clone = conn.clone();
                let key = redis_key.clone();
                async move {
                    redis::cmd("GET")
                        .arg(&key)
                        .query_async::<_, Option<String>>(&mut conn_clone)
                        .await
                        .map_err(|e| AppError::Internal(e.to_string()))
                }
            })
            .await
        {
            Ok(Some(json_str)) => {
                debug!("Cache hit for suggestions (user={})", user_id);
                serde_json::from_str::<Vec<UserWithScore>>(&json_str)
                    .unwrap_or_else(|_| Vec::new())
                    .into_iter()
                    .take(limit)
                    .collect()
            }
            Ok(None) => {
                debug!("Cache miss for suggestions (user={})", user_id);
                Vec::new()
            }
            Err(e) => {
                match &e {
                    AppError::Internal(msg) if msg.contains("Circuit breaker is OPEN") => {
                        warn!(
                            "Redis circuit is OPEN for cached suggestions (user={}), returning empty results",
                            user_id
                        );
                    }
                    _ => {
                        error!(
                            "Failed to query Redis for suggestions (user={}): {}",
                            user_id, e
                        );
                    }
                }
                Vec::new()
            }
        }
    };

    let count = users.len();

    debug!("Suggested users response: user={} count={}", user_id, count);

    let response = SuggestedUsersResponse { users, count };

    Ok(HttpResponse::Ok().json(response))
}

// REMOVED: User search functionality moved to search-service
// All search operations (users, posts, hashtags) are now handled by search-service:8086
// Route: /api/v1/search/users (via API Gateway)

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_suggested_users_response_serialization() {
        let response = SuggestedUsersResponse {
            users: vec![UserWithScore {
                user_id: "12345678-1234-1234-1234-123456789012".to_string(),
                score: 0.95,
                reason: "3 mutual connections".to_string(),
            }],
            count: 1,
        };

        let json = serde_json::to_string(&response).unwrap();
        assert!(json.contains("user_id"));
        assert!(json.contains("score"));
        assert!(json.contains("reason"));
    }
}
