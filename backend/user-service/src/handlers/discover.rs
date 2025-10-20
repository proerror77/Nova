use actix_web::{get, web, HttpMessage, HttpRequest, HttpResponse};
use serde::{Deserialize, Serialize};
use tracing::{debug, error};

use crate::error::{AppError, Result};
use crate::middleware::jwt_auth::UserId;

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
#[get("/suggested-users")]
pub async fn get_suggested_users(
    query: web::Query<std::collections::HashMap<String, String>>,
    redis_manager: web::Data<redis::aio::ConnectionManager>,
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

    // Get suggested users from Redis
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
            error!("Failed to query Redis for suggestions: {}", e);
            AppError::InternalServerError("Cache lookup failed".to_string())
        })?;

    let users = if let Some(json_str) = cached {
        // Parse cached JSON array
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
    };

    let count = users.len();

    debug!(
        "Suggested users response: user={} count={}",
        user_id, count
    );

    let response = SuggestedUsersResponse { users, count };

    Ok(HttpResponse::Ok().json(response))
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
