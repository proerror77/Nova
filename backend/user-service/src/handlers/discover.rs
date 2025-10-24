use actix_web::{get, web, HttpMessage, HttpRequest, HttpResponse};
use serde::{Deserialize, Serialize};
use tracing::{debug, error};
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::{AppError, Result};
use crate::middleware::jwt_auth::UserId;
use crate::services::graph::GraphService;
use crate::cache::{cache_search_results, get_cached_search_results};

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
pub async fn get_suggested_users(
    query: web::Query<std::collections::HashMap<String, String>>,
    redis_manager: web::Data<redis::aio::ConnectionManager>,
    graph: web::Data<GraphService>,
    http_req: HttpRequest,
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

    // Prefer Neo4j real-time suggestions when enabled; otherwise fallback to Redis cache
    let users: Vec<UserWithScore> = if graph.is_enabled() {
        match graph.suggested_friends(user_id, limit).await {
            Ok(list) => list
                .into_iter()
                .map(|(uid, mutuals)| UserWithScore {
                    user_id: uid.to_string(),
                    score: mutuals as f64,
                    reason: if mutuals == 1 {
                        "1 mutual connection".to_string()
                    } else {
                        format!("{} mutual connections", mutuals)
                    },
                })
                .collect(),
            Err(e) => {
                error!("Neo4j suggestion error: {}", e);
                Vec::new()
            }
        }
    } else {
        // Fallback: Get suggested users from Redis
        let mut conn = redis_manager.get_ref().clone();

        let cached: Option<String> = redis::cmd("GET")
            .arg(&redis_key)
            .query_async(&mut conn)
            .await
            .map_err(|e| {
                error!("Failed to query Redis for suggestions: {}", e);
                AppError::Internal("Cache lookup failed".to_string())
            })?;

        if let Some(json_str) = cached {
            serde_json::from_str::<Vec<UserWithScore>>(&json_str)
                .unwrap_or_else(|_| {
                    debug!("Failed to parse cached suggestions data, returning empty list");
                    Vec::new()
                })
                .into_iter()
                .take(limit)
                .collect()
        } else {
            debug!("No cached suggestions found for user: {}", user_id);
            Vec::new()
        }
    };

    let count = users.len();

    debug!(
        "Suggested users response: user={} count={}",
        user_id, count
    );

    let response = SuggestedUsersResponse { users, count };

    Ok(HttpResponse::Ok().json(response))
}

/// Search result for a user
#[derive(Debug, Serialize, Deserialize)]
pub struct UserSearchResult {
    pub id: String,
    pub username: String,
    pub display_name: Option<String>,
    pub bio: Option<String>,
    pub avatar_url: Option<String>,
    pub is_verified: bool,
}

/// User search response
#[derive(Debug, Serialize, Deserialize)]
pub struct UserSearchResponse {
    pub users: Vec<UserSearchResult>,
    pub count: usize,
}

/// GET /api/v1/search/users?q=query
///
/// Search for users by username, display name, or bio
///
/// Query parameters:
/// - q: search query (required, minimum 2 characters)
/// - limit: max results (default: 20, max: 100)
/// - offset: pagination offset (default: 0)
pub async fn search_users(
    query: web::Query<std::collections::HashMap<String, String>>,
    pool: web::Data<PgPool>,
    http_req: HttpRequest,
    redis: Option<web::Data<redis::aio::ConnectionManager>>,
) -> HttpResponse {
    // Get search query
    let search_query = match query.get("q") {
        Some(q) if q.len() >= 2 => q.clone(),
        _ => {
            return HttpResponse::BadRequest().json(serde_json::json!({
                "error": "Search query must be at least 2 characters"
            }))
        }
    };

    // Get pagination parameters
    let limit = query
        .get("limit")
        .and_then(|s| s.parse::<i64>().ok())
        .unwrap_or(20)
        .clamp(1, 100);

    let offset = query
        .get("offset")
        .and_then(|s| s.parse::<i64>().ok())
        .unwrap_or(0)
        .max(0);

    // Try to get from cache first
    if let Some(redis_mgr) = redis.as_ref() {
        if let Ok(Some(cached_json)) = get_cached_search_results(
            redis_mgr.get_ref(),
            &search_query,
            limit,
            offset,
        ).await {
            if let Ok(response) = serde_json::from_str::<UserSearchResponse>(&cached_json) {
                debug!("Search cache hit: q='{}' limit={} offset={}", search_query, limit, offset);
                return HttpResponse::Ok().json(response);
            }
        }
    }

    // Get requester info (if authenticated)
    let requester_id = http_req
        .extensions()
        .get::<UserId>()
        .map(|u| u.0);

    // Search users by username, display_name, or bio
    // OPTIMIZED: Single query with JOINs instead of N+1 pattern
    let search_pattern = format!("%{}%", search_query);

    let sql = r#"
        SELECT
            u.id, u.username, u.display_name, u.bio, u.avatar_url, u.email_verified,
            COALESCE(u.private_account, false) as private_account,
            CASE WHEN b1.id IS NOT NULL OR b2.id IS NOT NULL THEN true ELSE false END as is_blocked
        FROM users u
        LEFT JOIN blocks b1 ON b1.blocker_id = $5 AND b1.blocked_id = u.id
        LEFT JOIN blocks b2 ON b2.blocker_id = u.id AND b2.blocked_id = $5
        WHERE u.deleted_at IS NULL
        AND (
            u.username ILIKE $1
            OR u.display_name ILIKE $1
            OR u.bio ILIKE $1
        )
        ORDER BY
            CASE WHEN u.private_account THEN 1 ELSE 0 END,  -- Public accounts first
            CASE WHEN u.username ILIKE $2 THEN 0 ELSE 1 END,  -- Username matches rank higher
            u.username
        LIMIT $3
        OFFSET $4
    "#;

    match sqlx::query_as::<_, (Uuid, String, Option<String>, Option<String>, Option<String>, bool, bool, bool)>(sql)
        .bind(&search_pattern)
        .bind(&search_pattern)
        .bind(limit)
        .bind(offset)
        .bind(requester_id.unwrap_or(Uuid::nil()))  // For block check joins
        .fetch_all(pool.get_ref())
        .await
    {
        Ok(rows) => {
            let mut users = Vec::new();

            for (id, username, display_name, bio, avatar_url, is_verified, is_private, is_blocked) in rows {
                // Skip private accounts unless requester is the owner
                if is_private {
                    if let Some(req_id) = requester_id {
                        if req_id != id {
                            continue;  // Skip private accounts for non-owners
                        }
                    } else {
                        continue;  // Skip private accounts for unauthenticated users
                    }
                }

                // Skip blocked/blocking users
                if requester_id.is_some() && is_blocked {
                    continue;
                }

                users.push(UserSearchResult {
                    id: id.to_string(),
                    username,
                    display_name,
                    bio,
                    avatar_url,
                    is_verified,
                });
            }

            let count = users.len();
            let response = UserSearchResponse { users, count };

            // Cache the search results
            if let Some(redis_mgr) = redis.as_ref() {
                if let Ok(json) = serde_json::to_string(&response) {
                    let _ = cache_search_results(
                        redis_mgr.get_ref(),
                        &search_query,
                        limit,
                        offset,
                        &json,
                    ).await;
                }
            }

            HttpResponse::Ok().json(response)
        }
        Err(e) => {
            error!("User search error: {}", e);
            HttpResponse::InternalServerError().json(serde_json::json!({
                "error": "Search failed",
                "details": e.to_string()
            }))
        }
    }
}

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
